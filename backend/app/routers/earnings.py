"""
Earnings router — doctor-facing summary of completed visits and procedure revenue.
"""
from fastapi import APIRouter, Depends

from ..db import supabase
from ..deps import require_doctor

router = APIRouter()


@router.get("/me")
def get_earnings(user: dict = Depends(require_doctor)):
    """
    Returns:
      - completed bookings with consult fee
      - procedure_bills per booking (with status)
      - totals: consult_total, procedure_total, pending_review_total, grand_total
    """
    bookings = (
        supabase.table("bookings")
        .select("id, channel, scheduled_start, price_confirmed, status, users(name)")
        .eq("doctor_id", user["sub"])
        .eq("status", "completed")
        .order("scheduled_start", desc=True)
        .execute()
        .data
    )

    booking_ids = [b["id"] for b in bookings]
    bills = []
    if booking_ids:
        bills = (
            supabase.table("procedure_bills")
            .select("*")
            .in_("booking_id", booking_ids)
            .execute()
            .data
        )

    bills_by_booking = {b["booking_id"]: b for b in bills}

    consult_total = sum(
        float(b.get("price_confirmed") or 0) for b in bookings
    )
    # 'approved' means the patient *may* pay, not that they have. Counting it
    # as earned inflated the headline figure with money that had not arrived.
    procedure_total = sum(
        float(bill["total"]) for bill in bills if bill["status"] == "paid"
    )
    awaiting_payment_total = sum(
        float(bill["total"]) for bill in bills if bill["status"] == "approved"
    )
    pending_review_total = sum(
        float(bill["total"]) for bill in bills if bill["status"] == "under_review"
    )

    items = []
    for b in bookings:
        bill = bills_by_booking.get(b["id"])
        items.append({
            "booking_id": b["id"],
            "patient_name": (b.get("users") or {}).get("name", "Unknown"),
            "channel": b["channel"],
            "scheduled_start": b["scheduled_start"],
            "consult_fee": b.get("price_confirmed"),
            "procedure_bill": bill,
        })

    return {
        "items": items,
        "consult_total": consult_total,
        "procedure_total": procedure_total,
        # Payable but not yet paid — shown separately, never inside a total
        # described as earned.
        "awaiting_payment_total": awaiting_payment_total,
        "pending_review_total": pending_review_total,
        # Everything actually collected, over all time. The doctor app used to
        # label this "this month", which it never was — there is no date filter
        # here and adding one would silently change what the number means.
        "grand_total": consult_total + procedure_total,
        "period": "all_time",
    }


@router.get("/me/ratings")
def get_ratings(user: dict = Depends(require_doctor)):
    """Doctor's received ratings."""
    bookings = (
        supabase.table("bookings")
        .select("id")
        .eq("doctor_id", user["sub"])
        .execute()
        .data
    )
    booking_ids = [b["id"] for b in bookings]
    if not booking_ids:
        return []
    return (
        supabase.table("ratings")
        .select("*, bookings(scheduled_start, channel)")
        .in_("booking_id", booking_ids)
        .order("created_at", desc=True)
        .execute()
        .data
    )
