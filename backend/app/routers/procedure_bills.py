"""
Procedure bills router.

Flow:
  booking completed → POST /bookings/:id/procedure-bill (doctor submits line items)
  if total > doctor.procedure_review_threshold → status = under_review
  else                                          → status = approved (ready for patient payment)
  ops approves via admin → status = approved
  patient pays → status = paid (handled in payments router)
"""

from fastapi import APIRouter, BackgroundTasks, Depends
from pydantic import BaseModel, Field

from ..db import fetch_one, supabase
from ..deps import require_doctor, require_ops, get_current_user
from ..errors import AppError
from ..services import notifications

router = APIRouter()


class BillLineItem(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    price: float = Field(gt=0)


class ProcedureBillCreate(BaseModel):
    items: list[BillLineItem]


@router.post("/{booking_id}/procedure-bill", status_code=201)
def create_bill(
    booking_id: str,
    body: ProcedureBillCreate,
    background: BackgroundTasks,
    user: dict = Depends(require_doctor),
):
    if not body.items:
        raise AppError("At least one line item is required", 400)

    b = _get_completed_booking(booking_id, user["sub"])

    # Prevent duplicate bills
    existing = supabase.table("procedure_bills").select("id").eq("booking_id", booking_id).execute()
    if existing.data:
        raise AppError("A procedure bill already exists for this booking", 409)

    total = sum(item.price for item in body.items)
    if total <= 0:
        raise AppError("Bill total must be positive", 400)

    # Check senior review threshold
    doc = fetch_one(supabase.table("doctors").select("procedure_review_threshold") \
        .eq("id", user["sub"]))
    threshold = doc.get("procedure_review_threshold") if doc else None
    needs_review = threshold is not None and total > threshold
    status = "under_review" if needs_review else "approved"

    items = [item.model_dump() for item in body.items]

    # Written in one insert — the previous insert-then-update left a window where
    # a bill existed with no line items, which ops review would have shown empty.
    bill = supabase.table("procedure_bills").insert({
        "booking_id": booking_id,
        "total": total,
        "status": status,
        "items": items,
    }).execute().data[0]

    if needs_review:
        notifications.bill_under_review(b, total, background)
    else:
        notifications.bill_approved(b, total, background)

    return {**bill, "items": items, "needs_review": needs_review}


@router.get("/{booking_id}/procedure-bill")
def get_bill(booking_id: str, user: dict = Depends(get_current_user)):
    b = fetch_one(supabase.table("bookings").select("patient_id, doctor_id").eq("id", booking_id))
    if not b:
        raise AppError("Booking not found", 404)
    if b["patient_id"] != user["sub"] and b["doctor_id"] != user["sub"]:
        raise AppError("Forbidden", 403)
    result = supabase.table("procedure_bills").select("*").eq("booking_id", booking_id).execute()
    if not result.data:
        raise AppError("No procedure bill for this booking", 404)
    return result.data[0]


@router.patch("/{booking_id}/procedure-bill/approve")
def approve_bill(
    booking_id: str,
    background: BackgroundTasks,
    user: dict = Depends(require_ops),
):
    """Ops approves a bill that was under senior review — it becomes payable."""
    bill = _get_bill_for_booking(booking_id)
    if bill["status"] != "under_review":
        raise AppError(f"Bill status is '{bill['status']}', not under_review", 400)

    from datetime import datetime, timezone
    updated = supabase.table("procedure_bills").update({
        "status": "approved",
        "reviewed_by": _reviewer_id(user),
        "reviewed_at": datetime.now(timezone.utc).isoformat(),
    }).eq("id", bill["id"]).execute().data[0]

    booking = fetch_one(supabase.table("bookings").select("*").eq("id", booking_id))
    if booking:
        notifications.bill_approved(booking, bill["total"], background)

    return updated


@router.patch("/{booking_id}/procedure-bill/flag")
def flag_bill(booking_id: str, user: dict = Depends(require_ops)):
    """Ops flags a bill — keeps it under_review, logs reviewer."""
    bill = _get_bill_for_booking(booking_id)
    if bill["status"] != "under_review":
        raise AppError(f"Bill status is '{bill['status']}', cannot flag", 400)
    from datetime import datetime, timezone
    return supabase.table("procedure_bills").update({
        "reviewed_by": _reviewer_id(user),
        "reviewed_at": datetime.now(timezone.utc).isoformat(),
    }).eq("id", bill["id"]).execute().data[0]


# ── Helpers ───────────────────────────────────────────────────────────────────

def _reviewer_id(user: dict):
    """
    ``procedure_bills.reviewed_by`` is a doctors(id) foreign key, but the admin
    login issues a token with sub="admin". Writing that would violate the FK, so
    a non-UUID reviewer is recorded as null and the audit trail lives in
    audit_log instead.
    """
    sub = user.get("sub")
    return sub if _looks_like_uuid(sub) else None


def _looks_like_uuid(value) -> bool:
    import uuid
    try:
        uuid.UUID(str(value))
        return True
    except (ValueError, AttributeError, TypeError):
        return False

def _get_completed_booking(booking_id: str, doctor_id: str) -> dict:
    b = fetch_one(supabase.table("bookings").select("*").eq("id", booking_id))
    if not b:
        raise AppError("Booking not found", 404)
    if b["doctor_id"] != doctor_id:
        raise AppError("Forbidden", 403)
    if b["status"] != "completed":
        raise AppError("Booking must be completed before submitting a procedure bill", 400)
    return b


def _get_bill_for_booking(booking_id: str) -> dict:
    result = supabase.table("procedure_bills").select("*").eq("booking_id", booking_id).execute()
    if not result.data:
        raise AppError("No procedure bill for this booking", 404)
    return result.data[0]
