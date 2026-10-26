"""
Background jobs on a Postgres queue (``jobs``, migration 0023).

Work that must happen later or must survive a failed attempt (a reminder an
hour before a visit, a completion timer, a retry) is enqueued here instead of
being left to a FastAPI background task. Cloud Run can throttle a background
task's CPU once its response has gone, and it is lost if the instance stops.

    enqueue("visit.reminder", {"booking_id": ...}, run_at=..., dedupe_key=...)

``/maintenance/tick`` (Cloud Scheduler, every minute) calls ``run_due()``. It
claims due jobs with FOR UPDATE SKIP LOCKED, so overlapping ticks never run
one job twice, and runs each one's handler. A failed job is retried after 1,
2, 4 … minutes; after ``max_attempts`` it is 'dead' and stays visible.

Handlers must be idempotent: a job whose worker died mid-run is claimed again
once its lease expires.
"""
from __future__ import annotations

import logging
import time
from datetime import datetime
from typing import Callable, Optional

from ..db import supabase

logger = logging.getLogger(__name__)

HANDLERS: dict[str, Callable[[dict], None]] = {}

LEASE_SECONDS = 120


def handler(kind: str):
    """Register the function that runs jobs of ``kind``."""
    def register(fn: Callable[[dict], None]):
        if kind in HANDLERS and HANDLERS[kind] is not fn:
            raise ValueError(f"a handler for job kind {kind!r} is already registered")
        HANDLERS[kind] = fn
        return fn
    return register


def enqueue(kind: str, payload: Optional[dict] = None, *, run_at: Optional[datetime] = None,
            dedupe_key: Optional[str] = None, max_attempts: int = 8) -> Optional[int]:
    """Queue a job. With ``dedupe_key``, a second enqueue returns the first job's id."""
    if kind not in HANDLERS:
        # Caught at enqueue time rather than as a dead job hours later.
        raise ValueError(f"no handler registered for job kind {kind!r}")
    return supabase.rpc("enqueue_job", {
        "p_kind": kind,
        "p_payload": payload or {},
        "p_run_at": run_at.isoformat() if run_at else None,
        "p_dedupe_key": dedupe_key,
        "p_max_attempts": max_attempts,
    }).execute().data


def run_due(budget_seconds: float = 40.0, batch: int = 10,
            clock: Callable[[], float] = time.monotonic) -> dict:
    """Run due jobs until none are left or the time budget is spent."""
    started = clock()
    counts = {"done": 0, "retrying": 0, "dead": 0}
    while clock() - started < budget_seconds:
        jobs = supabase.rpc("claim_jobs", {
            "p_limit": batch, "p_lease_seconds": LEASE_SECONDS,
        }).execute().data or []
        if not jobs:
            break
        for job in jobs:
            fn = HANDLERS.get(job["kind"])
            try:
                if fn is None:
                    raise LookupError(f"no handler for job kind {job['kind']!r}")
                fn(job.get("payload") or {})
            except Exception as exc:                  # noqa: BLE001 — recorded on the job
                status = supabase.rpc("fail_job", {
                    "p_id": job["id"], "p_error": f"{type(exc).__name__}: {exc}",
                }).execute().data
                if status == "dead":
                    counts["dead"] += 1
                    logger.error("job %s (%s) is dead after %s attempts: %r",
                                 job["id"], job["kind"], job.get("attempts"), exc)
                else:
                    counts["retrying"] += 1
                    logger.warning("job %s (%s) failed, will retry: %r", job["id"], job["kind"], exc)
            else:
                supabase.rpc("finish_job", {"p_id": job["id"]}).execute()
                counts["done"] += 1
    return counts
