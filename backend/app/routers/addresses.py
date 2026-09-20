"""
Patient addresses — where a home visit actually goes.

Nothing in the backend captured an address before this, so ``home_visit``
bookings had no destination: the doctor app read ``booking.patient_address``
against a column that did not exist and fell back to placeholder text.

A patient may keep several addresses (their own home, a parent's, the office) and
choose one per booking. Coordinates are required, not optional: the service-radius
check and the directory's distance sort both depend on them, and an address that
cannot be located is an address a doctor cannot be dispatched to.
"""
from typing import Optional

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field, field_validator

from ..db import fetch_one, supabase
from ..deps import get_current_user
from ..errors import AppError

router = APIRouter()


class AddressIn(BaseModel):
    label: str = Field(default="Home", max_length=40)
    line1: str = Field(min_length=3, max_length=200)
    line2: Optional[str] = Field(default=None, max_length=200)
    landmark: Optional[str] = Field(default=None, max_length=200)
    city: str = Field(min_length=2, max_length=80)
    pincode: str
    lat: float = Field(ge=-90, le=90)
    lng: float = Field(ge=-180, le=180)
    is_default: bool = False

    @field_validator("pincode")
    @classmethod
    def _check_pincode(cls, v: str) -> str:
        v = v.strip()
        # Indian PIN: six digits, never leading zero. Matches the DB constraint,
        # so a bad value is a 422 here rather than a 500 from Postgres.
        if len(v) != 6 or not v.isdigit() or v[0] == "0":
            raise ValueError("pincode must be six digits, e.g. 411001")
        return v


class AddressUpdate(AddressIn):
    """Same shape; every field optional for a partial edit."""
    label: Optional[str] = Field(default=None, max_length=40)
    line1: Optional[str] = Field(default=None, min_length=3, max_length=200)
    city: Optional[str] = Field(default=None, min_length=2, max_length=80)
    pincode: Optional[str] = None
    lat: Optional[float] = Field(default=None, ge=-90, le=90)
    lng: Optional[float] = Field(default=None, ge=-180, le=180)
    is_default: Optional[bool] = None

    @field_validator("pincode")
    @classmethod
    def _check_pincode(cls, v):
        if v is None:
            return v
        return AddressIn._check_pincode(v)


@router.get("/")
def list_addresses(user: dict = Depends(get_current_user)):
    return (
        supabase.table("patient_addresses")
        .select("*")
        .eq("patient_id", user["sub"])
        .order("is_default", desc=True)
        .order("created_at", desc=True)
        .execute()
        .data
    )


@router.post("/", status_code=201)
def create_address(body: AddressIn, user: dict = Depends(get_current_user)):
    existing = (
        supabase.table("patient_addresses").select("id")
        .eq("patient_id", user["sub"]).execute().data or []
    )

    # The first address a patient saves is their default whether they ticked the
    # box or not — otherwise booking a home visit would require picking from a
    # list of one.
    make_default = body.is_default or not existing
    if make_default:
        _clear_default(user["sub"])

    return supabase.table("patient_addresses").insert({
        **body.model_dump(),
        "patient_id": user["sub"],
        "is_default": make_default,
    }).execute().data[0]


@router.patch("/{address_id}")
def update_address(address_id: str, body: AddressUpdate,
                   user: dict = Depends(get_current_user)):
    _owned(address_id, user["sub"])

    data = {k: v for k, v in body.model_dump().items() if v is not None}
    if not data:
        raise AppError("No fields to update", 400)

    if data.get("is_default"):
        _clear_default(user["sub"])

    return (
        supabase.table("patient_addresses").update(data)
        .eq("id", address_id).execute().data[0]
    )


@router.delete("/{address_id}")
def delete_address(address_id: str, user: dict = Depends(get_current_user)):
    """
    Delete an address.

    Bookings keep their own snapshot of where the doctor went, so removing an
    address never rewrites the history of a visit that already happened — the
    foreign key is ON DELETE SET NULL for exactly this reason.
    """
    address = _owned(address_id, user["sub"])
    supabase.table("patient_addresses").delete().eq("id", address_id).execute()

    # Promote another address so the patient is not left with none defaulted.
    if address.get("is_default"):
        remaining = (
            supabase.table("patient_addresses").select("id")
            .eq("patient_id", user["sub"]).order("created_at", desc=True)
            .limit(1).execute().data or []
        )
        if remaining:
            supabase.table("patient_addresses").update({"is_default": True}) \
                .eq("id", remaining[0]["id"]).execute()

    return {"ok": True}


# ── Helpers ───────────────────────────────────────────────────────────────────

def _owned(address_id: str, patient_id: str) -> dict:
    address = fetch_one(
        supabase.table("patient_addresses").select("*").eq("id", address_id)
    )
    if not address:
        raise AppError("Address not found", 404)
    if address["patient_id"] != patient_id:
        raise AppError("Forbidden", 403)
    return address


def _clear_default(patient_id: str) -> None:
    """A partial unique index allows only one default per patient, so the old one
    must be cleared before the new one is written."""
    supabase.table("patient_addresses").update({"is_default": False}) \
        .eq("patient_id", patient_id).eq("is_default", True).execute()
