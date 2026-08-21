"""
Clarification calls router.

Agora RTC token generation is stubbed here (returns a placeholder token).
Wire in a real Agora App ID + App Certificate in Day 49 when credentials are available.
"""
import os
import time
from typing import Optional

from fastapi import APIRouter, Depends
from pydantic import BaseModel

from ..db import supabase
from ..deps import require_doctor, get_current_user
from ..errors import AppError

router = APIRouter()


def _generate_agora_token(channel: str, uid: int) -> str:
    """
    Stub: returns a placeholder token.
    Replace with agora-token package once AGORA_APP_ID / AGORA_APP_CERT are set.
    """
    app_id = os.getenv("AGORA_APP_ID", "")
    if not app_id:
        return f"stub_token_{channel}_{uid}_{int(time.time())}"
    # Real implementation (uncomment when agora-token is installed):
    # from agora_token_builder import RtcTokenBuilder, Role_Publisher
    # expire = int(time.time()) + 3600
    # return RtcTokenBuilder.buildTokenWithUid(app_id, os.environ["AGORA_APP_CERT"], channel, uid, Role_Publisher, expire)
    return f"stub_token_{channel}_{uid}_{int(time.time())}"


class CallComplete(BaseModel):
    notes: Optional[str] = None


@router.post("/{booking_id}/clarification-call", status_code=201)
def initiate_call(booking_id: str, user: dict = Depends(require_doctor)):
    """Doctor initiates a clarification call. Returns Agora token + channel name."""
    result = supabase.table("bookings").select("*").eq("id", booking_id).single().execute()
    if not result.data:
        raise AppError("Booking not found", 404)
    b = result.data
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

    return {**row, "agora_channel": channel_name, "agora_token": token}


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
    result = supabase.table("bookings").select("patient_id, doctor_id").eq("id", booking_id).single().execute()
    if not result.data:
        raise AppError("Booking not found", 404)
    b = result.data
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
    result = supabase.table("clarification_calls").select("*, bookings(doctor_id)") \
        .eq("id", call_id).eq("booking_id", booking_id).single().execute()
    if not result.data:
        raise AppError("Call not found", 404)
    if result.data["bookings"]["doctor_id"] != doctor_id:
        raise AppError("Forbidden", 403)
    return result.data
