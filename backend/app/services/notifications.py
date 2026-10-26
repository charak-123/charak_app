"""
Notification dispatch.

Previously ``routers/push.py`` could register an FCM token but nothing ever sent
anything — no router called it. This module is the missing half: one ``notify()``
primitive plus a named function per product event, called from the routers that
own each state transition.

Two deliberate properties:

* **Every event is persisted** to the ``notifications`` table whether or not FCM
  is configured. The apps can therefore render a notification list today, and
  delivery is auditable when push goes live.
* **Delivery never breaks the caller.** A push failure is recorded on the row
  and swallowed; a booking must not fail to be accepted because Google timed out.

Sending is synchronous on purpose — the routers are sync functions, so an async
send would have needed an event loop per call. Pass ``background`` (a FastAPI
``BackgroundTasks``) to move the HTTP round-trip off the request path.
"""
from __future__ import annotations

import logging
from datetime import datetime, timedelta, timezone
from typing import Optional

import httpx
from postgrest.exceptions import APIError

from ..config import (
    FCM_PROJECT_ID,
    FCM_SERVER_KEY,
    FIREBASE_ADMIN_CREDENTIALS_JSON,
    GOOGLE_APPLICATION_CREDENTIALS,
)
from ..db import fetch_one, supabase

logger = logging.getLogger(__name__)

FCM_LEGACY_URL = "https://fcm.googleapis.com/fcm/send"
FCM_V1_URL     = "https://fcm.googleapis.com/v1/projects/{project}/messages:send"

_ROLE_TABLE = {"doctor": "doctors", "patient": "users", "ops": None}


def push_enabled() -> bool:
    return bool(FCM_SERVER_KEY) or bool(
        FCM_PROJECT_ID and (FIREBASE_ADMIN_CREDENTIALS_JSON or GOOGLE_APPLICATION_CREDENTIALS)
    )


# ── Core ─────────────────────────────────────────────────────────────────────
# The notifications table is an outbox (migration 0023). notify() records the
# row and makes one delivery attempt (in a background task when the caller
# passes one). Anything not delivered then, because the attempt never ran (Cloud
# Run can throttle CPU once a response has gone), FCM had a bad minute, or
# delivery was scheduled for later, is picked up by sweep_outbox() from
# /maintenance/tick. A row is claimed before it is sent, so the inline attempt
# and the sweep never both send it.

# Temporary failures are retried this many times, waiting 30s, 1m, 2m, 4m …
MAX_ATTEMPTS = 5
# How long a claim lasts. A sender that dies mid-send frees the row after this.
CLAIM_SECONDS = 60
# A push this stale helps nobody ("Doctor running 10 minutes late", hours
# later). It stays in the in-app inbox but is not sent.
MAX_PUSH_AGE = timedelta(hours=6)
# The sweep leaves a fresh row to its inline attempt for this long first.
INLINE_GRACE = timedelta(seconds=15)


class TokenGone(Exception):
    """FCM says this token no longer reaches an app install; forget it."""


class TransientPushError(Exception):
    """Worth retrying: a timeout, a 5xx, or a 429 from FCM."""


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _parse(ts) -> Optional[datetime]:
    if not ts:
        return None
    return datetime.fromisoformat(str(ts).replace("Z", "+00:00"))


def notify(
    recipient_id: str,
    recipient_role: str,
    event: str,
    title: str,
    body: str,
    data: Optional[dict] = None,
    booking_id: Optional[str] = None,
    background=None,
    *,
    dedupe_key: Optional[str] = None,
    deliver_after: Optional[datetime] = None,
) -> dict:
    """
    Record a notification and attempt delivery.

    ``dedupe_key`` makes a one-shot event (a booking accepted, a refund
    completed) impossible to record, and so to send, twice: a second call with
    the same key is a no-op. ``deliver_after`` schedules it instead of sending
    now.

    Returns the persisted row ({} if it was a duplicate or could not be
    recorded). Never raises: callers treat notification as a side effect of a
    transition that has already succeeded.
    """
    payload_data = {k: str(v) for k, v in (data or {}).items()}

    record = {
        "recipient_id": recipient_id,
        "recipient_role": recipient_role,
        "event": event,
        "title": title,
        "body": body,
        "data": payload_data,
        "booking_id": booking_id,
        "delivery": "pending",
        "dedupe_key": dedupe_key,
    }
    if deliver_after is not None:
        record["deliver_after"] = deliver_after.isoformat()

    try:
        row = supabase.table("notifications").insert(record).execute().data[0]
    except APIError as exc:
        if getattr(exc, "code", None) == "23505":
            return {}                              # already recorded once
        logger.error("could not persist %s for %s: %s", event, recipient_id, exc)
        return {}
    except Exception as exc:  # pragma: no cover — DB unavailable
        logger.error("could not persist %s for %s: %s", event, recipient_id, exc)
        return {}

    if deliver_after is not None and deliver_after > _now():
        return row

    notification_id = row.get("id")
    if background is not None:
        background.add_task(
            _deliver, recipient_id, recipient_role, title, body, payload_data, notification_id
        )
    else:
        _deliver(recipient_id, recipient_role, title, body, payload_data, notification_id)
    return row


def _deliver(
    recipient_id: str,
    recipient_role: str,
    title: str,
    body: str,
    data: dict,
    notification_id: Optional[str],
) -> None:
    """The inline attempt. Never raises; the sweep retries whatever is left."""
    if not notification_id:
        return
    try:
        deliver(notification_id)
    except Exception as exc:  # pragma: no cover — never take the caller down
        logger.error("delivery of notification %s raised: %r", notification_id, exc)


def deliver(notification_id: str) -> Optional[str]:
    """
    Claim one pending notification and send it to every device its recipient
    has registered. Returns the resulting delivery status, or None if the row
    was not ours to send (already sent, claimed elsewhere, not yet due).
    """
    now = _now()
    row = fetch_one(supabase.table("notifications").select("*").eq("id", notification_id))
    if not isinstance(row, dict) or row.get("delivery") != "pending":
        return None
    claimed_until = _parse(row.get("claimed_until"))
    if claimed_until and claimed_until > now:
        return None
    due = _parse(row.get("deliver_after"))
    if due and due > now:
        return None

    attempts = int(row.get("attempts") or 0)
    claimed = (
        supabase.table("notifications").update({
            "claimed_until": (now + timedelta(seconds=CLAIM_SECONDS)).isoformat(),
            "attempts": attempts + 1,
            "last_attempt_at": now.isoformat(),
        })
        .eq("id", notification_id).eq("delivery", "pending").eq("attempts", attempts)
        .execute().data or []
    )
    if not claimed:
        return None
    attempts += 1

    created = _parse(row.get("created_at"))
    if created and now - created > MAX_PUSH_AGE:
        return _finish(notification_id, "skipped", "too old to push; kept in the in-app inbox")
    if row.get("recipient_role") not in _ROLE_TABLE or _ROLE_TABLE[row["recipient_role"]] is None:
        return _finish(notification_id, "skipped", "no device for this recipient role")
    if not push_enabled():
        print(f"[FCM STUB] to={row['recipient_id']} ({row['recipient_role']}) "
              f"{row['title']!r} — {row['body']!r}")
        return _finish(notification_id, "skipped", None)

    tokens = _tokens(row["recipient_id"], row["recipient_role"])
    if not tokens:
        return _finish(notification_id, "skipped", "no token registered")

    sent, transient, errors = 0, False, []
    for token in tokens:
        try:
            _send(token, row["title"], row["body"], row.get("data") or {})
            sent += 1
        except TokenGone:
            _forget_token(token)
            errors.append("token no longer registered")
        except TransientPushError as exc:
            transient = True
            errors.append(str(exc)[:200])
        except Exception as exc:              # noqa: BLE001 — recorded, not raised
            errors.append(str(exc)[:200])

    if sent:
        return _finish(notification_id, "sent", None)
    if transient and attempts < MAX_ATTEMPTS:
        retry_at = now + timedelta(seconds=30 * 2 ** (attempts - 1))
        supabase.table("notifications").update({
            "claimed_until": None,
            "deliver_after": retry_at.isoformat(),
            "delivery_error": "; ".join(errors)[:500],
        }).eq("id", notification_id).execute()
        return "pending"
    return _finish(notification_id, "failed", "; ".join(errors)[:500] or "no device accepted it")


def _finish(notification_id: str, outcome: str, error: Optional[str]) -> str:
    supabase.table("notifications").update({
        "delivery": outcome,
        "delivery_error": error,
        "claimed_until": None,
    }).eq("id", notification_id).execute()
    return outcome


def sweep_outbox(now: Optional[datetime] = None, limit: int = 100) -> dict:
    """Deliver what is due and still pending: scheduled sends, retries, and
    rows whose inline attempt never ran."""
    now = now or _now()
    rows = (
        supabase.table("notifications").select("id")
        .eq("delivery", "pending")
        .lte("deliver_after", now.isoformat())
        .lte("created_at", (now - INLINE_GRACE).isoformat())
        .order("deliver_after")
        .limit(limit)
        .execute().data or []
    )
    outcomes: dict[str, int] = {}
    for r in rows:
        outcome = deliver(r["id"]) or "not_claimed"
        outcomes[outcome] = outcomes.get(outcome, 0) + 1
    return {"considered": len(rows), **outcomes}


# ── Devices ──────────────────────────────────────────────────────────────────

def _tokens(recipient_id: str, recipient_role: str) -> list[str]:
    """Every device this person has registered. Falls back to the single
    legacy column for a user who hasn't opened an updated app yet."""
    rows = (
        supabase.table("device_tokens").select("token")
        .eq("owner_id", recipient_id).eq("owner_role", recipient_role)
        .execute().data or []
    )
    tokens = [r["token"] for r in rows if r.get("token")]
    if tokens:
        return tokens
    legacy = _fcm_token(recipient_id, recipient_role)
    return [legacy] if legacy else []


def _fcm_token(recipient_id: str, recipient_role: str) -> Optional[str]:
    table = _ROLE_TABLE.get(recipient_role)
    if not table:
        return None  # ops users have no device token
    rows = supabase.table(table).select("fcm_token").eq("id", recipient_id).execute().data or []
    return (rows[0].get("fcm_token") if rows else None) or None


def _forget_token(token: str) -> None:
    try:
        supabase.table("device_tokens").delete().eq("token", token).execute()
    except Exception as exc:  # pragma: no cover
        logger.warning("could not forget a dead token: %r", exc)


def _send(token: str, title: str, body: str, data: dict) -> None:
    if FCM_PROJECT_ID and (FIREBASE_ADMIN_CREDENTIALS_JSON or GOOGLE_APPLICATION_CREDENTIALS):
        _send_v1(token, title, body, data)
    else:
        _send_legacy(token, title, body, data)


def _send_legacy(token: str, title: str, body: str, data: dict) -> None:
    try:
        with httpx.Client(timeout=5) as client:
            res = client.post(
                FCM_LEGACY_URL,
                json={"to": token, "notification": {"title": title, "body": body}, "data": data},
                headers={"Authorization": f"key={FCM_SERVER_KEY}"},
            )
    except httpx.TransportError as exc:
        raise TransientPushError(f"FCM unreachable: {exc!r}") from exc
    if res.status_code >= 500 or res.status_code == 429:
        raise TransientPushError(f"FCM {res.status_code}")
    res.raise_for_status()
    # The legacy API answers 200 and puts per-token errors in the body.
    result = ((res.json() or {}).get("results") or [{}])[0]
    if result.get("error") in ("NotRegistered", "InvalidRegistration"):
        raise TokenGone(result["error"])


def _send_v1(token: str, title: str, body: str, data: dict) -> None:
    """FCM HTTP v1 — the non-deprecated API. Needs a service-account JSON."""
    access_token = _google_access_token()
    try:
        with httpx.Client(timeout=5) as client:
            res = client.post(
                FCM_V1_URL.format(project=FCM_PROJECT_ID),
                json={"message": {
                    "token": token,
                    "notification": {"title": title, "body": body},
                    "data": data,
                    "android": {"priority": "high"},
                }},
                headers={"Authorization": f"Bearer {access_token}"},
            )
    except httpx.TransportError as exc:
        raise TransientPushError(f"FCM unreachable: {exc!r}") from exc
    if res.status_code >= 500 or res.status_code == 429:
        raise TransientPushError(f"FCM {res.status_code}")
    if res.status_code == 404:
        raise TokenGone("UNREGISTERED")
    if res.status_code == 400 and "registration token" in res.text.lower():
        raise TokenGone("INVALID_ARGUMENT")
    res.raise_for_status()


def _google_access_token() -> str:
    """
    Mint an OAuth token for the FCM v1 API.

    Prefers FIREBASE_ADMIN_CREDENTIALS_JSON (the full service-account JSON as
    an env var — Cloud Run secrets mount as env vars, not files; this is the
    same credential services/firebase_auth.py uses to verify sign-in tokens).
    Falls back to GOOGLE_APPLICATION_CREDENTIALS, a file path, for a
    deployment that has one sitting on disk instead. ``google-auth`` is
    imported lazily so the package is only required once FCM is actually
    switched on.
    """
    import json

    from google.oauth2 import service_account          # type: ignore
    from google.auth.transport.requests import Request  # type: ignore

    scopes = ["https://www.googleapis.com/auth/firebase.messaging"]
    if FIREBASE_ADMIN_CREDENTIALS_JSON:
        creds = service_account.Credentials.from_service_account_info(
            json.loads(FIREBASE_ADMIN_CREDENTIALS_JSON), scopes=scopes,
        )
    else:
        creds = service_account.Credentials.from_service_account_file(
            GOOGLE_APPLICATION_CREDENTIALS, scopes=scopes,
        )
    creds.refresh(Request())
    return creds.token


# ── Event helpers ────────────────────────────────────────────────────────────
# One per product event, so wording lives in exactly one place and the routers
# stay readable.

def _once(event: str, booking: dict, recipient_id: str) -> str:
    """Dedupe key for an event that can only happen once per booking."""
    return f"{event}:{booking['id']}:{recipient_id}"


def _money(amount) -> str:
    return f"₹{float(amount or 0):,.0f}"


def booking_requested(booking: dict, patient_name: str = "A patient", background=None):
    return notify(
        booking["doctor_id"], "doctor", "booking.requested",
        "New consultation request",
        f"{patient_name} has requested a "
        f"{'home visit' if booking['channel'] == 'home_visit' else 'online consult'}.",
        {"booking_id": booking["id"], "channel": booking["channel"]},
        booking["id"], background,
        dedupe_key=_once("booking.requested", booking, booking["doctor_id"]),
    )


def booking_accepted(booking: dict, doctor_name: str = "Your doctor", background=None):
    return notify(
        booking["patient_id"], "patient", "booking.accepted",
        "Request accepted",
        f"{doctor_name} accepted your request. Pay now to confirm your booking.",
        {"booking_id": booking["id"]},
        booking["id"], background,
        dedupe_key=_once("booking.accepted", booking, booking["patient_id"]),
    )


def free_booking_confirmed(booking: dict, doctor_name: str = "Your doctor", background=None):
    """A ₹0 follow-up: accepting it confirms it, with nothing to pay."""
    return notify(
        booking["patient_id"], "patient", "booking.confirmed",
        "Follow-up confirmed",
        f"{doctor_name} accepted your follow-up. There's nothing to pay.",
        {"booking_id": booking["id"]},
        booking["id"], background,
        dedupe_key=_once("booking.confirmed", booking, booking["patient_id"]),
    )


def booking_declined(booking: dict, doctor_name: str = "The doctor", background=None):
    return notify(
        booking["patient_id"], "patient", "booking.declined",
        "Request declined",
        f"{doctor_name} could not take this request. You have not been charged.",
        {"booking_id": booking["id"]},
        booking["id"], background,
        dedupe_key=_once("booking.declined", booking, booking["patient_id"]),
    )


def booking_cancelled(booking: dict, cancelled_by: str, background=None, kept_paise: int = 0):
    """
    Tells the other party — whoever did not press cancel. When a patient
    cancels late, the doctor learns what the policy leaves them (LD-005).
    """
    if cancelled_by == "patient":
        recipient_id, role, who = booking["doctor_id"], "doctor", "The patient"
    else:
        recipient_id, role, who = booking["patient_id"], "patient", "The doctor"
    message = f"{who} cancelled this booking."
    if cancelled_by == "patient" and kept_paise > 0:
        message += f" Under the cancellation policy, {_paise_money(kept_paise)} stays in your earnings."
    return notify(
        recipient_id, role, "booking.cancelled",
        "Booking cancelled",
        message,
        {"booking_id": booking["id"], "cancelled_by": cancelled_by},
        booking["id"], background,
        dedupe_key=_once("booking.cancelled", booking, recipient_id),
    )


def payment_received(booking: dict, amount, background=None):
    return notify(
        booking["doctor_id"], "doctor", "payment.received",
        "Payment received",
        f"{_money(amount)} received. This booking is confirmed.",
        {"booking_id": booking["id"], "amount": amount},
        booking["id"], background,
        dedupe_key=_once("payment.received", booking, booking["doctor_id"]),
    )


def payment_confirmed_to_patient(booking: dict, amount, background=None):
    return notify(
        booking["patient_id"], "patient", "payment.confirmed",
        "Payment confirmed",
        f"{_money(amount)} paid. Your booking is confirmed.",
        {"booking_id": booking["id"], "amount": amount},
        booking["id"], background,
        dedupe_key=_once("payment.confirmed", booking, booking["patient_id"]),
    )


def payment_failed(booking: dict, hold_minutes: int, background=None):
    return notify(
        booking["patient_id"], "patient", "payment.failed",
        "Payment did not go through",
        f"Your slot is held for {hold_minutes} more minutes. Tap to try again.",
        {"booking_id": booking["id"]},
        booking["id"], background,
    )


def booking_hold_expired(booking: dict, background=None):
    notify(
        booking["patient_id"], "patient", "booking.hold_expired",
        "Booking released",
        "The payment window closed, so your slot was released. You can book again.",
        {"booking_id": booking["id"]}, booking["id"], background,
        dedupe_key=_once("booking.hold_expired", booking, booking["patient_id"]),
    )
    return notify(
        booking["doctor_id"], "doctor", "booking.hold_expired",
        "Slot released",
        "A booking went unpaid and its slot is free again.",
        {"booking_id": booking["id"]}, booking["id"], background,
        dedupe_key=_once("booking.hold_expired", booking, booking["doctor_id"]),
    )


def request_expired(booking: dict, background=None):
    """A request the doctor never answered, closed by the system."""
    notify(
        booking["patient_id"], "patient", "booking.request_expired",
        "Request expired",
        "The doctor didn't respond in time, so this request was closed. You were "
        "not charged. Try another slot or another doctor.",
        {"booking_id": booking["id"]}, booking["id"], background,
        dedupe_key=_once("booking.request_expired", booking, booking["patient_id"]),
    )
    return notify(
        booking["doctor_id"], "doctor", "booking.request_expired",
        "Request expired",
        "A request you hadn't answered has expired.",
        {"booking_id": booking["id"]}, booking["id"], background,
        dedupe_key=_once("booking.request_expired", booking, booking["doctor_id"]),
    )


def doctor_running_late(booking: dict, minutes: int, background=None):
    return notify(
        booking["patient_id"], "patient", "visit.running_late",
        "Doctor running late",
        f"Your doctor is running about {minutes} minutes late.",
        {"booking_id": booking["id"], "minutes": minutes},
        booking["id"], background,
    )


def visit_completed(booking: dict, background=None):
    return notify(
        booking["patient_id"], "patient", "visit.completed",
        "Visit complete",
        "Your consultation is complete. Tap to rate your doctor.",
        {"booking_id": booking["id"]},
        booking["id"], background,
        dedupe_key=_once("visit.completed", booking, booking["patient_id"]),
    )


def marked_no_show(booking: dict, background=None):
    return notify(
        booking["patient_id"], "patient", "booking.no_show",
        "Marked as no-show",
        "This booking was marked as a no-show. You have not been charged.",
        {"booking_id": booking["id"]},
        booking["id"], background,
        dedupe_key=_once("booking.no_show", booking, booking["patient_id"]),
    )


def clarification_call_started(booking: dict, background=None):
    return notify(
        booking["patient_id"], "patient", "call.incoming",
        "Doctor is calling",
        "Your doctor is calling to clarify a few details before the consultation.",
        {"booking_id": booking["id"]},
        booking["id"], background,
    )


def bill_under_review(booking: dict, total, background=None):
    return notify(
        booking["doctor_id"], "doctor", "bill.under_review",
        "Bill sent for review",
        f"Your {_money(total)} procedure bill is with the senior review team.",
        {"booking_id": booking["id"], "total": total},
        booking["id"], background,
    )


def bill_approved(booking: dict, total, background=None):
    notify(
        booking["doctor_id"], "doctor", "bill.approved",
        "Bill approved",
        f"Your {_money(total)} procedure bill was approved.",
        {"booking_id": booking["id"], "total": total}, booking["id"], background,
    )
    return notify(
        booking["patient_id"], "patient", "bill.approved",
        "Procedure bill ready",
        f"A {_money(total)} procedure bill is ready for payment.",
        {"booking_id": booking["id"], "total": total}, booking["id"], background,
    )


def doctor_verified(doctor_id: str, background=None):
    return notify(
        doctor_id, "doctor", "doctor.verified",
        "You're verified",
        "Your profile is verified and now live in the Charak directory.",
        {}, None, background,
    )


def doctor_rejected(doctor_id: str, reason: str, background=None):
    return notify(
        doctor_id, "doctor", "doctor.rejected",
        "Verification needs attention",
        reason,
        {}, None, background,
    )


def doctor_suspended(doctor_id: str, reason: str, background=None):
    return notify(
        doctor_id, "doctor", "doctor.suspended",
        "Listing suspended",
        reason or "Your listing has been suspended. Contact support for details.",
        {}, None, background,
    )


def payout_paid(doctor_id: str, payout: dict, background=None):
    return notify(
        doctor_id, "doctor", "payout.paid",
        "Payout sent",
        f"{_money(payout['net_amount'])} has been sent to your payout account (UPI or bank).",
        {"payout_id": payout["id"], "reference": payout.get("reference") or ""},
        None, background,
    )


def rating_received(doctor_id: str, stars: int, booking_id: str, background=None):
    return notify(
        doctor_id, "doctor", "rating.received",
        "New rating",
        f"A patient rated your consultation {stars} star{'s' if stars != 1 else ''}.",
        {"booking_id": booking_id, "stars": stars},
        booking_id, background,
    )


def complaint_filed(booking: dict, background=None):
    """Complaints go to the ops queue; there is no ops device to push to, so this
    is an in-app/audit record only."""
    return notify(
        "00000000-0000-0000-0000-000000000000", "ops", "complaint.filed",
        "New complaint",
        "A patient filed a complaint that needs review.",
        {"booking_id": booking["id"]},
        booking["id"], background,
    )




def payment_auto_refunded(booking: dict, amount, background=None):
    """
    A payment landed after its booking was already gone.

    UPI makes this ordinary rather than exotic: the patient approves in GPay well
    after the hold expired, so the money arrives against a slot that has been
    released. They are told plainly that nothing is booked and the money is coming
    back, because the alternative is a silent debit with no booking behind it.

    "Is being refunded", never "refunded": Razorpay hasn't confirmed anything
    yet. refund_completed() says that once it has.
    """
    return notify(
        booking["patient_id"], "patient", "payment.auto_refunded",
        "Payment being refunded",
        f"{_money(amount)} arrived after your slot was released, so it is being "
        "refunded. Nothing was booked — please book again.",
        {"booking_id": booking["id"]}, booking["id"], background,
    )


# ── Refunds ──────────────────────────────────────────────────────────────────
# Each message matches what Razorpay has actually confirmed at that point
# (services/refunds.py). Amounts arrive in paise.

def _paise_money(amount_paise) -> str:
    rupees = int(amount_paise or 0) / 100
    return f"₹{rupees:,.0f}" if rupees == int(rupees) else f"₹{rupees:,.2f}"


def refund_started(booking: dict, amount_paise, background=None, refund_id: Optional[str] = None):
    return notify(
        booking["patient_id"], "patient", "refund.started",
        "Refund started",
        f"{_paise_money(amount_paise)} is on its way back to your original payment "
        "method. Banks usually take 5–7 working days.",
        {"booking_id": booking["id"]}, booking["id"], background,
        dedupe_key=f"refund.started:{refund_id}" if refund_id else None,
    )


def refund_completed(booking: dict, amount_paise, background=None, refund_id: Optional[str] = None):
    return notify(
        booking["patient_id"], "patient", "refund.completed",
        "Refund completed",
        f"{_paise_money(amount_paise)} has been refunded to your original payment method.",
        {"booking_id": booking["id"]}, booking["id"], background,
        dedupe_key=f"refund.completed:{refund_id}" if refund_id else None,
    )


def refund_delayed(booking: dict, amount_paise, background=None, refund_id: Optional[str] = None):
    return notify(
        booking["patient_id"], "patient", "refund.delayed",
        "Refund delayed",
        f"Your {_paise_money(amount_paise)} refund is taking longer than expected. "
        "Our team is on it — you don't need to do anything.",
        {"booking_id": booking["id"]}, booking["id"], background,
        dedupe_key=f"refund.delayed:{refund_id}" if refund_id else None,
    )


def refund_needs_attention(refund: dict, background=None):
    """For the admin refunds queue; ops has no device, so this is a record only."""
    return notify(
        "00000000-0000-0000-0000-000000000000", "ops", "refund.failed",
        "Refund needs attention",
        f"A {_paise_money(refund.get('amount_paise'))} refund could not be sent: "
        f"{(refund.get('failure_reason') or 'unknown error')[:200]}",
        {"refund_id": refund["id"], "booking_id": refund.get("booking_id") or ""},
        refund.get("booking_id"), background,
    )


# ── The visit (migration 0025) ───────────────────────────────────────────────
# Lock-screen text never carries medical detail: no medicine, diagnosis or
# advice, only that something is waiting in the app (spec §9.3, §16.2).
# tests/test_visit.py checks it.

def _when_ist(ts) -> str:
    dt = _parse(ts)
    if dt is None:
        return ""
    local = dt.astimezone(timezone(timedelta(hours=5, minutes=30)))
    return local.strftime("%-d %b, %-I:%M %p")


def journey_started(booking: dict, background=None):
    return notify(
        booking["patient_id"], "patient", "visit.journey_started",
        "Your doctor is on the way",
        "Your doctor has started travelling for your home visit.",
        {"booking_id": booking["id"]}, booking["id"], background,
        dedupe_key=_once("visit.journey_started", booking, booking["patient_id"]),
    )


def appointment_reminder(booking: dict, recipient_role: str, minutes: int):
    """Sent by the job queue ``minutes`` before the start."""
    online = booking.get("channel") == "online_consult"
    if minutes >= 1440:
        lead = f"tomorrow at {_when_ist(booking['scheduled_start']).split(', ')[-1]}"
    elif minutes >= 60:
        hours = minutes // 60
        lead = f"in {hours} hour{'s' if hours != 1 else ''}"
    else:
        lead = f"in {minutes} minutes"
    if recipient_role == "patient":
        recipient_id = booking["patient_id"]
        title = "Upcoming consultation" if online else "Upcoming home visit"
        body = (f"Your video consultation starts {lead}. Join from the app." if online
                else f"Your doctor's home visit is {lead}.")
    else:
        recipient_id = booking["doctor_id"]
        title = "Upcoming consultation" if online else "Upcoming home visit"
        body = (f"Your video consultation starts {lead}." if online
                else f"Your home visit is {lead}. Tap Start journey when you leave.")
    return notify(
        recipient_id, recipient_role, "booking.reminder", title, body,
        {"booking_id": booking["id"], "minutes": minutes}, booking["id"],
        dedupe_key=f"booking.reminder:{booking['id']}:{recipient_id}:{minutes}",
    )


def prescription_ready(booking: dict, prescription_id: str, background=None):
    return notify(
        booking["patient_id"], "patient", "prescription.ready",
        "Your prescription is ready",
        "Your prescription is available in CHARAK.",
        {"booking_id": booking["id"], "prescription_id": prescription_id},
        booking["id"], background,
        dedupe_key=f"prescription.ready:{prescription_id}",
    )


def prescription_updated(booking: dict, prescription_id: str, background=None):
    return notify(
        booking["patient_id"], "patient", "prescription.updated",
        "Prescription updated",
        "Your doctor sent a corrected prescription. Open CHARAK to see it.",
        {"booking_id": booking["id"], "prescription_id": prescription_id},
        booking["id"], background,
        dedupe_key=f"prescription.updated:{prescription_id}",
    )


def prescription_reminder(booking: dict, prescription_id: str, background=None):
    return notify(
        booking["patient_id"], "patient", "prescription.reminder",
        "Your prescription is waiting",
        "Your doctor's prescription is available in CHARAK.",
        {"booking_id": booking["id"], "prescription_id": prescription_id},
        booking["id"], background,
        dedupe_key=f"prescription.reminder:{prescription_id}",
    )


def visit_complete_to_doctor(booking: dict, source: str, available_at, background=None):
    """The booking completed: the patient opened the prescription, or the
    72-hour fallback ran. Says when the fee can be withdrawn (LD-006)."""
    when = _parse(available_at)
    if when is not None and when > _now():
        tail = f" The fee can be withdrawn from {_when_ist(when)}."
    else:
        tail = " The fee can be withdrawn now."
    first = ("Your patient opened the prescription. This visit is complete."
             if source == "patient_viewed" else "This visit is now complete.")
    return notify(
        booking["doctor_id"], "doctor", "visit.completed",
        "Visit complete", first + tail,
        {"booking_id": booking["id"]}, booking["id"], background,
        dedupe_key=_once("visit.completed", booking, booking["doctor_id"]),
    )


def follow_up_reminder(recommendation: dict, kind: str = "on_day"):
    """``kind`` is 'on_day' or 'advance' (D17)."""
    if kind == "advance":
        try:
            day = datetime.fromisoformat(str(recommendation["recommended_date"])).strftime("%-d %b")
        except ValueError:
            day = str(recommendation["recommended_date"])
        title, body = ("Follow-up coming up",
                       f"Your doctor recommended a follow-up around {day}. "
                       "Review it and book if you need to.")
    else:
        title, body = ("Follow-up due",
                       "Your doctor recommended a follow-up. Review the "
                       "recommendation and book if you need to.")
    return notify(
        recommendation["patient_id"], "patient", "follow_up.reminder", title, body,
        {"booking_id": recommendation["booking_id"], "follow_up_id": recommendation["id"]},
        recommendation["booking_id"],
        dedupe_key=f"follow_up.reminder:{recommendation['id']}:{kind}",
    )
