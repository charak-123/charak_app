"""Tests for complaints router."""
from unittest.mock import patch
import pytest
from fastapi.testclient import TestClient
from app.main import app

from tests.conftest import make_chain, make_supabase

PATIENT_PAYLOAD = {"sub": "patient-1", "role": "patient"}
OPS_PAYLOAD     = {"sub": "ops-1",     "role": "ops"}
BOOKING_ID   = "booking-abc"
COMPLAINT_ID = "complaint-1"

BOOKING_ROW   = {"id": BOOKING_ID, "patient_id": "patient-1", "doctor_id": "doctor-1", "status": "completed"}
COMPLAINT_ROW = {"id": COMPLAINT_ID, "booking_id": BOOKING_ID, "description": "Test complaint", "status": "open"}

DB_TARGET  = "app.routers.complaints.supabase"
JWT_TARGET = "app.deps.jwt"


def _client(jwt_payload, table_map):
    mock_sb = make_supabase(table_map)
    with patch(DB_TARGET, mock_sb), patch(JWT_TARGET) as jw:
        jw.decode.return_value = jwt_payload
        yield TestClient(app)


# ── POST /{booking_id}/complaint ──────────────────────────────────────────────

def test_file_complaint_success():
    bookings_chain   = make_chain(data=BOOKING_ROW)
    complaints_chain = make_chain(list_data=[COMPLAINT_ROW])
    for client in _client(PATIENT_PAYLOAD, {"bookings": bookings_chain, "complaints": complaints_chain}):
        resp = client.post(f"/bookings/{BOOKING_ID}/complaint",
                           json={"description": "Test complaint"},
                           headers={"Authorization": "Bearer t"})
    assert resp.status_code == 201
    assert resp.json()["description"] == "Test complaint"


def test_file_complaint_empty_description():
    for client in _client(PATIENT_PAYLOAD, {}):
        resp = client.post(f"/bookings/{BOOKING_ID}/complaint",
                           json={"description": "   "},
                           headers={"Authorization": "Bearer t"})
    assert resp.status_code == 400


def test_file_complaint_wrong_patient():
    booking = {**BOOKING_ROW, "patient_id": "other-patient"}
    bookings_chain = make_chain(data=booking)
    for client in _client(PATIENT_PAYLOAD, {"bookings": bookings_chain}):
        resp = client.post(f"/bookings/{BOOKING_ID}/complaint",
                           json={"description": "Test"},
                           headers={"Authorization": "Bearer t"})
    assert resp.status_code == 403


# ── GET /{booking_id}/complaint ───────────────────────────────────────────────

def test_get_complaints_returns_list():
    bookings_chain   = make_chain(data=BOOKING_ROW)
    complaints_chain = make_chain(list_data=[COMPLAINT_ROW])
    for client in _client(PATIENT_PAYLOAD, {"bookings": bookings_chain, "complaints": complaints_chain}):
        resp = client.get(f"/bookings/{BOOKING_ID}/complaint",
                          headers={"Authorization": "Bearer t"})
    assert resp.status_code == 200
    assert len(resp.json()) == 1


def test_get_complaints_forbidden_third_party():
    third_party = {"sub": "stranger", "role": "patient"}
    bookings_chain = make_chain(data=BOOKING_ROW)
    for client in _client(third_party, {"bookings": bookings_chain}):
        resp = client.get(f"/bookings/{BOOKING_ID}/complaint",
                          headers={"Authorization": "Bearer t"})
    assert resp.status_code == 403


# ── PATCH /complaints/{complaint_id} (ops only) ───────────────────────────────

def test_ops_update_complaint_status():
    complaints_chain = make_chain(data={**COMPLAINT_ROW, "status": "in_review"}, list_data=[COMPLAINT_ROW])
    for client in _client(OPS_PAYLOAD, {"complaints": complaints_chain}):
        resp = client.patch(f"/bookings/complaints/{COMPLAINT_ID}",
                            json={"status": "in_review"},
                            headers={"Authorization": "Bearer t"})
    assert resp.status_code == 200


def test_ops_invalid_status():
    complaints_chain = make_chain(data=COMPLAINT_ROW, list_data=[COMPLAINT_ROW])
    for client in _client(OPS_PAYLOAD, {"complaints": complaints_chain}):
        resp = client.patch(f"/bookings/complaints/{COMPLAINT_ID}",
                            json={"status": "bogus"},
                            headers={"Authorization": "Bearer t"})
    assert resp.status_code == 400
