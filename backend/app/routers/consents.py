"""
Consent records (DPDP accountability).

Append-only proof that a user accepted a given version of a legal document.
The apps post one row per document at sign-up / onboarding, and again whenever a
document's version changes. Records are retained even through account erasure —
they are the evidence that consent was validly obtained.
"""
from fastapi import APIRouter, Depends, Request
from pydantic import BaseModel, field_validator

from ..db import supabase
from ..deps import get_current_user
from ..services.rate_limit import client_ip

router = APIRouter()

VALID_TYPES = {"tos", "privacy", "telemedicine", "marketing"}


class ConsentRequest(BaseModel):
    type: str
    version: str

    @field_validator("type")
    @classmethod
    def _check_type(cls, v: str) -> str:
        if v not in VALID_TYPES:
            raise ValueError(f"type must be one of {sorted(VALID_TYPES)}")
        return v


@router.post("", status_code=201)
def record_consent(body: ConsentRequest, request: Request,
                   user: dict = Depends(get_current_user)):
    """Record that the current user accepted a document version."""
    row = supabase.table("consents").insert({
        "user_id": user["sub"],
        "type": body.type,
        "version": body.version,
        # The caller's address, not Cloud Run's proxy (request.client) —
        # this row is evidence of who consented.
        "ip": client_ip(request),
    }).execute().data[0]
    return row


@router.get("")
def my_consents(user: dict = Depends(get_current_user)):
    """Every consent row for the current user, newest first."""
    return (
        supabase.table("consents").select("*")
        .eq("user_id", user["sub"])
        .order("accepted_at", desc=True)
        .execute().data
    )
