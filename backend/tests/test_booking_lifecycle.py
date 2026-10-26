"""
Tests for the booking transitions added in Phase 4: payment holds, no-show,
running-late, cancellation attribution, and the sweeper that releases slots the
patient never paid for.
"""
from unittest.mock import MagicMock, patch

from fastapi.testclient import TestClient

from app.main import app
from tests.conftest import cancelled, make_chain, make_supabase, rpc_returns

DOCTOR  = {"sub": "doc-1", "role": "doctor"}
PATIENT = {"sub": "pat-1", "role": "patient"}
AUTH    = {"Authorization": "Bearer t"}

BOOK_DB  = "app.routers.bookings.supabase"
NOTIF_DB = "app.services.notifications.supabase"
MAINT_DB = "app.routers.maintenance.supabase"
JWT      = "app.deps.jwt"

BOOKING = {
    "id": "bk-1", "patient_id": "pat-1", "doctor_id": "doc-1",
    "channel": "online_consult", "status": "requested",
    "scheduled_start": "2026-09-20T09:00:00+00:00", "price_confirmed": 800.0,
}


def _bookings_chain(lookup, updated):
    """First execute answers the single() lookup, the second the update."""
    chain = make_chain()
    chain.execute.side_effect = [MagicMock(data=lookup), MagicMock(data=[updated])]
    return chain


def _db(lookup, updated, extra=None):
    chain = _bookings_chain(lookup, updated)
    tables = {
        "bookings": chain,
        "doctors": make_chain(list_data=[{"name": "Dr Rao"}]),
        "users": make_chain(list_data=[{"name": "Asha"}]),
        "notifications": make_chain(list_data=[{"id": "n-1"}]),
    }
    tables.update(extra or {})
    return make_supabase(tables), chain


def _client(payload, db):
    with patch(BOOK_DB, db), patch(NOTIF_DB, db), patch(JWT) as jw:
        jw.decode.return_value = payload
        yield TestClient(app)


# ── accept starts the payment hold ────────────────────────────────────────────

def test_accepting_a_booking_sets_a_payment_hold(transitions):
    """Without a hold an unpaid patient occupies a doctor's slot indefinitely."""
    db, _ = _db(BOOKING, {**BOOKING, "status": "accepted"})
    with patch("app.routers.bookings.PAYMENT_HOLD_MINUTES", 10):
        for c in _client(DOCTOR, db):
            res = c.patch("/bookings/bk-1/accept", headers=AUTH)

    assert res.status_code == 200
    call = transitions.last("accept")
    assert call["p_actor_role"] == "doctor" and call["p_actor_id"] == "doc-1"
    # Compare-and-set on the status the doctor saw (decision_at is stamped by
    # transition_booking itself for accept/decline).
    assert call["p_expected_status"] == "requested"
    assert call["p_patch"]["hold_expires_at"] is not None
    assert res.json()["status"] == "accepted"


def test_accepting_notifies_the_patient_to_pay():
    db, _ = _db(BOOKING, {**BOOKING, "status": "accepted"})
    for c in _client(DOCTOR, db):
        c.patch("/bookings/bk-1/accept", headers=AUTH)

    rows = [call[0][0] for call in db.table("notifications").insert.call_args_list]
    assert rows[0]["event"] == "booking.accepted"
    assert rows[0]["recipient_id"] == "pat-1"


def test_declining_clears_any_hold(transitions):
    db, _ = _db(BOOKING, {**BOOKING, "status": "declined"})
    for c in _client(DOCTOR, db):
        c.patch("/bookings/bk-1/decline", headers=AUTH)
    assert transitions.last("decline")["p_patch"] == {"hold_expires_at": None}


def test_another_doctor_cannot_accept_someone_elses_request():
    db, _ = _db({**BOOKING, "doctor_id": "doc-999"}, BOOKING)
    for c in _client(DOCTOR, db):
        res = c.patch("/bookings/bk-1/accept", headers=AUTH)
    assert res.status_code == 403


# ── no-show ───────────────────────────────────────────────────────────────────

def test_an_accepted_booking_can_be_marked_no_show(transitions):
    db, _ = _db({**BOOKING, "status": "accepted"}, {**BOOKING, "status": "no_show"})
    for c in _client(DOCTOR, db):
        res = c.patch("/bookings/bk-1/no-show", headers=AUTH)

    assert res.status_code == 200
    assert res.json()["status"] == "no_show"
    call = transitions.last("no_show")
    assert call["p_expected_status"] == "accepted"
    assert call["p_patch"]["no_show_marked_by"] == "doc-1"
    assert call["p_patch"]["hold_expires_at"] is None


def test_a_no_show_creates_no_ledger_entry():
    """Nobody is charged for a no-show, so no money may be recognised."""
    ledger = make_chain(list_data=[])
    db, _ = _db({**BOOKING, "status": "accepted"}, {**BOOKING, "status": "no_show"},
                extra={"doctor_ledger_entries": ledger})
    for c in _client(DOCTOR, db):
        c.patch("/bookings/bk-1/no-show", headers=AUTH)
    ledger.insert.assert_not_called()


def test_a_paid_booking_cannot_be_flipped_to_no_show():
    """Money has changed hands; that is a refund, which ops handles."""
    db, _ = _db({**BOOKING, "status": "paid"}, BOOKING)
    for c in _client(DOCTOR, db):
        res = c.patch("/bookings/bk-1/no-show", headers=AUTH)
    assert res.status_code == 400
    assert "accepted, unpaid" in res.json()["error"]


def test_a_requested_booking_cannot_be_marked_no_show():
    db, _ = _db({**BOOKING, "status": "requested"}, BOOKING)
    for c in _client(DOCTOR, db):
        res = c.patch("/bookings/bk-1/no-show", headers=AUTH)
    assert res.status_code == 400


def test_marking_no_show_notifies_the_patient():
    db, _ = _db({**BOOKING, "status": "accepted"}, {**BOOKING, "status": "no_show"})
    for c in _client(DOCTOR, db):
        c.patch("/bookings/bk-1/no-show", headers=AUTH)
    events = [call[0][0]["event"] for call in db.table("notifications").insert.call_args_list]
    assert "booking.no_show" in events


# ── running late ──────────────────────────────────────────────────────────────

def test_running_late_notifies_without_changing_state():
    bookings = make_chain(data={**BOOKING, "status": "paid"})
    db = make_supabase({
        "bookings": bookings,
        "notifications": make_chain(list_data=[{"id": "n-1"}]),
        "users": make_chain(list_data=[{"fcm_token": None}]),
    })
    for c in _client(DOCTOR, db):
        res = c.post("/bookings/bk-1/running-late", headers=AUTH, json={"minutes": 15})

    assert res.status_code == 200
    assert res.json()["minutes"] == 15
    bookings.update.assert_not_called()


def test_running_late_rejects_a_nonsense_delay():
    db = make_supabase({"bookings": make_chain(data={**BOOKING, "status": "paid"})})
    for c in _client(DOCTOR, db):
        assert c.post("/bookings/bk-1/running-late", headers=AUTH,
                      json={"minutes": 0}).status_code == 422
        assert c.post("/bookings/bk-1/running-late", headers=AUTH,
                      json={"minutes": 999}).status_code == 422


def test_running_late_is_rejected_on_an_inactive_booking():
    db = make_supabase({"bookings": make_chain(data={**BOOKING, "status": "completed"})})
    for c in _client(DOCTOR, db):
        res = c.post("/bookings/bk-1/running-late", headers=AUTH, json={"minutes": 10})
    assert res.status_code == 400


# ── cancellation attribution ──────────────────────────────────────────────────

def test_a_patient_cancellation_is_attributed_to_the_patient():
    row = {**BOOKING, "status": "accepted"}
    db, _ = _db(row, {**row, "status": "cancelled"})
    rpc_returns(db, cancelled(row))
    for c in _client(PATIENT, db):
        res = c.patch("/bookings/bk-1/cancel", headers=AUTH)
    assert res.status_code == 200
    name, params = db.rpc.call_args.args
    assert name == "cancel_booking"
    assert params["p_cancelled_by"] == "patient"
    # The status the decision was made on, so a concurrent change loses.
    assert params["p_expected_status"] == "accepted"
    assert params["p_actor_id"] == "pat-1"


def test_a_doctor_cancellation_is_attributed_to_the_doctor():
    row = {**BOOKING, "status": "accepted"}
    db, _ = _db(row, {**row, "status": "cancelled"})
    rpc_returns(db, cancelled(row))
    for c in _client(DOCTOR, db):
        c.patch("/bookings/bk-1/cancel", headers=AUTH)
    assert db.rpc.call_args.args[1]["p_cancelled_by"] == "doctor"


def test_a_no_show_booking_cannot_then_be_cancelled():
    db, _ = _db({**BOOKING, "status": "no_show"}, BOOKING)
    for c in _client(PATIENT, db):
        res = c.patch("/bookings/bk-1/cancel", headers=AUTH)
    assert res.status_code == 400


def test_an_unrelated_user_cannot_cancel_a_booking():
    db, _ = _db({**BOOKING, "patient_id": "other", "doctor_id": "other-doc"}, BOOKING)
    for c in _client(PATIENT, db):
        res = c.patch("/bookings/bk-1/cancel", headers=AUTH)
    assert res.status_code == 403


# ── suspension blocks new bookings ────────────────────────────────────────────

def test_a_suspended_doctor_cannot_receive_a_new_booking():
    db = make_supabase({
        "doctors": make_chain(data={
            "id": "doc-1", "name": "Dr Rao",
            "verification_status": "verified", "suspended": True,
        }),
    })
    for c in _client(PATIENT, db):
        res = c.post("/bookings/", headers=AUTH, json={
            "doctor_id": "doc-1", "channel": "online_consult",
            "scheduled_start": "2026-09-20T09:00:00+00:00",
        })
    assert res.status_code == 409
    assert "not currently accepting" in res.json()["error"]


def test_history_includes_no_show_bookings():
    bookings = make_chain(list_data=[{"id": "bk-1", "status": "no_show"}])
    db = make_supabase({"bookings": bookings})
    for c in _client(DOCTOR, db):
        res = c.get("/bookings/doctor/history", headers=AUTH)
    assert res.status_code == 200
    bookings.in_.assert_any_call("status", ["completed", "declined", "cancelled", "no_show"])


# ── the hold sweeper ──────────────────────────────────────────────────────────

def _maint_client(db):
    with patch(MAINT_DB, db), patch(NOTIF_DB, db), \
         patch("app.routers.maintenance.CRON_SECRET", "cron-secret"):
        yield TestClient(app)


def _sweeper_db(released=(), expired=()):
    """expire_payment_holds / expire_stale_requests (SQL, migration 0023) return
    the ids they moved; the bookings lookup then feeds the notifications."""
    rows = [{**BOOKING, "id": i} for i in [*released, *expired]]
    db = make_supabase({
        "bookings": make_chain(list_data=rows),
        "notifications": make_chain(list_data=[{"id": "n-1"}]),
    })
    answers = {"expire_payment_holds": list(released), "expire_stale_requests": list(expired)}

    def rpc(name, params):
        call = MagicMock()
        call.execute.return_value = MagicMock(data=answers.get(name))
        return call

    db.rpc.side_effect = rpc
    return db


def test_the_sweeper_releases_expired_holds_through_the_state_machine():
    db = _sweeper_db(released=["bk-1"])
    for c in _maint_client(db):
        res = c.post("/maintenance/release-expired-holds",
                     headers={"X-Cron-Secret": "cron-secret"})

    assert res.status_code == 200
    assert res.json() == {"released": 1, "booking_ids": ["bk-1"],
                          "expired_requests": 0, "expired_request_ids": []}
    assert [c.args[0] for c in db.rpc.call_args_list] == \
        ["expire_payment_holds", "expire_stale_requests"]
    # No direct status writes: the SQL functions move bookings, with events.
    db.table("bookings").update.assert_not_called()


def test_the_sweeper_notifies_both_parties_when_it_releases_a_slot():
    db = _sweeper_db(released=["bk-1"])
    for c in _maint_client(db):
        c.post("/maintenance/release-expired-holds", headers={"X-Cron-Secret": "cron-secret"})

    rows = [call[0][0] for call in db.table("notifications").insert.call_args_list]
    assert {r["recipient_id"] for r in rows} == {"pat-1", "doc-1"}
    assert {r["event"] for r in rows} == {"booking.hold_expired"}


def test_the_sweeper_expires_unanswered_requests_and_tells_both_sides():
    db = _sweeper_db(expired=["bk-9"])
    for c in _maint_client(db):
        res = c.post("/maintenance/release-expired-holds", headers={"X-Cron-Secret": "cron-secret"})

    assert res.json()["expired_request_ids"] == ["bk-9"]
    events = {call[0][0]["event"] for call in db.table("notifications").insert.call_args_list}
    assert events == {"booking.request_expired"}


def test_request_expiry_age_comes_from_app_config():
    """Off (only once the slot starts) unless ops sets request_expiry_minutes."""
    db = _sweeper_db()
    with patch("app.routers.maintenance.app_config.get",
               side_effect=lambda k, d=None: 45 if k == "request_expiry_minutes" else d):
        for c in _maint_client(db):
            c.post("/maintenance/release-expired-holds", headers={"X-Cron-Secret": "cron-secret"})
    stale_call = [c for c in db.rpc.call_args_list if c.args[0] == "expire_stale_requests"][0]
    assert stale_call.args[1] == {"p_max_age": "45 minutes"}


def test_the_sweeper_reports_zero_when_nothing_has_expired():
    db = _sweeper_db()
    for c in _maint_client(db):
        res = c.post("/maintenance/release-expired-holds",
                     headers={"X-Cron-Secret": "cron-secret"})
    assert res.json() == {"released": 0, "booking_ids": [],
                          "expired_requests": 0, "expired_request_ids": []}
    db.table("notifications").insert.assert_not_called()


def test_the_sweeper_rejects_a_wrong_secret():
    db = make_supabase({})
    for c in _maint_client(db):
        res = c.post("/maintenance/release-expired-holds", headers={"X-Cron-Secret": "guess"})
    assert res.status_code == 401


def test_the_sweeper_rejects_a_missing_secret():
    db = make_supabase({})
    for c in _maint_client(db):
        res = c.post("/maintenance/release-expired-holds")
    assert res.status_code == 401


def test_maintenance_refuses_to_run_open_when_no_secret_is_configured():
    """An unauthenticated endpoint that mutates bookings is not acceptable just
    because a deploy forgot an environment variable."""
    db = make_supabase({})
    with patch(MAINT_DB, db), patch("app.routers.maintenance.CRON_SECRET", ""):
        res = TestClient(app).post("/maintenance/release-expired-holds",
                                   headers={"X-Cron-Secret": "anything"})
    assert res.status_code == 503


# ── an unpaid visit cannot be closed ─────────────────────────────────────────

def test_complete_refuses_an_unpaid_booking():
    """
    Regression: completing an 'accepted' (unpaid) booking stranded the fee.

    _amount_due only issues a consult_fee order while the booking is 'accepted',
    so once the doctor marked it complete the patient could never pay — while
    get_earnings still counted the amount as earned.
    """
    from unittest.mock import MagicMock, patch
    from fastapi.testclient import TestClient
    from app.main import app
    from tests.conftest import make_chain, make_supabase

    chain = make_chain()
    chain.execute.side_effect = [
        MagicMock(data={"id": "bk-1", "doctor_id": "doc-1", "status": "accepted"}),
    ]
    db = make_supabase({"bookings": chain})

    with patch("app.routers.bookings.supabase", db), patch("app.deps.jwt") as jw:
        jw.decode.return_value = {"sub": "doc-1", "role": "doctor"}
        res = TestClient(app).patch(
            "/bookings/bk-1/complete", headers={"Authorization": "Bearer d"})

    assert res.status_code == 409
    assert "not been paid for" in res.json()["error"]
