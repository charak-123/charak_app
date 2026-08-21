"""
Procedure bills router.

Flow:
  booking completed → POST /bookings/:id/procedure-bill (doctor submits line items)
  if total > doctor.procedure_review_threshold → status = under_review
  else                                          → status = approved (ready for patient payment)
  ops approves via admin → status = approved
  patient pays → status = paid (handled in payments router)
"""
from typing import Optional

from fastapi import APIRouter, Depends
from pydantic import BaseModel

from ..db import supabase
from ..deps import require_doctor, require_ops, get_current_user
from ..errors import AppError

router = APIRouter()


class BillLineItem(BaseModel):
    name: str
    price: float


class ProcedureBillCreate(BaseModel):
    items: list[BillLineItem]


@router.post("/{booking_id}/procedure-bill", status_code=201)
def create_bill(booking_id: str, body: ProcedureBillCreate, user: dict = Depends(require_doctor)):
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
    doc = supabase.table("doctors").select("procedure_review_threshold") \
        .eq("id", user["sub"]).single().execute().data
    threshold = doc.get("procedure_review_threshold") if doc else None
    needs_review = threshold is not None and total > threshold
    status = "under_review" if needs_review else "approved"

    bill = supabase.table("procedure_bills").insert({
        "booking_id": booking_id,
        "total": total,
        "status": status,
    }).execute().data[0]

    # Store line items as procedure_bill_items (embedded in bill JSON for now via metadata)
    # Line items stored on procedure_bills.items JSONB column (added in migration 0006)
    supabase.table("procedure_bills").update({
        "items": [item.model_dump() for item in body.items],
    }).eq("id", bill["id"]).execute()

    return {**bill, "items": [item.model_dump() for item in body.items], "needs_review": needs_review}


@router.get("/{booking_id}/procedure-bill")
def get_bill(booking_id: str, user: dict = Depends(get_current_user)):
    b = supabase.table("bookings").select("patient_id, doctor_id").eq("id", booking_id).single().execute().data
    if not b:
        raise AppError("Booking not found", 404)
    if b["patient_id"] != user["sub"] and b["doctor_id"] != user["sub"]:
        raise AppError("Forbidden", 403)
    result = supabase.table("procedure_bills").select("*").eq("booking_id", booking_id).execute()
    if not result.data:
        raise AppError("No procedure bill for this booking", 404)
    return result.data[0]


@router.patch("/{booking_id}/procedure-bill/approve")
def approve_bill(booking_id: str, user: dict = Depends(require_ops)):
    """Ops approves a bill that was under senior review."""
    bill = _get_bill_for_booking(booking_id)
    if bill["status"] != "under_review":
        raise AppError(f"Bill status is '{bill['status']}', not under_review", 400)
    from datetime import datetime, timezone
    return supabase.table("procedure_bills").update({
        "status": "approved",
        "reviewed_by": user["sub"],
        "reviewed_at": datetime.now(timezone.utc).isoformat(),
    }).eq("id", bill["id"]).execute().data[0]


@router.patch("/{booking_id}/procedure-bill/flag")
def flag_bill(booking_id: str, user: dict = Depends(require_ops)):
    """Ops flags a bill — keeps it under_review, logs reviewer."""
    bill = _get_bill_for_booking(booking_id)
    if bill["status"] != "under_review":
        raise AppError(f"Bill status is '{bill['status']}', cannot flag", 400)
    from datetime import datetime, timezone
    return supabase.table("procedure_bills").update({
        "reviewed_by": user["sub"],
        "reviewed_at": datetime.now(timezone.utc).isoformat(),
    }).eq("id", bill["id"]).execute().data[0]


# ── Helpers ───────────────────────────────────────────────────────────────────

def _get_completed_booking(booking_id: str, doctor_id: str) -> dict:
    result = supabase.table("bookings").select("*").eq("id", booking_id).single().execute()
    if not result.data:
        raise AppError("Booking not found", 404)
    b = result.data
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
