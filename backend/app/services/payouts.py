"""
Commission and payout engine.

The gap this fills: earnings were *displayed* (``routers/earnings.py`` summed
completed bookings and approved bills) but no money ever moved, and Charak's own
cut was nowhere in the schema. Nothing recorded what a doctor was actually owed.

Model
-----
Every confirmed money event writes one **ledger entry**:

    gross      = what the patient paid
    commission = gross × commission_pct   (doctor override, else platform default)
    net        = gross − commission       (what the doctor is owed)

Entries start ``payable``. A **payout run** sweeps a doctor's payable entries for
a period into one ``payouts`` row, flips them to ``paid``, and records the bank
reference once the transfer settles.

Crediting is idempotent: a unique index on ``(booking_id, source)`` means a
Razorpay webhook delivered twice cannot pay a doctor twice.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from decimal import ROUND_HALF_UP, Decimal
from typing import Optional

from ..config import PLATFORM_COMMISSION_PCT
from ..db import supabase
from ..errors import AppError

VALID_SOURCES = ("consult_fee", "procedure_bill", "adjustment")

# Which statuses a payout may move to, from where. 'paid' and 'failed' are
# final: a failed transfer is retried by a new payout run, never by reviving
# this one.
PAYOUT_TRANSITIONS = {
    "processing": ("pending",),
    "paid": ("pending", "processing"),
    "failed": ("pending", "processing"),
}


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _paise(value) -> Decimal:
    """Round to 2dp the way money is rounded, not the way floats are."""
    return Decimal(str(value or 0)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


def commission_pct_for(doctor_id: str) -> Decimal:
    """Per-doctor override if set, else the platform default."""
    rows = supabase.table("doctors").select("commission_pct") \
        .eq("id", doctor_id).execute().data or []
    override = rows[0].get("commission_pct") if rows else None
    if override is None:
        return _paise(PLATFORM_COMMISSION_PCT)
    return _paise(override)


def split(gross, pct) -> tuple[Decimal, Decimal, Decimal]:
    """Return (gross, commission, net) as exact 2dp decimals."""
    g = _paise(gross)
    commission = _paise(g * _paise(pct) / Decimal("100"))
    return g, commission, _paise(g - commission)


def credit(
    doctor_id: str,
    gross,
    source: str,
    booking_id: Optional[str] = None,
    note: Optional[str] = None,
) -> Optional[dict]:
    """
    Record money owed to a doctor.

    Returns the ledger entry, or the existing one if this (booking, source) pair
    was already credited — so webhook replays are harmless. Returns None for a
    zero or negative gross, which is not an error (a free consult credits
    nothing).
    """
    if source not in VALID_SOURCES:
        raise AppError(f"Invalid ledger source '{source}'", 400)

    g = _paise(gross)
    if g <= 0:
        return None

    if booking_id:
        existing = (
            supabase.table("doctor_ledger_entries")
            .select("*")
            .eq("booking_id", booking_id)
            .eq("source", source)
            .execute()
            .data
            or []
        )
        if existing:
            return existing[0]

    pct = commission_pct_for(doctor_id)
    gross_amt, commission_amt, net_amt = split(g, pct)

    inserted = supabase.table("doctor_ledger_entries").insert({
        "doctor_id": doctor_id,
        "booking_id": booking_id,
        "source": source,
        "gross_amount": float(gross_amt),
        "commission_pct": float(pct),
        "commission_amount": float(commission_amt),
        "net_amount": float(net_amt),
        "status": "payable",
        "note": note,
    }).execute().data or []

    # A unique-index collision means a concurrent confirmation already credited
    # this booking. Return that entry rather than raising — the doctor is paid
    # exactly once either way.
    if not inserted:
        return _existing(booking_id, source)
    return inserted[0]


def _existing(booking_id: Optional[str], source: str) -> Optional[dict]:
    if not booking_id:
        return None
    rows = (
        supabase.table("doctor_ledger_entries")
        .select("*")
        .eq("booking_id", booking_id)
        .eq("source", source)
        .execute()
        .data
        or []
    )
    return rows[0] if rows else None


def reverse(booking_id: str, source: str, note: str = "reversed") -> Optional[dict]:
    """
    Reverse a credit — a refund, or a bill withdrawn after approval.

    Runs as one locked statement in the database (``reverse_ledger_credit``,
    migration 0022):

    * ``payable``: marked ``reversed``; the money never left.
    * ``paid``: a negative ``reversal`` entry is added, and the doctor's next
      payout recovers it. This used to raise a 409 *after* the booking had been
      cancelled and the refund sent, so the doctor kept the payout while the
      patient was refunded.
    * already reversed, or never credited: nothing changes.

    Safe to call repeatedly. Returns the entry that represents the reversal, or
    None if the booking was never credited.
    """
    if source not in ("consult_fee", "procedure_bill"):
        raise AppError(f"Cannot reverse a '{source}' entry", 400)
    return supabase.rpc("reverse_ledger_credit", {
        "p_booking_id": booking_id,
        "p_source": source,
        "p_note": note,
    }).execute().data


def balance(doctor_id: str) -> dict:
    """What a doctor is owed, has been paid, and has in flight."""
    entries = (
        supabase.table("doctor_ledger_entries")
        .select("gross_amount, commission_amount, net_amount, status, source")
        .eq("doctor_id", doctor_id)
        .execute()
        .data
        or []
    )

    def total(field, *statuses):
        return float(sum(
            _paise(e[field]) for e in entries if e["status"] in statuses
        ))

    return {
        "payable_net": total("net_amount", "payable"),
        "paid_net": total("net_amount", "paid"),
        "lifetime_gross": total("gross_amount", "payable", "paid"),
        "lifetime_commission": total("commission_amount", "payable", "paid"),
        "entry_count": len([e for e in entries if e["status"] != "reversed"]),
    }


def ledger(doctor_id: str, status: Optional[str] = None) -> list[dict]:
    query = (
        supabase.table("doctor_ledger_entries")
        .select("*, bookings(scheduled_start, channel)")
        .eq("doctor_id", doctor_id)
        .order("created_at", desc=True)
    )
    if status:
        query = query.eq("status", status)
    return query.execute().data or []


# ── Payout runs ──────────────────────────────────────────────────────────────

# What a doctor keeps from a late cancellation (LD-005) can be paid out this
# long after the cancellation (LD-006, proposed), the same wait a completed
# visit gets.
CANCELLATION_HOLD = timedelta(hours=48)


def is_payout_eligible(entry: dict, now: Optional[datetime] = None) -> bool:
    """
    Whether a payable entry may go into a payout yet.

    A consult fee is credited when the patient pays, which is before the visit
    happens. Paying it out then would hand the doctor money for a visit that can
    still be cancelled and refunded. So a fee waits until its booking is
    completed, or, for the part a late cancellation leaves the doctor, until 48
    hours after the cancellation. Adjustments and reversals have no visit to
    wait for.
    """
    if entry.get("source") in ("adjustment", "reversal"):
        return True
    booking = entry.get("bookings") or {}
    if booking.get("status") == "completed":
        return True
    if booking.get("status") == "cancelled" and booking.get("cancelled_at"):
        cancelled = datetime.fromisoformat(str(booking["cancelled_at"]).replace("Z", "+00:00"))
        return (now or datetime.now(timezone.utc)) - cancelled >= CANCELLATION_HOLD
    return False


def create_payout(doctor_id: str, period_start: str, period_end: str) -> dict:
    """
    Sweep every eligible payable entry created in the window into one payout.

    Raises if there is nothing to pay, if recoveries leave nothing to pay, or if
    the doctor has no payout destination on file. Paying out to nowhere is worse
    than refusing.
    """
    candidates = (
        supabase.table("doctor_ledger_entries")
        .select("*, bookings(status, cancelled_at)")
        .eq("doctor_id", doctor_id)
        .eq("status", "payable")
        .gte("created_at", period_start)
        .lte("created_at", period_end)
        .execute()
        .data
        or []
    )
    entries = [e for e in candidates if is_payout_eligible(e)]
    if not entries:
        raise AppError("No payable earnings from completed visits in this period", 400)

    bank = supabase.table("doctor_bank_accounts").select("id") \
        .eq("doctor_id", doctor_id).execute().data or []
    if not bank:
        raise AppError("Doctor has no payout details (UPI or bank account) on file", 400)

    gross      = _paise(sum(_paise(e["gross_amount"]) for e in entries))
    commission = _paise(sum(_paise(e["commission_amount"]) for e in entries))
    net        = _paise(sum(_paise(e["net_amount"]) for e in entries))
    if net <= 0:
        # Recoveries (reversals of fees already paid out) outweigh what is owed.
        # Nothing is sent; the entries stay payable and net off future earnings.
        raise AppError(
            f"Nothing to pay: recoveries exceed earnings in this period (net ₹{net})", 400
        )

    payout = supabase.table("payouts").insert({
        "doctor_id": doctor_id,
        "period_start": period_start,
        "period_end": period_end,
        "gross_amount": float(gross),
        "commission_amount": float(commission),
        "net_amount": float(net),
        "status": "pending",
    }).execute().data[0]

    # Attach the entries, but only those still payable. Two runs started at once
    # for the same doctor would otherwise both claim every entry, and the later
    # write would re-point entries the first payout had already counted.
    ids = [e["id"] for e in entries]
    claimed = (
        supabase.table("doctor_ledger_entries").update({
            "status": "paid",
            "payout_id": payout["id"],
        }).in_("id", ids).eq("status", "payable").execute().data or []
    )
    if len(claimed) != len(ids):
        # Lost a race. Give back what this run did claim and void the payout.
        if claimed:
            supabase.table("doctor_ledger_entries").update({
                "status": "payable",
                "payout_id": None,
            }).eq("payout_id", payout["id"]).execute()
        supabase.table("payouts").update({
            "status": "failed",
            "failure_reason": "voided: another payout run claimed these entries",
        }).eq("id", payout["id"]).execute()
        raise AppError("Another payout run for this doctor is in progress. Refresh and retry.", 409)

    return {**payout, "entry_count": len(entries)}


def mark_payout(payout_id: str, status: str, reference: Optional[str] = None,
                failure_reason: Optional[str] = None) -> dict:
    """
    Advance a payout to processing / paid / failed.

    A failed payout returns its entries to ``payable`` so the next run picks them
    up again — the doctor is still owed the money.
    """
    if status not in ("processing", "paid", "failed"):
        raise AppError("status must be processing, paid or failed", 400)

    rows = supabase.table("payouts").select("*").eq("id", payout_id).execute().data or []
    if not rows:
        raise AppError("Payout not found", 404)
    current = rows[0]["status"]

    # Only forward. Marking a *paid* payout failed used to put its entries back
    # to payable, so the next run paid the doctor a second time.
    allowed_from = PAYOUT_TRANSITIONS.get(status, ())
    if current not in allowed_from:
        raise AppError(f"A '{current}' payout cannot be marked '{status}'", 409)

    update: dict = {"status": status, "reference": reference}
    if status == "processing":
        update["initiated_at"] = _now_iso()
    elif status == "paid":
        update["paid_at"] = _now_iso()
    elif status == "failed":
        update["failure_reason"] = failure_reason or "unspecified"

    changed = (
        supabase.table("payouts").update(update)
        .eq("id", payout_id).in_("status", list(allowed_from))
        .execute().data or []
    )
    if not changed:
        raise AppError("This payout was just updated. Refresh to see where it stands.", 409)
    payout = changed[0]

    if status == "failed":
        supabase.table("doctor_ledger_entries").update({
            "status": "payable",
            "payout_id": None,
        }).eq("payout_id", payout_id).execute()

    return payout
