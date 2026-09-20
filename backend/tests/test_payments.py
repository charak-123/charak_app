"""
Tests for the payments router.

The properties that matter here are the ones that move money: the webhook
signature is enforced, a replayed webhook pays nobody twice, and confirming a
payment always credits the doctor's ledger with the commission split applied.
"""
import hashlib
import hmac
import json
from unittest.mock import MagicMock, patch

from fastapi.testclient import TestClient

from app.main import app
from tests.conftest import make_chain, make_supabase

PATIENT = {"sub": "pat-1", "role": "patient"}
DOCTOR  = {"sub": "doc-1", "role": "doctor"}
AUTH    = {"Authorization": "Bearer t"}

PAY_DB     = "app.routers.payments.supabase"
PAYOUTS_DB = "app.services.payouts.supabase"
NOTIF_DB   = "app.services.notifications.supabase"
JWT        = "app.deps.jwt"

BOOKING = {
    "id": "bk-1", "patient_id": "pat-1", "doctor_id": "doc-1",
    "channel": "online_consult", "status": "accepted",
    "price_confirmed": 800.0, "payment_attempts": 0,
}


def _client(payload, db):
    with patch(PAY_DB, db), patch(PAYOUTS_DB, db), patch(NOTIF_DB, db), patch(JWT) as jw:
        jw.decode.return_value = payload
        yield TestClient(app)


# ── create order ──────────────────────────────────────────────────────────────

def test_create_order_returns_a_stub_order_without_credentials():
    db = make_supabase({
        "bookings": make_chain(data=BOOKING),
        "payments": make_chain(list_data=[]),
    })
    # payments: first execute = open-order lookup, second = insert
    pay = make_chain()
    pay.execute.side_effect = [
        MagicMock(data=[]),
        MagicMock(data=[{"id": "p-1", "razorpay_order_id": "stub_order_cons-bk-1",
                         "type": "consult_fee", "amount": 800.0, "status": "initiated"}]),
    ]
    db = make_supabase({"bookings": make_chain(data=BOOKING), "payments": pay})

    for c in _client(PATIENT, db):
        res = c.post("/payments/bk-1/order", headers=AUTH, json={"type": "consult_fee"})

    body = res.json()
    assert res.status_code == 201
    assert body["amount"] == 80000          # paise
    assert body["live"] is False
    assert body["razorpay_key"] == "stub_key"


def test_create_order_reuses_an_open_order_of_the_same_amount():
    """Reopening the payment screen must not stack duplicate Razorpay orders."""
    open_row = {"id": "p-1", "razorpay_order_id": "stub_order_x", "type": "consult_fee",
                "amount": 800.0, "status": "initiated"}
    pay = make_chain(list_data=[open_row])
    db = make_supabase({"bookings": make_chain(data=BOOKING), "payments": pay})

    for c in _client(PATIENT, db):
        res = c.post("/payments/bk-1/order", headers=AUTH, json={"type": "consult_fee"})

    assert res.json()["payment_id"] == "p-1"
    pay.insert.assert_not_called()


def test_create_order_refuses_a_booking_that_is_not_accepted():
    db = make_supabase({"bookings": make_chain(data={**BOOKING, "status": "requested"})})
    for c in _client(PATIENT, db):
        res = c.post("/payments/bk-1/order", headers=AUTH, json={"type": "consult_fee"})
    assert res.status_code == 400


def test_create_order_refuses_another_patients_booking():
    db = make_supabase({"bookings": make_chain(data={**BOOKING, "patient_id": "someone-else"})})
    for c in _client(PATIENT, db):
        res = c.post("/payments/bk-1/order", headers=AUTH, json={"type": "consult_fee"})
    assert res.status_code == 403


def test_create_order_refuses_a_booking_with_no_confirmed_price():
    db = make_supabase({"bookings": make_chain(data={**BOOKING, "price_confirmed": None})})
    for c in _client(PATIENT, db):
        res = c.post("/payments/bk-1/order", headers=AUTH, json={"type": "consult_fee"})
    assert res.status_code == 400


def test_procedure_bill_order_requires_an_approved_bill():
    db = make_supabase({
        "bookings": make_chain(data={**BOOKING, "status": "completed"}),
        "procedure_bills": make_chain(list_data=[{"id": "pb-1", "status": "under_review", "total": 2000}]),
    })
    for c in _client(PATIENT, db):
        res = c.post("/payments/bk-1/order", headers=AUTH, json={"type": "procedure_bill"})
    assert res.status_code == 400
    assert "not yet payable" in res.json()["error"]


def test_procedure_bill_order_refuses_a_bill_already_paid():
    db = make_supabase({
        "bookings": make_chain(data={**BOOKING, "status": "completed"}),
        "procedure_bills": make_chain(list_data=[{"id": "pb-1", "status": "paid", "total": 2000}]),
    })
    for c in _client(PATIENT, db):
        res = c.post("/payments/bk-1/order", headers=AUTH, json={"type": "procedure_bill"})
    assert res.status_code == 409


def test_create_order_rejects_an_unknown_payment_type():
    db = make_supabase({"bookings": make_chain(data=BOOKING)})
    for c in _client(PATIENT, db):
        res = c.post("/payments/bk-1/order", headers=AUTH, json={"type": "tip"})
    assert res.status_code == 400


# ── failed attempt ────────────────────────────────────────────────────────────

def test_reporting_a_failure_extends_the_hold_rather_than_losing_the_slot():
    bookings = make_chain()
    bookings.execute.side_effect = [
        MagicMock(data=BOOKING),                               # single() lookup
        MagicMock(data=[{**BOOKING, "hold_expires_at": "2026-09-19T10:10:00+00:00"}]),
    ]
    db = make_supabase({"bookings": bookings, "payments": make_chain(list_data=[])})

    for c in _client(PATIENT, db):
        res = c.post("/payments/bk-1/failed", headers=AUTH)

    assert res.status_code == 200
    assert res.json()["retry_until"] == "2026-09-19T10:10:00+00:00"
    written = bookings.update.call_args[0][0]
    assert "payment_failed_at" in written and "hold_expires_at" in written


def test_reporting_a_failure_on_a_paid_booking_is_rejected():
    db = make_supabase({"bookings": make_chain(data={**BOOKING, "status": "paid"})})
    for c in _client(PATIENT, db):
        res = c.post("/payments/bk-1/failed", headers=AUTH)
    assert res.status_code == 400


# ── webhook signature ─────────────────────────────────────────────────────────

def _signed(body: dict, secret: str):
    raw = json.dumps(body).encode()
    sig = hmac.new(secret.encode(), raw, hashlib.sha256).hexdigest()
    return raw, sig


CAPTURED = {
    "event": "payment.captured",
    "payload": {"payment": {"entity": {
        "id": "pay_live_1", "order_id": "order_1", "method": "upi",
    }}},
}


def test_webhook_rejects_a_missing_signature_when_a_secret_is_configured():
    """This endpoint credits a doctor's ledger — an unsigned caller is refused."""
    db = make_supabase({})
    with patch(PAY_DB, db), patch("app.routers.payments._WEBHOOK_SECRET", "whsec"):
        res = TestClient(app).post("/payments/webhook", json=CAPTURED)
    assert res.status_code == 400
    assert "Missing webhook signature" in res.json()["error"]


def test_webhook_rejects_a_forged_signature():
    raw, _ = _signed(CAPTURED, "whsec")
    db = make_supabase({})
    with patch(PAY_DB, db), patch("app.routers.payments._WEBHOOK_SECRET", "whsec"):
        res = TestClient(app).post(
            "/payments/webhook", content=raw,
            headers={"x-razorpay-signature": "deadbeef", "content-type": "application/json"},
        )
    assert res.status_code == 400
    assert "Invalid webhook signature" in res.json()["error"]


def test_webhook_accepts_a_correctly_signed_request():
    raw, sig = _signed(CAPTURED, "whsec")
    payments = make_chain(list_data=[{
        "id": "p-1", "booking_id": "bk-1", "type": "consult_fee",
        "amount": 800.0, "status": "initiated",
    }])
    db = make_supabase({
        "payments": payments,
        "bookings": make_chain(data=BOOKING),
        "doctors": make_chain(list_data=[{"commission_pct": 15}]),
        "doctor_ledger_entries": make_chain(list_data=[]),
        "notifications": make_chain(list_data=[{"id": "n-1"}]),
    })
    with patch(PAY_DB, db), patch(PAYOUTS_DB, db), patch(NOTIF_DB, db), \
         patch("app.routers.payments._WEBHOOK_SECRET", "whsec"):
        res = TestClient(app).post(
            "/payments/webhook", content=raw,
            headers={"x-razorpay-signature": sig, "content-type": "application/json"},
        )
    assert res.status_code == 200
    assert res.json() == {"ok": True}


def test_webhook_rejects_a_malformed_body():
    db = make_supabase({})
    with patch(PAY_DB, db), patch("app.routers.payments._WEBHOOK_SECRET", ""):
        res = TestClient(app).post(
            "/payments/webhook", content=b"not json",
            headers={"content-type": "application/json"},
        )
    assert res.status_code == 400


# ── webhook behaviour ─────────────────────────────────────────────────────────

def _webhook_db(payment_row, booking=None):
    ledger = make_chain()
    ledger.execute.side_effect = [
        MagicMock(data=[]),                      # duplicate lookup
        MagicMock(data=[{"id": "led-1"}]),       # insert
    ]
    return make_supabase({
        "payments": make_chain(list_data=[payment_row]),
        "bookings": make_chain(data=booking or BOOKING),
        "doctors": make_chain(list_data=[{"commission_pct": 15}]),
        "doctor_ledger_entries": ledger,
        "notifications": make_chain(list_data=[{"id": "n-1"}]),
    }), ledger


def test_a_captured_consult_payment_credits_the_doctor_net_of_commission():
    db, ledger = _webhook_db({
        "id": "p-1", "booking_id": "bk-1", "type": "consult_fee",
        "amount": 800.0, "status": "initiated",
    })
    with patch(PAY_DB, db), patch(PAYOUTS_DB, db), patch(NOTIF_DB, db), \
         patch("app.routers.payments._WEBHOOK_SECRET", ""):
        TestClient(app).post("/payments/webhook", json=CAPTURED)

    written = ledger.insert.call_args[0][0]
    assert written["source"] == "consult_fee"
    assert written["gross_amount"] == 800.0
    assert written["commission_amount"] == 120.0     # 15%
    assert written["net_amount"] == 680.0


def test_a_replayed_webhook_is_a_no_op():
    """Razorpay retries deliveries; the second must not pay the doctor again."""
    db = make_supabase({
        "payments": make_chain(list_data=[{
            "id": "p-1", "booking_id": "bk-1", "type": "consult_fee",
            "amount": 800.0, "status": "completed",
        }]),
        "doctor_ledger_entries": make_chain(list_data=[]),
    })
    with patch(PAY_DB, db), patch(PAYOUTS_DB, db), patch(NOTIF_DB, db), \
         patch("app.routers.payments._WEBHOOK_SECRET", ""):
        res = TestClient(app).post("/payments/webhook", json=CAPTURED)

    assert res.json() == {"ok": True, "idempotent": True}
    db.table("doctor_ledger_entries").insert.assert_not_called()


def test_a_captured_procedure_bill_credits_the_procedure_source():
    db, ledger = _webhook_db({
        "id": "p-2", "booking_id": "bk-1", "type": "procedure_bill",
        "amount": 2000.0, "status": "initiated",
    })
    with patch(PAY_DB, db), patch(PAYOUTS_DB, db), patch(NOTIF_DB, db), \
         patch("app.routers.payments._WEBHOOK_SECRET", ""):
        TestClient(app).post("/payments/webhook", json=CAPTURED)

    written = ledger.insert.call_args[0][0]
    assert written["source"] == "procedure_bill"
    assert written["net_amount"] == 1700.0


def test_a_failed_payment_event_marks_the_payment_failed_only():
    payments = make_chain(list_data=[])
    db = make_supabase({"payments": payments, "doctor_ledger_entries": make_chain(list_data=[])})
    event = {"event": "payment.failed",
             "payload": {"payment": {"entity": {"id": "pay_1", "order_id": "order_1"}}}}
    with patch(PAY_DB, db), patch(PAYOUTS_DB, db), patch(NOTIF_DB, db), \
         patch("app.routers.payments._WEBHOOK_SECRET", ""):
        res = TestClient(app).post("/payments/webhook", json=event)

    assert res.status_code == 200
    assert payments.update.call_args[0][0] == {"status": "failed"}
    db.table("doctor_ledger_entries").insert.assert_not_called()


def test_an_unrelated_event_is_ignored():
    db = make_supabase({"payments": make_chain(list_data=[])})
    event = {"event": "refund.created",
             "payload": {"payment": {"entity": {"order_id": "order_1"}}}}
    with patch(PAY_DB, db), patch(PAYOUTS_DB, db), patch(NOTIF_DB, db), \
         patch("app.routers.payments._WEBHOOK_SECRET", ""):
        assert TestClient(app).post("/payments/webhook", json=event).json() == {"ok": True}


def test_a_webhook_without_an_order_id_is_ignored():
    db = make_supabase({})
    event = {"event": "payment.captured", "payload": {"payment": {"entity": {"id": "pay_1"}}}}
    with patch(PAY_DB, db), patch(PAYOUTS_DB, db), patch(NOTIF_DB, db), \
         patch("app.routers.payments._WEBHOOK_SECRET", ""):
        assert TestClient(app).post("/payments/webhook", json=event).json() == {"ok": True}


# ── dev shortcut ──────────────────────────────────────────────────────────────

def test_stub_complete_is_refused_once_live_keys_are_present():
    """The development bypass must be unreachable in production."""
    db = make_supabase({})
    for c in _client(PATIENT, db):
        with patch("app.routers.payments.live_mode", lambda: True):
            res = c.post("/payments/bk-1/stub-complete", headers=AUTH)
    assert res.status_code == 403


def test_stub_complete_credits_the_ledger_like_a_real_payment():
    """Development and production confirm through the same code path, so a
    behaviour difference cannot hide until launch day."""
    ledger = make_chain()
    ledger.execute.side_effect = [MagicMock(data=[]), MagicMock(data=[{"id": "led-1"}])]
    payments = make_chain()
    payments.execute.side_effect = [
        MagicMock(data=[]),                                   # no existing payment
        MagicMock(data=[{"id": "p-1", "booking_id": "bk-1", "type": "consult_fee",
                         "amount": 800.0, "status": "initiated",
                         "razorpay_order_id": "stub_order_bk-1"}]),
        MagicMock(data=[{"id": "p-1"}]),                      # the completion update
    ]
    db = make_supabase({
        "bookings": make_chain(data=BOOKING),
        "payments": payments,
        "doctors": make_chain(list_data=[{"commission_pct": 15}]),
        "doctor_ledger_entries": ledger,
        "notifications": make_chain(list_data=[{"id": "n-1"}]),
    })

    for c in _client(PATIENT, db):
        res = c.post("/payments/bk-1/stub-complete", headers=AUTH, json={"type": "consult_fee"})

    assert res.status_code == 200
    assert res.json()["status"] == "paid"
    assert ledger.insert.call_args[0][0]["net_amount"] == 680.0


def test_stub_complete_refuses_another_patients_booking():
    db = make_supabase({"bookings": make_chain(data={**BOOKING, "patient_id": "other"})})
    for c in _client(PATIENT, db):
        res = c.post("/payments/bk-1/stub-complete", headers=AUTH)
    assert res.status_code == 403


# ── read ──────────────────────────────────────────────────────────────────────

def test_the_doctor_can_read_the_payment_history_of_their_booking():
    db = make_supabase({
        "bookings": make_chain(data={"patient_id": "pat-1", "doctor_id": "doc-1"}),
        "payments": make_chain(list_data=[{"id": "p-1", "status": "completed"}]),
    })
    for c in _client(DOCTOR, db):
        res = c.get("/payments/bk-1", headers=AUTH)
    assert res.status_code == 200
    assert res.json()[0]["status"] == "completed"


def test_an_unrelated_user_cannot_read_payment_history():
    db = make_supabase({"bookings": make_chain(data={"patient_id": "x", "doctor_id": "y"})})
    for c in _client(PATIENT, db):
        res = c.get("/payments/bk-1", headers=AUTH)
    assert res.status_code == 403
