from fastapi import APIRouter, Depends
from postgrest.exceptions import APIError
from pydantic import BaseModel, field_validator
from ..db import fetch_one, supabase
from ..deps import get_current_user, require_patient
from ..errors import AppError
from ..phone import normalize_e164
from ..services import erasure

router = APIRouter()


class UserUpdate(BaseModel):
    name: str | None = None
    # Collected on the profile step after Google sign-in. A contact number, not
    # a proven one: changing it clears otp_verified (see update_me).
    phone: str | None = None

    @field_validator("phone")
    @classmethod
    def _check_phone(cls, v: str | None) -> str | None:
        return normalize_e164(v) if v is not None else None


@router.get("/me")
def get_me(user: dict = Depends(get_current_user)):
    return fetch_one(supabase.table("users").select("*").eq("id", user["sub"]))


@router.patch("/me")
def update_me(body: UserUpdate, user: dict = Depends(require_patient)):
    data = body.model_dump(exclude_none=True)
    if not data:
        raise AppError("No fields to update", 400)

    if "phone" in data:
        current = fetch_one(supabase.table("users").select("phone").eq("id", user["sub"]))
        if not current:
            raise AppError("Account not found", 404)
        # A typed-in number is a claim, not proof. Only OTP / Firebase phone
        # sign-in may mark a number verified (services/identity.py).
        if data["phone"] != current.get("phone"):
            data["otp_verified"] = False

    try:
        result = supabase.table("users").update(data).eq("id", user["sub"]).execute()
    except APIError as exc:
        if getattr(exc, "code", None) == "23505":
            raise AppError("This phone number is already linked to another account.", 409)
        raise
    return result.data[0]


@router.delete("/me")
def delete_me(user: dict = Depends(require_patient)):
    """
    Delete the patient's own account (DPDP erasure / App Store & Play requirement).

    Soft-deletes immediately — login is blocked and all outbound contact stops —
    and schedules the personal-data purge after the grace window. Financial and
    de-identified clinical records are retained. Logging back in before the purge
    cancels the deletion.
    """
    return erasure.request_patient_deletion(user["sub"])
