"""
Payments router.

Razorpay is stubbed when RAZORPAY_KEY_ID is not set.
Wire real credentials when provided.

Flow:
  POST /payments/:booking_id/order  → creates Razorpay order (or stub) + payments row
  POST /payments/webhook             → Razorpay webhook → marks booking paid
  GET  /payments/:booking_id         → returns payment status
"""
import os
import hmac
import hashlib

from fastapi import APIRouter, Depends, Request
from pydantic import BaseModel

from ..db import supabase
from ..deps import get_current_user
from ..errors import AppError

router = APIRouter()

RAZORPAY_KEY_ID     = os.getenv("RAZORPAY_KEY_ID", "")
RAZORPAY_KEY_SECRET = os.getenv("RAZORPAY_KEY_SECRET", "")


def _razorpay_create_order(amount_paise: int, receipt: str) -> dict:
    """Create a Razorpay order. Returns stub if credentials not set."""
    if not RAZORPAY_KEY_ID:
        return {
            "id": f"stub_order_{receipt}",
            "amount": amount_paise,
            "currency": "INR",
            "receipt": receipt,
        }
    import razorpay  # type: ignore  (add to requirements.txt when live)
    client = razorpay.Client(auth=(RAZORPAY_KEY_ID, RAZORPAY_KEY_SECRET))
    return client.order.create({
        "amount": amount_paise,
        "currency": "INR",
        "receipt": receipt,
    })


@router.post("/{booking_id}/order", status_code=201)
def create_order(booking_id: str, user: dict = Depends(get_current_user)):
    """Patient initiates payment — creates a Razorpay order."""
    booking = supabase.table("bookings").select("*") \
        .eq("id", booking_id).single().execute().data
    if not booking:
        raise AppError("Booking not found", 404)
    if booking["patient_id"] != user["sub"]:
        raise AppError("Forbidden", 403)
    if booking["status"] not in ("accepted",):
        raise AppError(f"Cannot pay for a booking with status '{booking['status']}'", 400)

    amount = booking.get("price_confirmed")
    if not amount:
        raise AppError("No confirmed price on booking", 400)

    amount_paise = int(float(amount) * 100)
    order = _razorpay_create_order(amount_paise, receipt=booking_id[:20])

    # Record in payments table
    payment = supabase.table("payments").insert({
        "booking_id": booking_id,
        "amount": amount,
        "status": "initiated",
        "type": "consult_fee",
        "razorpay_order_id": order["id"],
    }).execute().data[0]

    return {
        "payment_id": payment["id"],
        "razorpay_order_id": order["id"],
        "razorpay_key": RAZORPAY_KEY_ID or "stub_key",
        "amount": amount_paise,
        "currency": "INR",
        "booking_id": booking_id,
    }


@router.post("/webhook")
async def razorpay_webhook(request: Request):
    """
    Razorpay sends payment events here.
    Verify signature, mark booking as paid.
    """
    body = await request.body()
    sig  = request.headers.get("x-razorpay-signature", "")

    if RAZORPAY_KEY_SECRET and sig:
        expected = hmac.new(
            RAZORPAY_KEY_SECRET.encode(), body, hashlib.sha256
        ).hexdigest()
        if not hmac.compare_digest(expected, sig):
            raise AppError("Invalid webhook signature", 400)

    import json
    event = json.loads(body)
    if event.get("event") != "payment.captured":
        return {"ok": True}  # ignore other events

    payload      = event["payload"]["payment"]["entity"]
    order_id     = payload.get("order_id")
    payment_id   = payload.get("id")

    if not order_id:
        return {"ok": True}

    # Find the payment row
    payment_rows = supabase.table("payments") \
        .select("*").eq("razorpay_order_id", order_id).execute().data
    if not payment_rows:
        return {"ok": True}

    payment = payment_rows[0]
    from datetime import datetime, timezone
    now = datetime.now(timezone.utc).isoformat()

    supabase.table("payments").update({
        "status": "completed",
        "razorpay_payment_id": payment_id,
        "paid_at": now,
    }).eq("id", payment["id"]).execute()

    # Mark booking as paid
    supabase.table("bookings").update({"status": "paid"}) \
        .eq("id", payment["booking_id"]).execute()

    return {"ok": True}


@router.get("/{booking_id}")
def get_payment(booking_id: str, user: dict = Depends(get_current_user)):
    booking = supabase.table("bookings").select("patient_id,doctor_id") \
        .eq("id", booking_id).single().execute().data
    if not booking:
        raise AppError("Booking not found", 404)
    if booking["patient_id"] != user["sub"] and booking["doctor_id"] != user["sub"]:
        raise AppError("Forbidden", 403)
    result = supabase.table("payments").select("*").eq("booking_id", booking_id) \
        .order("created_at", desc=True).execute()
    return result.data


@router.post("/{booking_id}/stub-complete")
def stub_complete_payment(booking_id: str, user: dict = Depends(get_current_user)):
    """
    Dev-only: instantly mark the consult payment as paid.
    Disabled when RAZORPAY_KEY_ID is set.
    """
    if RAZORPAY_KEY_ID:
        raise AppError("Not available in production", 403)
    booking = supabase.table("bookings").select("*") \
        .eq("id", booking_id).single().execute().data
    if not booking:
        raise AppError("Booking not found", 404)
    if booking["patient_id"] != user["sub"]:
        raise AppError("Forbidden", 403)
    from datetime import datetime, timezone
    now = datetime.now(timezone.utc).isoformat()
    supabase.table("bookings").update({"status": "paid"}).eq("id", booking_id).execute()
    return {"ok": True, "status": "paid"}
