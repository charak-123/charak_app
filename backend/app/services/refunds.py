"""
Refunds: from "this money must go back" to "Razorpay confirmed it did".

A ``refunds`` row moves through:

    pending ──execute()──▶ processing ──webhook / poll──▶ processed
       ▲                        │
       └──── transient error ◀──┴──▶ failed  (Razorpay refused, or retries ran
                                              out; ops can retry from admin)

* **Queued before it is sent.** A refund is recorded in the same transaction as
  whatever decided it: ``cancel_booking()`` in SQL, or ``queue()`` below for a
  late capture. Razorpay is called only after that commits, so a crash can't
  lose the decision. ``sweep()`` finds anything left pending and finishes it.
* **Not "refunded" until Razorpay says so.** The payment stays ``completed``
  until Razorpay reports the refund ``processed``. Only then does it become
  ``refunded`` / ``partially_refunded``, and only then is the patient told the
  money is back.
* **Never twice.** Every request to Razorpay carries our refund id in
  ``notes``. A retry first looks for a live Razorpay refund carrying that id,
  so a timeout after Razorpay acted adopts that refund instead of making a
  second one. The database also refuses refunds that add up to more than the
  payment (``refunds_guard`` in migration 0022).
* **Claimed before it is sent.** ``execute()`` moves the row to ``processing``
  with a compare-and-set, so two callers (a request and the sweep) never send
  the same attempt.
"""
from __future__ import annotations

import logging
import uuid
from datetime import datetime, timedelta, timezone
from decimal import ROUND_HALF_UP, Decimal
from typing import Optional

from postgrest.exceptions import APIError

from ..db import fetch_one, supabase
from ..errors import AppError
from . import notifications
from .razorpay_gateway import TIMEOUT_SECONDS, is_permanent_error, live_mode
from .razorpay_gateway import client as razorpay_client

logger = logging.getLogger(__name__)

# The sweep retries transient failures this many times before handing the
# refund to ops. Each retry waits 2^attempts minutes (2, 4, 8, 16 …).
MAX_AUTO_ATTEMPTS = 5

# A row in 'processing' with no Razorpay id this long after it was claimed
# means the request that claimed it died mid-call.
STALE_CLAIM = timedelta(minutes=10)

# Razorpay accepted the refund but no webhook has confirmed it in this long:
# ask Razorpay directly, in case a delivery was lost.
POLL_AFTER = timedelta(minutes=30)

OPEN_STATUSES = ("pending", "processing", "failed")

_REFUND_COLUMNS = (
    "id, payment_id, booking_id, amount_paise, currency, reason, status, "
    "razorpay_refund_id, superseded_razorpay_refund_ids, attempts, last_attempt_at, failure_reason, "
    "requested_by_role, processed_at, created_at, updated_at"
)


def _now() -> datetime:
    return datetime.now(timezone.utc)


def to_paise(rupees) -> int:
    """Rupees (numeric(10,2) in payments.amount) to exact integer paise."""
    return int((Decimal(str(rupees or 0)) * 100).quantize(Decimal("1"), rounding=ROUND_HALF_UP))


def _uuid_or_none(value) -> Optional[str]:
    try:
        return str(uuid.UUID(str(value)))
    except (ValueError, TypeError, AttributeError):
        return None


# ── Reads ────────────────────────────────────────────────────────────────────

def get(refund_id: str) -> Optional[dict]:
    if not _uuid_or_none(refund_id):
        return None
    return fetch_one(supabase.table("refunds").select(_REFUND_COLUMNS).eq("id", refund_id))


def _by_key(key: str) -> Optional[dict]:
    return fetch_one(supabase.table("refunds").select(_REFUND_COLUMNS).eq("idempotency_key", key))


def _by_razorpay_id(razorpay_refund_id: Optional[str]) -> Optional[dict]:
    if not razorpay_refund_id:
        return None
    return fetch_one(
        supabase.table("refunds").select(_REFUND_COLUMNS)
        .eq("razorpay_refund_id", razorpay_refund_id)
    )


def _queued_paise(payment_id: str) -> int:
    rows = (
        supabase.table("refunds").select("amount_paise")
        .eq("payment_id", payment_id).execute().data or []
    )
    return sum(int(r["amount_paise"]) for r in rows)


def for_booking(booking_id: str) -> list[dict]:
    return (
        supabase.table("refunds").select(_REFUND_COLUMNS)
        .eq("booking_id", booking_id).order("created_at").execute().data or []
    )


# ── Queue ────────────────────────────────────────────────────────────────────

def queue(payment: dict, reason: str, requested_by_role: str,
          requested_by: Optional[str] = None) -> Optional[dict]:
    """
    Record that the unrefunded remainder of ``payment`` must go back.

    Idempotent on (payment, reason): a second call returns the refund already
    queued. Returns None when nothing is left to refund.
    """
    key = f"{payment['id']}:{reason}"
    existing = _by_key(key)
    if existing:
        return existing

    due = to_paise(payment["amount"]) - _queued_paise(payment["id"])
    if due <= 0:
        return None

    try:
        rows = supabase.table("refunds").insert({
            "payment_id": payment["id"],
            "booking_id": payment["booking_id"],
            "amount_paise": due,
            "reason": reason,
            "idempotency_key": key,
            "requested_by_role": requested_by_role,
            "requested_by": _uuid_or_none(requested_by),
        }).execute().data or []
    except APIError as exc:
        code = getattr(exc, "code", None)
        # 23505: a concurrent call queued the same refund a moment earlier.
        if code == "23505":
            return _by_key(key)
        # 23514: refunds_guard. Another path (a cancel racing this late capture)
        # queued the rest of the payment in the meantime, so nothing is left.
        if code == "23514":
            logger.info("payment %s already fully queued for refund", payment["id"])
            return None
        raise
    return rows[0] if rows else _by_key(key)


# ── Send ─────────────────────────────────────────────────────────────────────

def execute(refund: dict, background=None) -> dict:
    """
    Send one queued refund to Razorpay. Safe to call repeatedly and
    concurrently. Returns the refund as it now stands.
    """
    if refund.get("status") not in ("pending", "failed"):
        return refund

    attempts = int(refund.get("attempts") or 0)
    claimed = (
        supabase.table("refunds").update({
            "status": "processing",
            "attempts": attempts + 1,
            "last_attempt_at": _now().isoformat(),
        })
        .eq("id", refund["id"]).eq("status", refund["status"]).eq("attempts", attempts)
        .execute().data or []
    )
    if not claimed:
        # Someone else claimed this attempt, or it moved on already.
        return get(refund["id"]) or refund
    refund = claimed[0]

    if not live_mode():
        # Local development only (stub orders, ALLOW_INSECURE_PAYMENTS). There
        # is no Razorpay to ask, so the refund settles at once. A production
        # deploy without keys can't capture a payment in the first place.
        return _apply(refund, {"id": f"stub_rfnd_{refund['id']}", "status": "processed"},
                      background)

    payment = fetch_one(
        supabase.table("payments").select("id, razorpay_payment_id")
        .eq("id", refund["payment_id"])
    )
    razorpay_payment_id = (payment or {}).get("razorpay_payment_id")
    if not razorpay_payment_id:
        return _fail(refund, "No Razorpay payment id is recorded for this payment.",
                     permanent=True, background=background)

    try:
        entity = None
        if int(refund["attempts"]) > 1:
            # A retry. If an earlier attempt reached Razorpay before timing
            # out on our side, adopt that refund rather than sending another.
            entity = _find_at_razorpay(razorpay_payment_id, refund["id"])
        if entity is None:
            entity = razorpay_client().payment.refund(razorpay_payment_id, {
                "amount": int(refund["amount_paise"]),
                "speed": "normal",
                "receipt": refund["id"],
                "notes": {
                    "charak_refund_id": refund["id"],
                    "booking_id": refund["booking_id"],
                    "reason": refund["reason"],
                },
            }, timeout=TIMEOUT_SECONDS)
    except Exception as exc:                      # noqa: BLE001 — classified below
        logger.warning("refund %s attempt %s failed: %r", refund["id"], refund["attempts"], exc)
        return _fail(refund, str(exc)[:500] or type(exc).__name__,
                     permanent=is_permanent_error(exc), background=background)

    return _apply(refund, entity, background)


def _find_at_razorpay(razorpay_payment_id: str, refund_id: str) -> Optional[dict]:
    """A live (not failed) Razorpay refund on this payment carrying our id."""
    page = razorpay_client().payment.fetch_multiple_refund(
        razorpay_payment_id, {"count": 100}, timeout=TIMEOUT_SECONDS,
    )
    for item in (page or {}).get("items", []):
        notes = item.get("notes") if isinstance(item.get("notes"), dict) else {}
        if notes.get("charak_refund_id") == refund_id and item.get("status") != "failed":
            return item
    return None


def _apply(refund: dict, entity: dict, background=None) -> dict:
    """
    Record what Razorpay says about this refund. Only moves forward: a refund
    already ``processed`` is never changed again.
    """
    rzp_status = (entity or {}).get("status")
    rzp_id = (entity or {}).get("id")

    if rzp_status == "failed":
        return _fail({**refund, "razorpay_refund_id": rzp_id or refund.get("razorpay_refund_id")},
                     "Razorpay reported the refund as failed.",
                     permanent=True, background=background)

    update: dict = {"razorpay_refund_id": rzp_id or refund.get("razorpay_refund_id")}
    if rzp_status == "processed":
        update.update(status="processed", processed_at=_now().isoformat(), failure_reason=None)
    else:
        # 'pending' / 'created': accepted by Razorpay, not yet with the bank.
        update.update(status="processing", failure_reason=None)

    rows = (
        supabase.table("refunds").update(update)
        .eq("id", refund["id"]).neq("status", "processed")
        .execute().data or []
    )
    if not rows:
        return get(refund["id"]) or refund
    row = rows[0]
    if row["status"] == "processed":
        _settle_payment(row["payment_id"])
        _notify_patient(row, notifications.refund_completed, background)
    return row


def _fail(refund: dict, reason: str, *, permanent: bool, background=None) -> dict:
    """
    A transient error goes back to ``pending`` for the sweep to retry. A
    permanent one, or one that has run out of retries, becomes ``failed`` and
    lands in the admin refunds queue; the patient is told it's delayed.
    """
    give_up = permanent or int(refund.get("attempts") or 0) >= MAX_AUTO_ATTEMPTS
    status = "failed" if give_up else "pending"
    rows = (
        supabase.table("refunds").update({
            "status": status,
            "failure_reason": reason,
            "razorpay_refund_id": refund.get("razorpay_refund_id"),
        })
        .eq("id", refund["id"]).eq("status", "processing")
        .execute().data or []
    )
    if not rows:
        return get(refund["id"]) or refund
    row = rows[0]
    if give_up:
        logger.error("refund %s needs ops: %s", row["id"], reason)
        _notify_patient(row, notifications.refund_delayed, background)
        notifications.refund_needs_attention(row, background)
    return row


def _settle_payment(payment_id: str) -> None:
    """Mark the payment refunded once Razorpay has confirmed enough refunds."""
    payment = fetch_one(supabase.table("payments").select("id, amount, status").eq("id", payment_id))
    if not payment:
        return
    processed = sum(
        int(r["amount_paise"]) for r in (
            supabase.table("refunds").select("amount_paise")
            .eq("payment_id", payment_id).eq("status", "processed")
            .execute().data or []
        )
    )
    if processed <= 0:
        return
    status = "refunded" if processed >= to_paise(payment["amount"]) else "partially_refunded"
    supabase.table("payments").update({"status": status}) \
        .eq("id", payment_id).in_("status", ["completed", "partially_refunded"]).execute()


def _notify_patient(refund: dict, event, background=None) -> None:
    booking = fetch_one(
        supabase.table("bookings").select("id, patient_id").eq("id", refund["booking_id"])
    )
    if booking:
        event(booking, refund["amount_paise"], background, refund_id=refund["id"])


# ── Webhooks ─────────────────────────────────────────────────────────────────

def apply_webhook(kind: str, entity: dict, background=None) -> dict:
    """
    Apply a Razorpay ``refund.*`` event. Events can arrive more than once and
    out of order; each is matched to our row and only ever moves it forward.
    """
    rzp_id = entity.get("id")
    notes = entity.get("notes") if isinstance(entity.get("notes"), dict) else {}

    row = _by_razorpay_id(rzp_id) or get(notes.get("charak_refund_id"))
    if row is None:
        row = _adopt_external(entity)
        if row is None:
            return {"ok": True, "ignored": "unknown refund"}

    # An event about an earlier attempt that ops has since retried.
    if rzp_id and (rzp_id in (row.get("superseded_razorpay_refund_ids") or [])
                   or (row.get("razorpay_refund_id") and row["razorpay_refund_id"] != rzp_id)):
        return {"ok": True, "ignored": "superseded attempt"}
    if row["status"] == "processed":
        return {"ok": True, "idempotent": True}

    if kind == "refund.processed":
        row = _apply(row, {**entity, "status": "processed"}, background)
    elif kind == "refund.failed":
        if row["status"] == "processing":
            row = _fail({**row, "razorpay_refund_id": rzp_id}, "Razorpay reported the refund as failed.",
                        permanent=True, background=background)
    elif kind == "refund.created" and row["status"] == "processing" and rzp_id:
        row = _apply(row, {**entity, "status": "pending"}, background)
    return {"ok": True, "refund_status": row.get("status")}


def _adopt_external(entity: dict) -> Optional[dict]:
    """
    A refund made outside the app, usually by ops in the Razorpay dashboard.
    Record it against the payment so our books match Razorpay's. The ledger is
    left to ops: a manual refund has no booking decision behind it to say
    whether the doctor's credit should go too.
    """
    rzp_id, rzp_payment_id = entity.get("id"), entity.get("payment_id")
    if not rzp_id or not rzp_payment_id:
        return None
    payment = fetch_one(
        supabase.table("payments").select("id, booking_id")
        .eq("razorpay_payment_id", rzp_payment_id)
    )
    if not payment:
        return None
    status = {"processed": "processed", "failed": "failed"}.get(entity.get("status"), "processing")
    try:
        supabase.table("refunds").insert({
            "payment_id": payment["id"],
            "booking_id": payment["booking_id"],
            "amount_paise": int(entity.get("amount") or 0),
            "reason": "ops",
            "idempotency_key": f"razorpay:{rzp_id}",
            "requested_by_role": "ops",
            "status": status,
            "razorpay_refund_id": rzp_id,
            "processed_at": _now().isoformat() if status == "processed" else None,
        }).execute()
    except APIError as exc:
        if getattr(exc, "code", None) != "23505":
            logger.error("could not record external refund %s: %s", rzp_id, exc)
            return None
    row = _by_razorpay_id(rzp_id)
    if row and row["status"] == "processed":
        _settle_payment(row["payment_id"])
    logger.warning("refund %s was made outside the app; ledger left for ops", rzp_id)
    # Returned as already handled, so apply_webhook doesn't apply it twice.
    return {**row, "status": "processed"} if row and row["status"] == "processed" else row


# ── Sweep (cron) ─────────────────────────────────────────────────────────────

def sweep(now: Optional[datetime] = None) -> dict:
    """
    Finish whatever a request didn't:
      1. reclaim attempts whose worker died mid-call,
      2. send pending refunds whose backoff has elapsed,
      3. ask Razorpay about refunds it accepted but never confirmed.
    """
    now = now or _now()
    result = {"reclaimed": 0, "sent": 0, "polled": 0}

    # Every 'processing' row untouched for STALE_CLAIM. Without a Razorpay id
    # it's a dead claim; with one, it's waiting on Razorpay and is polled once
    # it has waited POLL_AFTER.
    quiet = (
        supabase.table("refunds").select(_REFUND_COLUMNS)
        .eq("status", "processing")
        .lt("last_attempt_at", (now - STALE_CLAIM).isoformat())
        .order("last_attempt_at").limit(100)
        .execute().data or []
    )
    for row in quiet:
        if not row.get("razorpay_refund_id"):
            reset = (
                supabase.table("refunds").update({"status": "pending"})
                .eq("id", row["id"]).eq("status", "processing")
                .is_("razorpay_refund_id", "null")
                .execute().data or []
            )
            result["reclaimed"] += len(reset)
        elif _older_than(row.get("last_attempt_at"), now - POLL_AFTER):
            _poll(row, now)
            result["polled"] += 1

    pending = (
        supabase.table("refunds").select(_REFUND_COLUMNS)
        .eq("status", "pending").order("created_at").limit(50)
        .execute().data or []
    )
    for row in pending:
        if _due(row, now):
            execute(row)
            result["sent"] += 1

    return result


def _parse(ts) -> Optional[datetime]:
    if not ts:
        return None
    return datetime.fromisoformat(str(ts).replace("Z", "+00:00"))


def _older_than(ts, cutoff: datetime) -> bool:
    parsed = _parse(ts)
    return parsed is None or parsed < cutoff


def _due(row: dict, now: datetime) -> bool:
    last = _parse(row.get("last_attempt_at"))
    if last is None:
        return True
    return now - last >= timedelta(minutes=2 ** int(row.get("attempts") or 0))


def _poll(row: dict, now: datetime) -> None:
    if not live_mode():
        return
    # Stamp first, so a Razorpay outage doesn't make every sweep re-poll.
    supabase.table("refunds").update({"last_attempt_at": now.isoformat()}) \
        .eq("id", row["id"]).execute()
    try:
        entity = razorpay_client().refund.fetch(row["razorpay_refund_id"], {},
                                                timeout=TIMEOUT_SECONDS)
    except Exception as exc:                      # noqa: BLE001 — try again next sweep
        logger.warning("could not poll refund %s: %r", row["id"], exc)
        return
    if entity.get("status") in ("processed", "failed"):
        _apply(row, entity)


# ── Ops ──────────────────────────────────────────────────────────────────────

def retry(refund_id: str) -> dict:
    """
    Ops: send a failed refund again. The earlier Razorpay attempt, if any, moves
    to ``superseded_razorpay_refund_ids``: kept for the record, and so a late
    webhook about it is recognised as stale.
    """
    row = get(refund_id)
    if not row:
        raise AppError("Refund not found", 404)
    if row["status"] != "failed":
        raise AppError(f"Only a failed refund can be retried (this one is '{row['status']}')", 409)

    superseded = list(row.get("superseded_razorpay_refund_ids") or [])
    if row.get("razorpay_refund_id"):
        superseded.append(row["razorpay_refund_id"])
    reset = (
        supabase.table("refunds").update({
            "razorpay_refund_id": None,
            "superseded_razorpay_refund_ids": superseded,
        })
        .eq("id", refund_id).eq("status", "failed").execute().data or []
    )
    if not reset:
        raise AppError("This refund was just updated. Refresh and try again.", 409)
    return execute(reset[0])
