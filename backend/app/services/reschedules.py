"""
A doctor can't make a visit, or the call failed (spec §13.2): they propose up
to three new times and say why. The patient picks one (the same booking moves
there, at the same price) or takes a full refund. No answer within 24 hours
and the patient is refunded.

Every reschedule is recorded as an incident with the doctor's stated cause.
"I wasn't available" or "my device/network" is the doctor's doing and counts
towards reliability straight away (they said so); the patient's connection,
a platform fault or a mutual agreement doesn't; "other" goes to ops.
"""
from __future__ import annotations

import logging
from datetime import datetime, timedelta, timezone
from typing import Optional

from ..db import fetch_one, supabase
from ..errors import AppError
from . import app_config, availability, incidents, notifications, remedies

logger = logging.getLogger(__name__)

CAUSES = {
    # doctor's stated cause → (incident cause, status)
    "doctor_unavailable": ("doctor", "confirmed"),
    "doctor_device": ("doctor", "confirmed"),
    "patient_device": ("patient", "confirmed"),
    "platform": ("platform", "confirmed"),
    "mutual": ("mutual", "confirmed"),
    "other": ("undetermined", "reported"),
}
MAX_OPTIONS = 3
MIN_LEAD = timedelta(minutes=30)


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _ts(value) -> datetime:
    return value if isinstance(value, datetime) else datetime.fromisoformat(str(value).replace("Z", "+00:00"))


def open_for_booking(booking_id: str) -> Optional[dict]:
    return fetch_one(supabase.table("reschedule_requests").select("*")
                     .eq("booking_id", booking_id).eq("status", "proposed"))


def propose(booking_id: str, doctor_id: str, cause: str, options: list[str],
            note: Optional[str], background=None) -> dict:
    if cause not in CAUSES:
        raise AppError("Say why the visit needs to move", 400)
    if not 1 <= len(options) <= MAX_OPTIONS:
        raise AppError(f"Offer between 1 and {MAX_OPTIONS} new times", 400)
    booking = fetch_one(supabase.table("bookings").select("*").eq("id", booking_id))
    if not booking or booking["doctor_id"] != doctor_id:
        raise AppError("Booking not found", 404)
    if booking["status"] not in ("paid", "in_progress"):
        raise AppError("Only a confirmed visit that hasn't ended can be moved", 409)
    if open_for_booking(booking_id):
        raise AppError("You've already proposed new times for this visit", 409)

    duration = booking.get("duration_min") or 15
    starts = []
    for raw in options:
        try:
            start = _ts(raw)
        except ValueError:
            raise AppError("Times must look like 2026-11-02T10:30:00+05:30", 400)
        if start.tzinfo is None:
            raise AppError("Times must include a timezone offset", 400)
        if start < _now() + MIN_LEAD:
            raise AppError("New times must be at least 30 minutes from now", 400)
        local = availability.to_ist(start)
        grid = availability.get_available_slots(doctor_id, local.date(), days=1, duration_min=duration,
                                                channel=booking.get("channel"))
        if local.strftime("%H:%M") not in {s["start"] for s in grid.get(str(local.date()), [])}:
            raise AppError(f"{local.strftime('%-d %b, %-I:%M %p')} isn't open on your calendar for a "
                           f"{duration}-minute visit", 409)
        starts.append(start.isoformat())
    if len(set(starts)) != len(starts):
        raise AppError("Offer different times", 400)

    inc_cause, inc_status = CAUSES[cause]
    now = _now()
    inc = supabase.table("incidents").insert({
        "booking_id": booking_id, "doctor_id": doctor_id, "patient_id": booking["patient_id"],
        "type": "doctor_reschedule", "reported_by_role": "doctor", "reported_by": doctor_id,
        "cause": inc_cause, "status": inc_status,
        "decided_at": now.isoformat() if inc_status == "confirmed" else None,
        "decision_reason": f"The doctor moved the visit: {cause.replace('_', ' ')}."
                           if inc_status == "confirmed" else None,
        "doctor_response": (note or "").strip()[:1000] or None,
        "evidence": {"scheduled_start": booking["scheduled_start"], "status": booking["status"],
                     "stated_cause": cause},
        # The patient may prefer a refund to any new time.
        "remedy_eligible": True, "remedy": "pending", "remedy_offered_at": now.isoformat(),
    }).execute().data[0]
    incidents.event(inc["id"], "reschedule_proposed", "doctor", doctor_id, note, {"cause": cause})

    hours = int(app_config.get("reschedule_answer_hours", 24) or 24)
    req = supabase.table("reschedule_requests").insert({
        "booking_id": booking_id, "doctor_id": doctor_id, "incident_id": inc["id"], "cause": cause,
        "note": (note or "").strip()[:500] or None, "options": starts,
        "expires_at": (now + timedelta(hours=hours)).isoformat(),
    }).execute().data[0]
    notifications.reschedule_proposed(booking, background)
    return {**req, "case_ref": inc["case_ref"]}


def accept(request_id: str, patient_id: str, start: str, background=None) -> dict:
    result = supabase.rpc("accept_reschedule", {
        "p_request_id": request_id, "p_patient_id": patient_id, "p_start": start,
    }).execute().data or {}
    outcome = result.get("outcome")
    if outcome in ("not_found", "forbidden"):
        raise AppError("Request not found", 404)
    if outcome == "not_open":
        raise AppError("This request has closed", 409)
    if outcome == "bad_time":
        raise AppError("Pick one of the times your doctor offered", 400)
    if outcome == "slot_taken":
        raise AppError("That time has just been taken. Pick another, or take a refund.", 409)
    booking = result["booking"]
    # Reminders for the new time (the old ones find the start has moved and skip).
    from . import visits
    visits.schedule_reminders(booking)
    notifications.reschedule_answered(booking, accepted=True, background=background)
    return booking


def decline(request_id: str, patient_id: str, background=None) -> dict:
    """None of the times work: a full refund."""
    req = fetch_one(supabase.table("reschedule_requests").select("*").eq("id", request_id))
    booking = fetch_one(supabase.table("bookings").select("*").eq("id", req["booking_id"])) if req else None
    if not req or not booking or booking["patient_id"] != patient_id:
        raise AppError("Request not found", 404)
    if req["status"] != "proposed":
        raise AppError("This request has closed", 409)
    out = remedies.refund(req["incident_id"], "patient", patient_id, background)
    supabase.table("reschedule_requests").update({"status": "declined", "decided_at": _now().isoformat()}) \
        .eq("id", request_id).eq("status", "proposed").execute()
    notifications.reschedule_answered(booking, accepted=False, background=background)
    return out


def expire_due(now: Optional[datetime] = None) -> int:
    """No answer in time: the request lapses and the patient is refunded."""
    rows = (
        supabase.table("reschedule_requests").select("*")
        .eq("status", "proposed").lte("expires_at", (now or _now()).isoformat())
        .limit(50).execute().data or []
    )
    for req in rows:
        updated = (
            supabase.table("reschedule_requests").update({"status": "expired", "decided_at": _now().isoformat()})
            .eq("id", req["id"]).eq("status", "proposed").execute().data or []
        )
        if updated and req.get("incident_id"):
            try:
                remedies.refund(req["incident_id"], "system", None)
            except AppError as exc:
                logger.info("no refund on lapsed reschedule %s: %s", req["id"], exc.message)
    return len(rows)
