"""
Unit tests for procedure bills + senior review state machine.
"""
from unittest.mock import MagicMock, patch
import pytest
from fastapi.testclient import TestClient
from app.main import app
from tests.conftest import make_chain, make_supabase

DOCTOR_TOKEN  = "Bearer doctor_token"
OPS_TOKEN     = "Bearer ops_token"
DOCTOR_PAYLOAD = {"sub": "doc-1", "role": "doctor"}
OPS_PAYLOAD    = {"sub": "ops-1", "role": "ops"}

BILLS_TARGET = "app.routers.procedure_bills.supabase"
JWT_TARGET   = "app.deps.jwt"

COMPLETED_BOOKING = {
    "id": "bk-1", "doctor_id": "doc-1", "patient_id": "pat-1",
    "channel": "home_visit", "status": "completed",
    "scheduled_start": "2026-08-25T09:00:00+00:00",
}
DOCTOR_ROW = {"id": "doc-1", "procedure_review_threshold": 1000.0}


def _bills_chain_for_create(bill_status: str):
    """Returns chain that: no existing bill → inserts → updates items."""
    bill_row = {
        "id": "bill-1", "booking_id": "bk-1",
        "total": 500.0, "status": bill_status,
    }
    c = make_chain()
    calls = {"n": 0}
    def execute():
        calls["n"] += 1
        if calls["n"] == 1:
            return MagicMock(data=[])             # no existing bill
        if calls["n"] == 2:
            return MagicMock(data=[bill_row])     # insert
        return MagicMock(data=[bill_row])         # update items
    c.execute.side_effect = execute
    return c


def test_create_bill_below_threshold_is_approved():
    mock_db = make_supabase({
        "bookings": make_chain(data=COMPLETED_BOOKING),
        "procedure_bills": _bills_chain_for_create("approved"),
        "doctors": make_chain(data=DOCTOR_ROW),
    })
    with patch(BILLS_TARGET, mock_db), patch(JWT_TARGET) as jw:
        jw.decode.return_value = DOCTOR_PAYLOAD
        client = TestClient(app)
        resp = client.post(
            "/bookings/bk-1/procedure-bill",
            json={"items": [{"name": "Injection", "price": 300}, {"name": "Dressing", "price": 200}]},
            headers={"Authorization": DOCTOR_TOKEN},
        )
    assert resp.status_code == 201
    data = resp.json()
    assert data["status"] == "approved"
    assert data["needs_review"] is False


def test_create_bill_above_threshold_is_under_review():
    mock_db = make_supabase({
        "bookings": make_chain(data=COMPLETED_BOOKING),
        "procedure_bills": _bills_chain_for_create("under_review"),
        "doctors": make_chain(data={"id": "doc-1", "procedure_review_threshold": 1000.0}),
    })
    with patch(BILLS_TARGET, mock_db), patch(JWT_TARGET) as jw:
        jw.decode.return_value = DOCTOR_PAYLOAD
        client = TestClient(app)
        resp = client.post(
            "/bookings/bk-1/procedure-bill",
            json={"items": [{"name": "Surgery", "price": 5000}]},
            headers={"Authorization": DOCTOR_TOKEN},
        )
    assert resp.status_code == 201
    data = resp.json()
    assert data["status"] == "under_review"
    assert data["needs_review"] is True


def test_create_bill_on_non_completed_booking_returns_400():
    accepted_booking = {**COMPLETED_BOOKING, "status": "accepted"}
    mock_db = make_supabase({
        "bookings": make_chain(data=accepted_booking),
    })
    with patch(BILLS_TARGET, mock_db), patch(JWT_TARGET) as jw:
        jw.decode.return_value = DOCTOR_PAYLOAD
        client = TestClient(app)
        resp = client.post(
            "/bookings/bk-1/procedure-bill",
            json={"items": [{"name": "X", "price": 100}]},
            headers={"Authorization": DOCTOR_TOKEN},
        )
    assert resp.status_code == 400


def test_create_bill_empty_items_returns_400():
    mock_db = make_supabase({"bookings": make_chain(data=COMPLETED_BOOKING)})
    with patch(BILLS_TARGET, mock_db), patch(JWT_TARGET) as jw:
        jw.decode.return_value = DOCTOR_PAYLOAD
        client = TestClient(app)
        resp = client.post(
            "/bookings/bk-1/procedure-bill",
            json={"items": []},
            headers={"Authorization": DOCTOR_TOKEN},
        )
    assert resp.status_code == 400


def test_duplicate_bill_returns_409():
    mock_db = make_supabase({
        "bookings": make_chain(data=COMPLETED_BOOKING),
        "procedure_bills": make_chain(list_data=[{"id": "existing-bill"}]),
        "doctors": make_chain(data=DOCTOR_ROW),
    })
    with patch(BILLS_TARGET, mock_db), patch(JWT_TARGET) as jw:
        jw.decode.return_value = DOCTOR_PAYLOAD
        client = TestClient(app)
        resp = client.post(
            "/bookings/bk-1/procedure-bill",
            json={"items": [{"name": "X", "price": 100}]},
            headers={"Authorization": DOCTOR_TOKEN},
        )
    assert resp.status_code == 409


def test_ops_approve_bill():
    under_review_bill = {"id": "bill-1", "booking_id": "bk-1", "total": 5000.0, "status": "under_review"}
    approved_bill     = {**under_review_bill, "status": "approved"}

    c = make_chain()
    calls = {"n": 0}
    def execute():
        calls["n"] += 1
        if calls["n"] == 1:
            return MagicMock(data=[under_review_bill])  # GET
        return MagicMock(data=[approved_bill])           # UPDATE
    c.execute.side_effect = execute

    mock_db = make_supabase({"procedure_bills": c})
    with patch(BILLS_TARGET, mock_db), patch(JWT_TARGET) as jw:
        jw.decode.return_value = OPS_PAYLOAD
        client = TestClient(app)
        resp = client.patch("/bookings/bk-1/procedure-bill/approve", headers={"Authorization": OPS_TOKEN})

    assert resp.status_code == 200
    assert resp.json()["status"] == "approved"


def test_ops_approve_non_review_bill_returns_400():
    approved_bill = {"id": "bill-1", "booking_id": "bk-1", "total": 500.0, "status": "approved"}
    mock_db = make_supabase({"procedure_bills": make_chain(list_data=[approved_bill])})

    with patch(BILLS_TARGET, mock_db), patch(JWT_TARGET) as jw:
        jw.decode.return_value = OPS_PAYLOAD
        client = TestClient(app)
        resp = client.patch("/bookings/bk-1/procedure-bill/approve", headers={"Authorization": OPS_TOKEN})

    assert resp.status_code == 400
