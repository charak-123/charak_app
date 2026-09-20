"""
Payouts router.

Doctor-facing: what am I owed, what has been paid, where does it go.
Ops-facing:    run a payout, advance it, record the bank reference.

The transfer itself is deliberately manual-by-default: ``mark_payout`` records
what ops did in the bank portal. Razorpay Payouts (RazorpayX) can be plugged into
``_initiate_transfer`` without touching the ledger model.
"""
from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import APIRouter, BackgroundTasks, Depends
from pydantic import BaseModel, Field, field_validator

from ..db import supabase
from ..deps import require_doctor, require_ops
from ..errors import AppError
from ..services import notifications, payouts as engine

router = APIRouter()


def _now() -> datetime:
    return datetime.now(timezone.utc)


# ── Doctor: balance, ledger, payout history ───────────────────────────────────

@router.get("/me/balance")
def my_balance(user: dict = Depends(require_doctor)):
    """
    Money view for the doctor's earnings tab.

    ``payable_net`` is the number that matters: gross earned minus Charak's
    commission, not yet transferred.
    """
    return {
        **engine.balance(user["sub"]),
        "commission_pct": float(engine.commission_pct_for(user["sub"])),
    }


@router.get("/me/ledger")
def my_ledger(status: Optional[str] = None, user: dict = Depends(require_doctor)):
    """Per-visit breakdown: gross, commission withheld, net owed."""
    if status and status not in ("payable", "paid", "reversed"):
        raise AppError("status must be payable, paid or reversed", 400)
    return engine.ledger(user["sub"], status)


@router.get("/me")
def my_payouts(user: dict = Depends(require_doctor)):
    return (
        supabase.table("payouts").select("*")
        .eq("doctor_id", user["sub"])
        .order("created_at", desc=True)
        .execute()
        .data
    )


# ── Doctor: bank account ──────────────────────────────────────────────────────

class BankAccount(BaseModel):
    account_holder: str = Field(min_length=2, max_length=120)
    account_number: str = Field(min_length=6, max_length=20)
    ifsc: str
    bank_name: Optional[str] = None
    upi_id: Optional[str] = None

    @field_validator("ifsc")
    @classmethod
    def _check_ifsc(cls, v: str) -> str:
        v = v.strip().upper()
        # RBI format: 4 letters, '0', then 6 alphanumerics.
        if len(v) != 11 or not v[:4].isalpha() or v[4] != "0" or not v[5:].isalnum():
            raise ValueError("ifsc must be 11 characters, e.g. HDFC0001234")
        return v

    @field_validator("account_number")
    @classmethod
    def _check_account(cls, v: str) -> str:
        v = v.strip()
        if not v.isdigit():
            raise ValueError("account_number must be digits only")
        return v


@router.put("/me/bank-account")
def upsert_bank_account(body: BankAccount, user: dict = Depends(require_doctor)):
    """
    Save or replace the payout destination.

    Editing resets ``verified`` — a changed account has not been checked, and
    treating it as verified is how money reaches the wrong person.
    """
    payload = {**body.model_dump(), "doctor_id": user["sub"], "verified": False}
    row = (
        supabase.table("doctor_bank_accounts")
        .upsert(payload, on_conflict="doctor_id")
        .execute()
        .data[0]
    )
    return _mask(row)


@router.get("/me/bank-account")
def get_bank_account(user: dict = Depends(require_doctor)):
    rows = (
        supabase.table("doctor_bank_accounts").select("*")
        .eq("doctor_id", user["sub"]).execute().data or []
    )
    if not rows:
        raise AppError("No bank account on file", 404)
    return _mask(rows[0])


def _mask(row: dict) -> dict:
    """Never echo a full account number back — last four is enough to recognise."""
    number = str(row.get("account_number") or "")
    return {**row, "account_number": f"••••{number[-4:]}" if len(number) >= 4 else "••••"}


# ── Ops: run and advance payouts ──────────────────────────────────────────────

class PayoutRunRequest(BaseModel):
    doctor_id: str
    period_start: Optional[str] = None   # ISO; defaults to 30 days ago
    period_end: Optional[str] = None     # ISO; defaults to now


@router.post("/run", status_code=201)
def run_payout(body: PayoutRunRequest, user: dict = Depends(require_ops)):
    """Sweep a doctor's payable ledger entries for the period into one payout."""
    end = body.period_end or _now().isoformat()
    start = body.period_start or (_now() - timedelta(days=30)).isoformat()
    if start >= end:
        raise AppError("period_start must be before period_end", 400)
    return engine.create_payout(body.doctor_id, start, end)


class PayoutStatusUpdate(BaseModel):
    status: str                        # "processing" | "paid" | "failed"
    reference: Optional[str] = None    # bank UTR / RazorpayX payout id
    failure_reason: Optional[str] = None


@router.patch("/{payout_id}")
def update_payout(
    payout_id: str,
    body: PayoutStatusUpdate,
    background: BackgroundTasks,
    user: dict = Depends(require_ops),
):
    """
    Advance a payout.

    ``paid`` requires a reference so every rupee that left the account is
    traceable to a bank transaction. ``failed`` returns the entries to payable so
    the next run retries them.
    """
    if body.status == "paid" and not body.reference:
        raise AppError("reference (bank UTR) is required to mark a payout paid", 400)

    payout = engine.mark_payout(payout_id, body.status, body.reference, body.failure_reason)

    if body.status == "paid":
        notifications.payout_paid(payout["doctor_id"], payout, background)

    return payout


@router.get("/")
def list_payouts(
    status: Optional[str] = None,
    doctor_id: Optional[str] = None,
    user: dict = Depends(require_ops),
):
    query = (
        supabase.table("payouts")
        .select("*, doctors(name, phone)")
        .order("created_at", desc=True)
    )
    if status:
        query = query.eq("status", status)
    if doctor_id:
        query = query.eq("doctor_id", doctor_id)
    return query.execute().data


@router.get("/pending-summary")
def pending_summary(user: dict = Depends(require_ops)):
    """
    Every doctor with unpaid earnings — the ops worklist for a payout cycle.

    One query over payable entries, grouped in memory: the row count here is
    bounded by unpaid visits, not by all history.
    """
    entries = (
        supabase.table("doctor_ledger_entries")
        .select("doctor_id, net_amount, gross_amount, commission_amount, doctors(name, phone)")
        .eq("status", "payable")
        .execute()
        .data
        or []
    )

    by_doctor: dict[str, dict] = {}
    for e in entries:
        bucket = by_doctor.setdefault(e["doctor_id"], {
            "doctor_id": e["doctor_id"],
            "doctor_name": (e.get("doctors") or {}).get("name"),
            "doctor_phone": (e.get("doctors") or {}).get("phone"),
            "entry_count": 0,
            "gross": 0.0,
            "commission": 0.0,
            "net": 0.0,
        })
        bucket["entry_count"] += 1
        bucket["gross"] += float(e["gross_amount"] or 0)
        bucket["commission"] += float(e["commission_amount"] or 0)
        bucket["net"] += float(e["net_amount"] or 0)

    rows = sorted(by_doctor.values(), key=lambda r: r["net"], reverse=True)
    return {
        "doctors": rows,
        "total_net": round(sum(r["net"] for r in rows), 2),
        "total_commission": round(sum(r["commission"] for r in rows), 2),
    }


# ── Ops: manual adjustment ────────────────────────────────────────────────────

class AdjustmentRequest(BaseModel):
    doctor_id: str
    amount: float          # positive credits the doctor
    note: str = Field(min_length=3, max_length=300)


@router.post("/adjustments", status_code=201)
def create_adjustment(body: AdjustmentRequest, user: dict = Depends(require_ops)):
    """
    Credit a doctor outside the booking flow — a goodwill payment, or correcting
    a settled payout that can no longer be reversed. Commission does not apply to
    adjustments, so the full amount reaches the doctor.
    """
    if body.amount <= 0:
        raise AppError("amount must be positive", 400)

    gross, _, _ = engine.split(body.amount, 0)
    return supabase.table("doctor_ledger_entries").insert({
        "doctor_id": body.doctor_id,
        "booking_id": None,
        "source": "adjustment",
        "gross_amount": float(gross),
        "commission_pct": 0,
        "commission_amount": 0,
        "net_amount": float(gross),
        "status": "payable",
        "note": body.note,
    }).execute().data[0]
