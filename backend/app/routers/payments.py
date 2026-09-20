"""
Payments router.

Razorpay is stubbed while RAZORPAY_KEY_ID is unset; setting the key and secret is
the only change needed to go live. The real client is created lazily so the SDK
is an optional dependency until then.

Flow
----
  POST /payments/{booking_id}/order    patient starts payment → order + payments row
  POST /payments/{booking_id}/failed   client reports a failed attempt → retry window
  POST /payments/webhook               Razorpay → mark paid, credit the doctor's ledger
  GET  /payments/{booking_id}          payment history for a booking
  POST /payments/{booking_id}/stub-complete   dev only, refuses once keys are set

Confirming a payment is idempotent end to end: a replayed webhook finds the
payment already completed and the ledger credit already present, so nobody is
paid twice.
"""
import hashlib
import hmac
import json
from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import APIRouter, BackgroundTasks, Depends, Request
from pydantic import BaseModel

from ..config import (
    PAYMENT_HOLD_MINUTES,
    RAZORPAY_KEY_ID,
    RAZORPAY_KEY_SECRET,
    RAZORPAY_WEBHOOK_SECRET,
)
from ..db import fetch_one, supabase
from ..deps import get_current_user
from ..errors import AppError
from ..services import notifications, payouts

router = APIRouter()

# Razorpay signs webhooks with the webhook secret, which is distinct from the API
# key secret. Fall back to the key secret so a single-secret setup still verifies.
_WEBHOOK_SECRET = RAZORPAY_WEBHOOK_SECRET or RAZORPAY_KEY_SECRET


def _now() -> datetime:
    return datetime.now(timezone.utc)


def live_mode() -> bool:
    return bool(RAZORPAY_KEY_ID and RAZORPAY_KEY_SECRET)


def _razorpay_create_order(amount_paise: int, receipt: str) -> dict:
    """Create a Razorpay order, or a deterministic stub when keys are unset."""
    if not live_mode():
        return {
            "id": f"stub_order_{receipt}",
            "amount": amount_paise,
            "currency": "INR",
            "receipt": receipt,
        }
    import razorpay  # type: ignore — optional until credentials are configured

    client = razorpay.Client(auth=(RAZORPAY_KEY_ID, RAZORPAY_KEY_SECRET))
    return client.order.create({
        "amount": amount_paise,
        "currency": "INR",
        "receipt": receipt,
        "payment_capture": 1,
    })


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

    hold_until = _now() + timedelta(minutes=PAYMENT_HOLD_MINUTES)
    updated = supabase.table("bookings").update({
        "payment_failed_at": _now().isoformat(),
        "hold_expires_at": hold_until.isoformat(),
    }).eq("id", booking_id).execute().data[0]

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

    kind = event.get("event")
    entity = (event.get("payload", {}).get("payment", {}) or {}).get("entity", {}) or {}
    order_id = entity.get("order_id")
    if not order_id:
        return {"ok": True}

    if kind == "payment.failed":
        supabase.table("payments").update({"status": "failed"}) \
            .eq("razorpay_order_id", order_id).execute()
        return {"ok": True}

    if kind != "payment.captured":
        return {"ok": True}   # ignore refunds, order.paid, etc.

    payment_rows = (
        supabase.table("payments").select("*")
        .eq("razorpay_order_id", order_id).execute().data or []
    )
    if not payment_rows:
        return {"ok": True}
    payment = payment_rows[0]

    if payment["status"] == "completed":
        return {"ok": True, "idempotent": True}   # replayed delivery

    _confirm_payment(payment, entity.get("id"), entity.get("method"), background)
    return {"ok": True}


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
        supabase.table("bookings").update({
            "status": "paid",
            "hold_expires_at": None,
            "payment_failed_at": None,
        }).eq("id", booking["id"]).execute()
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
    return (
        supabase.table("payments").select("*")
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
    if live_mode():
        raise AppError("Not available in production", 403)

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
