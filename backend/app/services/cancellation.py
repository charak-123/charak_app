"""
Cancellation policies and quotes (``policies``, ``cancellation_quote()``,
migration 0024).

A booking keeps the policy version it was made under. The refund for a
cancellation is calculated in one place, the ``cancellation_quote()`` SQL
function, and the cancel itself uses that same function. So the amount a
patient is shown and the amount refunded can't disagree. If the outcome moves
between the two (the doctor started travelling a moment earlier), the cancel
refuses with 409 and the new quote, and the patient confirms again.
"""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Optional

from ..db import fetch_one, supabase
from ..errors import AppError

# Structured reasons (with "other" for anything else), so cancellations can be
# counted by cause instead of read one by one.
REASON_CODES = {
    "patient": ("schedule_conflict", "feeling_better", "booked_elsewhere",
                "doctor_running_late", "price", "other"),
    "doctor": ("emergency", "unavailable", "outside_service_area", "patient_request", "other"),
}


def current_policy(channel: str) -> dict:
    """The version a booking made now would get."""
    # Only a version someone has approved (the legal review gate, migration
    # 0029) is ever offered.
    rows = (
        supabase.table("policies")
        .select("id, channel, version, rules, summary, effective_from, policy_approvals!inner(id)")
        .eq("kind", "cancellation").eq("channel", channel)
        .lte("effective_from", datetime.now(timezone.utc).isoformat())
        .order("effective_from", desc=True).limit(1)
        .execute().data or []
    )
    if not rows:
        raise AppError("No cancellation policy is published for this kind of booking", 503)
    rows[0].pop("policy_approvals", None)
    return rows[0]


def policy_by_id(policy_id: Optional[str]) -> Optional[dict]:
    if not policy_id:
        return None
    return fetch_one(
        supabase.table("policies").select("id, channel, version, rules, summary")
        .eq("id", policy_id)
    )


def free_cancellation_minutes(rules: list) -> Optional[int]:
    """
    How long before the start a cancellation stops being a full refund: the
    widest time window among the rules that refund less than 100%. None when
    no time-based rule reduces the refund. Mirrors cancellation_quote().
    """
    windows = [
        int(r["when"]["minutes_before_start_lt"])
        for r in rules or []
        if int(r.get("refund_pct", 100)) < 100 and "minutes_before_start_lt" in (r.get("when") or {})
    ]
    return max(windows) if windows else None


def public_policy(policy: dict) -> dict:
    """What the apps show before and after booking."""
    return {
        "channel": policy["channel"],
        "version": policy["version"],
        "summary": policy["summary"],
        "free_cancellation_minutes": free_cancellation_minutes(policy.get("rules")),
        "points": points(policy),
        "refund_timing": REFUND_TIMING,
    }


# What the Cancellation & Refund Policy (docs/legal) promises about timing.
REFUND_TIMING = "Refunds go back to the way you paid, usually within 5 to 7 working days."


def _duration(minutes: int) -> str:
    if minutes % 60 == 0:
        hours = minutes // 60
        return f"{hours} hour{'s' if hours != 1 else ''}"
    return f"{minutes} minutes"


def _outcome(pct: int) -> tuple[str, str]:
    if pct >= 100:
        return "Full refund", "full"
    if pct <= 0:
        return "No refund", "none"
    return f"{pct}% refund", "partial"


def _patient_points(channel: str, rules: list) -> list[dict]:
    """
    The patient's own cancellation, one line per rule, earliest first, from
    the rules cancellation_quote() applies. Only the shapes that function
    understands (journey_started, minutes_before_start_lt, the catch-all);
    anything else returns [] and the apps show the summary alone rather than
    a description that might not match the refund.
    """
    visit = "visit" if channel == "home_visit" else "consultation"
    journey, timed, catch_all = None, [], None
    for rule in rules or []:
        when = rule.get("when") or {}
        pct = int(rule.get("refund_pct", 100))
        if set(when) - {"journey_started", "minutes_before_start_lt"}:
            return []
        if when.get("journey_started") is True and len(when) == 1:
            journey = journey if journey is not None else pct
        elif set(when) == {"minutes_before_start_lt"}:
            timed.append((int(when["minutes_before_start_lt"]), pct))
        elif not when:
            catch_all = pct
            break                                  # nothing after it can match
        else:
            return []

    out = []
    timed.sort(reverse=True)
    travelling = " and the doctor hasn't set out" if journey is not None else ""
    if catch_all is not None:
        when = (f"You cancel {_duration(timed[0][0])} or more before the {visit}"
                if timed else f"You cancel any time before the {visit} starts")
        out.append((when, catch_all))
    for i, (minutes, pct) in enumerate(timed):
        when = f"You cancel less than {_duration(minutes)} before the {visit}{travelling}"
        if i + 1 < len(timed):
            when = (f"You cancel between {_duration(timed[i + 1][0])} and {_duration(minutes)} "
                    f"before the {visit}{travelling}")
        out.append((when, pct))
    if journey is not None:
        out.append(("You cancel after the doctor has started travelling", journey))
    return [{"when": w, "outcome": _outcome(p)[0], "tone": _outcome(p)[1]} for w, p in out]


def points(policy: dict) -> list[dict]:
    """
    Every case the Cancellation & Refund Policy covers for this kind of
    booking, as {when, outcome, tone}: the patient's own cancellation from the
    policy's rules, then what happens when the doctor cancels, moves the
    booking or doesn't come, from the same settings the backend enforces.
    tone is full / partial / none / choice, for colour.
    """
    from . import incidents                       # imports notifications; keep this module light
    from .app_config import get as config

    channel = policy["channel"]
    grace = incidents.grace_minutes(channel)
    remedy_hours = int(config("remedy_default_refund_hours", 24) or 24)
    absent = (f"The doctor hasn't arrived {grace} minutes after the start" if channel == "home_visit"
              else f"The doctor hasn't joined {grace} minutes after the start")
    moved = ("The doctor can't keep the time" if channel == "home_visit"
             else "The doctor can't keep the time, or the call fails")
    return [
        {"when": "You withdraw your request before the doctor accepts",
         "outcome": "Nothing is charged", "tone": "full"},
        *_patient_points(channel, policy.get("rules")),
        {"when": "The doctor cancels", "outcome": "Full refund", "tone": "full"},
        {"when": moved, "outcome": "A new time or a full refund, your choice", "tone": "choice"},
        {"when": absent,
         "outcome": f"A full refund or another doctor, your choice (refunded if you don't choose "
                    f"within {remedy_hours} hours)", "tone": "choice"},
        {"when": "You miss the " + ("visit" if channel == "home_visit" else "consultation"),
         "outcome": "No refund", "tone": "none"},
    ]


def quote(booking_id: str, actor_role: str) -> dict:
    """What cancelling now would refund, per the booking's own policy version."""
    q = supabase.rpc("cancellation_quote", {
        "p_booking_id": booking_id, "p_actor_role": actor_role,
    }).execute().data
    if not q:
        raise AppError("Booking not found", 404)
    return q


def validate_reason(role: str, reason_code: Optional[str]) -> Optional[str]:
    if reason_code is None:
        return None
    allowed = REASON_CODES.get(role, ())
    if reason_code not in allowed:
        raise AppError(f"reason_code must be one of: {', '.join(allowed)}", 400)
    return reason_code
