"""
The patient's remedy when a doctor doesn't attend (migration 0028, spec §14,
D11/D12 at their recommended defaults): a full refund, or another doctor
paid from the same payment.

No wallet and no credit balance. Choosing another doctor cancels the original
booking without a refund (its doctor's credit is reversed) and requests the
new one; when the new doctor accepts, the original payment is re-pointed to
the new booking and whatever is left over is refunded (settle_replacement).
A replacement can't cost more than what's left of the payment: the patient
can take the refund and book anyone. If the new doctor doesn't take it, the
patient chooses again; with no choice within 24 hours, they're refunded.
"""
from __future__ import annotations

import logging
from datetime import datetime, timedelta, timezone
from typing import Optional

from ..db import fetch_one, supabase
from ..errors import AppError
from . import app_config, incidents, notifications, payouts, refunds, visits

logger = logging.getLogger(__name__)


def _now() -> datetime:
    return datetime.now(timezone.utc)


def budget_paise(booking_id: str) -> int:
    """What a replacement can cost: what's still refundable on the original
    consult payment."""
    pay = fetch_one(
        supabase.table("payments").select("id").eq("booking_id", booking_id)
        .eq("type", "consult_fee").in_("status", ["completed", "partially_refunded"])
        .order("created_at").limit(1)
    )
    if not pay:
        return 0
    return int(supabase.rpc("payment_refundable_paise", {"p_payment_id": pay["id"]}).execute().data or 0)


def options(incident: dict) -> dict:
    """What the patient can choose now."""
    open_ = incident["remedy_eligible"] and incident["remedy"] in ("none", "pending")
    booking = fetch_one(supabase.table("bookings").select("channel, doctor_id, category_id")
                        .eq("id", incident["booking_id"])) or {}
    return {
        "available": open_,
        "refund_paise": budget_paise(incident["booking_id"]) if open_ else 0,
        "replacement_budget_paise": budget_paise(incident["booking_id"]) if open_ else 0,
        "channel": booking.get("channel"),
        "exclude_doctor_id": booking.get("doctor_id"),
        "default_refund_at": (
            (datetime.fromisoformat(str(incident["remedy_offered_at"]).replace("Z", "+00:00"))
             + timedelta(hours=_default_hours())).isoformat()
            if open_ and incident.get("remedy_offered_at") else None
        ),
    }


def _default_hours() -> int:
    return int(app_config.get("remedy_default_refund_hours", 24) or 24)


def _send_refunds(rows: list[dict], booking: dict, background=None) -> None:
    for r in rows:
        try:
            refunds.execute(r, background)
        except Exception as exc:                   # noqa: BLE001 — the sweep retries
            logger.error("refund %s not sent inline: %r", r.get("id"), exc)
        notifications.refund_started(booking, r["amount_paise"], background, refund_id=r.get("id"))


def refund(incident_id: str, actor_role: str, actor_id: Optional[str], background=None) -> dict:
    result = supabase.rpc("apply_remedy_refund", {
        "p_incident_id": incident_id, "p_actor_role": actor_role, "p_actor_id": actor_id,
    }).execute().data or {}
    outcome = result.get("outcome")
    if outcome == "forbidden" or outcome == "not_found":
        raise AppError("Case not found", 404)
    if outcome == "already":
        raise AppError("This has already been resolved", 409)
    if outcome == "not_eligible":
        raise AppError("A refund isn't available for this case yet. Our team is looking at it.", 409)
    if outcome != "ok":
        raise AppError("This couldn't be completed. Please try again.", 409)
    inc = incidents.get(incident_id)
    booking = fetch_one(supabase.table("bookings").select("*").eq("id", inc["booking_id"])) or {}
    _send_refunds(result.get("refunds") or [], booking, background)
    return {"incident": incidents.public(inc), "refunds": result.get("refunds") or []}


def start_replacement(incident_id: str, patient_id: str, booking_fields: dict) -> dict:
    """Create the replacement booking (the backend has already priced it and
    checked the slot). Returns the new booking."""
    try:
        result = supabase.rpc("start_replacement", {
            "p_incident_id": incident_id, "p_patient_id": patient_id, "p_booking": booking_fields,
        }).execute().data or {}
    except Exception as exc:                       # noqa: BLE001
        if "slot_taken" in str(exc):
            raise AppError("Slot already booked", 409)
        raise
    outcome = result.get("outcome")
    if outcome in ("not_found", "forbidden"):
        raise AppError("Case not found", 404)
    if outcome == "already":
        raise AppError("This case has already been resolved", 409)
    if outcome == "not_eligible":
        raise AppError("Another doctor can't be arranged for this case", 409)
    if outcome == "over_budget":
        raise AppError("That costs more than your earlier payment covers. Choose a price within "
                       "it, or take the refund and book as usual.", 409,
                       budget_paise=result.get("budget_paise"))
    if outcome != "ok":
        raise AppError("This couldn't be completed. Please try again.", 409)
    return result["booking"]


def settle(booking: dict, doctor_name: str, background=None) -> dict:
    """The replacement doctor accepted: pay the booking from the original
    payment, credit the new doctor, refund any difference."""
    result = supabase.rpc("settle_replacement", {"p_booking_id": booking["id"]}).execute().data or {}
    if result.get("outcome") != "ok":
        raise AppError("The earlier payment no longer covers this booking. Our team will be in touch.", 409)
    paid = {**booking, **(result.get("booking") or {})}
    payouts.credit(paid["doctor_id"], paid["price_paise"] / 100, "consult_fee",
                   booking_id=paid["id"], note="consult fee (paid from an earlier booking)")
    original = fetch_one(supabase.table("bookings").select("*").eq("id", paid["replaces_booking_id"])) or paid
    _send_refunds(result.get("refunds") or [], original, background)
    visits.schedule_reminders(paid)
    notifications.replacement_confirmed(paid, doctor_name, background)
    return paid


def sweep(now: Optional[datetime] = None) -> dict:
    """Run every tick: replacements whose doctor didn't take them go back to
    the patient; remedies left unchosen for 24 hours become refunds; online
    no-shows with clear evidence are confirmed after 48 hours."""
    now = now or _now()
    reopened = refunded = 0

    pending = (
        supabase.table("incidents").select("id, remedy_booking_id, patient_id, booking_id")
        .eq("remedy", "replacement").not_.is_("remedy_booking_id", "null").limit(100).execute().data or []
    )
    for inc in pending:
        b = fetch_one(supabase.table("bookings").select("id, status").eq("id", inc["remedy_booking_id"]))
        if not b or b["status"] not in ("declined", "cancelled"):
            continue
        settled = supabase.table("payments").select("id").eq("booking_id", b["id"]) \
            .not_.is_("transferred_from_payment_id", "null").execute().data
        if settled:
            continue                               # paid, then cancelled: an ordinary cancel
        updated = (
            supabase.table("incidents").update({
                "remedy": "pending", "remedy_booking_id": None, "remedy_offered_at": now.isoformat(),
            }).eq("id", inc["id"]).eq("remedy", "replacement").execute().data or []
        )
        if updated:
            incidents.event(inc["id"], "remedy_replacement_fell_through", "system", None,
                            metadata={"booking_id": b["id"], "status": b["status"]})
            notifications.remedy_reopened(updated[0])
            reopened += 1

    cutoff = (now - timedelta(hours=_default_hours())).isoformat()
    stale = (
        supabase.table("incidents").select("id")
        .eq("remedy_eligible", True).in_("remedy", ["none", "pending"])
        .lte("remedy_offered_at", cutoff).limit(50).execute().data or []
    )
    for inc in stale:
        try:
            refund(inc["id"], "system", None)
            refunded += 1
        except AppError as exc:
            # The visit went ahead after all, or it was resolved meanwhile.
            logger.info("no default refund for incident %s: %s", inc["id"], exc.message)
            supabase.table("incidents").update({"remedy": "none", "remedy_eligible": False}) \
                .eq("id", inc["id"]).in_("remedy", ["none", "pending"]).execute()

    return {"replacements_reopened": reopened, "default_refunds": refunded,
            "auto_confirmed": incidents.auto_confirm_due(now)}
