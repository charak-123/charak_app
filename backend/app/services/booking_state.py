"""
The booking state machine's one entry point.

Every booking status change goes through ``transition_booking()`` in Postgres
(migration 0023). It locks the row, checks the actor and the expected status,
looks the move up in ``booking_transitions``, applies it, and appends a
``booking_events`` row, all in one transaction. This module calls it and turns
a refusal into the HTTP error the apps already understand.

Routers still read the booking first, for authorisation and for the friendly
messages they already give ("This booking has not been paid for yet …"). The
database decides authoritatively; a router check is a courtesy, never the
guard.
"""
from __future__ import annotations

from typing import Optional

from ..db import supabase
from ..errors import AppError

# How a refused move reads to a person, per event: "Cannot <verb> a booking
# with status 'x'".
_VERBS = {
    "accept": "accept",
    "decline": "decline",
    "cancel": "cancel",
    "complete": "complete",
    "no_show": "mark as no-show",
    "pay": "confirm payment for",
    "hold_expire": "release",
    "request_expire": "expire",
}

CONFLICT_MESSAGE = "This booking was just updated. Refresh to see where it stands."


class TransitionRefused(AppError):
    """The state machine refused the move. ``outcome`` says why; ``status`` is
    where the booking actually stands (when known)."""

    def __init__(self, outcome: str, event: str, status: Optional[str]):
        self.outcome = outcome
        self.current_status = status
        if outcome == "not_found":
            super().__init__("Booking not found", 404)
        elif outcome == "forbidden":
            super().__init__("Forbidden", 403)
        elif outcome == "conflict":
            super().__init__(CONFLICT_MESSAGE, 409)
        elif outcome == "key_reused":
            super().__init__("This request key was already used for a different action.", 422)
        else:  # invalid
            verb = _VERBS.get(event, event.replace("_", " "))
            super().__init__(f"Cannot {verb} a booking with status '{status}'", 400)


def transition(
    booking_id: str,
    event: str,
    *,
    actor_role: str,
    actor_id: Optional[str] = None,
    expected: Optional[str] = None,
    patch: Optional[dict] = None,
    idempotency_key: Optional[str] = None,
    metadata: Optional[dict] = None,
) -> dict:
    """
    Move a booking by ``event`` and return the updated row. Raises
    ``TransitionRefused`` when the state machine says no.

    ``expected`` is the status the caller read and based its decision on: if
    the booking moved in the meantime, nothing changes and the caller gets a
    409 rather than acting on a stale read.
    """
    result = supabase.rpc("transition_booking", {
        "p_booking_id": booking_id,
        "p_event": event,
        "p_actor_role": actor_role,
        "p_actor_id": actor_id,
        "p_expected_status": expected,
        "p_patch": patch or {},
        "p_idempotency_key": idempotency_key,
        "p_metadata": metadata or {},
    }).execute().data or {}

    outcome = result.get("outcome")
    if outcome in ("ok", "replayed"):
        return result["booking"]
    raise TransitionRefused(outcome or "conflict", event, result.get("status"))


def timeline(booking_id: str) -> list[dict]:
    """Every recorded event for a booking, oldest first."""
    return (
        supabase.table("booking_events")
        .select("id, event, from_status, to_status, actor_role, actor_id, occurred_at, metadata")
        .eq("booking_id", booking_id)
        .order("occurred_at")
        .order("id")
        .execute()
        .data
        or []
    )
