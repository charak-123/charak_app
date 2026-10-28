import logging
from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import APIRouter, BackgroundTasks, Depends, Request
from postgrest.exceptions import APIError
from pydantic import BaseModel, Field

from ..config import PAYMENT_HOLD_MINUTES
from ..db import fetch_one, supabase
from ..deps import get_current_user, require_doctor, require_patient
from ..errors import AppError
from ..services import (
    app_config, availability, booking_state, cancellation, geo, incidents, legal, notifications,
    pricing, refunds, remedies, reschedules, visits,
)
from ..services.rate_limit import client_ip, rate_limiter

logger = logging.getLogger(__name__)

router = APIRouter()

VALID_STATUSES = (
    "requested", "accepted", "declined", "paid", "in_progress", "consulted", "completed",
    "cancelled", "no_show",
)

# Statuses a patient or doctor can still cancel from. Once the consultation has
# started there is nothing left to cancel (cancel_booking() agrees).
CANCELLABLE_STATUSES = ("requested", "accepted", "paid")

# Statuses that occupy a slot — a new booking cannot take a time already held by
# one of these. Derived from the availability service's list so the grid and the
# booking check can never disagree: anything hidden from the patient must also
# be refused here, and vice versa. `completed` is excluded only because a
# completed booking is necessarily in the past.
SLOT_HOLDING_STATUSES = [
    s for s in availability.SLOT_OCCUPYING_STATUSES if s != "completed"
]


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _now_iso() -> str:
    return _now().isoformat()


# ── Patient creates a booking ─────────────────────────────────────────────────

class BookingCreate(BaseModel):
    doctor_id: str
    channel: str                 # "online_consult" | "home_visit"
    scheduled_start: str         # ISO datetime "2026-08-25T09:00:00+05:30"
    category_id: Optional[str]   = None
    # Required for home_visit: which of the patient's saved addresses to visit.
    # Ignored for online_consult, which has no destination.
    address_id: Optional[str]    = None
    # The cancellation policy version the patient ticked on the confirm screen
    # (GET /legal/cancellation-policy). Recorded with the booking; refused if
    # it is no longer the current version, so nobody books on terms they
    # weren't shown.
    accepted_policy_version: Optional[str] = Field(default=None, max_length=40)
    # The price option the patient picked (GET /doctors/{id}/prices, or
    # /bookings/{id}/follow-up-options), and the price it showed. The server
    # resolves the price itself (services/pricing.py); expected_price_paise
    # only stops a booking at a price the patient wasn't shown — if the doctor
    # changed it since, nothing is booked and the new prices come back.
    # All optional: app builds from before migration 0026 send none of them
    # and get the first-visit price they were shown.
    price_rule_id: Optional[str] = Field(default=None, max_length=40)
    duration_min: Optional[int] = Field(default=None, ge=5, le=240)
    expected_price_paise: Optional[int] = Field(default=None, ge=0)
    # The consultation this follow-up continues, for the follow-up price.
    follow_up_of: Optional[str] = Field(default=None, max_length=40)
    # A doctor didn't attend and the patient chose another doctor instead of a
    # refund (services/remedies.py): the case it remedies. Nothing is paid;
    # the earlier payment covers it when the new doctor accepts.
    replaces_incident_id: Optional[str] = Field(default=None, max_length=40)


@router.post("/", status_code=201, dependencies=[rate_limiter("booking-create", 10, 600)])
def create_booking(
    body: BookingCreate,
    background: BackgroundTasks,
    request: Request,
    # require_patient, not get_current_user: this writes patient_id from the
    # token subject, so a doctor's token would have created a booking whose
    # patient is a doctor id — a row nothing downstream can make sense of.
    user: dict = Depends(require_patient),
):
    if body.channel not in ("online_consult", "home_visit"):
        raise AppError("Invalid channel", 400)

    # Doctor must exist, be verified, and not be suspended.
    doc = fetch_one(
        supabase.table("doctors")
        .select("*")
        .eq("id", body.doctor_id)
    )
    if not doc or doc["verification_status"] != "verified":
        raise AppError("Doctor not found or not verified", 404)
    if doc.get("suspended"):
        raise AppError("This doctor is not currently accepting bookings", 409)
    if doc.get("accepting_requests") is False:
        raise AppError("This doctor isn't taking new requests right now", 409)

    if body.channel == "home_visit" and not doc.get("offers_home_visit"):
        raise AppError("This doctor does not offer home visits", 400)
    if body.channel == "online_consult" and not doc.get("offers_online_consult"):
        raise AppError("This doctor does not offer online consults", 400)

    # Terms, Privacy and (for an online consult) Telemedicine consent, at their
    # current versions. Switched on once app builds with the consent screens
    # are out (app_config); a 428 makes the app show the consent sheet.
    if app_config.get("require_legal_acceptance") is True:
        needed = legal.REQUIRED["patient"] + (
            legal.ONLINE_EXTRA if body.channel == "online_consult" else ())
        legal.require(user["sub"], "patient", needed)

    policy = cancellation.current_policy(body.channel)
    if body.accepted_policy_version is not None:
        if body.accepted_policy_version != policy["version"]:
            raise AppError(
                "The cancellation policy has just changed. Please review it again.",
                409, policy=cancellation.public_policy(policy),
            )
    elif app_config.get("require_booking_policy_acceptance") is True:
        raise AppError("Please review and accept the cancellation policy.", 428,
                       policy=cancellation.public_policy(policy))

    try:
        start = datetime.fromisoformat(body.scheduled_start.replace("Z", "+00:00"))
    except ValueError:
        raise AppError("Invalid scheduled_start format", 400)
    if start.tzinfo is None:
        raise AppError("scheduled_start must include a timezone offset, e.g. +05:30", 400)

    # A home visit needs somewhere to go, and that somewhere has to be inside the
    # radius the doctor agreed to cover.
    address_fields = _resolve_home_visit_address(body, doc, user["sub"])

    # The price rule this booking is charged by, snapshotted onto it: a doctor
    # changing their prices later never changes what this patient pays.
    rule = pricing.resolve(
        body.doctor_id, body.channel, patient_id=user["sub"], start=start,
        rule_id=body.price_rule_id, duration_min=body.duration_min,
        follow_up_of=body.follow_up_of,
    )
    if body.expected_price_paise is not None and body.expected_price_paise != rule["price_paise"]:
        raise AppError(
            "This doctor has just changed their price. Please check it again.", 409,
            code="price_changed", price_paise=rule["price_paise"],
            prices=pricing.price_list(body.doctor_id, doc),
        )
    # A legacy request (no length chosen) was offered times on the legacy grid.
    legacy_grid = body.price_rule_id is None and body.duration_min is None

    if body.replaces_incident_id:
        return _create_replacement(body, doc, rule, start, policy, user, background)

    existing = (
        supabase.table("bookings")
        .select("id")
        .eq("doctor_id", body.doctor_id)
        .eq("scheduled_start", body.scheduled_start)
        .in_("status", SLOT_HOLDING_STATUSES)
        .execute()
    )
    if existing.data:
        raise AppError("Slot already booked", 409)

    _assert_bookable(body.doctor_id, start, None if legacy_grid else rule["duration_min"])

    # The check above loses to a concurrent request that passed it a moment
    # earlier, so uq_booking_doctor_slot_active (migration 0010) is what actually
    # guarantees one live booking per doctor per slot. Whichever insert arrives
    # second raises 23505, and its patient gets the same 409 as the slow path.
    try:
        row = supabase.table("bookings").insert({
            "patient_id": user["sub"],
            "doctor_id": body.doctor_id,
            "channel": body.channel,
            "scheduled_start": body.scheduled_start,
            "category_id": body.category_id,
            "price_confirmed": rule["price_paise"] / 100,
            "price_paise": rule["price_paise"],
            "price_rule_id": rule["id"],
            "duration_min": rule["duration_min"],
            "scheduled_end": (start + timedelta(minutes=rule["duration_min"])).isoformat(),
            "visit_category": rule["visit_category"],
            "follow_up_of": body.follow_up_of,
            "status": "requested",
            # The version shown and accepted, not whatever is current a moment
            # later when the row lands.
            "cancellation_policy_id": policy["id"],
            **address_fields,
        }).execute().data[0]
    except APIError as exc:
        code = getattr(exc, "code", None)
        if code == "23505" and "uq_bookings_one_follow_up" in str(exc):
            raise AppError("A follow-up for that consultation is already booked", 409)
        # 23505: same start (0010). 23P01: overlapping times (0026).
        if code in ("23505", "23P01"):
            raise AppError("Slot already booked", 409)
        raise

    if body.accepted_policy_version is not None:
        try:
            legal.record_booking_policy(user["sub"], policy, row["id"], ip=client_ip(request))
        except Exception as exc:                  # noqa: BLE001 — the booking stands
            logger.error("could not record policy acceptance for %s: %r", row["id"], exc)

    patient = supabase.table("users").select("name").eq("id", user["sub"]).execute().data or []
    patient_name = (patient[0].get("name") if patient else None) or "A patient"
    notifications.booking_requested(row, patient_name, background)

    return {**row, "cancellation_policy": cancellation.public_policy(policy)}


# ── Doctor lists ──────────────────────────────────────────────────────────────

@router.get("/doctor/incoming")
def list_incoming(user: dict = Depends(require_doctor)):
    """
    All requested bookings for this doctor, newest first.

    Street addresses are withheld here — these are requests the doctor has not
    accepted yet. City, PIN and distance still come through.
    """
    rows = (
        supabase.table("bookings")
        .select("*, users(name), intake_media(media_type, transcript_text, transcript_summary, created_at)")
        .eq("doctor_id", user["sub"])
        .eq("status", "requested")
        .order("created_at", desc=True)
        .execute()
        .data
        or []
    )
    return [_with_issue(_redact_address_for_doctor(r)) for r in rows]


def _with_issue(row: dict) -> dict:
    """
    Put the patient's own words on the request card (design system V2): the
    typed note, else the summary of a voice note, else its transcript. The
    full intake, media included, stays on the request detail screen.
    """
    media = sorted(row.pop("intake_media", None) or [], key=lambda m: m.get("created_at") or "")
    issue = None
    for m in media:
        if m.get("media_type") == "text" and m.get("transcript_text"):
            issue = m["transcript_text"]
            break
    if issue is None:
        for m in media:
            if m.get("transcript_summary") or m.get("transcript_text"):
                issue = m.get("transcript_summary") or m.get("transcript_text")
                break
    return {**row, "issue": issue}


@router.get("/doctor/active")
def list_active(user: dict = Depends(require_doctor)):
    """The current queue: accepted, paid, and consultations under way."""
    rows = (
        supabase.table("bookings")
        .select("*, users(name)")
        .eq("doctor_id", user["sub"])
        .in_("status", ["accepted", "paid", "in_progress"])
        .order("scheduled_start")
        .execute()
        .data
        or []
    )
    return [_redact_address_for_doctor(r) for r in rows]


@router.get("/doctor/history")
def list_history(user: dict = Depends(require_doctor)):
    """Everything past: finished, declined, cancelled, and consultations whose
    prescription is with the patient ('consulted', waiting for them to open it)."""
    rows = (
        supabase.table("bookings")
        .select("*, users(name)")
        .eq("doctor_id", user["sub"])
        .in_("status", ["consulted", "completed", "declined", "cancelled", "no_show"])
        .order("scheduled_start", desc=True)
        .execute()
        .data
        or []
    )
    return [_redact_address_for_doctor(r) for r in rows]


# ── Patient: own bookings ─────────────────────────────────────────────────────

@router.get("/patient/mine")
@router.get("/patient/list")
def patient_bookings(user: dict = Depends(get_current_user)):
    return (
        supabase.table("bookings")
        .select("*, doctors(name, photo_url, categories(name))")
        .eq("patient_id", user["sub"])
        .order("scheduled_start", desc=True)
        .execute()
        .data
    )


# ── Single booking ────────────────────────────────────────────────────────────

@router.get("/{booking_id}")
def get_booking(booking_id: str, user: dict = Depends(get_current_user)):
    b = fetch_one(
        supabase.table("bookings")
        .select("*, users(name), doctors(name, photo_url, categories(name)), "
                "policies(channel, version, summary, rules)")
        .eq("id", booking_id)
    )
    if not b:
        raise AppError("Booking not found", 404)
    if b["patient_id"] != user["sub"] and b["doctor_id"] != user["sub"]:
        raise AppError("Forbidden", 403)
    policy = b.pop("policies", None)
    b["cancellation_policy"] = cancellation.public_policy(policy) if policy else None

    # The patient always sees their own address; the doctor only after accepting.
    if b["doctor_id"] == user["sub"] and b["patient_id"] != user["sub"]:
        return _redact_address_for_doctor(b)
    return b


# ── Follow-up prices ──────────────────────────────────────────────────────────

@router.get("/{booking_id}/follow-up-options")
def follow_up_options(booking_id: str, user: dict = Depends(require_patient)):
    """
    Booking a follow-up to this consultation: the doctor's follow-up prices
    and until when they apply. 409 saying why when it doesn't qualify (the
    window has passed, one is already booked, the doctor offers none).
    """
    return pricing.follow_up_options(booking_id, user["sub"])


# ── Timeline ──────────────────────────────────────────────────────────────────

# What the patient and doctor may see of an event's metadata. Payment ids and
# who-did-what inside ops stay with ops (GET /admin/bookings/{id}/timeline).
_PARTICIPANT_METADATA = ("cancelled_by", "minutes")


@router.get("/{booking_id}/timeline")
def booking_timeline(booking_id: str, user: dict = Depends(get_current_user)):
    """The booking's history, oldest first: requested, accepted, paid …"""
    b = fetch_one(supabase.table("bookings").select("patient_id, doctor_id").eq("id", booking_id))
    if not b:
        raise AppError("Booking not found", 404)
    if user["sub"] not in (b["patient_id"], b["doctor_id"]):
        raise AppError("Forbidden", 403)
    return [
        {
            "event": e["event"],
            "from_status": e["from_status"],
            "to_status": e["to_status"],
            "actor_role": e["actor_role"],
            "occurred_at": e["occurred_at"],
            "metadata": {k: v for k, v in (e.get("metadata") or {}).items()
                         if k in _PARTICIPANT_METADATA},
        }
        for e in booking_state.timeline(booking_id)
    ]


# ── Accept / Decline ──────────────────────────────────────────────────────────

@router.patch("/{booking_id}/accept")
def accept_booking(
    booking_id: str,
    background: BackgroundTasks,
    user: dict = Depends(require_doctor),
):
    """
    Accepting starts the payment hold: the patient has PAYMENT_HOLD_MINUTES to
    pay before the slot is released back to the doctor's calendar.
    """
    b = _get_booking_for_doctor(booking_id, user["sub"])
    if b["status"] != "requested":
        raise AppError(f"Cannot accept a booking with status '{b['status']}'", 400)

    # The Practitioner Agreement, Privacy Policy and Cancellation & Refund
    # Policy, at their current versions: the same switch as the patient's
    # side. A 428 makes the doctor app show the documents to sign, then retry.
    if app_config.get("require_legal_acceptance") is True:
        legal.require(user["sub"], "doctor", legal.REQUIRED["doctor"])

    # create_booking checks the doctor is listed, but a request can already be
    # open when ops suspend or reject them. Accepting releases the patient's
    # address and starts their payment hold, so the check has to run here too.
    standing = supabase.table("doctors").select("verification_status, suspended") \
        .eq("id", user["sub"]).execute().data or []
    if not standing or standing[0].get("suspended") or standing[0].get("verification_status") != "verified":
        raise AppError("Your account cannot accept requests right now.", 403)

    updated = booking_state.transition(
        booking_id, "accept", actor_role="doctor", actor_id=user["sub"], expected="requested",
        patch={
            "hold_expires_at": (_now() + timedelta(minutes=PAYMENT_HOLD_MINUTES)).isoformat(),
            # Accepting is what entitles the doctor to the patient's full
            # address. Until now they saw only the area and distance.
            "address_released_at": _now_iso() if b["channel"] == "home_visit" else None,
        },
    )

    doctor = supabase.table("doctors").select("name").eq("id", user["sub"]).execute().data or []
    doctor_name = (doctor[0].get("name") if doctor else None) or "Your doctor"

    if b.get("prepaid_from_payment_id"):
        # A replacement for a doctor who didn't attend: paid from the earlier
        # booking's payment, with anything left over refunded.
        return remedies.settle({**b, **updated}, doctor_name, background)

    if b.get("price_paise") == 0:
        # A free follow-up (the doctor priced it at ₹0): nothing to pay, so
        # accepting confirms it. Same transition a captured payment makes.
        updated = booking_state.transition(
            booking_id, "pay", actor_role="system", expected="accepted",
            patch={"hold_expires_at": None}, metadata={"free": True},
        )
        visits.schedule_reminders({**b, **updated})
        notifications.free_booking_confirmed({**b, **updated}, doctor_name, background)
        return updated

    notifications.booking_accepted({**b, **updated}, doctor_name, background)
    return updated


@router.patch("/{booking_id}/decline")
def decline_booking(
    booking_id: str,
    background: BackgroundTasks,
    user: dict = Depends(require_doctor),
):
    b = _get_booking_for_doctor(booking_id, user["sub"])
    if b["status"] not in ("requested", "accepted"):
        raise AppError(f"Cannot decline a booking with status '{b['status']}'", 400)

    updated = booking_state.transition(
        booking_id, "decline", actor_role="doctor", actor_id=user["sub"],
        expected=b["status"], patch={"hold_expires_at": None},
    )

    doctor = supabase.table("doctors").select("name").eq("id", user["sub"]).execute().data or []
    doctor_name = (doctor[0].get("name") if doctor else None) or "The doctor"
    notifications.booking_declined({**b, **updated}, doctor_name, background)

    # The RPC returns the whole row. A decline before accept must not hand the
    # doctor the address the list and detail views withhold.
    return _redact_address_for_doctor(updated)


# ── Complete ──────────────────────────────────────────────────────────────────

@router.patch("/{booking_id}/complete")
def complete_booking(
    booking_id: str,
    background: BackgroundTasks,
    user: dict = Depends(require_doctor),
):
    b = _get_booking_for_doctor(booking_id, user["sub"])
    if b["status"] not in ("accepted", "paid"):
        raise AppError(f"Cannot complete a booking with status '{b['status']}'", 400)
    # Completing an unpaid booking stranded the fee: _amount_due only issues a
    # consult_fee order while the booking is 'accepted', so once it went to
    # 'completed' the money could never be collected — while still being counted
    # as earnings. The visit has to be paid for before it can be closed.
    if b["status"] == "accepted":
        raise AppError(
            "This booking has not been paid for yet. The patient must pay the "
            "consult fee before the visit can be marked complete.",
            409,
        )

    # Doctor app builds from before migration 0025. Newer builds send the
    # prescription instead, and the booking completes when the patient opens it.
    updated = booking_state.transition(
        booking_id, "complete", actor_role="doctor", actor_id=user["sub"],
        expected="paid", patch={"hold_expires_at": None, "completion_source": "doctor"},
    )
    notifications.visit_completed({**b, **updated}, background)
    return updated


# ── Running late ──────────────────────────────────────────────────────────────

class RunningLate(BaseModel):
    minutes: int = Field(gt=0, le=180)


@router.post("/{booking_id}/running-late")
def running_late(
    booking_id: str,
    body: RunningLate,
    background: BackgroundTasks,
    user: dict = Depends(require_doctor),
):
    """Doctor tells the patient they are delayed. No state change — a nudge only."""
    b = _get_booking_for_doctor(booking_id, user["sub"])
    if b["status"] not in ("accepted", "paid"):
        raise AppError("Only an active booking can be marked running late", 400)

    notifications.doctor_running_late(b, body.minutes, background)
    return {"ok": True, "minutes": body.minutes}


# ── No-show ───────────────────────────────────────────────────────────────────

@router.patch("/{booking_id}/no-show")
def mark_no_show(
    booking_id: str,
    background: BackgroundTasks,
    user: dict = Depends(require_doctor),
):
    """
    Patient never turned up. Terminal, and deliberately does not charge: no
    ledger entry is created, so the doctor earns nothing and the patient owes
    nothing. A paid booking cannot be flipped to no-show — that is a refund,
    which ops handles.
    """
    b = _get_booking_for_doctor(booking_id, user["sub"])
    if b["status"] != "accepted":
        raise AppError(
            f"Only an accepted, unpaid booking can be marked no-show (status is '{b['status']}')",
            400,
        )

    updated = booking_state.transition(
        booking_id, "no_show", actor_role="doctor", actor_id=user["sub"], expected="accepted",
        patch={
            "no_show_marked_by": user["sub"],
            "no_show_at": _now_iso(),
            "hold_expires_at": None,
        },
    )
    notifications.marked_no_show({**b, **updated}, background)
    return updated


# ── Cancel ────────────────────────────────────────────────────────────────────

@router.get("/{booking_id}/cancellation-quote")
def cancellation_quote(booking_id: str, user: dict = Depends(get_current_user)):
    """
    What cancelling now would refund, under this booking's policy version. The
    app shows it in the confirm sheet and sends ``refund_paise`` back as
    ``expected_refund_paise``, so the cancel refunds exactly what was shown.
    """
    b = fetch_one(supabase.table("bookings").select("patient_id, doctor_id, status, "
                                                     "cancellation_policy_id").eq("id", booking_id))
    if not b:
        raise AppError("Booking not found", 404)
    if user["sub"] not in (b["patient_id"], b["doctor_id"]):
        raise AppError("Forbidden", 403)
    by = "patient" if b["patient_id"] == user["sub"] else "doctor"
    policy = cancellation.policy_by_id(b.get("cancellation_policy_id"))
    return {
        **_quote_view(cancellation.quote(booking_id, by)),
        "cancellable": b["status"] in CANCELLABLE_STATUSES,
        "reason_codes": list(cancellation.REASON_CODES[by]),
        "policy": cancellation.public_policy(policy) if policy else None,
    }


def _quote_view(q: dict) -> dict:
    return {k: q.get(k) for k in ("paid_paise", "refund_paise", "kept_paise", "refund_pct",
                                  "free_until", "reason", "policy_version")}


class CancelRequest(BaseModel):
    # The refund the patient was shown (GET .../cancellation-quote). If the
    # outcome has moved since, nothing is cancelled and the new quote comes
    # back with a 409. Optional, for app builds that predate the quote.
    expected_refund_paise: Optional[int] = Field(default=None, ge=0)
    reason_code: Optional[str] = Field(default=None, max_length=40)


@router.patch("/{booking_id}/cancel")
def cancel_booking(
    booking_id: str,
    background: BackgroundTasks,
    body: Optional[CancelRequest] = None,
    user: dict = Depends(get_current_user),
):
    b = fetch_one(supabase.table("bookings").select("*").eq("id", booking_id))
    if not b:
        raise AppError("Booking not found", 404)
    if b["patient_id"] != user["sub"] and b["doctor_id"] != user["sub"]:
        raise AppError("Forbidden", 403)
    if b["status"] not in CANCELLABLE_STATUSES:
        raise AppError(f"Cannot cancel a booking with status '{b['status']}'", 400)

    by = "patient" if b["patient_id"] == user["sub"] else "doctor"
    body = body or CancelRequest()
    reason_code = cancellation.validate_reason(by, body.reason_code)

    # One transaction (migrations 0022–0024): lock the booking, check it's
    # still in the status read above and the refund is still what the patient
    # was shown, cancel it, queue the refund the booking's policy allows, and
    # reverse the doctor's credit for the refunded part (or recover it, if it
    # was already paid out). Doing these as separate calls is what used to
    # leave a cancel half-applied.
    result = supabase.rpc("cancel_booking", {
        "p_booking_id": booking_id,
        "p_expected_status": b["status"],
        "p_cancelled_by": by,
        "p_actor_id": user["sub"],
        "p_expected_refund_paise": body.expected_refund_paise,
        "p_reason_code": reason_code,
    }).execute().data or {}

    outcome = result.get("outcome")
    if outcome == "not_found":
        raise AppError("Booking not found", 404)
    if outcome == "forbidden":
        raise AppError("Forbidden", 403)
    if outcome == "not_cancellable":
        raise AppError(f"Cannot cancel a booking with status '{result.get('status')}'", 400)
    if outcome == "quote_changed":
        raise AppError(
            "The refund for cancelling has just changed. Please check the new amount.",
            409, quote=_quote_view(result.get("quote") or {}),
        )
    if outcome != "cancelled":
        raise AppError(booking_state.CONFLICT_MESSAGE, 409)

    updated = result["booking"]
    booking = {**b, **updated}

    # Razorpay is called only now, after the decision is committed. Inline
    # rather than as a background task, so the patient's "Refund started"
    # reflects a refund Razorpay has accepted. Anything that fails here is
    # retried by /maintenance/retry-refunds.
    queued = result.get("refunds") or []
    sent = []
    for refund in queued:
        try:
            sent.append(refunds.execute(refund, background))
        except Exception as exc:                  # noqa: BLE001 — the cancel has committed
            # The refund is queued; the sweep sends it. Failing the request now
            # would tell the patient their cancel didn't happen when it did.
            logger.error("refund %s not sent inline: %r", refund.get("id"), exc)
            sent.append(refund)
        notifications.refund_started(booking, refund["amount_paise"], background,
                                     refund_id=refund.get("id"))

    quote = result.get("quote") or {}
    notifications.booking_cancelled(booking, by, background,
                                    kept_paise=int(quote.get("kept_paise") or 0))
    # Times the doctor had proposed no longer apply.
    supabase.table("reschedule_requests").update({"status": "withdrawn"}) \
        .eq("booking_id", booking_id).eq("status", "proposed").execute()
    # A doctor cancelling a paid visit close to its time is recorded (they
    # can appeal it, for an emergency say).
    if by == "doctor" and b["status"] == "paid":
        try:
            incidents.record_late_cancel(booking, background)
        except Exception as exc:                  # noqa: BLE001 — the cancel stands
            logger.error("could not record late cancel for %s: %r", booking_id, exc)
    response = {
        **updated,
        "quote": _quote_view(quote),
        "refunded_payments": len(queued),
        "refunds": [
            {"id": r["id"], "amount_paise": r["amount_paise"], "status": r["status"]}
            for r in sent
        ],
    }
    # A doctor cancelling before accept must not receive the address either.
    return _redact_address_for_doctor(response) if by == "doctor" else response


# ── Helpers ───────────────────────────────────────────────────────────────────

def _create_replacement(body: "BookingCreate", doc: dict, rule: dict, start: datetime,
                        policy: dict, user: dict, background) -> dict:
    """The patient's replacement for a doctor who didn't attend: priced like
    any booking, checked against the slot grid, and created in one
    transaction with cancelling the original (services/remedies.py)."""
    if body.follow_up_of:
        raise AppError("A replacement is a new consultation, not a follow-up", 400)
    inc = incidents.get(body.replaces_incident_id)
    if not inc or inc["patient_id"] != user["sub"]:
        raise AppError("Case not found", 404)
    if inc["doctor_id"] == body.doctor_id:
        raise AppError("Choose a different doctor", 400)
    _assert_bookable(body.doctor_id, start, rule["duration_min"])
    fields = {
        "doctor_id": body.doctor_id, "channel": body.channel, "scheduled_start": start.isoformat(),
        "duration_min": rule["duration_min"], "price_paise": rule["price_paise"],
        "price_rule_id": rule["id"], "category_id": body.category_id,
        "cancellation_policy_id": policy["id"],
        **_resolve_home_visit_address(body, doc, user["sub"]),
    }
    row = remedies.start_replacement(body.replaces_incident_id, user["sub"], fields)
    patient = supabase.table("users").select("name").eq("id", user["sub"]).execute().data or []
    notifications.booking_requested(row, (patient[0].get("name") if patient else None) or "A patient",
                                    background)
    return {**row, "cancellation_policy": cancellation.public_policy(policy)}


def _assert_bookable(doctor_id: str, start: datetime, duration_min: Optional[int] = None) -> None:
    """
    Refuse a time the patient could not have picked from the slot grid.

    The grid only ever offers future, unblocked times inside the doctor's
    schedule, but nothing checked that the request matched it: a crafted
    request could book 3am, last week, or a time the doctor had blocked off.
    The same availability service that draws the grid decides here, so the
    two cannot disagree.
    """
    local = availability.to_ist(start)
    if local <= availability.now_ist():
        raise AppError("That time has already passed. Pick another slot.", 409)

    open_slots = availability.get_available_slots(doctor_id, local.date(), days=1,
                                                  duration_min=duration_min)
    starts = {s["start"] for s in open_slots.get(str(local.date()), [])}
    if local.second or local.microsecond or local.strftime("%H:%M") not in starts:
        raise AppError(
            "That time isn't open on this doctor's calendar. Pick another slot.", 409
        )


def _resolve_home_visit_address(body: "BookingCreate", doctor: dict,
                                patient_id: str) -> dict:
    """
    Validate the chosen address against the doctor's service area and return the
    booking columns to persist.

    The address is snapshotted onto the booking, not merely referenced. The
    patient may later edit or delete the address, and a record of where a doctor
    was actually sent must not change underneath it.

    Returns {} for online consults, which have no destination.
    """
    if body.channel != "home_visit":
        return {}

    if not body.address_id:
        raise AppError("address_id is required for a home visit", 400)

    address = fetch_one(
        supabase.table("patient_addresses").select("*").eq("id", body.address_id)
    )
    if not address:
        raise AppError("Address not found", 404)
    if address["patient_id"] != patient_id:
        raise AppError("Forbidden", 403)

    allowed, distance = geo.within_service_area(doctor, address["lat"], address["lng"])
    if not allowed:
        if distance is None:
            raise AppError(
                "This doctor has not finished setting up their home-visit area yet", 409
            )
        raise AppError(
            f"That address is {distance:.1f}km away, outside this doctor's "
            f"{doctor['service_radius_km']}km service area",
            409,
        )

    return {
        "address_id": address["id"],
        "patient_address": _format_address(address),
        "patient_address_lat": address["lat"],
        "patient_address_lng": address["lng"],
        "distance_km": distance,
    }


def _format_address(address: dict) -> str:
    """One-line address, in the order someone would read it aloud to a driver."""
    parts = [
        address.get("line1"),
        address.get("line2"),
        f"near {address['landmark']}" if address.get("landmark") else None,
        address.get("city"),
        address.get("pincode"),
    ]
    return ", ".join(p for p in parts if p)


def _redact_address_for_doctor(booking: dict) -> dict:
    """
    Hide the street address from the doctor until they have accepted.

    Both apps already tell the patient the address is "shared on accept"; this is
    what makes that true rather than a caption. The doctor still sees the city,
    PIN and distance before deciding — enough to judge whether the visit is
    practical, without handing a stranger's home address to someone who may
    decline.
    """
    if booking.get("channel") != "home_visit" or booking.get("address_released_at"):
        return booking

    redacted = dict(booking)
    redacted["patient_address"] = None
    redacted["patient_address_lat"] = None
    redacted["patient_address_lng"] = None
    redacted["address_withheld"] = True
    return redacted


def _get_booking_for_doctor(booking_id: str, doctor_id: str) -> dict:
    booking = fetch_one(supabase.table("bookings").select("*").eq("id", booking_id))
    if not booking:
        raise AppError("Booking not found", 404)
    if booking["doctor_id"] != doctor_id:
        raise AppError("Forbidden", 403)
    return booking
