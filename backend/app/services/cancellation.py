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
    rows = (
        supabase.table("policies").select("id, channel, version, rules, summary, effective_from")
        .eq("kind", "cancellation").eq("channel", channel)
        .lte("effective_from", datetime.now(timezone.utc).isoformat())
        .order("effective_from", desc=True).limit(1)
        .execute().data or []
    )
    if not rows:
        raise AppError("No cancellation policy is published for this kind of booking", 503)
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
    }


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
