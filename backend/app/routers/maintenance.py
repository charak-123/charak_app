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

    released = []
    for booking in expired:
        supabase.table("bookings").update({
            "status": "cancelled",
            "cancelled_by": "system",
            "hold_expires_at": None,
        }).eq("id", booking["id"]).execute()

        supabase.table("payments").update({"status": "failed"}) \
            .eq("booking_id", booking["id"]).eq("status", "initiated").execute()

        notifications.booking_hold_expired(booking)
        released.append(booking["id"])

    return {"released": len(released), "booking_ids": released}


@router.post("/purge-expired-otps")
def purge_expired_otps(_: bool = Depends(require_cron)):
    """Drop OTP rows more than a day past expiry — they are dead weight and PII."""
    return {"deleted": otp_store.purge_expired()}
