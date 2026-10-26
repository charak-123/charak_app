"""
The visit itself (migration 0025): Start Journey, starting the consultation,
call joins, appointment reminders, and the ops queues that watch them.

    paid ──start_consultation──▶ in_progress ──(prescription sent)──▶ consulted ──▶ completed

The consultation reaches 'consulted' only by the doctor sending a prescription
or consultation notes (services/prescriptions.py). There is no bare "end
consultation" button, so a booking can't sit in 'consulted' with nothing for the
patient to open, and so never complete.
"""
from __future__ import annotations

import logging
from datetime import datetime, timedelta, timezone
from typing import Optional

from ..db import fetch_one, supabase
from ..errors import AppError
from . import app_config, booking_state, jobs, notifications

logger = logging.getLogger(__name__)

# Start Journey opens this long before the slot (LD-005: tapping earlier would
# make a booking non-refundable for no reason).
JOURNEY_WINDOW_MINUTES = 120

_DEFAULT_START_WINDOW = {"online_consult": 15, "home_visit": 120}
_DEFAULT_REMINDERS = {"online_consult": [1440, 15], "home_visit": [1440, 120]}


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _ts(value) -> datetime:
    return datetime.fromisoformat(str(value).replace("Z", "+00:00"))


# ── Start Journey ────────────────────────────────────────────────────────────

def start_journey(booking_id: str, doctor_id: str, background=None) -> dict:
    """The doctor has left for a home visit. Server time, once, notified once."""
    result = supabase.rpc("start_journey", {
        "p_booking_id": booking_id, "p_doctor_id": doctor_id,
        "p_window_minutes": JOURNEY_WINDOW_MINUTES,
    }).execute().data or {}
    outcome = result.get("outcome")
    if outcome == "not_found":
        raise AppError("Booking not found", 404)
    if outcome == "forbidden":
        raise AppError("Forbidden", 403)
    if outcome == "too_early":
        opens = _ts(result["opens_at"]).astimezone(timezone(timedelta(hours=5, minutes=30)))
        raise AppError(
            f"Start journey opens 2 hours before the visit, at {opens.strftime('%-I:%M %p')}.",
            409, opens_at=result["opens_at"],
        )
    if outcome == "invalid":
        if result.get("channel") != "home_visit":
            raise AppError("Start journey is only for home visits", 400)
        raise AppError(f"A journey can't be started for a '{result.get('status')}' booking", 409)
    if outcome not in ("ok", "already_started"):
        raise AppError(booking_state.CONFLICT_MESSAGE, 409)

    booking = result["booking"]
    if outcome == "ok":
        notifications.journey_started(booking, background)
    return {"journey_started_at": booking["journey_started_at"],
            "already_started": outcome == "already_started", "booking": booking}


# ── The consultation ─────────────────────────────────────────────────────────

def start_window_minutes(channel: str) -> int:
    cfg = app_config.get("consultation_start_window_minutes", _DEFAULT_START_WINDOW) or {}
    return int(cfg.get(channel, _DEFAULT_START_WINDOW.get(channel, 15)))


def start_consultation(booking: dict, doctor_id: str, *, now: Optional[datetime] = None) -> dict:
    """
    paid → in_progress. Starting it ends the patient's right to cancel, so it
    opens only shortly before the slot. Starting it again is a no-op.
    """
    if booking["doctor_id"] != doctor_id:
        raise AppError("Forbidden", 403)
    if booking["status"] in ("in_progress", "consulted", "completed"):
        return booking
    if booking["status"] != "paid":
        raise AppError(f"A '{booking['status']}' booking can't start", 409)
    now = now or _now()
    opens = _ts(booking["scheduled_start"]) - timedelta(minutes=start_window_minutes(booking["channel"]))
    if now < opens:
        local = opens.astimezone(timezone(timedelta(hours=5, minutes=30)))
        raise AppError(f"The consultation can be started from {local.strftime('%-I:%M %p')}.",
                       409, opens_at=opens.isoformat())
    try:
        return booking_state.transition(booking["id"], "start_consultation", actor_role="doctor",
                                        actor_id=doctor_id, expected="paid")
    except booking_state.TransitionRefused as refused:
        if refused.current_status in ("in_progress", "consulted", "completed"):
            return fetch_one(supabase.table("bookings").select("*").eq("id", booking["id"])) or booking
        raise


# ── Call joins ───────────────────────────────────────────────────────────────

def record_call_join(booking: dict, actor_role: str, actor_id: str, kind: str) -> None:
    """Who joined the call, and when: evidence for "the doctor never joined"
    that doesn't rest on anyone's word. Best-effort; never blocks the call.
    The doctor joining a scheduled online consult starts the consultation."""
    try:
        supabase.table("call_joins").insert({
            "booking_id": booking["id"], "actor_role": actor_role,
            "actor_id": actor_id, "kind": kind,
        }).execute()
    except Exception as exc:                       # noqa: BLE001
        logger.error("could not record call join on %s: %r", booking["id"], exc)
    if (kind == "consultation" and actor_role == "doctor"
            and booking.get("status") == "paid" and booking.get("channel") == "online_consult"):
        try:
            start_consultation(booking, actor_id)
        except AppError:
            pass                                   # early join: the call still works


# ── Appointment reminders ────────────────────────────────────────────────────

def schedule_reminders(booking: dict, now: Optional[datetime] = None) -> int:
    """Queue reminders for a booking that has just been paid: to the patient
    and the doctor, at the configured minutes before the start. Times already
    past are skipped. Returns how many were queued."""
    try:
        cfg = app_config.get("appointment_reminders", _DEFAULT_REMINDERS) or {}
        offsets = cfg.get(booking.get("channel"), _DEFAULT_REMINDERS.get(booking.get("channel"), []))
        start = _ts(booking["scheduled_start"])
    except Exception as exc:                       # noqa: BLE001 — never fails the payment
        logger.error("no reminders for %s: %r", booking.get("id"), exc)
        return 0
    now = now or _now()
    queued = 0
    for minutes in offsets:
        when = start - timedelta(minutes=int(minutes))
        if when <= now:
            continue
        try:
            jobs.enqueue("booking.reminder", {"booking_id": booking["id"], "minutes": int(minutes)},
                         run_at=when, dedupe_key=f"booking-reminder:{booking['id']}:{minutes}")
            queued += 1
        except Exception as exc:                   # noqa: BLE001 — the payment has succeeded
            logger.error("could not queue reminder for %s: %r", booking["id"], exc)
    return queued


@jobs.handler("booking.reminder")
def _send_reminder(payload: dict) -> None:
    booking = fetch_one(supabase.table("bookings")
                        .select("id, patient_id, doctor_id, channel, status, scheduled_start")
                        .eq("id", payload["booking_id"]))
    # Only a booking that's still going ahead. A reminder for a cancelled or
    # moved visit is worse than none.
    if not booking or booking["status"] != "paid":
        return
    minutes = int(payload.get("minutes") or 0)
    if _ts(booking["scheduled_start"]) <= _now():
        return
    notifications.appointment_reminder(booking, "patient", minutes)
    notifications.appointment_reminder(booking, "doctor", minutes)


# ── Completion backstop ──────────────────────────────────────────────────────

def complete_overdue(now: Optional[datetime] = None, limit: int = 50) -> int:
    """
    The fallback's backstop. Each sent prescription queues its own completion
    job, but a job that died or was never queued would leave a booking in
    'consulted' forever. This completes any whose fallback time has passed.
    Run every tick; cheap, because 'consulted' bookings are few.
    """
    hours = int(app_config.get("completion_fallback_hours", 72) or 72)
    cutoff = ((now or _now()) - timedelta(hours=hours)).isoformat()
    rows = (
        supabase.table("bookings").select("id")
        .eq("status", "consulted").lte("prescription_sent_at", cutoff)
        .limit(limit).execute().data or []
    )
    done = 0
    for row in rows:
        result = supabase.rpc("complete_unviewed_booking", {"p_booking_id": row["id"]}).execute().data or {}
        if result.get("outcome") == "ok":
            done += 1
            after_completion(result.get("booking") or {"id": row["id"]}, "fallback")
    return done


def after_completion(booking: dict, source: str) -> None:
    """Tell the doctor the visit is complete and when the fee can be withdrawn."""
    from . import payouts                          # payouts imports nothing from here
    full = booking if booking.get("doctor_id") else fetch_one(
        supabase.table("bookings").select("*").eq("id", booking["id"])) or {}
    if not full.get("doctor_id"):
        return
    when = payouts.available_at({"source": "consult_fee", "bookings": full})
    notifications.visit_complete_to_doctor(full, source, when)
    # Two hours on, once: time to have left the visit behind, not to forget it.
    if full.get("patient_id"):
        notifications.review_prompt(full, deliver_after=_now() + timedelta(hours=2))


# ── Ops queues ───────────────────────────────────────────────────────────────

def ops_queues(now: Optional[datetime] = None) -> dict:
    """
    What ops should look at (spec §7.3, §17.2). Flags, not verdicts: a home
    visit with no journey near its time isn't assumed to be a no-show.

    * ``journey_not_started``: paid home visits starting within 30 minutes (or
      already started) with no Start Journey
    * ``prescription_overdue``: paid or in-progress bookings more than 2 hours
      past their start with nothing sent to the patient
    * ``prescription_unviewed``: sent more than 24 hours ago and not opened
    """
    now = now or _now()
    cols = "id, channel, status, scheduled_start, journey_started_at, prescription_sent_at, " \
           "patient_id, doctor_id, users(name), doctors(name)"
    journey = (
        supabase.table("bookings").select(cols)
        .eq("channel", "home_visit").eq("status", "paid").is_("journey_started_at", "null")
        .lte("scheduled_start", (now + timedelta(minutes=30)).isoformat())
        .gte("scheduled_start", (now - timedelta(hours=6)).isoformat())
        .order("scheduled_start").limit(200).execute().data or []
    )
    overdue = (
        supabase.table("bookings").select(cols)
        .in_("status", ["paid", "in_progress"])
        .lte("scheduled_start", (now - timedelta(hours=2)).isoformat())
        .order("scheduled_start").limit(200).execute().data or []
    )
    unviewed = (
        supabase.table("bookings").select(cols)
        .eq("status", "consulted").is_("prescription_viewed_at", "null")
        .lte("prescription_sent_at", (now - timedelta(hours=24)).isoformat())
        .order("prescription_sent_at").limit(200).execute().data or []
    )
    return {"journey_not_started": journey, "prescription_overdue": overdue,
            "prescription_unviewed": unviewed}
