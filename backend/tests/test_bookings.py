"""
Unit tests for the bookings router.
Patches app.routers.bookings.supabase (the local name bound at import).
"""
from unittest.mock import MagicMock, patch
import pytest
from fastapi.testclient import TestClient
from app.main import app

from tests.conftest import make_chain, make_supabase

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
    verified_doc = make_chain(data={"id": "doc-1", "verification_status": "verified"})
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

    mock_db = make_supabase({"doctors": verified_doc, "bookings": bookings_chain})

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
    verified_doc    = make_chain(data={"id": "doc-1", "verification_status": "verified"})
    conflict_chain  = make_chain(list_data=[{"id": "existing"}])

    mock_db = make_supabase({"doctors": verified_doc, "bookings": conflict_chain})
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
    mock_db = make_supabase({"bookings": chain})

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
