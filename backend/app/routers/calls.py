"""
Clarification calls router.

Agora RTC tokens are minted for real as soon as AGORA_APP_ID and
AGORA_APP_CERTIFICATE are set; until then a clearly-labelled stub token is
returned so the call UI is testable end to end without credentials.
"""
import time
from typing import Optional

from fastapi import APIRouter, BackgroundTasks, Depends
from pydantic import BaseModel, Field

from ..config import AGORA_APP_CERTIFICATE, AGORA_APP_ID
from ..db import fetch_one, supabase
from ..deps import require_doctor, get_current_user
from ..errors import AppError
from ..services import notifications

router = APIRouter()

TOKEN_TTL_SECONDS = 3600


def agora_configured() -> bool:
    return bool(AGORA_APP_ID and AGORA_APP_CERTIFICATE)


def _generate_agora_token(channel: str, uid: int) -> str:
    """
    Mint an RTC token valid for one hour.

    ``agora-token-builder`` is imported lazily so it stays an optional dependency
    until credentials exist. If the package is missing while credentials *are*
    set, that is a deployment error worth surfacing rather than silently handing
    the app a token that cannot join a channel.
    """
    if not agora_configured():
        return f"stub_token_{channel}_{uid}_{int(time.time())}"

    try:
        from agora_token_builder import RtcTokenBuilder  # type: ignore
    except ImportError:
        raise AppError(
            "Agora credentials are set but agora-token-builder is not installed", 500
        )

    return RtcTokenBuilder.buildTokenWithUid(
        AGORA_APP_ID,
        AGORA_APP_CERTIFICATE,
        channel,
        uid,
        1,                                    # 1 = publisher
        int(time.time()) + TOKEN_TTL_SECONDS,
    )


class CallComplete(BaseModel):
    notes: Optional[str] = None


@router.post("/{booking_id}/clarification-call", status_code=201)
def initiate_call(
    booking_id: str,
    background: BackgroundTasks,
    user: dict = Depends(require_doctor),
):
    """Doctor initiates a clarification call. Returns Agora token + channel name."""
    b = fetch_one(supabase.table("bookings").select("*").eq("id", booking_id))
    if not b:
        raise AppError("Booking not found", 404)
    if b["doctor_id"] != user["sub"]:
        raise AppError("Forbidden", 403)
    if b["status"] not in ("requested", "accepted"):
        raise AppError("Can only clarify requested or accepted bookings", 400)

    # Prevent duplicate active calls
    active = (
        supabase.table("clarification_calls")
        .select("id")
        .eq("booking_id", booking_id)
        .eq("call_status", "initiated")
        .execute()
    )
    if active.data:
        raise AppError("A call is already in progress for this booking", 409)

    row = supabase.table("clarification_calls").insert({
        "booking_id": booking_id,
        "call_status": "initiated",
    }).execute().data[0]

    channel_name = f"charak_{booking_id[:8]}"
    token = _generate_agora_token(channel_name, 0)

    notifications.clarification_call_started(b, background)

    return {
        **row,
        "agora_channel": channel_name,
        "agora_token": token,
        "agora_app_id": AGORA_APP_ID,
        "live": agora_configured(),
        "expires_in": TOKEN_TTL_SECONDS,
    }


class JoinRequest(BaseModel):
    uid: int = Field(default=0, ge=0)


@router.post("/{booking_id}/clarification-call/{call_id}/token")
def patient_join_token(
    booking_id: str,
    call_id: str,
    body: Optional[JoinRequest] = None,
    user: dict = Depends(get_current_user),
):
    """
    Token for the patient side of an in-progress call.

    The doctor gets theirs from the initiate response; without this the patient
    app had no way to join the channel it was being called on.
    """
    booking = fetch_one(
        supabase.table("bookings").select("patient_id, doctor_id").eq("id", booking_id)
    )
    if not booking:
        raise AppError("Booking not found", 404)
    if user["sub"] not in (booking["patient_id"], booking["doctor_id"]):
        raise AppError("Forbidden", 403)

    call = (
        supabase.table("clarification_calls").select("*")
        .eq("id", call_id).eq("booking_id", booking_id).execute().data or []
    )
    if not call:
        raise AppError("Call not found", 404)
    if call[0]["call_status"] != "initiated":
        raise AppError("Call is no longer in progress", 400)

    channel_name = f"charak_{booking_id[:8]}"
    uid = (body or JoinRequest()).uid
    return {
        "agora_channel": channel_name,
        "agora_token": _generate_agora_token(channel_name, uid),
        "agora_app_id": AGORA_APP_ID,
        "uid": uid,
        "live": agora_configured(),
        "expires_in": TOKEN_TTL_SECONDS,
    }


@router.patch("/{booking_id}/clarification-call/{call_id}/complete")
def complete_call(booking_id: str, call_id: str, body: CallComplete, user: dict = Depends(require_doctor)):
    call = _get_call(call_id, booking_id, user["sub"])
    if call["call_status"] != "initiated":
        raise AppError("Call is not in progress", 400)
    from datetime import datetime, timezone
    return supabase.table("clarification_calls").update({
        "call_status": "completed",
        "notes": body.notes,
        "ended_at": datetime.now(timezone.utc).isoformat(),
    }).eq("id", call_id).execute().data[0]


@router.patch("/{booking_id}/clarification-call/{call_id}/missed")
def mark_missed(booking_id: str, call_id: str, user: dict = Depends(require_doctor)):
    call = _get_call(call_id, booking_id, user["sub"])
    if call["call_status"] != "initiated":
        raise AppError("Call is not in progress", 400)
    return supabase.table("clarification_calls").update({
        "call_status": "missed",
    }).eq("id", call_id).execute().data[0]


@router.get("/{booking_id}/clarification-calls")
def list_calls(booking_id: str, user: dict = Depends(get_current_user)):
    b = fetch_one(supabase.table("bookings").select("patient_id, doctor_id").eq("id", booking_id))
    if not b:
        raise AppError("Booking not found", 404)
    if b["patient_id"] != user["sub"] and b["doctor_id"] != user["sub"]:
        raise AppError("Forbidden", 403)
    return (
        supabase.table("clarification_calls")
        .select("*")
        .eq("booking_id", booking_id)
        .order("created_at")
        .execute()
        .data
    )


def _get_call(call_id: str, booking_id: str, doctor_id: str) -> dict:
    call = fetch_one(
        supabase.table("clarification_calls").select("*, bookings(doctor_id)")
        .eq("id", call_id).eq("booking_id", booking_id)
    )
    if not call:
        raise AppError("Call not found", 404)
    if call["bookings"]["doctor_id"] != doctor_id:
        raise AppError("Forbidden", 403)
    return call
