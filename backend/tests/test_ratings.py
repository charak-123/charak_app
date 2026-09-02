"""Tests for ratings router."""
from unittest.mock import patch
import pytest
from fastapi.testclient import TestClient
from app.main import app

from tests.conftest import make_chain, make_chain_seq, make_supabase

PATIENT_PAYLOAD = {"sub": "patient-1", "role": "patient"}
DOCTOR_PAYLOAD  = {"sub": "doctor-1",  "role": "doctor"}
BOOKING_ID = "booking-abc"

BOOKING_COMPLETED = {
    "id": BOOKING_ID, "patient_id": "patient-1", "doctor_id": "doctor-1",
    "status": "completed",
}
BOOKING_PAID = {
    "id": BOOKING_ID, "patient_id": "patient-1", "doctor_id": "doctor-1",
    "status": "paid",
}
RATING_ROW = {"id": "rating-1", "booking_id": BOOKING_ID, "stars": 5, "comment": "Great!"}

DB_TARGET  = "app.routers.ratings.supabase"
JWT_TARGET = "app.deps.jwt"


def _client(jwt_payload, table_map):
    mock_sb = make_supabase(table_map)
    with patch(DB_TARGET, mock_sb), patch(JWT_TARGET) as jw:
        jw.decode.return_value = jwt_payload
        yield TestClient(app)


# ── POST /{booking_id}/rate ────────────────────────────────────────────────────

def test_rate_booking_success():
    bookings_chain = make_chain(data=BOOKING_COMPLETED)
    # 1st execute: select existing (none) → 2nd execute: insert returns row
    ratings_chain  = make_chain_seq([], [RATING_ROW])
    for client in _client(PATIENT_PAYLOAD, {"bookings": bookings_chain, "ratings": ratings_chain}):
        resp = client.post(f"/bookings/{BOOKING_ID}/rate",
                           json={"stars": 5, "comment": "Great!"},
                           headers={"Authorization": "Bearer t"})
    assert resp.status_code == 201
    assert resp.json()["stars"] == 5


def test_rate_booking_invalid_stars():
    for client in _client(PATIENT_PAYLOAD, {}):
        resp = client.post(f"/bookings/{BOOKING_ID}/rate",
                           json={"stars": 6},
                           headers={"Authorization": "Bearer t"})
    assert resp.status_code == 400


def test_rate_booking_not_completed():
    bookings_chain = make_chain(data=BOOKING_PAID)
    ratings_chain  = make_chain(list_data=[])
    for client in _client(PATIENT_PAYLOAD, {"bookings": bookings_chain, "ratings": ratings_chain}):
        resp = client.post(f"/bookings/{BOOKING_ID}/rate",
                           json={"stars": 4},
                           headers={"Authorization": "Bearer t"})
    assert resp.status_code == 400


def test_rate_booking_wrong_patient():
    booking = {**BOOKING_COMPLETED, "patient_id": "other-patient"}
    bookings_chain = make_chain(data=booking)
    for client in _client(PATIENT_PAYLOAD, {"bookings": bookings_chain}):
        resp = client.post(f"/bookings/{BOOKING_ID}/rate",
                           json={"stars": 3},
                           headers={"Authorization": "Bearer t"})
    assert resp.status_code == 403


def test_rate_booking_duplicate():
    bookings_chain = make_chain(data=BOOKING_COMPLETED)
    ratings_chain  = make_chain(data=RATING_ROW, list_data=[RATING_ROW])
    for client in _client(PATIENT_PAYLOAD, {"bookings": bookings_chain, "ratings": ratings_chain}):
        resp = client.post(f"/bookings/{BOOKING_ID}/rate",
                           json={"stars": 5},
                           headers={"Authorization": "Bearer t"})
    assert resp.status_code == 409


# ── GET /{booking_id}/rate ────────────────────────────────────────────────────

def test_get_rating_returns_rating():
    bookings_chain = make_chain(data=BOOKING_COMPLETED)
    ratings_chain  = make_chain(data=RATING_ROW, list_data=[RATING_ROW])
    for client in _client(PATIENT_PAYLOAD, {"bookings": bookings_chain, "ratings": ratings_chain}):
        resp = client.get(f"/bookings/{BOOKING_ID}/rate",
                          headers={"Authorization": "Bearer t"})
    assert resp.status_code == 200
    assert resp.json()["stars"] == 5


def test_get_rating_none_returns_null():
    bookings_chain = make_chain(data=BOOKING_COMPLETED)
    ratings_chain  = make_chain(list_data=[])
    for client in _client(PATIENT_PAYLOAD, {"bookings": bookings_chain, "ratings": ratings_chain}):
        resp = client.get(f"/bookings/{BOOKING_ID}/rate",
                          headers={"Authorization": "Bearer t"})
    assert resp.status_code == 200
    assert resp.json() is None
