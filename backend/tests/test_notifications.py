"""
Tests for the notification layer.

The gap this covers: before this, nothing in the backend ever sent a
notification. The behaviours under test are that every event is recorded even
with push switched off, that a delivery failure cannot break the transition that
triggered it, and that the inbox is scoped to its owner.
"""
from unittest.mock import MagicMock, patch

from fastapi.testclient import TestClient

from app.main import app
from app.services import notifications as notif
from tests.conftest import make_chain, make_supabase

PATIENT = {"sub": "pat-1", "role": "patient"}
DOCTOR  = {"sub": "doc-1", "role": "doctor"}
AUTH    = {"Authorization": "Bearer t"}

SVC_DB    = "app.services.notifications.supabase"
ROUTER_DB = "app.routers.notifications.supabase"
JWT       = "app.deps.jwt"

BOOKING = {
    "id": "bk-1", "patient_id": "pat-1", "doctor_id": "doc-1",
    "channel": "home_visit", "status": "accepted", "price_confirmed": 800.0,
}


def _db(notification_row=None, token=None):
    return make_supabase({
        "notifications": make_chain(list_data=[notification_row or {"id": "n-1"}]),
        "users": make_chain(list_data=[{"fcm_token": token}]),
        "doctors": make_chain(list_data=[{"fcm_token": token}]),
    })


# ── persistence ───────────────────────────────────────────────────────────────

def test_an_event_is_recorded_even_with_push_disabled():
    """The in-app inbox works today; push only changes delivery, not the record."""
    db = _db()
    with patch(SVC_DB, db), patch.object(notif, "push_enabled", lambda: False):
        notif.notify("pat-1", "patient", "booking.accepted", "Accepted", "Pay now")

    written = db.table("notifications").insert.call_args[0][0]
    assert written["recipient_id"] == "pat-1"
    assert written["event"] == "booking.accepted"
    assert written["delivery"] == "pending"


def test_delivery_is_marked_skipped_when_push_is_not_configured():
    notifications = make_chain(list_data=[{"id": "n-1"}])
    db = make_supabase({"notifications": notifications})
    with patch(SVC_DB, db), patch.object(notif, "push_enabled", lambda: False):
        notif.notify("pat-1", "patient", "test.event", "T", "B")

    assert notifications.update.call_args[0][0]["delivery"] == "skipped"


def test_delivery_is_marked_sent_when_the_push_succeeds():
    notifications = make_chain(list_data=[{"id": "n-1"}])
    db = make_supabase({
        "notifications": notifications,
        "users": make_chain(list_data=[{"fcm_token": "tok-123"}]),
    })
    with patch(SVC_DB, db), patch.object(notif, "push_enabled", lambda: True), \
         patch.object(notif, "_send", lambda *a: None):
        notif.notify("pat-1", "patient", "test.event", "T", "B")

    assert notifications.update.call_args[0][0]["delivery"] == "sent"


def test_a_missing_device_token_is_recorded_not_raised():
    notifications = make_chain(list_data=[{"id": "n-1"}])
    db = make_supabase({
        "notifications": notifications,
        "users": make_chain(list_data=[{"fcm_token": None}]),
    })
    with patch(SVC_DB, db), patch.object(notif, "push_enabled", lambda: True):
        notif.notify("pat-1", "patient", "test.event", "T", "B")

    update = notifications.update.call_args[0][0]
    assert update["delivery"] == "skipped"
    assert update["delivery_error"] == "no token registered"


def test_a_push_failure_is_swallowed_and_recorded():
    """A booking must not fail to be accepted because Google timed out."""
    notifications = make_chain(list_data=[{"id": "n-1"}])
    db = make_supabase({
        "notifications": notifications,
        "users": make_chain(list_data=[{"fcm_token": "tok-123"}]),
    })

    def _boom(*a):
        raise RuntimeError("FCM 503")

    with patch(SVC_DB, db), patch.object(notif, "push_enabled", lambda: True), \
         patch.object(notif, "_send", _boom):
        notif.notify("pat-1", "patient", "test.event", "T", "B")   # must not raise

    update = notifications.update.call_args[0][0]
    assert update["delivery"] == "failed"
    assert "FCM 503" in update["delivery_error"]


def test_notify_survives_the_notifications_table_being_unavailable():
    """Recording is best-effort; losing it must not take the request down."""
    broken = MagicMock()
    broken.table.side_effect = RuntimeError("relation does not exist")
    with patch(SVC_DB, broken), patch.object(notif, "push_enabled", lambda: False):
        assert notif.notify("pat-1", "patient", "e", "T", "B") == {}


def test_data_payload_values_are_stringified_for_fcm():
    """FCM rejects non-string data values, so ints must be coerced at the edge."""
    db = _db()
    with patch(SVC_DB, db), patch.object(notif, "push_enabled", lambda: False):
        notif.notify("pat-1", "patient", "e", "T", "B", {"stars": 5, "amount": 800.0})

    written = db.table("notifications").insert.call_args[0][0]["data"]
    assert written == {"stars": "5", "amount": "800.0"}


def test_ops_recipients_are_recorded_without_a_device_lookup():
    """There is no ops app, so an ops notification is an audit record only."""
    db = _db(token="tok")
    with patch(SVC_DB, db), patch.object(notif, "push_enabled", lambda: True):
        notif.notify("00000000-0000-0000-0000-000000000000", "ops", "complaint.filed", "T", "B")

    assert db.table("notifications").insert.call_args[0][0]["recipient_role"] == "ops"


# ── event helpers: right person, right words ──────────────────────────────────

def _event(fn, *args):
    db = _db()
    with patch(SVC_DB, db), patch.object(notif, "push_enabled", lambda: False):
        fn(*args)
    return db.table("notifications").insert.call_args[0][0]


def test_a_new_request_goes_to_the_doctor():
    row = _event(notif.booking_requested, BOOKING, "Asha")
    assert row["recipient_id"] == "doc-1"
    assert row["recipient_role"] == "doctor"
    assert "Asha" in row["body"]
    assert "home visit" in row["body"]


def test_an_acceptance_goes_to_the_patient_and_asks_for_payment():
    row = _event(notif.booking_accepted, BOOKING, "Dr Rao")
    assert row["recipient_id"] == "pat-1"
    assert "Dr Rao" in row["body"]
    assert "Pay now" in row["body"]


def test_a_decline_reassures_the_patient_about_charges():
    row = _event(notif.booking_declined, BOOKING, "Dr Rao")
    assert row["recipient_id"] == "pat-1"
    assert "not been charged" in row["body"]


def test_a_patient_cancellation_notifies_the_doctor():
    row = _event(notif.booking_cancelled, BOOKING, "patient")
    assert row["recipient_id"] == "doc-1"
    assert "patient cancelled" in row["body"].lower()


def test_a_doctor_cancellation_notifies_the_patient():
    row = _event(notif.booking_cancelled, BOOKING, "doctor")
    assert row["recipient_id"] == "pat-1"
    assert "doctor cancelled" in row["body"].lower()


def test_money_is_formatted_in_rupees_without_decimals():
    row = _event(notif.payment_received, BOOKING, 1500)
    assert "₹1,500" in row["body"]


def test_a_payment_failure_tells_the_patient_how_long_they_have():
    row = _event(notif.payment_failed, BOOKING, 10)
    assert row["recipient_id"] == "pat-1"
    assert "10 more minutes" in row["body"]


def test_running_late_carries_the_minutes():
    row = _event(notif.doctor_running_late, BOOKING, 20)
    assert row["recipient_id"] == "pat-1"
    assert "20 minutes late" in row["body"]


def test_a_no_show_tells_the_patient_they_were_not_charged():
    row = _event(notif.marked_no_show, BOOKING)
    assert "not been charged" in row["body"]


def test_a_completed_visit_prompts_a_rating():
    row = _event(notif.visit_completed, BOOKING)
    assert "rate" in row["body"].lower()


def test_a_single_star_rating_is_not_pluralised():
    row = _event(notif.rating_received, "doc-1", 1, "bk-1")
    assert "1 star." in row["body"]


def test_multiple_stars_are_pluralised():
    row = _event(notif.rating_received, "doc-1", 4, "bk-1")
    assert "4 stars" in row["body"]


def test_a_hold_expiry_notifies_both_parties():
    db = _db()
    with patch(SVC_DB, db), patch.object(notif, "push_enabled", lambda: False):
        notif.booking_hold_expired(BOOKING)

    recipients = [c[0][0]["recipient_id"] for c in db.table("notifications").insert.call_args_list]
    assert set(recipients) == {"pat-1", "doc-1"}


def test_bill_approval_notifies_both_parties():
    db = _db()
    with patch(SVC_DB, db), patch.object(notif, "push_enabled", lambda: False):
        notif.bill_approved(BOOKING, 2000)

    rows = [c[0][0] for c in db.table("notifications").insert.call_args_list]
    assert {r["recipient_role"] for r in rows} == {"doctor", "patient"}
    assert all("₹2,000" in r["body"] for r in rows)


def test_a_payout_notification_names_the_net_amount():
    row = _event(notif.payout_paid, "doc-1", {"id": "po-1", "net_amount": 17000, "reference": "UTR1"})
    assert "₹17,000" in row["body"]
    assert row["data"]["reference"] == "UTR1"


# ── inbox routes ──────────────────────────────────────────────────────────────

def _client(payload, db):
    with patch(ROUTER_DB, db), patch(JWT) as jw:
        jw.decode.return_value = payload
        yield TestClient(app)


def test_the_inbox_is_scoped_to_the_caller():
    rows = make_chain(list_data=[{"id": "n-1", "title": "Accepted", "read_at": None}])
    db = make_supabase({"notifications": rows})
    for c in _client(PATIENT, db):
        res = c.get("/notifications/", headers=AUTH)
    assert res.status_code == 200
    rows.eq.assert_any_call("recipient_id", "pat-1")


def test_the_inbox_limit_is_capped():
    rows = make_chain(list_data=[])
    db = make_supabase({"notifications": rows})
    for c in _client(PATIENT, db):
        c.get("/notifications/?limit=100000", headers=AUTH)
    rows.limit.assert_called_with(200)


def test_unread_only_filters_on_a_null_read_timestamp():
    rows = make_chain(list_data=[])
    db = make_supabase({"notifications": rows})
    for c in _client(PATIENT, db):
        c.get("/notifications/?unread_only=true", headers=AUTH)
    rows.is_.assert_called_with("read_at", "null")


def test_the_unread_count_reports_whether_push_is_live():
    db = make_supabase({"notifications": make_chain(list_data=[{"id": "n-1"}, {"id": "n-2"}])})
    for c in _client(PATIENT, db):
        body = c.get("/notifications/unread-count", headers=AUTH).json()
    assert body["count"] == 2
    assert body["push_enabled"] is False


def test_a_user_cannot_mark_someone_elses_notification_read():
    notifications = make_chain(list_data=[{"recipient_id": "pat-999"}])
    db = make_supabase({"notifications": notifications})
    for c in _client(PATIENT, db):
        res = c.patch("/notifications/n-1/read", headers=AUTH)
    assert res.status_code == 403


def test_marking_an_unknown_notification_read_is_a_404():
    db = make_supabase({"notifications": make_chain(list_data=[])})
    for c in _client(PATIENT, db):
        res = c.patch("/notifications/nope/read", headers=AUTH)
    assert res.status_code == 404


def test_marking_read_stamps_the_timestamp():
    notifications = make_chain()
    notifications.execute.side_effect = [
        MagicMock(data=[{"recipient_id": "pat-1"}]),
        MagicMock(data=[{"id": "n-1", "read_at": "2026-09-19T00:00:00+00:00"}]),
    ]
    db = make_supabase({"notifications": notifications})
    for c in _client(PATIENT, db):
        res = c.patch("/notifications/n-1/read", headers=AUTH)
    assert res.status_code == 200
    assert "read_at" in notifications.update.call_args[0][0]


def test_read_all_reports_how_many_it_updated():
    db = make_supabase({"notifications": make_chain(list_data=[{"id": "n-1"}, {"id": "n-2"}])})
    for c in _client(PATIENT, db):
        res = c.patch("/notifications/read-all", headers=AUTH)
    assert res.json() == {"updated": 2}


# ── token registration ────────────────────────────────────────────────────────

def test_registering_a_token_writes_to_the_doctors_table_for_a_doctor():
    doctors = make_chain(list_data=[{"id": "doc-1"}])
    db = make_supabase({"doctors": doctors})
    with patch("app.routers.push.supabase", db), patch(JWT) as jw:
        jw.decode.return_value = DOCTOR
        res = TestClient(app).post("/push/register", headers=AUTH,
                                   json={"fcm_token": "tok", "platform": "android"})
    assert res.status_code == 200
    db.table.assert_any_call("doctors")


def test_registering_rejects_an_unknown_platform():
    db = make_supabase({})
    with patch("app.routers.push.supabase", db), patch(JWT) as jw:
        jw.decode.return_value = PATIENT
        res = TestClient(app).post("/push/register", headers=AUTH,
                                   json={"fcm_token": "tok", "platform": "windows"})
    assert res.status_code == 400


def test_unregistering_clears_the_token_on_logout():
    """The next person to use a shared device must not receive medical alerts."""
    users = make_chain(list_data=[{"id": "pat-1"}])
    db = make_supabase({"users": users})
    with patch("app.routers.push.supabase", db), patch(JWT) as jw:
        jw.decode.return_value = PATIENT
        res = TestClient(app).delete("/push/register", headers=AUTH)
    assert res.status_code == 200
    assert users.update.call_args[0][0] == {"fcm_token": None, "fcm_platform": None}
