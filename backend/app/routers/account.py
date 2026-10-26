"""
The signed-in patient's own records.

  GET /me/payments   every payment and refund, newest first, with its booking
"""
from fastapi import APIRouter, Depends

from ..db import supabase
from ..deps import require_patient

router = APIRouter()


@router.get("/payments")
def my_payments(limit: int = 100, user: dict = Depends(require_patient)):
    """
    Payment history for Profile → Payments. Each payment carries its refunds,
    so the app can say "Refund processing" or "Refunded" from what Razorpay has
    confirmed (services/refunds.py). Attempts that never completed are left
    out: they moved no money.
    """
    limit = max(1, min(limit, 200))
    bookings = (
        supabase.table("bookings").select("id")
        .eq("patient_id", user["sub"]).execute().data or []
    )
    ids = [b["id"] for b in bookings]
    if not ids:
        return []
    return (
        supabase.table("payments")
        .select("id, booking_id, amount, type, status, method, paid_at, created_at, "
                "razorpay_payment_id, "
                "refunds(id, amount_paise, status, reason, created_at, processed_at), "
                "bookings(id, channel, scheduled_start, status, doctors(name))")
        .in_("booking_id", ids)
        .in_("status", ["completed", "refunded", "partially_refunded"])
        .order("created_at", desc=True)
        .limit(limit)
        .execute().data or []
    )
