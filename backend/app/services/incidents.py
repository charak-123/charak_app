"""
When a visit goes wrong (migration 0028; spec §12.6–12.7, §13; decisions
D5–D10 at their recommended defaults).

An incident records what was reported, by whom, the evidence at that moment
(the slot, the journey, who joined the call) and, separately, what was
decided. Nothing about it is erased: every step is an incident_event.

    reported ──doctor responds──▶ under_review ──ops──▶ confirmed | dismissed | undetermined
        │                                                   │
        └── online, clear evidence, no response in 48 h ────┘ (confirmed)
    confirmed ──doctor appeals (7 days, once)──▶ appealed ──ops──▶ upheld | reversed

Only incidents that are confirmed, caused by the doctor and not reversed on
appeal count against the doctor's reliability, which is kept apart from the
patient-experience rating (spec §12.6). An unconfirmed report never changes it.

The patient's remedy doesn't wait for that verdict when the evidence already
supports it: a home visit with no journey after the grace period, or an
online consult the doctor never joined. Otherwise ops decides
(services/remedies.py does the money).
"""
from __future__ import annotations

import logging
from datetime import datetime, timedelta, timezone
from typing import Optional

from ..db import fetch_one, supabase
from ..errors import AppError
from . import app_config, notifications

logger = logging.getLogger(__name__)

REPORT_TYPES = {
    # what the patient pressed → (incident type, statuses it can be reported from)
    "doctor_not_arrived": ("doctor_no_show", ("paid",)),
    "doctor_not_joined": ("doctor_no_show", ("paid",)),
    "call_failed": ("technical", ("paid", "in_progress")),
    "other": ("other", ("paid", "in_progress", "consulted")),
}
CAUSES = ("doctor", "patient", "platform", "mutual", "undetermined")
DECISIONS = ("confirmed", "dismissed", "undetermined")
RELIABILITY_DAYS = 90
AUTO_CONFIRM_AFTER = timedelta(hours=48)
_DEFAULT_GRACE = {"home_visit": 30, "online_consult": 10}

_PUBLIC = ("id", "case_ref", "booking_id", "type", "reported_as", "reported_by_role", "cause", "status",
           "patient_note", "doctor_response", "doctor_responded_at", "decided_at", "decision_reason",
           "appeal_status", "appeal_note", "appealed_at", "appeal_decided_at", "appeal_reason",
           "remedy_eligible", "remedy", "remedy_booking_id", "auto_confirm_at", "created_at")


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _ts(value) -> Optional[datetime]:
    if not value:
        return None
    return datetime.fromisoformat(str(value).replace("Z", "+00:00"))


def public(incident: dict) -> dict:
    return {k: incident.get(k) for k in _PUBLIC}


def get(incident_id: str) -> Optional[dict]:
    return fetch_one(supabase.table("incidents").select("*").eq("id", incident_id))


def event(incident_id: str, name: str, actor_role: str, actor_id: Optional[str],
          note: Optional[str] = None, metadata: Optional[dict] = None) -> None:
    supabase.table("incident_events").insert({
        "incident_id": incident_id, "event": name, "actor_role": actor_role,
        "actor_id": actor_id, "note": note, "metadata": metadata or {},
    }).execute()


def grace_minutes(channel: str) -> int:
    cfg = app_config.get("no_show_grace_minutes", _DEFAULT_GRACE) or {}
    return int(cfg.get(channel, _DEFAULT_GRACE.get(channel, 15)))


def help_opens_at(booking: dict) -> datetime:
    """When "Doctor hasn't arrived/joined?" becomes available (D5, D6)."""
    return _ts(booking["scheduled_start"]) + timedelta(minutes=grace_minutes(booking["channel"]))


def open_for_booking(booking_id: str) -> Optional[dict]:
    rows = (
        supabase.table("incidents").select("*").eq("booking_id", booking_id)
        .order("created_at", desc=True).limit(1).execute().data or []
    )
    return rows[0] if rows else None


# ── The patient reports ──────────────────────────────────────────────────────

def _evidence(booking: dict) -> dict:
    joins = (
        supabase.table("call_joins").select("actor_role, kind, joined_at")
        .eq("booking_id", booking["id"]).order("joined_at").execute().data or []
    )
    return {
        "scheduled_start": booking["scheduled_start"],
        "channel": booking["channel"],
        "status": booking["status"],
        "journey_started_at": booking.get("journey_started_at"),
        "started_at": booking.get("started_at"),
        "patient_joined": any(j["actor_role"] == "patient" and j["kind"] == "consultation" for j in joins),
        "doctor_joined": any(j["actor_role"] == "doctor" and j["kind"] == "consultation" for j in joins),
        "reported_at": _now().isoformat(),
    }


def report(booking_id: str, patient_id: str, reported_as: str, note: Optional[str],
           background=None) -> dict:
    """The patient says something went wrong. Returns the incident, with
    whether a refund or another doctor can be offered right away."""
    if reported_as not in REPORT_TYPES:
        raise AppError("Choose what happened", 400)
    booking = fetch_one(supabase.table("bookings").select("*").eq("id", booking_id))
    if not booking or booking["patient_id"] != patient_id:
        raise AppError("Booking not found", 404)
    existing = open_for_booking(booking_id)
    if existing and existing["status"] in ("reported", "under_review") and existing["reported_by_role"] == "patient":
        return existing                                    # pressing again shows the same case

    incident_type, statuses = REPORT_TYPES[reported_as]
    if booking["status"] not in statuses:
        raise AppError("This visit can't be reported that way now. Contact support from Profile.", 409)
    if reported_as == "doctor_not_arrived" and booking["channel"] != "home_visit":
        raise AppError("This is an online consultation", 400)
    if reported_as == "doctor_not_joined" and booking["channel"] != "online_consult":
        raise AppError("This is a home visit", 400)
    if reported_as in ("doctor_not_arrived", "doctor_not_joined") and _now() < help_opens_at(booking):
        opens = help_opens_at(booking).astimezone(timezone(timedelta(hours=5, minutes=30)))
        raise AppError(f"Doctors get {grace_minutes(booking['channel'])} minutes' grace. You can report "
                       f"this from {opens.strftime('%-I:%M %p')}.", 409, opens_at=help_opens_at(booking).isoformat())

    evidence = _evidence(booking)
    # Clear evidence: a remedy now, and (online) confirmation unless the doctor
    # answers within 48 hours. Conflicting evidence goes to ops first.
    eligible, auto_confirm, status = False, None, "reported"
    if reported_as == "doctor_not_arrived":
        eligible = evidence["journey_started_at"] is None
        if not eligible:
            status = "under_review"
    elif reported_as == "doctor_not_joined":
        eligible = not evidence["doctor_joined"]
        if not eligible:
            status = "under_review"
        elif evidence["patient_joined"]:
            auto_confirm = (_now() + AUTO_CONFIRM_AFTER).isoformat()

    try:
        row = supabase.table("incidents").insert({
            "booking_id": booking_id, "doctor_id": booking["doctor_id"], "patient_id": patient_id,
            "type": incident_type, "reported_as": reported_as, "reported_by_role": "patient",
            "reported_by": patient_id, "status": status, "evidence": evidence,
            "patient_note": (note or "").strip()[:1000] or None,
            "auto_confirm_at": auto_confirm,
            "remedy_eligible": eligible, "remedy": "pending" if eligible else "none",
            "remedy_offered_at": _now().isoformat() if eligible else None,
        }).execute().data[0]
    except Exception as exc:                       # noqa: BLE001
        if "23505" in str(exc):                    # a report raced this one
            return open_for_booking(booking_id)
        raise
    event(row["id"], "reported", "patient", patient_id, row["patient_note"],
          {"reported_as": reported_as, "remedy_eligible": eligible})
    notifications.incident_reported_to_doctor(row, background)
    return row


# ── The doctor's side ────────────────────────────────────────────────────────

def respond(incident_id: str, doctor_id: str, note: str) -> dict:
    """The doctor's account of what happened. It goes to ops; an automatic
    confirmation no longer applies."""
    note = (note or "").strip()
    if len(note) < 5:
        raise AppError("Say what happened", 400)
    inc = get(incident_id)
    if not inc or inc["doctor_id"] != doctor_id:
        raise AppError("Case not found", 404)
    if inc["status"] not in ("reported", "under_review"):
        raise AppError("This case has been decided. If it counts against you, you can appeal it.", 409)
    if inc.get("doctor_responded_at"):
        raise AppError("You've already responded to this case", 409)
    row = supabase.table("incidents").update({
        "doctor_response": note[:1000], "doctor_responded_at": _now().isoformat(),
        "status": "under_review", "auto_confirm_at": None,
    }).eq("id", incident_id).execute().data[0]
    event(incident_id, "doctor_responded", "doctor", doctor_id, note[:1000])
    return row


def appeal(incident_id: str, doctor_id: str, note: str) -> dict:
    """Once, within the appeal window after a decision that counts (D10)."""
    note = (note or "").strip()
    if len(note) < 10:
        raise AppError("Explain why this shouldn't count", 400)
    inc = get(incident_id)
    if not inc or inc["doctor_id"] != doctor_id:
        raise AppError("Case not found", 404)
    if not counts(inc):
        raise AppError("Only a confirmed case that counts against you can be appealed", 409)
    if inc["appeal_status"] != "none":
        raise AppError("A case can be appealed once", 409)
    days = int(app_config.get("incident_appeal_days", 7) or 7)
    if _now() > _ts(inc["decided_at"]) + timedelta(days=days):
        raise AppError(f"Appeals are open for {days} days after a decision", 409)
    row = supabase.table("incidents").update({
        "appeal_status": "appealed", "appeal_note": note[:1000], "appealed_at": _now().isoformat(),
    }).eq("id", incident_id).execute().data[0]
    event(incident_id, "appealed", "doctor", doctor_id, note[:1000])
    return row


# ── Ops ──────────────────────────────────────────────────────────────────────

def decide(incident_id: str, ops: dict, status: str, cause: str, reason: str,
           offer_remedy: bool = False, background=None) -> dict:
    reason = (reason or "").strip()
    if status not in DECISIONS or cause not in CAUSES:
        raise AppError("Choose an outcome and a cause", 400)
    if len(reason) < 5:
        raise AppError("Give the reason for this decision", 400)
    if status == "confirmed" and cause == "undetermined":
        raise AppError("A confirmed case needs a cause. If it can't be told, mark it undetermined.", 400)
    inc = get(incident_id)
    if not inc:
        raise AppError("Case not found", 404)
    if inc["appeal_status"] == "appealed":
        raise AppError("This case is under appeal; decide the appeal instead", 409)
    patch = {"status": status, "cause": cause, "decision_reason": reason,
             "decided_by": ops.get("sub"), "decided_at": _now().isoformat(), "auto_confirm_at": None}
    if offer_remedy and not inc["remedy_eligible"]:
        patch.update({"remedy_eligible": True, "remedy": "pending", "remedy_offered_at": _now().isoformat()})
    row = supabase.table("incidents").update(patch).eq("id", incident_id).execute().data[0]
    event(incident_id, f"decided_{status}", "ops", ops.get("sub"), reason,
          {"cause": cause, "offer_remedy": offer_remedy, "before": {"status": inc["status"], "cause": inc["cause"]}})
    notifications.incident_decided(row, background)
    return row


def decide_appeal(incident_id: str, ops: dict, outcome: str, reason: str, background=None) -> dict:
    reason = (reason or "").strip()
    if outcome not in ("upheld", "reversed") or len(reason) < 5:
        raise AppError("Choose upheld or reversed, and give the reason", 400)
    inc = get(incident_id)
    if not inc or inc["appeal_status"] != "appealed":
        raise AppError("There's no open appeal on this case", 409)
    row = supabase.table("incidents").update({
        "appeal_status": outcome, "appeal_reason": reason,
        "appeal_decided_at": _now().isoformat(), "appeal_decided_by": ops.get("sub"),
    }).eq("id", incident_id).execute().data[0]
    event(incident_id, f"appeal_{outcome}", "ops", ops.get("sub"), reason)
    notifications.incident_decided(row, background)
    return row


def _doctor_showed_up(booking_id: Optional[str]) -> bool:
    """True if the doctor has joined the call, or the booking has moved past
    `paid`, since the report was filed."""
    if not booking_id:
        return False
    booking = supabase.table("bookings").select("status").eq("id", booking_id).execute().data or []
    if booking and booking[0].get("status") in ("in_progress", "consulted", "completed"):
        return True
    joins = (
        supabase.table("call_joins").select("id").eq("booking_id", booking_id)
        .eq("actor_role", "doctor").eq("kind", "consultation").limit(1).execute().data or []
    )
    return bool(joins)


def auto_confirm_due(now: Optional[datetime] = None) -> int:
    """D7: an online no-show with clear evidence that the doctor didn't
    answer within 48 hours is confirmed."""
    rows = (
        supabase.table("incidents").select("id, booking_id")
        .eq("status", "reported").lte("auto_confirm_at", (now or _now()).isoformat())
        .limit(50).execute().data or []
    )
    for r in rows:
        if _doctor_showed_up(r.get("booking_id")):
            # The evidence behind the timer was a snapshot taken when the patient
            # reported. The doctor has joined, or the visit has gone ahead, since:
            # naming them at fault now would be wrong, so a person decides.
            moved = (
                supabase.table("incidents").update({"status": "under_review", "auto_confirm_at": None})
                .eq("id", r["id"]).eq("status", "reported").execute().data or []
            )
            if moved:
                event(r["id"], "needs_review", "system", None,
                      "the doctor joined or the visit went ahead after the report")
            continue
        updated = (
            supabase.table("incidents").update({
                "status": "confirmed", "cause": "doctor", "decided_at": _now().isoformat(),
                "decision_reason": "The patient joined and the doctor didn't, and the doctor didn't "
                                   "respond within 48 hours.",
                "auto_confirm_at": None,
            }).eq("id", r["id"]).eq("status", "reported").execute().data or []
        )
        if updated:
            event(r["id"], "decided_confirmed", "system", None, "automatic after 48 hours")
            notifications.incident_decided(updated[0])
    return len(rows)


def record_late_cancel(booking: dict, background=None) -> Optional[dict]:
    """A doctor cancelling a paid visit close to its start is an incident they
    caused (they can appeal, say for an emergency)."""
    minutes = int(app_config.get("doctor_late_cancel_minutes", 120) or 120)
    start = _ts(booking["scheduled_start"])
    if start - _now() > timedelta(minutes=minutes):
        return None
    row = supabase.table("incidents").insert({
        "booking_id": booking["id"], "doctor_id": booking["doctor_id"], "patient_id": booking["patient_id"],
        "type": "doctor_late_cancel", "reported_by_role": "system", "cause": "doctor", "status": "confirmed",
        "decided_at": _now().isoformat(),
        "decision_reason": f"The doctor cancelled a paid visit less than {minutes // 60} hours before it.",
        "evidence": {"scheduled_start": booking["scheduled_start"], "cancelled_at": _now().isoformat()},
    }).execute().data[0]
    event(row["id"], "recorded", "system", None, "doctor cancelled late")
    notifications.incident_decided(row, background)
    return row


# ── Reliability ──────────────────────────────────────────────────────────────

def counts(inc: dict) -> bool:
    """Whether an incident counts against the doctor: confirmed, the doctor's
    doing, and not reversed on appeal. Nothing unverified ever counts."""
    return inc.get("status") == "confirmed" and inc.get("cause") == "doctor" \
        and inc.get("appeal_status") != "reversed"


def reliability(doctor_id: str, now: Optional[datetime] = None) -> dict:
    """Visits kept over the last 90 days: those that went ahead, against those
    plus the ones that count against the doctor."""
    since = ((now or _now()) - timedelta(days=RELIABILITY_DAYS)).isoformat()
    held = (
        supabase.table("bookings").select("id", count="exact")
        .eq("doctor_id", doctor_id).in_("status", ["in_progress", "consulted", "completed"])
        .gte("scheduled_start", since).execute()
    )
    held_n = held.count if getattr(held, "count", None) is not None else len(held.data or [])
    incidents = (
        supabase.table("incidents").select("*").eq("doctor_id", doctor_id)
        .gte("created_at", since).order("created_at", desc=True).execute().data or []
    )
    counted = [i for i in incidents if counts(i)]
    total = held_n + len(counted)
    return {
        "days": RELIABILITY_DAYS,
        "visits_kept": held_n,
        "counted": len(counted),
        "kept_pct": round(100 * held_n / total) if total else None,
        "explanation": "Visits that went ahead in the last 90 days, out of those plus the cases our "
                       "team confirmed were yours: not arriving or joining, cancelling within 2 hours, "
                       "or moving a visit for your own reasons. Reports that aren't confirmed, and "
                       "anything outside your control, never count. You can appeal a decision "
                       "within 7 days.",
    }


def doctor_cases(doctor_id: str, limit: int = 50) -> list[dict]:
    rows = (
        supabase.table("incidents").select("*").eq("doctor_id", doctor_id)
        .order("created_at", desc=True).limit(limit).execute().data or []
    )
    days = int(app_config.get("incident_appeal_days", 7) or 7)
    out = []
    for i in rows:
        item = public(i)
        item.pop("patient_note", None)              # the patient's own words stay with ops
        item["counts"] = counts(i)
        decided = _ts(i.get("decided_at"))
        item["can_respond"] = i["status"] in ("reported", "under_review") and not i.get("doctor_responded_at")
        item["can_appeal"] = counts(i) and i["appeal_status"] == "none" and decided is not None \
            and _now() <= decided + timedelta(days=days)
        out.append(item)
    return out


def ops_queue(view: str = "open", limit: int = 200) -> list[dict]:
    q = supabase.table("incidents").select("*, bookings(channel, scheduled_start, status), "
                                           "doctors(name), users(name)")
    if view == "open":
        q = q.in_("status", ["reported", "under_review"])
    elif view == "appealed":
        q = q.eq("appeal_status", "appealed")
    rows = q.order("created_at").limit(limit).execute().data or []
    for r in rows:
        r["events"] = (supabase.table("incident_events").select("event, actor_role, note, occurred_at")
                       .eq("incident_id", r["id"]).order("occurred_at").execute().data or [])
    return rows
