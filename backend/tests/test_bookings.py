"""
Unit tests for the bookings router.
Patches app.routers.bookings.supabase (the local name bound at import).
"""
from unittest.mock import MagicMock, patch

import pytest

from postgrest.exceptions import APIError
from fastapi.testclient import TestClient
from app.main import app

from tests.conftest import cancelled, make_chain, make_supabase, pricing_chain, rpc_returns

DOCTOR_TOKEN  = "Bearer doctor_token"
PATIENT_TOKEN = "Bearer patient_token"
DOCTOR_PAYLOAD  = {"sub": "doc-1", "role": "doctor"}
PATIENT_PAYLOAD = {"sub": "pat-1", "role": "patient"}

PATCH_TARGET = "app.routers.bookings.supabase"
JWT_TARGET   = "app.deps.jwt"


def _client(jwt_payload, mock_db):
    with patch(PATCH_TARGET, mock_db), patch(JWT_TARGET) as jw:
        jw.decode.return_value = jwt_payload
        yield TestClient(app)


# ── create_booking ─────────────────────────────────────────────────────────────

def test_create_booking_success():
    verified_doc = make_chain(data={"id": "doc-1", "verification_status": "verified",
                                     "offers_online_consult": True, "offers_home_visit": False})
    created_row  = {
        "id": "bk-1", "patient_id": "pat-1", "doctor_id": "doc-1",
        "channel": "online_consult", "scheduled_start": "2026-08-25T09:00:00+00:00",
        "status": "requested",
    }

    # bookings table: first call = slot check (empty), second = insert
    bookings_calls = {"n": 0}
    bookings_chain = make_chain()
    def bookings_execute():
        bookings_calls["n"] += 1
        if bookings_calls["n"] == 1:
            return MagicMock(data=[])          # no slot conflict
        return MagicMock(data=[created_row])   # inserted row
    bookings_chain.execute.side_effect = bookings_execute

    mock_db = make_supabase({"doctors": verified_doc, "bookings": bookings_chain,
                             "doctor_pricing": pricing_chain()})

    with patch(PATCH_TARGET, mock_db), patch(JWT_TARGET) as jw:
        jw.decode.return_value = PATIENT_PAYLOAD
        client = TestClient(app)
        resp = client.post(
            "/bookings/",
            json={"doctor_id": "doc-1", "channel": "online_consult",
                  "scheduled_start": "2026-08-25T09:00:00+00:00"},
            headers={"Authorization": PATIENT_TOKEN},
        )

    assert resp.status_code == 201
    assert resp.json()["status"] == "requested"


def test_create_booking_invalid_channel():
    mock_db = make_supabase({})
    with patch(PATCH_TARGET, mock_db), patch(JWT_TARGET) as jw:
        jw.decode.return_value = PATIENT_PAYLOAD
        client = TestClient(app)
        resp = client.post(
            "/bookings/",
            json={"doctor_id": "doc-1", "channel": "smoke_signal",
                  "scheduled_start": "2026-08-25T09:00:00+00:00"},
            headers={"Authorization": PATIENT_TOKEN},
        )
    assert resp.status_code == 400


def test_create_booking_slot_conflict():
    verified_doc    = make_chain(data={"id": "doc-1", "verification_status": "verified",
                                     "offers_online_consult": True, "offers_home_visit": False})
    conflict_chain  = make_chain(list_data=[{"id": "existing"}])

    mock_db = make_supabase({"doctors": verified_doc, "bookings": conflict_chain,
                             "doctor_pricing": pricing_chain()})
    with patch(PATCH_TARGET, mock_db), patch(JWT_TARGET) as jw:
        jw.decode.return_value = PATIENT_PAYLOAD
        client = TestClient(app)
        resp = client.post(
            "/bookings/",
            json={"doctor_id": "doc-1", "channel": "online_consult",
                  "scheduled_start": "2026-08-25T09:00:00+00:00"},
            headers={"Authorization": PATIENT_TOKEN},
        )
    assert resp.status_code == 409


# ── accept / decline ──────────────────────────────────────────────────────────

def _booking(status="requested", doctor_id="doc-1"):
    return {
        "id": "bk-1", "doctor_id": doctor_id, "patient_id": "pat-1",
        "channel": "online_consult", "scheduled_start": "2026-08-25T09:00:00+00:00",
        "status": status,
    }


def _booking_chain(get_row, update_row):
    """Chain that returns get_row on first execute(), update_row ([...]) on second."""
    c = make_chain()
    calls = {"n": 0}
    def execute():
        calls["n"] += 1
        if calls["n"] == 1:
            return MagicMock(data=get_row)       # GET (single → dict)
        return MagicMock(data=[update_row])       # UPDATE (list)
    c.execute.side_effect = execute
    return c


def test_accept_booking():
    row = _booking("requested")
    chain = _booking_chain(row, {**row, "status": "accepted"})
    mock_db = make_supabase({"bookings": chain})

    with patch(PATCH_TARGET, mock_db), patch(JWT_TARGET) as jw:
        jw.decode.return_value = DOCTOR_PAYLOAD
        client = TestClient(app)
        resp = client.patch("/bookings/bk-1/accept", headers={"Authorization": DOCTOR_TOKEN})

    assert resp.status_code == 200
    assert resp.json()["status"] == "accepted"


def test_accept_already_accepted_returns_400():
    chain = make_chain(data=_booking("accepted"))
    mock_db = make_supabase({"bookings": chain})

    with patch(PATCH_TARGET, mock_db), patch(JWT_TARGET) as jw:
        jw.decode.return_value = DOCTOR_PAYLOAD
        client = TestClient(app)
        resp = client.patch("/bookings/bk-1/accept", headers={"Authorization": DOCTOR_TOKEN})

    assert resp.status_code == 400


def test_decline_booking():
    row = _booking("requested")
    chain = _booking_chain(row, {**row, "status": "declined"})
    mock_db = make_supabase({"bookings": chain})

    with patch(PATCH_TARGET, mock_db), patch(JWT_TARGET) as jw:
        jw.decode.return_value = DOCTOR_PAYLOAD
        client = TestClient(app)
        resp = client.patch("/bookings/bk-1/decline", headers={"Authorization": DOCTOR_TOKEN})

    assert resp.status_code == 200
    assert resp.json()["status"] == "declined"


def test_wrong_doctor_cannot_accept():
    """doc-1 JWT, but booking belongs to doc-99 → 403."""
    chain = make_chain(data=_booking("requested", doctor_id="doc-99"))
    mock_db = make_supabase({"bookings": chain})

    with patch(PATCH_TARGET, mock_db), patch(JWT_TARGET) as jw:
        jw.decode.return_value = DOCTOR_PAYLOAD   # sub = doc-1
        client = TestClient(app)
        resp = client.patch("/bookings/bk-1/accept", headers={"Authorization": DOCTOR_TOKEN})

    assert resp.status_code == 403


def test_cancel_by_patient():
    row = _booking("accepted")
    chain = _booking_chain(row, {**row, "status": "cancelled"})
    mock_db = rpc_returns(make_supabase({"bookings": chain}), cancelled(row))

    with patch(PATCH_TARGET, mock_db), patch(JWT_TARGET) as jw:
        jw.decode.return_value = PATIENT_PAYLOAD
        client = TestClient(app)
        resp = client.patch("/bookings/bk-1/cancel", headers={"Authorization": PATIENT_TOKEN})

    assert resp.status_code == 200
    assert resp.json()["status"] == "cancelled"


def test_cannot_cancel_completed_booking():
    chain = make_chain(data=_booking("completed"))
    mock_db = make_supabase({"bookings": chain})

    with patch(PATCH_TARGET, mock_db), patch(JWT_TARGET) as jw:
        jw.decode.return_value = PATIENT_PAYLOAD
        client = TestClient(app)
        resp = client.patch("/bookings/bk-1/cancel", headers={"Authorization": PATIENT_TOKEN})

    assert resp.status_code == 400


# ── concurrent double-booking ─────────────────────────────────────────────────
#
# The pre-insert conflict SELECT cannot see a booking that another request is
# inserting at the same moment. uq_booking_doctor_slot_active (migration 0010) is
# what actually serialises them: the second insert raises 23505, and the patient
# behind it must get the same friendly 409 as the slow path — not a 500.

def _slot_free_but_insert_conflicts(sqlstate="23505"):
    """bookings table whose conflict check passes, then whose insert violates."""
    chain = make_chain(list_data=[])
    insert_chain = MagicMock()
    insert_chain.execute.side_effect = APIError(
        {"code": sqlstate, "message": "duplicate key value violates unique constraint"}
    )
    chain.insert.return_value = insert_chain
    return chain


def test_create_booking_loses_insert_race_returns_409():
    verified_doc = make_chain(data={"id": "doc-1", "verification_status": "verified",
                                    "offers_online_consult": True, "offers_home_visit": False})

    mock_db = make_supabase({"doctors": verified_doc,
                             "doctor_pricing": pricing_chain(),
                             "bookings": _slot_free_but_insert_conflicts()})
    with patch(PATCH_TARGET, mock_db), patch(JWT_TARGET) as jw:
        jw.decode.return_value = PATIENT_PAYLOAD
        client = TestClient(app)
        resp = client.post(
            "/bookings/",
            json={"doctor_id": "doc-1", "channel": "online_consult",
                  "scheduled_start": "2026-08-25T09:00:00+00:00"},
            headers={"Authorization": PATIENT_TOKEN},
        )
    assert resp.status_code == 409
    assert resp.json()["error"] == "Slot already booked"


def test_create_booking_other_db_error_is_not_reported_as_a_slot_conflict():
    """
    A constraint violation that isn't the slot index must not be disguised as one.

    The router re-raises anything but 23505, and the app-wide db_error_handler
    then translates it — a foreign-key violation is a 409 too, but it must not
    claim the slot was taken, because that sends the patient to pick another time
    for a problem another time will not fix.
    """
    verified_doc = make_chain(data={"id": "doc-1", "verification_status": "verified",
                                    "offers_online_consult": True, "offers_home_visit": False})

    mock_db = make_supabase({"doctors": verified_doc,
                             "doctor_pricing": pricing_chain(),
                             "bookings": _slot_free_but_insert_conflicts(sqlstate="23503")})
    with patch(PATCH_TARGET, mock_db), patch(JWT_TARGET) as jw:
        jw.decode.return_value = PATIENT_PAYLOAD
        client = TestClient(app, raise_server_exceptions=False)
        resp = client.post(
            "/bookings/",
            json={"doctor_id": "doc-1", "channel": "online_consult",
                  "scheduled_start": "2026-08-25T09:00:00+00:00"},
            headers={"Authorization": PATIENT_TOKEN},
        )

    assert resp.status_code == 409
    assert resp.json()["error"] != "Slot already booked"
    assert "Referenced record" in resp.json()["error"]


# ── server-authoritative pricing ──────────────────────────────────────────────

def _price_db(pricing, created_row=None):
    verified_doc = make_chain(data={"id": "doc-1", "verification_status": "verified",
                                    "offers_online_consult": True, "offers_home_visit": False})
    bookings_chain = make_chain()
    calls = {"n": 0}
    def execute():
        calls["n"] += 1
        if calls["n"] == 1:
            return MagicMock(data=[])
        return MagicMock(data=[created_row or {
            "id": "bk-1", "status": "requested", "doctor_id": "doc-1",
            "patient_id": "pat-1", "channel": "online_consult",
            "scheduled_start": "2026-08-25T09:00:00+00:00"}])
    bookings_chain.execute.side_effect = execute
    db = make_supabase({"doctors": verified_doc, "bookings": bookings_chain,
                        "doctor_pricing": pricing,
                        "users": make_chain(list_data=[{"name": "Asha"}])})
    return db, bookings_chain


def _post(db, body):
    with patch(PATCH_TARGET, db), patch(JWT_TARGET) as jw:
        jw.decode.return_value = PATIENT_PAYLOAD
        return TestClient(app).post("/bookings/", json=body,
                                    headers={"Authorization": PATIENT_TOKEN})


BASE_BODY = {"doctor_id": "doc-1", "channel": "online_consult",
             "scheduled_start": "2026-08-25T09:00:00+00:00"}


def test_create_booking_snapshots_the_published_price():
    """
    Regression: nothing used to write price_confirmed, so _amount_due refused
    every consult with "No confirmed price on booking" and no patient could pay.
    """
    db, bookings = _price_db(pricing_chain(750.0))
    resp = _post(db, BASE_BODY)

    assert resp.status_code == 201
    assert bookings.insert.call_args[0][0]["price_confirmed"] == 750.0


def test_create_booking_ignores_a_price_supplied_by_the_client():
    """A patient naming their own fee must not be charged it."""
    db, bookings = _price_db(pricing_chain(750.0))
    resp = _post(db, {**BASE_BODY, "price_confirmed": 1.0})

    assert resp.status_code == 201
    assert bookings.insert.call_args[0][0]["price_confirmed"] == 750.0


def test_create_booking_refuses_a_doctor_with_no_published_price():
    """Better to refuse than to create a booking that can never be paid for."""
    db, _ = _price_db(make_chain(data=None))
    resp = _post(db, BASE_BODY)

    assert resp.status_code == 409
    assert "has not published a price" in resp.json()["error"]


def test_cancelling_a_paid_booking_queues_and_sends_the_refund():
    """
    A paid cancel refunds the patient. The refund is queued and the ledger is
    reversed inside cancel_booking() (one transaction, tested against real SQL
    in tests/integration/test_refunds.py). The router then sends each queued
    refund to Razorpay and tells the patient it has started, not that it's done.
    """
    row = _booking("paid")
    queued = {"id": "rf-1", "payment_id": "pay-1", "booking_id": "bk-1",
              "amount_paise": 50000, "status": "pending", "attempts": 0}
    mock_db = rpc_returns(
        make_supabase({"bookings": _booking_chain(row, row)}),
        cancelled(row, refunds=[queued]),
    )

    with patch(PATCH_TARGET, mock_db), patch(JWT_TARGET) as jw, \
         patch("app.routers.bookings.refunds.execute",
               return_value={**queued, "status": "processing"}) as send, \
         patch("app.routers.bookings.notifications") as notify:
        jw.decode.return_value = PATIENT_PAYLOAD
        client = TestClient(app)
        resp = client.patch("/bookings/bk-1/cancel", headers={"Authorization": PATIENT_TOKEN})

    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "cancelled"
    assert body["refunded_payments"] == 1
    assert body["refunds"] == [{"id": "rf-1", "amount_paise": 50000, "status": "processing"}]
    send.assert_called_once()
    assert send.call_args.args[0]["id"] == "rf-1"
    notify.refund_started.assert_called_once()
    assert notify.refund_started.call_args.args[1] == 50000
    notify.booking_cancelled.assert_called_once()


def test_a_refund_razorpay_rejects_inline_does_not_fail_the_cancel():
    """
    The cancel has committed by the time Razorpay is called. An error there must
    not tell the patient their cancel failed; the sweep sends the refund later.
    """
    row = _booking("paid")
    queued = {"id": "rf-1", "payment_id": "pay-1", "booking_id": "bk-1",
              "amount_paise": 50000, "status": "pending", "attempts": 0}
    mock_db = rpc_returns(
        make_supabase({"bookings": _booking_chain(row, row)}),
        cancelled(row, refunds=[queued]),
    )
    with patch(PATCH_TARGET, mock_db), patch(JWT_TARGET) as jw, \
         patch("app.routers.bookings.refunds.execute", side_effect=RuntimeError("db blip")), \
         patch("app.routers.bookings.notifications"):
        jw.decode.return_value = PATIENT_PAYLOAD
        resp = TestClient(app).patch("/bookings/bk-1/cancel",
                                     headers={"Authorization": PATIENT_TOKEN})

    assert resp.status_code == 200
    assert resp.json()["refunds"][0]["status"] == "pending"


def test_cancelling_an_unpaid_booking_sends_no_refund():
    """An accepted (unpaid) cancel has nothing to refund."""
    row = _booking("accepted")
    mock_db = rpc_returns(make_supabase({"bookings": _booking_chain(row, row)}), cancelled(row))

    with patch(PATCH_TARGET, mock_db), patch(JWT_TARGET) as jw, \
         patch("app.routers.bookings.refunds.execute") as send:
        jw.decode.return_value = PATIENT_PAYLOAD
        client = TestClient(app)
        resp = client.patch("/bookings/bk-1/cancel", headers={"Authorization": PATIENT_TOKEN})

    assert resp.status_code == 200
    assert resp.json()["refunded_payments"] == 0
    send.assert_not_called()


@pytest.mark.parametrize("outcome,code", [
    ({"outcome": "conflict", "status": "paid"}, 409),
    ({"outcome": "not_cancellable", "status": "completed"}, 400),
    ({"outcome": "not_found"}, 404),
])
def test_cancel_reports_what_the_database_decided(outcome, code):
    row = _booking("accepted")
    mock_db = rpc_returns(make_supabase({"bookings": _booking_chain(row, row)}), outcome)
    with patch(PATCH_TARGET, mock_db), patch(JWT_TARGET) as jw, \
         patch("app.routers.bookings.refunds.execute") as send:
        jw.decode.return_value = PATIENT_PAYLOAD
        resp = TestClient(app).patch("/bookings/bk-1/cancel",
                                     headers={"Authorization": PATIENT_TOKEN})
    assert resp.status_code == code
    send.assert_not_called()


def test_create_booking_is_rate_limited():
    """10 bookings in 10 minutes is the cap (services/rate_limit.py)."""
    ten_recent_attempts = [{"id": i} for i in range(10)]
    rl_db = make_supabase({"rate_limit_hits": make_chain(list_data=ten_recent_attempts)})

    with patch(PATCH_TARGET, make_supabase({})), \
         patch("app.services.rate_limit.supabase", rl_db), \
         patch(JWT_TARGET) as jw:
        jw.decode.return_value = PATIENT_PAYLOAD
        client = TestClient(app)
        resp = client.post(
            "/bookings/",
            json={"doctor_id": "doc-1", "channel": "online_consult",
                  "scheduled_start": "2026-08-25T09:00:00+00:00"},
            headers={"Authorization": PATIENT_TOKEN},
        )

    assert resp.status_code == 429
