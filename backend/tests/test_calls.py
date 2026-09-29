"""
Unit tests for clarification calls router.
"""
from unittest.mock import MagicMock, patch
import pytest
from fastapi.testclient import TestClient
from app.main import app
from tests.conftest import make_chain, make_supabase

DOCTOR_TOKEN   = "Bearer doctor_token"
DOCTOR_PAYLOAD = {"sub": "doc-1", "role": "doctor"}

CALLS_TARGET = "app.routers.calls.supabase"
JWT_TARGET   = "app.deps.jwt"

REQUESTED_BOOKING = {
    "id": "bk-1", "doctor_id": "doc-1", "patient_id": "pat-1",
    "channel": "home_visit", "status": "requested",
}

CALL_ROW = {
    "id": "call-1", "booking_id": "bk-1", "call_status": "initiated",
    "notes": None, "started_at": None, "ended_at": None,
}


def test_initiate_call_success():
    calls_chain = make_chain()
    calls_c = {"n": 0}
    def calls_execute():
        calls_c["n"] += 1
        if calls_c["n"] == 1:
            return MagicMock(data=[])           # no active calls
        return MagicMock(data=[CALL_ROW])       # inserted
    calls_chain.execute.side_effect = calls_execute

    mock_db = make_supabase({
        "bookings": make_chain(data=REQUESTED_BOOKING),
        "clarification_calls": calls_chain,
    })
    with patch(CALLS_TARGET, mock_db), patch(JWT_TARGET) as jw:
        jw.decode.return_value = DOCTOR_PAYLOAD
        client = TestClient(app)
        resp = client.post("/bookings/bk-1/clarification-call", headers={"Authorization": DOCTOR_TOKEN})

    assert resp.status_code == 201
    data = resp.json()
    assert data["call_status"] == "initiated"
    assert "agora_channel" in data
    assert "agora_token" in data


def test_initiate_call_on_completed_booking_returns_400():
    completed = {**REQUESTED_BOOKING, "status": "completed"}
    mock_db = make_supabase({"bookings": make_chain(data=completed)})

    with patch(CALLS_TARGET, mock_db), patch(JWT_TARGET) as jw:
        jw.decode.return_value = DOCTOR_PAYLOAD
        client = TestClient(app)
        resp = client.post("/bookings/bk-1/clarification-call", headers={"Authorization": DOCTOR_TOKEN})

    assert resp.status_code == 400


def test_duplicate_active_call_returns_409():
    calls_chain = make_chain(list_data=[{"id": "existing-call"}])
    mock_db = make_supabase({
        "bookings": make_chain(data=REQUESTED_BOOKING),
        "clarification_calls": calls_chain,
    })

    with patch(CALLS_TARGET, mock_db), patch(JWT_TARGET) as jw:
        jw.decode.return_value = DOCTOR_PAYLOAD
        client = TestClient(app)
        resp = client.post("/bookings/bk-1/clarification-call", headers={"Authorization": DOCTOR_TOKEN})

    assert resp.status_code == 409


def test_complete_call():
    initiated_call = {**CALL_ROW, "bookings": {"doctor_id": "doc-1"}}
    completed_call = {**initiated_call, "call_status": "completed", "notes": "Fever for 3 days"}

    calls_chain = make_chain()
    n = {"v": 0}
    def execute():
        n["v"] += 1
        if n["v"] == 1:
            return MagicMock(data=initiated_call)   # GET
        return MagicMock(data=[completed_call])      # UPDATE
    calls_chain.execute.side_effect = execute

    mock_db = make_supabase({"clarification_calls": calls_chain})

    with patch(CALLS_TARGET, mock_db), patch(JWT_TARGET) as jw:
        jw.decode.return_value = DOCTOR_PAYLOAD
        client = TestClient(app)
        resp = client.patch(
            "/bookings/bk-1/clarification-call/call-1/complete",
            json={"notes": "Fever for 3 days"},
            headers={"Authorization": DOCTOR_TOKEN},
        )

    assert resp.status_code == 200
    assert resp.json()["call_status"] == "completed"


def test_complete_already_completed_call_returns_400():
    already_done = {**CALL_ROW, "call_status": "completed", "bookings": {"doctor_id": "doc-1"}}
    mock_db = make_supabase({"clarification_calls": make_chain(data=already_done)})

    with patch(CALLS_TARGET, mock_db), patch(JWT_TARGET) as jw:
        jw.decode.return_value = DOCTOR_PAYLOAD
        client = TestClient(app)
        resp = client.patch(
            "/bookings/bk-1/clarification-call/call-1/complete",
            json={"notes": ""},
            headers={"Authorization": DOCTOR_TOKEN},
        )

    assert resp.status_code == 400


def test_mark_missed():
    initiated = {**CALL_ROW, "bookings": {"doctor_id": "doc-1"}}
    missed    = {**initiated, "call_status": "missed"}

    calls_chain = make_chain()
    n = {"v": 0}
    def execute():
        n["v"] += 1
        return MagicMock(data=initiated) if n["v"] == 1 else MagicMock(data=[missed])
    calls_chain.execute.side_effect = execute

    mock_db = make_supabase({"clarification_calls": calls_chain})

    with patch(CALLS_TARGET, mock_db), patch(JWT_TARGET) as jw:
        jw.decode.return_value = DOCTOR_PAYLOAD
        client = TestClient(app)
        resp = client.patch(
            "/bookings/bk-1/clarification-call/call-1/missed",
            headers={"Authorization": DOCTOR_TOKEN},
        )

    assert resp.status_code == 200
    assert resp.json()["call_status"] == "missed"


# ── Joining an in-progress call ──────────────────────────────────────────────

PATIENT_TOKEN   = "Bearer patient_token"
PATIENT_PAYLOAD = {"sub": "pat-1", "role": "patient"}

BOOKING_WITH_DOCTOR = {
    "patient_id": "pat-1", "doctor_id": "doc-1", "doctors": {"name": "Dr Rao"},
}


def test_patient_joins_active_call():
    """The patient app has no call id — it asks to be let into whatever is ringing."""
    mock_db = make_supabase({
        "bookings": make_chain(data=BOOKING_WITH_DOCTOR),
        "clarification_calls": make_chain(data=[CALL_ROW]),
    })

    with patch(CALLS_TARGET, mock_db), patch(JWT_TARGET) as jw:
        jw.decode.return_value = PATIENT_PAYLOAD
        client = TestClient(app)
        resp = client.post(
            "/bookings/bk-1/call",
            json={"uid": 1001},
            headers={"Authorization": PATIENT_TOKEN},
        )

    assert resp.status_code == 200
    data = resp.json()
    assert data["call_id"] == "call-1"
    assert data["uid"] == 1001
    assert data["doctor_name"] == "Dr Rao"
    # The legacy key the patient app reads must stay in step with agora_token.
    assert data["token"] == data["agora_token"]
    assert data["agora_channel"].startswith("charak_")


def test_join_with_no_active_call_returns_404():
    mock_db = make_supabase({
        "bookings": make_chain(data=BOOKING_WITH_DOCTOR),
        "clarification_calls": make_chain(data=[]),
    })

    with patch(CALLS_TARGET, mock_db), patch(JWT_TARGET) as jw:
        jw.decode.return_value = PATIENT_PAYLOAD
        client = TestClient(app)
        resp = client.post(
            "/bookings/bk-1/call", json={}, headers={"Authorization": PATIENT_TOKEN}
        )

    assert resp.status_code == 404


def test_outsider_cannot_join_call():
    mock_db = make_supabase({"bookings": make_chain(data=BOOKING_WITH_DOCTOR)})

    with patch(CALLS_TARGET, mock_db), patch(JWT_TARGET) as jw:
        jw.decode.return_value = {"sub": "pat-9", "role": "patient"}
        client = TestClient(app)
        resp = client.post(
            "/bookings/bk-1/call", json={}, headers={"Authorization": PATIENT_TOKEN}
        )

    assert resp.status_code == 403


# ── a paid consult is joinable without a clarification call ──────────────────

def _join_db(booking, calls=None):
    from tests.conftest import make_chain, make_supabase
    return make_supabase({
        "bookings": make_chain(data=booking),
        "clarification_calls": make_chain(list_data=calls or []),
    })


def test_patient_can_join_a_paid_online_consult_with_no_call_row():
    """
    Regression: the consult itself had no clarification_calls row, so the
    patient's "Join call" button (gated on status == paid && online) always
    returned 404 "No call is in progress for this booking".
    """
    from unittest.mock import patch
    from fastapi.testclient import TestClient
    from app.main import app

    db = _join_db({"patient_id": "pat-1", "doctor_id": "doc-1",
                   "channel": "online_consult", "status": "paid",
                   "doctors": {"name": "Dr A"}})

    with patch("app.routers.calls.supabase", db), patch("app.deps.jwt") as jw:
        jw.decode.return_value = {"sub": "pat-1", "role": "patient"}
        res = TestClient(app).post("/bookings/bk-1/call", json={"uid": 1001},
                                   headers={"Authorization": "Bearer p"})

    assert res.status_code == 200
    body = res.json()
    assert body["agora_channel"] == "charak_bk-1"
    assert body["call_id"] is None          # no clarification call to report
    assert body["doctor_name"] == "Dr A"


def test_joining_an_unpaid_consult_with_no_call_row_is_still_refused():
    """The permissive path is for *paid* consults only."""
    from unittest.mock import patch
    from fastapi.testclient import TestClient
    from app.main import app

    db = _join_db({"patient_id": "pat-1", "doctor_id": "doc-1",
                   "channel": "online_consult", "status": "accepted",
                   "doctors": {"name": "Dr A"}})

    with patch("app.routers.calls.supabase", db), patch("app.deps.jwt") as jw:
        jw.decode.return_value = {"sub": "pat-1", "role": "patient"}
        res = TestClient(app).post("/bookings/bk-1/call", json={"uid": 1001},
                                   headers={"Authorization": "Bearer p"})

    assert res.status_code == 404


def test_a_home_visit_cannot_be_joined_without_a_clarification_call():
    """A home visit has no video consult to fall back to."""
    from unittest.mock import patch
    from fastapi.testclient import TestClient
    from app.main import app

    db = _join_db({"patient_id": "pat-1", "doctor_id": "doc-1",
                   "channel": "home_visit", "status": "paid",
                   "doctors": {"name": "Dr A"}})

    with patch("app.routers.calls.supabase", db), patch("app.deps.jwt") as jw:
        jw.decode.return_value = {"sub": "pat-1", "role": "patient"}
        res = TestClient(app).post("/bookings/bk-1/call", json={"uid": 1001},
                                   headers={"Authorization": "Bearer p"})

    assert res.status_code == 404
