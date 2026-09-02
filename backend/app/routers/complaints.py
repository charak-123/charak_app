from fastapi import APIRouter, Depends
from pydantic import BaseModel

from ..db import supabase
from ..deps import get_current_user, require_ops
from ..errors import AppError

router = APIRouter()


class ComplaintCreate(BaseModel):
    description: str


class ComplaintStatusUpdate(BaseModel):
    status: str  # open | in_review | resolved | closed


VALID_STATUSES = {"open", "in_review", "resolved", "closed"}


@router.post("/{booking_id}/complaint", status_code=201)
def file_complaint(booking_id: str, body: ComplaintCreate, user: dict = Depends(get_current_user)):
    if not body.description.strip():
        raise AppError("Description is required", 400)

    booking = supabase.table("bookings").select("patient_id,status") \
        .eq("id", booking_id).single().execute().data
    if not booking:
        raise AppError("Booking not found", 404)
    if booking["patient_id"] != user["sub"]:
        raise AppError("Forbidden", 403)

    result = supabase.table("complaints").insert({
        "booking_id": booking_id,
        "description": body.description.strip(),
        "status": "open",
    }).execute()
    return result.data[0]


@router.get("/{booking_id}/complaint")
def get_complaints(booking_id: str, user: dict = Depends(get_current_user)):
    booking = supabase.table("bookings").select("patient_id,doctor_id") \
        .eq("id", booking_id).single().execute().data
    if not booking:
        raise AppError("Booking not found", 404)
    if booking["patient_id"] != user["sub"] and booking["doctor_id"] != user["sub"]:
        raise AppError("Forbidden", 403)

    result = supabase.table("complaints").select("*").eq("booking_id", booking_id) \
        .order("created_at", desc=True).execute()
    return result.data


@router.patch("/complaints/{complaint_id}")
def update_complaint_status(
    complaint_id: str,
    body: ComplaintStatusUpdate,
    user: dict = Depends(require_ops),
):
    if body.status not in VALID_STATUSES:
        raise AppError(f"Invalid status '{body.status}'", 400)

    complaint = supabase.table("complaints").select("id").eq("id", complaint_id).execute().data
    if not complaint:
        raise AppError("Complaint not found", 404)

    result = supabase.table("complaints").update({"status": body.status}) \
        .eq("id", complaint_id).execute()
    return result.data[0]
