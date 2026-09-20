from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import APIRouter, BackgroundTasks, Depends
from pydantic import BaseModel, Field

from ..config import PAYMENT_HOLD_MINUTES
from ..db import fetch_one, supabase
from ..deps import get_current_user, require_doctor
from ..errors import AppError
from ..services import notifications

router = APIRouter()

VALID_STATUSES = (
    "requested", "accepted", "declined", "paid", "completed", "cancelled", "no_show",
)

# Statuses that occupy a slot — a new booking cannot take a time already held by
# one of these.
SLOT_HOLDING_STATUSES = ["requested", "accepted", "paid"]


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _now_iso() -> str:
    return _now().isoformat()


# ── Patient creates a booking ─────────────────────────────────────────────────

class BookingCreate(BaseModel):
    doctor_id: str
    channel: str                 # "online_consult" | "home_visit"
    scheduled_start: str         # ISO datetime "2026-08-25T09:00:00+05:30"
    category_id: Optional[str]   = None
    price_confirmed: Optional[float] = None


@router.post("/", status_code=201)
def create_booking(
    body: BookingCreate,
    background: BackgroundTasks,
    user: dict = Depends(get_current_user),
):
    if body.channel not in ("online_consult", "home_visit"):
        raise AppError("Invalid channel", 400)

    # Doctor must exist, be verified, and not be suspended.
    doc = fetch_one(
        supabase.table("doctors")
        .select("id, name, verification_status, suspended")
        .eq("id", body.doctor_id)
    )
    if not doc or doc["verification_status"] != "verified":
        raise AppError("Doctor not found or not verified", 404)
    if doc.get("suspended"):
        raise AppError("This doctor is not currently accepting bookings", 409)

    try:
        datetime.fromisoformat(body.scheduled_start.replace("Z", "+00:00"))
    except ValueError:
        raise AppError("Invalid scheduled_start format", 400)

    existing = (
        supabase.table("bookings")
        .select("id")
        .eq("doctor_id", body.doctor_id)
        .eq("scheduled_start", body.scheduled_start)
        .in_("status", SLOT_HOLDING_STATUSES)
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

    patient = supabase.table("users").select("name").eq("id", user["sub"]).execute().data or []
    patient_name = (patient[0].get("name") if patient else None) or "A patient"
    notifications.booking_requested(row, patient_name, background)

    return row


# ── Doctor lists ──────────────────────────────────────────────────────────────

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
    """Terminal bookings — everything no longer actionable."""
    return (
        supabase.table("bookings")
        .select("*, users(name, phone)")
        .eq("doctor_id", user["sub"])
        .in_("status", ["completed", "declined", "cancelled", "no_show"])
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
    b = fetch_one(
        supabase.table("bookings")
        .select("*, users(name, phone), doctors(name, photo_url, phone, categories(name))")
        .eq("id", booking_id)
    )
    if not b:
        raise AppError("Booking not found", 404)
    if b["patient_id"] != user["sub"] and b["doctor_id"] != user["sub"]:
        raise AppError("Forbidden", 403)
    return b


# ── Accept / Decline ──────────────────────────────────────────────────────────

@router.patch("/{booking_id}/accept")
def accept_booking(
    booking_id: str,
    background: BackgroundTasks,
    user: dict = Depends(require_doctor),
):
    """
    Accepting starts the payment hold: the patient has PAYMENT_HOLD_MINUTES to
    pay before the slot is released back to the doctor's calendar.
    """
    b = _get_booking_for_doctor(booking_id, user["sub"])
    if b["status"] != "requested":
        raise AppError(f"Cannot accept a booking with status '{b['status']}'", 400)

    updated = _update_status(booking_id, "accepted", {
        "hold_expires_at": (_now() + timedelta(minutes=PAYMENT_HOLD_MINUTES)).isoformat(),
    })

    doctor = supabase.table("doctors").select("name").eq("id", user["sub"]).execute().data or []
    doctor_name = (doctor[0].get("name") if doctor else None) or "Your doctor"
    notifications.booking_accepted({**b, **updated}, doctor_name, background)

    return updated


@router.patch("/{booking_id}/decline")
def decline_booking(
    booking_id: str,
    background: BackgroundTasks,
    user: dict = Depends(require_doctor),
):
    b = _get_booking_for_doctor(booking_id, user["sub"])
    if b["status"] not in ("requested", "accepted"):
        raise AppError(f"Cannot decline a booking with status '{b['status']}'", 400)

    updated = _update_status(booking_id, "declined", {"hold_expires_at": None})

    doctor = supabase.table("doctors").select("name").eq("id", user["sub"]).execute().data or []
    doctor_name = (doctor[0].get("name") if doctor else None) or "The doctor"
    notifications.booking_declined({**b, **updated}, doctor_name, background)

    return updated


# ── Complete ──────────────────────────────────────────────────────────────────

@router.patch("/{booking_id}/complete")
def complete_booking(
    booking_id: str,
    background: BackgroundTasks,
    user: dict = Depends(require_doctor),
):
    b = _get_booking_for_doctor(booking_id, user["sub"])
    if b["status"] not in ("accepted", "paid"):
        raise AppError(f"Cannot complete a booking with status '{b['status']}'", 400)

    updated = _update_status(booking_id, "completed", {"hold_expires_at": None})
    notifications.visit_completed({**b, **updated}, background)
    return updated


# ── Running late ──────────────────────────────────────────────────────────────

class RunningLate(BaseModel):
    minutes: int = Field(gt=0, le=180)


@router.post("/{booking_id}/running-late")
def running_late(
    booking_id: str,
    body: RunningLate,
    background: BackgroundTasks,
    user: dict = Depends(require_doctor),
):
    """Doctor tells the patient they are delayed. No state change — a nudge only."""
    b = _get_booking_for_doctor(booking_id, user["sub"])
    if b["status"] not in ("accepted", "paid"):
        raise AppError("Only an active booking can be marked running late", 400)

    notifications.doctor_running_late(b, body.minutes, background)
    return {"ok": True, "minutes": body.minutes}


# ── No-show ───────────────────────────────────────────────────────────────────

@router.patch("/{booking_id}/no-show")
def mark_no_show(
    booking_id: str,
    background: BackgroundTasks,
    user: dict = Depends(require_doctor),
):
    """
    Patient never turned up. Terminal, and deliberately does not charge: no
    ledger entry is created, so the doctor earns nothing and the patient owes
    nothing. A paid booking cannot be flipped to no-show — that is a refund,
    which ops handles.
    """
    b = _get_booking_for_doctor(booking_id, user["sub"])
    if b["status"] != "accepted":
        raise AppError(
            f"Only an accepted, unpaid booking can be marked no-show (status is '{b['status']}')",
            400,
        )

    updated = _update_status(booking_id, "no_show", {
        "no_show_marked_by": user["sub"],
        "no_show_at": _now_iso(),
        "hold_expires_at": None,
    })
    notifications.marked_no_show({**b, **updated}, background)
    return updated


# ── Cancel ────────────────────────────────────────────────────────────────────

@router.patch("/{booking_id}/cancel")
def cancel_booking(
    booking_id: str,
    background: BackgroundTasks,
    user: dict = Depends(get_current_user),
):
    b = fetch_one(supabase.table("bookings").select("*").eq("id", booking_id))
    if not b:
        raise AppError("Booking not found", 404)
    if b["patient_id"] != user["sub"] and b["doctor_id"] != user["sub"]:
        raise AppError("Forbidden", 403)
    if b["status"] in ("completed", "cancelled", "declined", "no_show"):
        raise AppError(f"Cannot cancel a booking with status '{b['status']}'", 400)

    by = "patient" if b["patient_id"] == user["sub"] else "doctor"
    updated = _update_status(booking_id, "cancelled", {
        "cancelled_by": by,
        "hold_expires_at": None,
    })
    notifications.booking_cancelled({**b, **updated}, by, background)
    return updated


# ── Helpers ───────────────────────────────────────────────────────────────────

def _get_booking_for_doctor(booking_id: str, doctor_id: str) -> dict:
    booking = fetch_one(supabase.table("bookings").select("*").eq("id", booking_id))
    if not booking:
        raise AppError("Booking not found", 404)
    if booking["doctor_id"] != doctor_id:
        raise AppError("Forbidden", 403)
    return booking


def _update_status(booking_id: str, status: str, extra: Optional[dict] = None) -> dict:
    data: dict = {"status": status}
    if status in ("accepted", "declined"):
        data["decision_at"] = _now_iso()
    if extra:
        data.update(extra)
    return supabase.table("bookings").update(data).eq("id", booking_id).execute().data[0]
