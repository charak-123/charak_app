"""
Unit tests for earnings aggregation endpoint.
"""
from unittest.mock import MagicMock, patch
import pytest
from fastapi.testclient import TestClient
from app.main import app
from tests.conftest import make_chain, make_supabase

DOCTOR_TOKEN   = "Bearer doctor_token"
DOCTOR_PAYLOAD = {"sub": "doc-1", "role": "doctor"}

EARNINGS_TARGET = "app.routers.earnings.supabase"
JWT_TARGET      = "app.deps.jwt"


def test_earnings_no_completed_bookings():
    mock_db = make_supabase({
        "bookings": make_chain(list_data=[]),
        "procedure_bills": make_chain(list_data=[]),
    })
    with patch(EARNINGS_TARGET, mock_db), patch(JWT_TARGET) as jw:
        jw.decode.return_value = DOCTOR_PAYLOAD
        client = TestClient(app)
        resp = client.get("/earnings/me", headers={"Authorization": DOCTOR_TOKEN})

    assert resp.status_code == 200
    data = resp.json()
    assert data["grand_total"] == 0.0
    assert data["items"] == []


def test_earnings_with_approved_procedure_bill():
    bookings = [
        {
            "id": "bk-1", "channel": "home_visit",
            "scheduled_start": "2026-08-25T09:00:00+00:00",
            "price_confirmed": 800.0, "status": "completed",
            "users": {"name": "Ramesh"},
        },
    ]
    bills = [
        {"id": "bill-1", "booking_id": "bk-1", "total": 1200.0, "status": "approved", "items": []},
    ]
    mock_db = make_supabase({
        "bookings": make_chain(list_data=bookings),
        "procedure_bills": make_chain(list_data=bills),
    })
    with patch(EARNINGS_TARGET, mock_db), patch(JWT_TARGET) as jw:
        jw.decode.return_value = DOCTOR_PAYLOAD
        client = TestClient(app)
        resp = client.get("/earnings/me", headers={"Authorization": DOCTOR_TOKEN})

    assert resp.status_code == 200
    data = resp.json()
    assert data["consult_total"] == 800.0
    assert data["procedure_total"] == 1200.0
    assert data["grand_total"] == 2000.0
    assert len(data["items"]) == 1


def test_earnings_multiple_bookings():
    bookings = [
        {"id": "bk-1", "channel": "online_consult", "scheduled_start": "2026-08-25T09:00:00+00:00",
         "price_confirmed": 500.0, "status": "completed", "users": {"name": "Ramesh"}},
        {"id": "bk-2", "channel": "home_visit",     "scheduled_start": "2026-08-26T10:00:00+00:00",
         "price_confirmed": 800.0, "status": "completed", "users": {"name": "Priya"}},
    ]
    bills = [
        {"id": "bill-1", "booking_id": "bk-2", "total": 1200.0, "status": "approved", "items": []},
    ]
    mock_db = make_supabase({
        "bookings": make_chain(list_data=bookings),
        "procedure_bills": make_chain(list_data=bills),
    })
    with patch(EARNINGS_TARGET, mock_db), patch(JWT_TARGET) as jw:
        jw.decode.return_value = DOCTOR_PAYLOAD
        client = TestClient(app)
        resp = client.get("/earnings/me", headers={"Authorization": DOCTOR_TOKEN})

    data = resp.json()
    assert data["consult_total"] == 1300.0   # 500 + 800
    assert data["procedure_total"] == 1200.0
    assert data["grand_total"] == 2500.0
    assert len(data["items"]) == 2


def test_earnings_under_review_bill_excluded_from_total():
    bookings = [
        {"id": "bk-1", "channel": "home_visit", "scheduled_start": "2026-08-25T09:00:00+00:00",
         "price_confirmed": 600.0, "status": "completed", "users": {"name": "Suresh"}},
    ]
    bills = [
        {"id": "bill-1", "booking_id": "bk-1", "total": 5000.0, "status": "under_review", "items": []},
    ]
    mock_db = make_supabase({
        "bookings": make_chain(list_data=bookings),
        "procedure_bills": make_chain(list_data=bills),
    })
    with patch(EARNINGS_TARGET, mock_db), patch(JWT_TARGET) as jw:
        jw.decode.return_value = DOCTOR_PAYLOAD
        client = TestClient(app)
        resp = client.get("/earnings/me", headers={"Authorization": DOCTOR_TOKEN})

    data = resp.json()
    assert data["procedure_total"] == 0.0          # under_review not counted yet
    assert data["pending_review_total"] == 5000.0
    assert data["grand_total"] == 600.0            # only consult fee
