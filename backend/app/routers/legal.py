"""
Legal documents and consent, against published versions (migration 0024).

  GET  /legal/current                     what this user must accept, and what is outstanding
  POST /legal/accept                      record acceptance (sign-up checkboxes, re-consent)
  GET  /legal/cancellation-policy?channel the policy a booking made now would get

The old ``/consents`` endpoints stay for app builds that predate these.
"""
from typing import Optional

from fastapi import APIRouter, Depends, Request
from pydantic import BaseModel, Field

from ..deps import get_current_user
from ..errors import AppError
from ..services import cancellation, legal
from ..services.rate_limit import client_ip

router = APIRouter()

ROLES = {"patient", "doctor"}
METHODS = {"signup_checkbox", "reconsent", "booking_confirmation"}


def _role(user: dict) -> str:
    role = user.get("role")
    if role not in ROLES:
        raise AppError("Only patients and doctors accept these documents", 403)
    return role


@router.get("/current")
def current(user: dict = Depends(get_current_user)):
    role = _role(user)
    docs = legal.current_documents(role)
    accepted = legal.accepted_versions(user["sub"])
    return {
        "documents": [
            {**legal._public(d), "accepted": (d["type"], d["version"]) in accepted}
            for d in docs.values()
        ],
        # What blocks this user right now (telemedicine is asked for at the
        # first online booking, not here).
        "missing": legal.missing(user["sub"], role, legal.REQUIRED[role]),
    }


class AcceptItem(BaseModel):
    type: str = Field(max_length=40)
    version: str = Field(max_length=40)


class AcceptRequest(BaseModel):
    documents: list[AcceptItem] = Field(min_length=1, max_length=10)
    method: str = "signup_checkbox"
    app_version: Optional[str] = Field(default=None, max_length=32)


@router.post("/accept", status_code=201)
def accept(body: AcceptRequest, request: Request, user: dict = Depends(get_current_user)):
    role = _role(user)
    if body.method not in METHODS:
        raise AppError(f"method must be one of {', '.join(sorted(METHODS))}", 400)
    recorded = legal.record(
        user["sub"], role, [d.model_dump() for d in body.documents],
        method=body.method, ip=client_ip(request), app_version=body.app_version,
    )
    return {
        "recorded": [{"type": r["type"], "version": r["version"]} for r in recorded],
        "missing": legal.missing(user["sub"], role, legal.REQUIRED[role]),
    }


@router.get("/cancellation-policy")
def cancellation_policy(channel: str, user: dict = Depends(get_current_user)):
    if channel not in ("online_consult", "home_visit"):
        raise AppError("channel must be 'online_consult' or 'home_visit'", 400)
    return cancellation.public_policy(cancellation.current_policy(channel))
