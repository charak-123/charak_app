from typing import Optional

from fastapi import APIRouter, Depends
from pydantic import BaseModel

from ..db import fetch_one, supabase
from ..deps import get_current_user
from ..errors import AppError

router = APIRouter()

VALID_MEDIA_TYPES = ("voice", "text", "video", "image")


class IntakeMediaCreate(BaseModel):
    media_type: str
    file_url: Optional[str]        = None
    transcript_text: Optional[str] = None


def _assert_booking_access(booking_id: str, user: dict) -> dict:
    b = fetch_one(supabase.table("bookings").select("*").eq("id", booking_id))
    if not b:
        raise AppError("Booking not found", 404)
    if b["patient_id"] != user["sub"] and b["doctor_id"] != user["sub"]:
        raise AppError("Forbidden", 403)
    return b


@router.post("/{booking_id}/intake", status_code=201)
def add_intake(booking_id: str, body: IntakeMediaCreate, user: dict = Depends(get_current_user)):
    if body.media_type not in VALID_MEDIA_TYPES:
        raise AppError(f"Invalid media_type. Must be one of: {', '.join(VALID_MEDIA_TYPES)}", 400)
    if not body.file_url and not body.transcript_text:
        raise AppError("Either file_url or transcript_text is required", 400)
    b = _assert_booking_access(booking_id, user)
    if b["patient_id"] != user["sub"]:
        raise AppError("Only the patient may add intake media", 403)
    return supabase.table("intake_media").insert({
        "booking_id": booking_id,
        "media_type": body.media_type,
        "file_url": body.file_url,
        "transcript_text": body.transcript_text,
    }).execute().data[0]


@router.get("/{booking_id}/intake")
def list_intake(booking_id: str, user: dict = Depends(get_current_user)):
    _assert_booking_access(booking_id, user)
    return (
        supabase.table("intake_media")
        .select("*")
        .eq("booking_id", booking_id)
        .order("created_at")
        .execute()
        .data
    )
