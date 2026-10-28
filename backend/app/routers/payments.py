"""
Payments router.

Razorpay is stubbed while RAZORPAY_KEY_ID is unset; setting the key and secret is
the only change needed to go live. The real client is created lazily so the SDK
is an optional dependency until then.

Flow
----
  POST /payments/{booking_id}/order    patient starts payment → order + payments row
  POST /payments/{booking_id}/failed   client reports a failed attempt → retry window
  POST /payments/webhook               Razorpay → mark paid, credit the doctor's ledger;
                                       refund.* → services/refunds.py
  GET  /payments/{booking_id}          payment history for a booking, with its refunds
  POST /payments/{booking_id}/stub-complete   dev only, refuses once keys are set

Confirming a payment is idempotent end to end: a replayed webhook finds the
payment already completed and the ledger credit already present, so nobody is
paid twice. Refunds have their own lifecycle in services/refunds.py; nothing
here marks a payment refunded until Razorpay confirms it.
"""
import hashlib
import hmac
import json
import logging
from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import APIRouter, BackgroundTasks, Depends, Request
from starlette.concurrency import run_in_threadpool
from pydantic import BaseModel

from ..config import (
    ALLOW_INSECURE_PAYMENTS,
    PAYMENT_HOLD_MINUTES,
    PAYMENT_MAX_ATTEMPTS,
    RAZORPAY_KEY_ID,
    RAZORPAY_WEBHOOK_SECRET,
)
from ..db import fetch_one, supabase
from ..deps import get_current_user
from ..errors import AppError
from ..services import booking_state, notifications, payouts, refunds, visits, webhook_inbox
from ..services.razorpay_gateway import TIMEOUT_SECONDS
from ..services.razorpay_gateway import client as razorpay_client
from ..services.razorpay_gateway import live_mode

logger = logging.getLogger(__name__)

router = APIRouter()

# Razorpay signs webhooks with the webhook secret set in the dashboard, which is a
# different value from the API key secret — it never signs with the latter. Falling
# back to the key secret therefore could not rescue a single-secret setup; it only
# HMAC'd every delivery against the wrong key, rejecting all of them with a 400
# while looking configured. Razorpay retries a few times, gives up, and no payment
# ever confirms. Better to verify with the right secret or not at all, and let
# /readyz say which.
_WEBHOOK_SECRET = RAZORPAY_WEBHOOK_SECRET


def webhook_verified() -> bool:
    """Whether incoming webhooks are signature-checked. Surfaced by /readyz."""
    return bool(_WEBHOOK_SECRET)


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _razorpay_create_order(amount_paise: int, receipt: str) -> dict:
    """Create a Razorpay order, or a deterministic stub when keys are unset."""
    if not live_mode():
        return {
            "id": f"stub_order_{receipt}",
            "amount": amount_paise,
            "currency": "INR",
            "receipt": receipt,
        }
    return razorpay_client().order.create({
        "amount": amount_paise,
        "currency": "INR",
        "receipt": receipt,
        "payment_capture": 1,
    }, timeout=TIMEOUT_SECONDS)


# ── Create order ──────────────────────────────────────────────────────────────

class OrderRequest(BaseModel):
    type: str = "consult_fee"   # "consult_fee" | "procedure_bill"


@router.post("/{booking_id}/order", status_code=201)
def create_order(
    booking_id: str,
    body: Optional[OrderRequest] = None,
    user: dict = Depends(get_current_user),
):
    """Patient initiates payment for the consult fee or an approved procedure bill."""
    kind = (body or OrderRequest()).type
    if kind not in ("consult_fee", "procedure_bill"):
        raise AppError("type must be 'consult_fee' or 'procedure_bill'", 400)

    booking = fetch_one(supabase.table("bookings").select("*").eq("id", booking_id))
    if not booking:
        raise AppError("Booking not found", 404)
    if booking["patient_id"] != user["sub"]:
        raise AppError("Forbidden", 403)

    amount = _amount_due(booking, kind)

    # Reuse an order that is still open rather than stacking duplicates every
    # time the patient reopens the payment screen.
    open_rows = (
        supabase.table("payments")
        .select("*")
        .eq("booking_id", booking_id)
        .eq("type", kind)
        .eq("status", "initiated")
        .order("created_at", desc=True)
        .execute()
        .data
        or []
    )
    if open_rows and float(open_rows[0]["amount"]) == float(amount):
        payment = open_rows[0]
        return _order_response(payment, booking_id, amount)

    amount_paise = int(round(float(amount) * 100))
    order = _razorpay_create_order(amount_paise, receipt=f"{kind[:4]}-{booking_id[:18]}")

    payment = supabase.table("payments").insert({
        "booking_id": booking_id,
        "amount": float(amount),
        "status": "initiated",
        "type": kind,
        "razorpay_order_id": order["id"],
    }).execute().data[0]

    supabase.table("bookings").update({
        "payment_attempts": int(booking.get("payment_attempts") or 0) + 1,
    }).eq("id", booking_id).execute()

    return _order_response(payment, booking_id, amount)


def _amount_due(booking: dict, kind: str):
    if kind == "consult_fee":
        if booking["status"] not in ("accepted",):
            raise AppError(
                f"Cannot pay the consult fee for a booking with status '{booking['status']}'", 400
            )
        amount = booking.get("price_confirmed")
        if not amount:
            raise AppError("No confirmed price on booking", 400)
        return amount

    bills = (
        supabase.table("procedure_bills").select("*")
        .eq("booking_id", booking["id"]).execute().data or []
    )
    if not bills:
        raise AppError("No procedure bill for this booking", 404)
    bill = bills[0]
    if bill["status"] == "paid":
        raise AppError("This procedure bill is already paid", 409)
    if bill["status"] != "approved":
        raise AppError(f"Procedure bill is '{bill['status']}', not yet payable", 400)
    return bill["total"]


def _order_response(payment: dict, booking_id: str, amount) -> dict:
    return {
        "payment_id": payment["id"],
        "razorpay_order_id": payment["razorpay_order_id"],
        "razorpay_key": RAZORPAY_KEY_ID or "stub_key",
        "amount": int(round(float(amount) * 100)),
        "currency": "INR",
        "booking_id": booking_id,
        "type": payment["type"],
        "live": live_mode(),
    }


# ── Failed attempt → retry window ─────────────────────────────────────────────

@router.post("/{booking_id}/failed")
def report_failure(
    booking_id: str,
    background: BackgroundTasks,
    user: dict = Depends(get_current_user),
):
    """
    The client reports a failed or abandoned attempt.

    The slot stays held for the remainder of PAYMENT_HOLD_MINUTES, and the hold
    is extended to give a full window from now if less than that remains — a card
    failure should not cost the patient their slot.
    """
    booking = fetch_one(supabase.table("bookings").select("*").eq("id", booking_id))
    if not booking:
        raise AppError("Booking not found", 404)
    if booking["patient_id"] != user["sub"]:
        raise AppError("Forbidden", 403)
    if booking["status"] != "accepted":
        raise AppError("Only an accepted, unpaid booking can report a payment failure", 400)

    # Cap the number of extensions. Without this the hold could be reset to a
    # full window on every call, letting a patient pin a doctor's slot forever
    # without ever paying. Once the cap is hit we stop extending and let the
    # existing hold expire so the sweeper releases the slot.
    attempts = int(booking.get("payment_attempts") or 0)
    if attempts >= PAYMENT_MAX_ATTEMPTS:
        return {
            "ok": False,
            "retry_until": booking.get("hold_expires_at"),
            "hold_minutes": 0,
            "max_attempts_reached": True,
        }

    hold_until = _now() + timedelta(minutes=PAYMENT_HOLD_MINUTES)
    # Only while still accepted: a hold extended on a booking that was paid or
    # released a moment ago would put a dead hold back on it.
    rows = supabase.table("bookings").update({
        "payment_failed_at": _now().isoformat(),
        "hold_expires_at": hold_until.isoformat(),
        "payment_attempts": attempts + 1,
    }).eq("id", booking_id).eq("status", "accepted").execute().data
    if not rows:
        raise AppError("This booking was just updated. Refresh to see where it stands.", 409)
    updated = rows[0]

    supabase.table("payments").update({"status": "failed"}) \
        .eq("booking_id", booking_id).eq("status", "initiated").execute()

    notifications.payment_failed(booking, PAYMENT_HOLD_MINUTES, background)

    return {
        "ok": True,
        "retry_until": updated.get("hold_expires_at"),
        "hold_minutes": PAYMENT_HOLD_MINUTES,
    }


# ── Webhook ───────────────────────────────────────────────────────────────────

@router.post("/webhook")
async def razorpay_webhook(request: Request, background: BackgroundTasks):
    """
    Razorpay payment events.

    The signature is mandatory whenever a secret is configured — an unsigned or
    mis-signed request is rejected rather than trusted, since this endpoint moves
    money into a doctor's ledger.
    """
    body = await request.body()
    sig = request.headers.get("x-razorpay-signature", "")

    if not _WEBHOOK_SECRET and (live_mode() or not ALLOW_INSECURE_PAYMENTS):
        # Nothing can prove this request came from Razorpay, and this endpoint
        # moves money into a doctor's ledger. Live mode never trusts an unsigned
        # event; a non-live deployment only does so when it has explicitly opted
        # into insecure local-dev payments. 503 because the deployment is
        # misconfigured, not because the caller did anything wrong — Razorpay's
        # retries will deliver once the secret is set.
        raise AppError("RAZORPAY_WEBHOOK_SECRET is not configured", 503)

    if _WEBHOOK_SECRET:
        if not sig:
            raise AppError("Missing webhook signature", 400)
        expected = hmac.new(_WEBHOOK_SECRET.encode(), body, hashlib.sha256).hexdigest()
        if not hmac.compare_digest(expected, sig):
            raise AppError("Invalid webhook signature", 400)

    try:
        event = json.loads(body)
    except json.JSONDecodeError:
        raise AppError("Malformed webhook body", 400)
    if not isinstance(event, dict):
        raise AppError("Malformed webhook body", 400)

    # The webhook inbox: Razorpay's own event id (or, without one, a hash of
    # the signed body) identifies a delivery. Processing runs in the threadpool
    # because every database call here is blocking; on the event loop it would
    # stall every other request while it ran.
    event_id = request.headers.get("x-razorpay-event-id") or hashlib.sha256(body).hexdigest()
    return await run_in_threadpool(_process_webhook, event_id, event, background)


def _process_webhook(event_id: str, event: dict, background) -> dict:
    """
    Record the delivery, skip it if it was already processed, otherwise handle
    it and mark it processed. A delivery that raised stays unprocessed, with
    its error, so Razorpay's retry runs it again.
    """
    if not webhook_inbox.claim("razorpay", event_id, event.get("event"), event):
        return {"ok": True, "duplicate": True}
    try:
        result = _handle_event(event, background)
    except Exception as exc:
        webhook_inbox.record_failure("razorpay", event_id, exc)
        raise
    webhook_inbox.mark_processed("razorpay", event_id)
    return result


def _handle_event(event: dict, background) -> dict:
    kind = event.get("event")
    payload = event.get("payload") if isinstance(event.get("payload"), dict) else {}

    # Refund events carry the payment too, so they are routed before the
    # payment handling below can mistake one for a payment event.
    if isinstance(kind, str) and kind.startswith("refund."):
        refund_entity = (payload.get("refund") or {}).get("entity") or {}
        if not refund_entity.get("id"):
            return {"ok": True}
        return refunds.apply_webhook(kind, refund_entity, background)

    entity = (payload.get("payment", {}) or {}).get("entity", {}) or {}
    order_id = entity.get("order_id")
    if not order_id:
        return {"ok": True}

    if kind == "payment.failed":
        # Only an attempt still open can fail. On UPI one order can see a failed
        # attempt and then a captured one, and Razorpay doesn't promise to
        # deliver them in that order. Without the status condition, a late
        # 'failed' would overwrite a captured payment, and a later cancel would
        # find nothing completed to refund.
        supabase.table("payments").update({"status": "failed"}) \
            .eq("razorpay_order_id", order_id).eq("status", "initiated").execute()
        return {"ok": True}

    if kind != "payment.captured":
        return {"ok": True}   # order.paid etc. carry nothing payment.captured doesn't

    payment_rows = (
        supabase.table("payments").select("*")
        .eq("razorpay_order_id", order_id).execute().data or []
    )
    if not payment_rows:
        return {"ok": True}
    payment = payment_rows[0]

    if payment["status"] == "completed" and payment.get("type") == "consult_fee":
        # _confirm_payment marks the payment completed before it moves the
        # booking to `paid`, as separate calls. If the second one failed, this
        # redelivery is the only thing that can finish the job: left as a plain
        # replay, the booking stays `accepted` until the hold sweeper cancels
        # it with the patient's money taken. Every step of the confirm is
        # idempotent, so run it again.
        booking = fetch_one(supabase.table("bookings").select("id, status").eq("id", payment["booking_id"]))
        if booking and booking.get("status") == "accepted":
            return _confirm_payment(payment, entity.get("id"), entity.get("method"), background)

    if payment["status"] in ("completed", "refunded", "partially_refunded"):
        # A replayed delivery. A refunded payment counts too: treating it as new
        # would queue its refund a second time.
        return {"ok": True, "idempotent": True}

    # Pass the outcome straight through: a late capture that got refunded rather
    # than confirmed must say so, or the distinction is invisible in Razorpay's
    # delivery log and in ours.
    return _confirm_payment(payment, entity.get("id"), entity.get("method"), background)


def _refund_orphaned_payment(
    payment: dict,
    booking: dict,
    razorpay_payment_id: Optional[str],
    method: Optional[str] = None,
    background=None,
) -> None:
    """
    Send back money that arrived too late, and reverse any credit behind it.

    The payment is recorded as what it is, money Razorpay captured, and a refund
    is queued against it. It becomes 'refunded' only when Razorpay confirms (see
    services/refunds.py). Marking it refunded here, before asking, is how a
    failed refund used to go unnoticed.

    The ledger reversal is belt and braces: reaching here means the credit never
    ran, but a replayed webhook or a hand-fixed row could have left one, and
    ``payouts.reverse`` returns None when there is nothing to reverse.
    """
    supabase.table("payments").update({
        "status": "completed",
        "razorpay_payment_id": razorpay_payment_id,
        "method": method,
        "paid_at": _now().isoformat(),
    }).eq("id", payment["id"]).in_("status", ["initiated", "failed"]).execute()

    source = "consult_fee" if payment["type"] == "consult_fee" else "procedure_bill"
    payouts.reverse(booking["id"], source, note="payment refunded — booking was gone")

    refund = refunds.queue(
        {**payment, "razorpay_payment_id": razorpay_payment_id},
        reason="late_capture", requested_by_role="system",
    )
    if refund:
        refunds.execute(refund, background)
    notifications.payment_auto_refunded(booking, payment["amount"], background)


def _confirm_payment(
    payment: dict,
    razorpay_payment_id: Optional[str],
    method: Optional[str],
    background=None,
) -> dict:
    """
    Credit the doctor, then mark the payment complete and advance the booking.

    This is the single place money is recognised, so the commission split happens
    exactly once per payment regardless of which entry point confirmed it.

    Ordering is deliberate. The ledger credit runs *before* the payment is
    flipped to ``completed``, because crediting is idempotent on
    ``(booking_id, source)`` while the completed flag is what makes a replayed
    webhook a no-op. Marking complete first would mean a failure between the two
    steps loses the doctor's earnings permanently: Razorpay's retry would see a
    completed payment and return early, and nothing would ever credit the ledger.
    This way a retry re-runs the credit harmlessly and finishes the job.
    """
    booking = fetch_one(
        supabase.table("bookings").select("*").eq("id", payment["booking_id"])
    )
    if not booking:
        return {"ok": True}

    # A capture can arrive after the booking is already gone. UPI makes this
    # routine rather than rare: the patient is app-switched into GPay against the
    # payment-hold clock, and PSP delays of several minutes are normal, so the
    # hold sweeper cancels the booking and releases the slot while the payment is
    # still in flight. Confirming here would credit the doctor and flip a
    # cancelled booking back to `paid` — on a slot that has since been sold to
    # someone else. The money goes back instead.
    if booking["status"] in ("cancelled", "declined", "no_show"):
        _refund_orphaned_payment(payment, booking, razorpay_payment_id, method, background)
        return {"ok": True, "refunded": True}

    source = "consult_fee" if payment["type"] == "consult_fee" else "procedure_bill"
    payouts.credit(
        booking["doctor_id"], payment["amount"], source,
        booking_id=booking["id"], note=source.replace("_", " "),
    )

    supabase.table("payments").update({
        "status": "completed",
        "razorpay_payment_id": razorpay_payment_id,
        "method": method,
        "paid_at": _now().isoformat(),
    }).eq("id", payment["id"]).execute()

    if source == "consult_fee":
        # Conditional, like every other status change: the booking read above
        # can be cancelled (by the patient, the doctor or the hold sweeper)
        # before this write lands. Flipping it to `paid` regardless would
        # revive a cancelled booking whose slot may already be someone else's.
        try:
            booking_state.transition(
                booking["id"], "pay", actor_role="system", expected="accepted",
                patch={"hold_expires_at": None, "payment_failed_at": None},
                metadata={"payment_id": payment["id"], "method": method},
            )
            visits.schedule_reminders(booking)
        except booking_state.TransitionRefused as refused:
            if refused.current_status in ("cancelled", "declined", "no_show"):
                # Lost the race to a cancel: same outcome as arriving after it.
                _refund_orphaned_payment(payment, booking, razorpay_payment_id, method, background)
                return {"ok": True, "refunded": True}
            if refused.current_status != "paid":
                raise
            # Already `paid`. Either a redelivery finishing a confirm that got
            # this far before (nothing to change), or a second, different
            # payment for a booking that another capture already paid, e.g. an
            # order the patient abandoned that was paid after all. The second
            # one is money taken twice for one consultation: send it back.
            other = (
                supabase.table("payments").select("id")
                .eq("booking_id", booking["id"]).eq("type", payment["type"])
                .eq("status", "completed").neq("id", payment["id"]).execute().data or []
            )
            if other:
                # No ledger reversal: the doctor's one credit belongs to the
                # payment that actually confirmed the booking.
                refund = refunds.queue(
                    {**payment, "razorpay_payment_id": razorpay_payment_id},
                    reason="late_capture", requested_by_role="system",
                )
                if refund:
                    refunds.execute(refund, background)
                notifications.payment_auto_refunded(booking, payment["amount"], background)
                return {"ok": True, "refunded": True}
    else:
        supabase.table("procedure_bills").update({"status": "paid"}) \
            .eq("booking_id", booking["id"]).execute()

    notifications.payment_received(booking, payment["amount"], background)
    notifications.payment_confirmed_to_patient(booking, payment["amount"], background)

    return {"ok": True}


# ── Read ──────────────────────────────────────────────────────────────────────

@router.get("/{booking_id}")
def get_payment(booking_id: str, user: dict = Depends(get_current_user)):
    booking = fetch_one(
        supabase.table("bookings").select("patient_id,doctor_id").eq("id", booking_id)
    )
    if not booking:
        raise AppError("Booking not found", 404)
    if booking["patient_id"] != user["sub"] and booking["doctor_id"] != user["sub"]:
        raise AppError("Forbidden", 403)
    # Each payment carries its refunds, so the app can say "Refund processing"
    # or "Refunded" from what Razorpay has actually confirmed.
    return (
        supabase.table("payments")
        .select("*, refunds(id, amount_paise, status, reason, created_at, processed_at)")
        .eq("booking_id", booking_id).order("created_at", desc=True).execute().data
    )


# ── Dev shortcut ──────────────────────────────────────────────────────────────

@router.post("/{booking_id}/stub-complete")
def stub_complete_payment(
    booking_id: str,
    background: BackgroundTasks,
    body: Optional[OrderRequest] = None,
    user: dict = Depends(get_current_user),
):
    """
    Dev-only: confirm a payment without Razorpay.

    Routes through the same ``_confirm_payment`` path as the webhook, so ledger
    credits and notifications behave identically in development. Refuses outright
    once live keys are present.
    """
    # Both gates, like the webhook: the flag alone left a deploy that set it
    # next to live keys letting any patient mark their own booking paid.
    if not ALLOW_INSECURE_PAYMENTS or live_mode():
        raise AppError("Not available: set ALLOW_INSECURE_PAYMENTS for local dev", 403)

    kind = (body or OrderRequest()).type
    booking = fetch_one(supabase.table("bookings").select("*").eq("id", booking_id))
    if not booking:
        raise AppError("Booking not found", 404)
    if booking["patient_id"] != user["sub"]:
        raise AppError("Forbidden", 403)

    rows = (
        supabase.table("payments").select("*")
        .eq("booking_id", booking_id).eq("type", kind)
        .order("created_at", desc=True).execute().data or []
    )
    if rows:
        payment = rows[0]
    else:
        amount = _amount_due(booking, kind)
        payment = supabase.table("payments").insert({
            "booking_id": booking_id,
            "amount": float(amount),
            "status": "initiated",
            "type": kind,
            "razorpay_order_id": f"stub_order_{booking_id[:18]}-{kind[:4]}",
        }).execute().data[0]

    if payment["status"] == "completed":
        return {"ok": True, "status": "already_paid"}

    _confirm_payment(payment, f"stub_pay_{payment['id'][:12]}", "stub", background)
    return {"ok": True, "status": "paid", "type": kind}
