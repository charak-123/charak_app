from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends
from pydantic import BaseModel

from ..db import supabase
from ..deps import require_doctor, get_current_user
from ..errors import AppError

router = APIRouter()

VALID_STATUSES = ("requested", "accepted", "declined", "paid", "completed", "cancelled")


# ── Patient creates a booking (called by patient app, no doctor auth) ─────────

class BookingCreate(BaseModel):
    doctor_id: str
    channel: str                 # "online_consult" | "home_visit"
    scheduled_start: str         # ISO datetime "2026-08-25T09:00:00+05:30"
    category_id: Optional[str]   = None
    price_confirmed: Optional[float] = None


@router.post("/", status_code=201)
def create_booking(body: BookingCreate, user: dict = Depends(get_current_user)):
    if body.channel not in ("online_consult", "home_visit"):
        raise AppError("Invalid channel", 400)

    # Verify doctor exists and is verified
    doc = supabase.table("doctors").select("id,verification_status") \
        .eq("id", body.doctor_id).single().execute()
    if not doc.data or doc.data["verification_status"] != "verified":
        raise AppError("Doctor not found or not verified", 404)

    # Confirm slot is still available
    from datetime import datetime
    try:
        dt = datetime.fromisoformat(body.scheduled_start.replace("Z", "+00:00"))
    except ValueError:
        raise AppError("Invalid scheduled_start format", 400)

    existing = (
        supabase.table("bookings")
        .select("id")
        .eq("doctor_id", body.doctor_id)
        .eq("scheduled_start", body.scheduled_start)
        .in_("status", ["requested", "accepted", "paid"])
        .execute()
    )
    if existing.data:
        raise AppError("Slot already booked", 409)

    row = supabase.table("bookings").insert({
        "patient_id": user["sub"],
        "doctor_id": body.doctor_id,
        "channel": body.channel,
        "scheduled_start": body.scheduled_start,
        "category_id": body.category_id,
        "price_confirmed": body.price_confirmed,
        "status": "requested",
    }).execute().data[0]

    return row


# ── Doctor: list incoming requests ────────────────────────────────────────────

@router.get("/doctor/incoming")
def list_incoming(user: dict = Depends(require_doctor)):
    """All requested bookings for this doctor, newest first."""
    return (
        supabase.table("bookings")
        .select("*, users(name, phone)")
        .eq("doctor_id", user["sub"])
        .eq("status", "requested")
        .order("created_at", desc=True)
        .execute()
        .data
    )


@router.get("/doctor/active")
def list_active(user: dict = Depends(require_doctor)):
    """Accepted/paid bookings — current queue."""
    return (
        supabase.table("bookings")
        .select("*, users(name, phone)")
        .eq("doctor_id", user["sub"])
        .in_("status", ["accepted", "paid"])
        .order("scheduled_start")
        .execute()
        .data
    )


@router.get("/doctor/history")
def list_history(user: dict = Depends(require_doctor)):
    """Completed/declined/cancelled bookings."""
    return (
        supabase.table("bookings")
        .select("*, users(name, phone)")
        .eq("doctor_id", user["sub"])
        .in_("status", ["completed", "declined", "cancelled"])
        .order("scheduled_start", desc=True)
        .execute()
        .data
    )


# ── Patient: own bookings ─────────────────────────────────────────────────────

@router.get("/patient/mine")
@router.get("/patient/list")
def patient_bookings(user: dict = Depends(get_current_user)):
    return (
        supabase.table("bookings")
        .select("*, doctors(name, photo_url, categories(name))")
        .eq("patient_id", user["sub"])
        .order("scheduled_start", desc=True)
        .execute()
        .data
    )


# ── Single booking ────────────────────────────────────────────────────────────

@router.get("/{booking_id}")
def get_booking(booking_id: str, user: dict = Depends(get_current_user)):
    result = (
        supabase.table("bookings")
        .select("*, users(name, phone), doctors(name, photo_url, phone, categories(name))")
        .eq("id", booking_id)
        .single()
        .execute()
    )
    if not result.data:
        raise AppError("Booking not found", 404)
    b = result.data
    # Access control: must be the patient or the doctor
    if b["patient_id"] != user["sub"] and b["doctor_id"] != user["sub"]:
        raise AppError("Forbidden", 403)
    return b


# ── Accept / Decline ──────────────────────────────────────────────────────────

@router.patch("/{booking_id}/accept")
def accept_booking(booking_id: str, user: dict = Depends(require_doctor)):
    b = _get_booking_for_doctor(booking_id, user["sub"])
    if b["status"] != "requested":
        raise AppError(f"Cannot accept a booking with status '{b['status']}'", 400)
    return _update_status(booking_id, "accepted")


@router.patch("/{booking_id}/decline")
def decline_booking(booking_id: str, user: dict = Depends(require_doctor)):
    b = _get_booking_for_doctor(booking_id, user["sub"])
    if b["status"] not in ("requested", "accepted"):
        raise AppError(f"Cannot decline a booking with status '{b['status']}'", 400)
    return _update_status(booking_id, "declined")


# ── Complete (triggers procedure bill creation) ───────────────────────────────

@router.patch("/{booking_id}/complete")
def complete_booking(booking_id: str, user: dict = Depends(require_doctor)):
    b = _get_booking_for_doctor(booking_id, user["sub"])
    if b["status"] not in ("accepted", "paid"):
        raise AppError(f"Cannot complete a booking with status '{b['status']}'", 400)
    updated = _update_status(booking_id, "completed")
    return updated


# ── Cancel (patient or doctor) ────────────────────────────────────────────────

@router.patch("/{booking_id}/cancel")
def cancel_booking(booking_id: str, user: dict = Depends(get_current_user)):
    result = supabase.table("bookings").select("*").eq("id", booking_id).single().execute()
    if not result.data:
        raise AppError("Booking not found", 404)
    b = result.data
    if b["patient_id"] != user["sub"] and b["doctor_id"] != user["sub"]:
        raise AppError("Forbidden", 403)
    if b["status"] in ("completed", "cancelled", "declined"):
        raise AppError(f"Cannot cancel a booking with status '{b['status']}'", 400)
    return _update_status(booking_id, "cancelled")


# ── Helpers ───────────────────────────────────────────────────────────────────

def _get_booking_for_doctor(booking_id: str, doctor_id: str) -> dict:
    result = supabase.table("bookings").select("*").eq("id", booking_id).single().execute()
    if not result.data:
        raise AppError("Booking not found", 404)
    if result.data["doctor_id"] != doctor_id:
        raise AppError("Forbidden", 403)
    return result.data


def _update_status(booking_id: str, status: str) -> dict:
    data: dict = {"status": status}
    if status in ("accepted", "declined"):
        data["decision_at"] = datetime.now(timezone.utc).isoformat()
    return supabase.table("bookings").update(data).eq("id", booking_id).execute().data[0]
