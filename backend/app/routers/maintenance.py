"""
Maintenance endpoints — the jobs that have to run on a timer.

Authenticated with a shared secret in ``X-Cron-Secret`` rather than a user token,
because the caller is a scheduler (Fly machine cron, GitHub Actions, or an
external pinger), not a person. When CRON_SECRET is unset these are ops-only, so
a missing secret in development is inconvenient rather than dangerous.
"""
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, Header
from typing import Optional

from ..config import CRON_SECRET
from ..db import supabase
from ..errors import AppError
from ..services import notifications, otp_store

router = APIRouter()


def require_cron(x_cron_secret: Optional[str] = Header(None)) -> bool:
    """
    Accept the shared secret. If none is configured, refuse rather than run
    open — an unauthenticated endpoint that mutates bookings is not acceptable
    just because a deploy forgot an env var.
    """
    if not CRON_SECRET:
        raise AppError("CRON_SECRET is not configured on this deployment", 503)
    if not x_cron_secret or x_cron_secret != CRON_SECRET:
        raise AppError("Invalid cron secret", 401)
    return True


@router.post("/release-expired-holds")
def release_expired_holds(_: bool = Depends(require_cron)):
    """
    Release accepted-but-unpaid bookings whose payment window has closed.

    Without this a patient who never pays holds a doctor's slot forever. The
    booking is cancelled by ``system`` so it is distinguishable from a real
    cancellation in reporting, and both parties are told.
    """
    now = datetime.now(timezone.utc).isoformat()

    expired = (
        supabase.table("bookings")
        .select("*")
        .eq("status", "accepted")
        .lt("hold_expires_at", now)
        .execute()
        .data
        or []
    )

    if not expired:
        return {"released": 0, "booking_ids": []}

    booking_ids = [b["id"] for b in expired]

    # Two statements for the whole batch rather than two per booking. This runs
    # on a timer with no user waiting on it, but a backlog (a queue stall, a
    # missed run) is exactly when it is largest and least affordable.
    supabase.table("bookings").update({
        "status": "cancelled",
        "cancelled_by": "system",
        "hold_expires_at": None,
    }).in_("id", booking_ids).execute()

    supabase.table("payments").update({"status": "failed"}) \
        .in_("booking_id", booking_ids).eq("status", "initiated").execute()

    # Only once the rows are actually released — a notification about a hold
    # that is still live would be a lie.
    for booking in expired:
        notifications.booking_hold_expired(booking)

    return {"released": len(booking_ids), "booking_ids": booking_ids}


@router.post("/purge-expired-otps")
def purge_expired_otps(_: bool = Depends(require_cron)):
    """Drop OTP rows more than a day past expiry — they are dead weight and PII."""
    return {"deleted": otp_store.purge_expired()}
