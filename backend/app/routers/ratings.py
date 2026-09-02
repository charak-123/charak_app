from fastapi import APIRouter, Depends
from pydantic import BaseModel

from ..db import supabase
from ..deps import get_current_user
from ..errors import AppError

router = APIRouter()


class RatingCreate(BaseModel):
    stars: int
    comment: str | None = None


@router.post("/{booking_id}/rate", status_code=201)
def rate_booking(booking_id: str, body: RatingCreate, user: dict = Depends(get_current_user)):
    if not 1 <= body.stars <= 5:
        raise AppError("Stars must be between 1 and 5", 400)

    booking = supabase.table("bookings").select("patient_id,doctor_id,status") \
        .eq("id", booking_id).single().execute().data
    if not booking:
        raise AppError("Booking not found", 404)
    if booking["patient_id"] != user["sub"]:
        raise AppError("Forbidden", 403)
    if booking["status"] != "completed":
        raise AppError("Can only rate completed bookings", 400)

    # Prevent duplicate ratings
    existing = supabase.table("ratings").select("id").eq("booking_id", booking_id).execute().data
    if existing:
        raise AppError("Already rated this booking", 409)

    data: dict = {"booking_id": booking_id, "stars": body.stars}
    if body.comment:
        data["comment"] = body.comment

    result = supabase.table("ratings").insert(data).execute()
    return result.data[0]


@router.get("/{booking_id}/rate")
def get_rating(booking_id: str, user: dict = Depends(get_current_user)):
    booking = supabase.table("bookings").select("patient_id,doctor_id") \
        .eq("id", booking_id).single().execute().data
    if not booking:
        raise AppError("Booking not found", 404)
    if booking["patient_id"] != user["sub"] and booking["doctor_id"] != user["sub"]:
        raise AppError("Forbidden", 403)

    result = supabase.table("ratings").select("*").eq("booking_id", booking_id).execute()
    return result.data[0] if result.data else None
