"""
The webhook inbox (``webhook_events``, migration 0023).

Providers deliver at least once, sometimes out of order, sometimes long after
the fact. Every delivery is recorded by the provider's own event id before it
is handled:

* first delivery: recorded, handled, marked processed;
* redelivery of a processed event: acknowledged, not handled again;
* redelivery of one that failed part way: handled again (processing is
  idempotent downstream: the payment and refund code only ever move forward).

The table is also the record ops reconciles against: what the provider said,
when, and whether we acted on it.
"""
from __future__ import annotations

import logging
from datetime import datetime, timezone

from postgrest.exceptions import APIError

from ..db import fetch_one, supabase

logger = logging.getLogger(__name__)


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def claim(provider: str, event_id: str, event_type, payload: dict) -> bool:
    """
    Record a delivery. True when it should be processed now: it is new, or an
    earlier delivery of it never finished. False when it was already processed.
    """
    try:
        supabase.table("webhook_events").insert({
            "provider": provider,
            "event_id": event_id,
            "event_type": event_type if isinstance(event_type, str) else None,
            "payload": payload,
            "attempts": 1,
        }).execute()
        return True
    except APIError as exc:
        if getattr(exc, "code", None) != "23505":
            raise

    row = fetch_one(
        supabase.table("webhook_events").select("id, processed_at, attempts")
        .eq("provider", provider).eq("event_id", event_id)
    )
    if row and row.get("processed_at"):
        return False
    if row:
        supabase.table("webhook_events").update({"attempts": int(row.get("attempts") or 0) + 1}) \
            .eq("id", row["id"]).execute()
    return True


def mark_processed(provider: str, event_id: str) -> None:
    supabase.table("webhook_events").update({"processed_at": _now_iso(), "last_error": None}) \
        .eq("provider", provider).eq("event_id", event_id).execute()


def record_failure(provider: str, event_id: str, exc: BaseException) -> None:
    try:
        supabase.table("webhook_events").update({"last_error": repr(exc)[:2000]}) \
            .eq("provider", provider).eq("event_id", event_id).execute()
    except Exception as inner:                    # noqa: BLE001 — never mask the original
        logger.error("could not record webhook failure %s/%s: %r", provider, event_id, inner)


# ── Retention ────────────────────────────────────────────────────────────────
#
# A delivery is kept in full only while it can still be needed to replay or
# debug it. After that the payer's contact details, email, UPI id, card and
# notes are stripped and only what reconciliation needs stays: the event, the
# provider's ids, the amount and the status. (Payment records themselves keep
# their own, longer retention; this is the raw copy of what the provider sent.)

REDACT_AFTER_DAYS = 30

_KEEP_ENTITY = {"id", "entity", "order_id", "payment_id", "amount", "amount_refunded",
                "currency", "status", "method", "captured", "created_at", "speed_processed"}


def redact_payload(payload: dict) -> dict:
    """The reconciliation-only form of a Razorpay event."""
    out: dict = {"event": payload.get("event"), "created_at": payload.get("created_at"),
                 "redacted": True, "payload": {}}
    for name, wrapper in (payload.get("payload") or {}).items():
        entity = (wrapper or {}).get("entity") if isinstance(wrapper, dict) else None
        if isinstance(entity, dict):
            out["payload"][name] = {"entity": {k: v for k, v in entity.items() if k in _KEEP_ENTITY}}
    return out


def redact_processed(days: int = REDACT_AFTER_DAYS, limit: int = 200) -> int:
    """Strip personal fields from processed events older than ``days``."""
    from datetime import timedelta
    cutoff = (datetime.now(timezone.utc) - timedelta(days=days)).isoformat()
    rows = (
        supabase.table("webhook_events").select("id, payload")
        .not_.is_("processed_at", "null").lt("processed_at", cutoff)
        .limit(limit).execute().data or []
    )
    done = 0
    for row in rows:
        payload = row.get("payload")
        if not isinstance(payload, dict) or payload.get("redacted"):
            continue
        supabase.table("webhook_events").update({"payload": redact_payload(payload)}) \
            .eq("id", row["id"]).execute()
        done += 1
    return done
