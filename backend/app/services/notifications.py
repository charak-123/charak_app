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

from typing import Optional

import httpx

from ..config import (
    FCM_PROJECT_ID,
    FCM_SERVER_KEY,
    GOOGLE_APPLICATION_CREDENTIALS,
)
from ..db import supabase

FCM_LEGACY_URL = "https://fcm.googleapis.com/fcm/send"
FCM_V1_URL     = "https://fcm.googleapis.com/v1/projects/{project}/messages:send"

_ROLE_TABLE = {"doctor": "doctors", "patient": "users", "ops": None}


def push_enabled() -> bool:
    return bool(FCM_SERVER_KEY) or bool(FCM_PROJECT_ID and GOOGLE_APPLICATION_CREDENTIALS)


# ── Core ─────────────────────────────────────────────────────────────────────

def notify(
    recipient_id: str,
    recipient_role: str,
    event: str,
    title: str,
    body: str,
    data: Optional[dict] = None,
    booking_id: Optional[str] = None,
    background=None,
) -> dict:
    """
    Record a notification and attempt delivery.

    Returns the persisted row. Never raises — callers treat notification as a
    side effect of a transition that has already succeeded.
    """
    payload_data = {k: str(v) for k, v in (data or {}).items()}

    row = None
    try:
        row = supabase.table("notifications").insert({
            "recipient_id": recipient_id,
            "recipient_role": recipient_role,
            "event": event,
            "title": title,
            "body": body,
            "data": payload_data,
            "booking_id": booking_id,
            "delivery": "pending",
        }).execute().data[0]
    except Exception as exc:  # pragma: no cover — DB unavailable
        print(f"[notify] could not persist {event} for {recipient_id}: {exc}")

    notification_id = (row or {}).get("id")

    if background is not None:
        background.add_task(
            _deliver, recipient_id, recipient_role, title, body, payload_data, notification_id
        )
    else:
        _deliver(recipient_id, recipient_role, title, body, payload_data, notification_id)

    return row or {}


def _deliver(
    recipient_id: str,
    recipient_role: str,
    title: str,
    body: str,
    data: dict,
    notification_id: Optional[str],
) -> None:
    """Resolve the FCM token and send. Records the outcome on the row."""
    outcome, error = "skipped", None
    try:
        if not push_enabled():
            print(f"[FCM STUB] to={recipient_id} ({recipient_role}) {title!r} — {body!r}")
        else:
            token = _fcm_token(recipient_id, recipient_role)
            if not token:
                error = "no token registered"
            else:
                _send(token, title, body, data)
                outcome = "sent"
    except Exception as exc:
        outcome, error = "failed", str(exc)[:500]

    if notification_id:
        try:
            supabase.table("notifications").update({
                "delivery": outcome,
                "delivery_error": error,
            }).eq("id", notification_id).execute()
        except Exception:  # pragma: no cover
            pass


def _fcm_token(recipient_id: str, recipient_role: str) -> Optional[str]:
    table = _ROLE_TABLE.get(recipient_role)
    if not table:
        return None  # ops users have no device token
    rows = supabase.table(table).select("fcm_token").eq("id", recipient_id).execute().data or []
    return (rows[0].get("fcm_token") if rows else None) or None


def _send(token: str, title: str, body: str, data: dict) -> None:
    if FCM_PROJECT_ID and GOOGLE_APPLICATION_CREDENTIALS:
        _send_v1(token, title, body, data)
    else:
        _send_legacy(token, title, body, data)


def _send_legacy(token: str, title: str, body: str, data: dict) -> None:
    with httpx.Client(timeout=5) as client:
        res = client.post(
            FCM_LEGACY_URL,
            json={"to": token, "notification": {"title": title, "body": body}, "data": data},
            headers={"Authorization": f"key={FCM_SERVER_KEY}"},
        )
        res.raise_for_status()


def _send_v1(token: str, title: str, body: str, data: dict) -> None:
    """FCM HTTP v1 — the non-deprecated API. Needs a service-account JSON."""
    access_token = _google_access_token()
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
        res.raise_for_status()


def _google_access_token() -> str:
    """
    Mint an OAuth token from the service-account file.

    ``google-auth`` is imported lazily so the package is only required once FCM
    v1 is actually switched on.
    """
    from google.oauth2 import service_account          # type: ignore
    from google.auth.transport.requests import Request  # type: ignore

    creds = service_account.Credentials.from_service_account_file(
        GOOGLE_APPLICATION_CREDENTIALS,
        scopes=["https://www.googleapis.com/auth/firebase.messaging"],
    )
    creds.refresh(Request())
    return creds.token


# ── Event helpers ────────────────────────────────────────────────────────────
# One per product event, so wording lives in exactly one place and the routers
# stay readable.

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
    )


def booking_accepted(booking: dict, doctor_name: str = "Your doctor", background=None):
    return notify(
        booking["patient_id"], "patient", "booking.accepted",
        "Request accepted",
        f"{doctor_name} accepted your request. Pay now to confirm your booking.",
        {"booking_id": booking["id"]},
        booking["id"], background,
    )


def booking_declined(booking: dict, doctor_name: str = "The doctor", background=None):
    return notify(
        booking["patient_id"], "patient", "booking.declined",
        "Request declined",
        f"{doctor_name} could not take this request. You have not been charged.",
        {"booking_id": booking["id"]},
        booking["id"], background,
    )


def booking_cancelled(booking: dict, cancelled_by: str, background=None):
    """Tells the other party — whoever did not press cancel."""
    if cancelled_by == "patient":
        recipient_id, role, who = booking["doctor_id"], "doctor", "The patient"
    else:
        recipient_id, role, who = booking["patient_id"], "patient", "The doctor"
    return notify(
        recipient_id, role, "booking.cancelled",
        "Booking cancelled",
        f"{who} cancelled this booking.",
        {"booking_id": booking["id"], "cancelled_by": cancelled_by},
        booking["id"], background,
    )


def payment_received(booking: dict, amount, background=None):
    return notify(
        booking["doctor_id"], "doctor", "payment.received",
        "Payment received",
        f"{_money(amount)} received. This booking is confirmed.",
        {"booking_id": booking["id"], "amount": amount},
        booking["id"], background,
    )


def payment_confirmed_to_patient(booking: dict, amount, background=None):
    return notify(
        booking["patient_id"], "patient", "payment.confirmed",
        "Payment confirmed",
        f"{_money(amount)} paid. Your booking is confirmed.",
        {"booking_id": booking["id"], "amount": amount},
        booking["id"], background,
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
    )
    return notify(
        booking["doctor_id"], "doctor", "booking.hold_expired",
        "Slot released",
        "A booking went unpaid and its slot is free again.",
        {"booking_id": booking["id"]}, booking["id"], background,
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
    )


def marked_no_show(booking: dict, background=None):
    return notify(
        booking["patient_id"], "patient", "booking.no_show",
        "Marked as no-show",
        "This booking was marked as a no-show. You have not been charged.",
        {"booking_id": booking["id"]},
        booking["id"], background,
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
        f"{_money(payout['net_amount'])} has been sent to your bank account.",
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


