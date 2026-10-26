"""
Maintenance endpoints — the jobs that have to run on a timer.

Authenticated with a shared secret in ``X-Cron-Secret`` rather than a user token,
because the caller is a scheduler (Fly machine cron, GitHub Actions, or an
external pinger), not a person. When CRON_SECRET is unset these are ops-only, so
a missing secret in development is inconvenient rather than dangerous.
"""
import hmac
import logging
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, Header
from typing import Optional

from ..config import CRON_SECRET
from ..db import supabase
from ..errors import AppError
from ..services import app_config, erasure, jobs, notifications, otp_store, refunds
# Imported for their job handlers: a tick must be able to run every kind
# that can be queued, whichever routes this instance has served.
from ..services import prescriptions, visits  # noqa: F401

logger = logging.getLogger(__name__)

router = APIRouter()


def require_cron(x_cron_secret: Optional[str] = Header(None)) -> bool:
    """
    Accept the shared secret. If none is configured, refuse rather than run
    open — an unauthenticated endpoint that mutates bookings is not acceptable
    just because a deploy forgot an env var.
    """
    if not CRON_SECRET:
        raise AppError("CRON_SECRET is not configured on this deployment", 503)
    # Constant-time: `!=` returns at the first differing byte, which leaks how
    # much of a guess was right.
    if not x_cron_secret or not hmac.compare_digest(x_cron_secret, CRON_SECRET):
        raise AppError("Invalid cron secret", 401)
    return True


@router.post("/release-expired-holds")
def release_expired_holds(_: bool = Depends(require_cron)):
    """
    Release bookings that can no longer go ahead, through the state machine
    (migration 0023), each in its own transaction with its own event:

    * accepted but unpaid after the payment window: cancelled by ``system``;
      any payment attempt still open is marked failed. A booking whose payment
      is being confirmed at this moment is skipped (SKIP LOCKED) and left to the
      payment, not cancelled under it.
    * requested but never answered: cancelled by ``system`` once the slot has
      started (it can never happen), or sooner if app_config
      ``request_expiry_minutes`` is set (decision N4).

    Both parties are told, and only after the row has actually moved.
    """
    released = [str(r) for r in (supabase.rpc("expire_payment_holds", {}).execute().data or [])]

    max_age = app_config.get("request_expiry_minutes")
    expired = [str(r) for r in (supabase.rpc("expire_stale_requests", {
        "p_max_age": f"{int(max_age)} minutes" if max_age else None,
    }).execute().data or [])]

    for booking in _bookings(released):
        notifications.booking_hold_expired(booking)
    for booking in _bookings(expired):
        notifications.request_expired(booking)

    return {
        "released": len(released),
        "booking_ids": released,
        "expired_requests": len(expired),
        "expired_request_ids": expired,
    }


def _bookings(ids: list[str]) -> list[dict]:
    if not ids:
        return []
    return (
        supabase.table("bookings").select("id, patient_id, doctor_id, channel, scheduled_start")
        .in_("id", ids).execute().data or []
    )


@router.post("/tick")
def tick(_: bool = Depends(require_cron)):
    """
    The every-minute heartbeat (Cloud Scheduler job ``charak-tick``):
    delivers notifications still waiting in the outbox (retries, scheduled
    sends, and inline attempts that never ran), then runs due jobs from the
    queue. Each part has its own time budget so a backlog in one can't starve
    the other, and the whole call stays well inside the scheduler's deadline.
    """
    outbox = notifications.sweep_outbox()
    queue = jobs.run_due(budget_seconds=40.0)
    # Backstop for the 72-hour completion: anything a lost job left waiting.
    try:
        completed = visits.complete_overdue()
    except Exception as exc:                       # noqa: BLE001 — never fail the tick
        logger.error("completion backstop failed: %r", exc)
        completed = None
    return {"notifications": outbox, "jobs": queue, "completed_overdue": completed}


@router.post("/retry-refunds")
def retry_refunds(_: bool = Depends(require_cron)):
    """
    Finish refunds a request didn't: send queued ones whose backoff has passed,
    reclaim attempts whose worker died mid-call, and ask Razorpay about refunds
    it accepted but never confirmed by webhook. Retries that run out land in
    the admin refunds queue. See services/refunds.py.
    """
    return refunds.sweep()


@router.post("/purge-expired-otps")
def purge_expired_otps(_: bool = Depends(require_cron)):
    """Drop OTP rows more than a day past expiry — they are dead weight and PII."""
    return {"deleted": otp_store.purge_expired()}


@router.post("/purge-old-rate-limit-hits")
def purge_old_rate_limit_hits(_: bool = Depends(require_cron)):
    """
    Drop rate_limit_hits rows older than a day. Every limiter in the app
    (services/rate_limit.py) looks back at most an hour, so nothing older than
    that is ever read again — it's pure growth otherwise, on a table written
    once per request to every rate-limited endpoint.
    """
    cutoff = (datetime.now(timezone.utc) - timedelta(days=1)).isoformat()
    deleted = (
        supabase.table("rate_limit_hits")
        .delete()
        .lt("created_at", cutoff)
        .execute()
        .data
        or []
    )
    # Idempotency keys share the 24-hour horizon: a client retries within
    # seconds or minutes, never a day later.
    keys = (
        supabase.table("idempotency_keys")
        .delete()
        .lt("created_at", cutoff)
        .execute()
        .data
        or []
    )
    return {"deleted": len(deleted), "idempotency_keys_deleted": len(keys)}


@router.post("/purge-deleted-accounts")
def purge_deleted_accounts(_: bool = Depends(require_cron)):
    """
    Purge the personal data of patients whose deletion grace window has closed.

    De-identified financial and clinical records are retained; only PII is
    scrubbed. Runs on the same cron schedule as the other maintenance jobs.
    """
    return erasure.purge_due()
