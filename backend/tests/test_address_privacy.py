"""
Tests for the home-visit address privacy rule.

Both apps tell the patient their address is "shared on accept". These tests are
what make that a rule rather than a caption: before a doctor accepts, they see the
city, PIN and distance but not the street address — enough to judge whether the
visit is practical, without handing a stranger's home address to someone who may
decline.
"""
from unittest.mock import MagicMock, patch

from fastapi.testclient import TestClient

from app.main import app
from tests.conftest import make_chain, make_supabase

PATIENT = {"sub": "pat-1", "role": "patient"}
DOCTOR  = {"sub": "doc-1", "role": "doctor"}
AUTH    = {"Authorization": "Bearer t"}

BOOK_DB  = "app.routers.bookings.supabase"
NOTIF_DB = "app.services.notifications.supabase"
JWT      = "app.deps.jwt"

FULL = "12 Rose Lane, Flat 3, near City Park, New Delhi, 110001"

def _booking(status="requested", released=None, channel="home_visit"):
    return {
        "id": "bk-1", "patient_id": "pat-1", "doctor_id": "doc-1",
        "channel": channel, "status": status,
        "scheduled_start": "2026-10-01T09:00:00+00:00", "price_confirmed": 800.0,
        "patient_address": FULL,
        "patient_address_lat": 28.6315, "patient_address_lng": 77.2167,
        "distance_km": 2.1, "address_released_at": released,
    }


def _client(payload, db):
    with patch(BOOK_DB, db), patch(NOTIF_DB, db), patch(JWT) as jw:
        jw.decode.return_value = payload
        yield TestClient(app)


# ── before accept ─────────────────────────────────────────────────────────────

def test_the_incoming_queue_withholds_the_street_address():
    db = make_supabase({"bookings": make_chain(list_data=[_booking()])})
    for c in _client(DOCTOR, db):
        row = c.get("/bookings/doctor/incoming", headers=AUTH).json()[0]

    assert row["patient_address"] is None
    assert row["patient_address_lat"] is None
    assert row["address_withheld"] is True


def test_the_doctor_still_sees_the_distance_before_accepting():
    """They need to judge whether the visit is practical."""
    db = make_supabase({"bookings": make_chain(list_data=[_booking()])})
    for c in _client(DOCTOR, db):
        row = c.get("/bookings/doctor/incoming", headers=AUTH).json()[0]
    assert row["distance_km"] == 2.1


def test_a_single_booking_read_withholds_the_address_from_the_doctor():
    db = make_supabase({"bookings": make_chain(data=_booking())})
    for c in _client(DOCTOR, db):
        body = c.get("/bookings/bk-1", headers=AUTH).json()
    assert body["patient_address"] is None
    assert body["address_withheld"] is True


def test_the_patient_always_sees_their_own_address():
    db = make_supabase({"bookings": make_chain(data=_booking())})
    for c in _client(PATIENT, db):
        body = c.get("/bookings/bk-1", headers=AUTH).json()
    assert body["patient_address"] == FULL
    assert "address_withheld" not in body


# ── on accept ─────────────────────────────────────────────────────────────────

def test_accepting_releases_the_address():
    bookings = make_chain()
    bookings.execute.side_effect = [
        MagicMock(data=_booking()),                                    # lookup
        MagicMock(data=[_booking("accepted", released="2026-10-01T00:00:00+00:00")]),
    ]
    db = make_supabase({
        "bookings": bookings,
        "doctors": make_chain(list_data=[{"name": "Dr Rao"}]),
        "notifications": make_chain(list_data=[{"id": "n-1"}]),
    })
    for c in _client(DOCTOR, db):
        res = c.patch("/bookings/bk-1/accept", headers=AUTH)

    assert res.status_code == 200
    assert bookings.update.call_args[0][0]["address_released_at"] is not None


def test_accepting_an_online_consult_releases_nothing():
    """There is no address to release, and stamping one would be misleading."""
    bookings = make_chain()
    bookings.execute.side_effect = [
        MagicMock(data=_booking(channel="online_consult")),
        MagicMock(data=[_booking("accepted", channel="online_consult")]),
    ]
    db = make_supabase({
        "bookings": bookings,
        "doctors": make_chain(list_data=[{"name": "Dr Rao"}]),
        "notifications": make_chain(list_data=[{"id": "n-1"}]),
    })
    for c in _client(DOCTOR, db):
        c.patch("/bookings/bk-1/accept", headers=AUTH)
    assert bookings.update.call_args[0][0]["address_released_at"] is None


# ── after accept ──────────────────────────────────────────────────────────────

def test_an_accepted_booking_shows_the_doctor_the_full_address():
    released = _booking("accepted", released="2026-10-01T00:00:00+00:00")
    db = make_supabase({"bookings": make_chain(list_data=[released])})
    for c in _client(DOCTOR, db):
        row = c.get("/bookings/doctor/active", headers=AUTH).json()[0]

    assert row["patient_address"] == FULL
    assert row["patient_address_lat"] == 28.6315      # for the maps hand-off
    assert "address_withheld" not in row


def test_an_active_booking_without_a_release_stamp_still_withholds():
    """Defensive: if a row ever reaches the active list unreleased, withholding is
    the safe failure rather than leaking."""
    db = make_supabase({"bookings": make_chain(list_data=[_booking("accepted")])})
    for c in _client(DOCTOR, db):
        row = c.get("/bookings/doctor/active", headers=AUTH).json()[0]
    assert row["patient_address"] is None


def test_history_shows_where_the_doctor_actually_went():
    done = _booking("completed", released="2026-10-01T00:00:00+00:00")
    db = make_supabase({"bookings": make_chain(list_data=[done])})
    for c in _client(DOCTOR, db):
        row = c.get("/bookings/doctor/history", headers=AUTH).json()[0]
    assert row["patient_address"] == FULL


def test_an_online_consult_is_never_marked_withheld():
    db = make_supabase({"bookings": make_chain(list_data=[
        _booking(channel="online_consult")])})
    for c in _client(DOCTOR, db):
        row = c.get("/bookings/doctor/incoming", headers=AUTH).json()[0]
    assert "address_withheld" not in row
