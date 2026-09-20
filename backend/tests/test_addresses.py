"""
Tests for patient addresses and the home-visit booking rules built on them.

Two things are load-bearing here: an address is validated against the doctor's
service radius before a visit can be booked, and the booking keeps its own
snapshot so a later edit cannot rewrite where a doctor was sent.
"""
from unittest.mock import MagicMock, patch

from fastapi.testclient import TestClient

from app.main import app
from tests.conftest import make_chain, make_supabase

PATIENT = {"sub": "pat-1", "role": "patient"}
DOCTOR  = {"sub": "doc-1", "role": "doctor"}
AUTH    = {"Authorization": "Bearer t"}

ADDR_DB  = "app.routers.addresses.supabase"
BOOK_DB  = "app.routers.bookings.supabase"
NOTIF_DB = "app.services.notifications.supabase"
JWT      = "app.deps.jwt"

ADDRESS = {
    "id": "addr-1", "patient_id": "pat-1", "label": "Home",
    "line1": "12 Rose Lane", "line2": "Flat 3", "landmark": "City Park",
    "city": "New Delhi", "pincode": "110001",
    "lat": 28.6315, "lng": 77.2167, "is_default": True,
}

VALID = {
    "label": "Home", "line1": "12 Rose Lane", "city": "New Delhi",
    "pincode": "110001", "lat": 28.6315, "lng": 77.2167,
}


def _client(payload, db, target=ADDR_DB):
    with patch(target, db), patch(JWT) as jw:
        jw.decode.return_value = payload
        yield TestClient(app)


# ── validation ────────────────────────────────────────────────────────────────

def test_a_valid_address_is_created():
    addresses = make_chain()
    addresses.execute.side_effect = [
        MagicMock(data=[{"id": "existing"}]),   # the "any existing?" lookup
        MagicMock(data=[ADDRESS]),              # insert
    ]
    db = make_supabase({"patient_addresses": addresses})
    for c in _client(PATIENT, db):
        res = c.post("/addresses/", headers=AUTH, json=VALID)
    assert res.status_code == 201


def test_the_first_address_becomes_the_default_automatically():
    """Otherwise booking a home visit would mean picking from a list of one."""
    addresses = make_chain()
    addresses.execute.side_effect = [
        MagicMock(data=[]),                     # no existing addresses
        MagicMock(data=[]),                     # clear-default (a no-op here)
        MagicMock(data=[ADDRESS]),              # insert
    ]
    db = make_supabase({"patient_addresses": addresses})
    for c in _client(PATIENT, db):
        c.post("/addresses/", headers=AUTH, json={**VALID, "is_default": False})
    assert addresses.insert.call_args[0][0]["is_default"] is True


def test_setting_a_new_default_clears_the_previous_one():
    """A partial unique index allows only one default per patient."""
    addresses = make_chain()
    addresses.execute.side_effect = [
        MagicMock(data=[{"id": "existing"}]),
        MagicMock(data=[{"id": "existing"}]),   # the clear-default update
        MagicMock(data=[ADDRESS]),
    ]
    db = make_supabase({"patient_addresses": addresses})
    for c in _client(PATIENT, db):
        c.post("/addresses/", headers=AUTH, json={**VALID, "is_default": True})
    assert addresses.update.call_args[0][0] == {"is_default": False}


def test_a_bad_pincode_is_rejected():
    db = make_supabase({})
    for c in _client(PATIENT, db):
        for bad in ("11001", "1100011", "abcdef", "011001"):
            res = c.post("/addresses/", headers=AUTH, json={**VALID, "pincode": bad})
            assert res.status_code == 422, bad


def test_out_of_range_coordinates_are_rejected():
    db = make_supabase({})
    for c in _client(PATIENT, db):
        assert c.post("/addresses/", headers=AUTH,
                      json={**VALID, "lat": 100}).status_code == 422
        assert c.post("/addresses/", headers=AUTH,
                      json={**VALID, "lng": -200}).status_code == 422


def test_coordinates_are_required():
    """An address that cannot be located is one a doctor cannot be sent to, and
    both the radius check and the distance sort depend on them."""
    db = make_supabase({})
    for c in _client(PATIENT, db):
        body = {k: v for k, v in VALID.items() if k not in ("lat", "lng")}
        assert c.post("/addresses/", headers=AUTH, json=body).status_code == 422


# ── ownership ─────────────────────────────────────────────────────────────────

def test_a_patient_cannot_read_or_edit_another_patients_address():
    db = make_supabase({"patient_addresses": make_chain(data={**ADDRESS, "patient_id": "pat-999"})})
    for c in _client(PATIENT, db):
        assert c.patch("/addresses/addr-1", headers=AUTH,
                       json={"label": "Mine now"}).status_code == 403
        assert c.delete("/addresses/addr-1", headers=AUTH).status_code == 403


def test_an_unknown_address_is_a_404():
    db = make_supabase({"patient_addresses": make_chain(data=None)})
    for c in _client(PATIENT, db):
        assert c.delete("/addresses/nope", headers=AUTH).status_code == 404


def test_deleting_the_default_promotes_another_address():
    addresses = make_chain()
    addresses.execute.side_effect = [
        MagicMock(data=ADDRESS),                 # ownership lookup (maybe_single)
        MagicMock(data=[]),                      # delete
        MagicMock(data=[{"id": "addr-2"}]),      # remaining
        MagicMock(data=[{"id": "addr-2"}]),      # promote
    ]
    db = make_supabase({"patient_addresses": addresses})
    for c in _client(PATIENT, db):
        res = c.delete("/addresses/addr-1", headers=AUTH)
    assert res.status_code == 200
    assert addresses.update.call_args[0][0] == {"is_default": True}


def test_the_list_is_scoped_to_the_caller():
    addresses = make_chain(list_data=[ADDRESS])
    db = make_supabase({"patient_addresses": addresses})
    for c in _client(PATIENT, db):
        assert c.get("/addresses/", headers=AUTH).status_code == 200
    addresses.eq.assert_any_call("patient_id", "pat-1")


# ── home-visit booking rules ──────────────────────────────────────────────────

DOCTOR_ROW = {
    "id": "doc-1", "name": "Dr Rao", "verification_status": "verified",
    "suspended": False, "offers_home_visit": True, "offers_online_consult": True,
    "base_lat": 28.6139, "base_lng": 77.2090, "service_radius_km": 3,
}

BOOK_BODY = {
    "doctor_id": "doc-1", "channel": "home_visit",
    "scheduled_start": "2026-10-01T09:00:00+00:00",
    "price_confirmed": 800.0, "address_id": "addr-1",
}


def _book_db(doctor=None, address=ADDRESS):
    bookings = make_chain()
    bookings.execute.side_effect = [
        MagicMock(data=[]),                                    # slot conflict check
        MagicMock(data=[{"id": "bk-1", "status": "requested",
                         "doctor_id": "doc-1", "patient_id": "pat-1",
                         "channel": "home_visit"}]),
    ]
    db = make_supabase({
        "doctors": make_chain(data=doctor or DOCTOR_ROW),
        "patient_addresses": make_chain(data=address),
        "bookings": bookings,
        "users": make_chain(list_data=[{"name": "Asha"}]),
        "notifications": make_chain(list_data=[{"id": "n-1"}]),
    })
    return db, bookings


def _book(db):
    with patch(BOOK_DB, db), patch(NOTIF_DB, db), patch(JWT) as jw:
        jw.decode.return_value = PATIENT
        return TestClient(app).post("/bookings/", headers=AUTH, json=BOOK_BODY)


def test_a_home_visit_requires_an_address():
    db, _ = _book_db()
    with patch(BOOK_DB, db), patch(NOTIF_DB, db), patch(JWT) as jw:
        jw.decode.return_value = PATIENT
        res = TestClient(app).post("/bookings/", headers=AUTH,
                                   json={k: v for k, v in BOOK_BODY.items()
                                         if k != "address_id"})
    assert res.status_code == 400
    assert "address_id is required" in res.json()["error"]


def test_an_in_range_address_books_and_is_snapshotted():
    db, bookings = _book_db()
    res = _book(db)
    assert res.status_code == 201

    written = bookings.insert.call_args[0][0]
    assert written["address_id"] == "addr-1"
    # The snapshot is a readable one-line address, not an id the doctor app would
    # have to resolve — and it survives the address later being edited.
    assert "12 Rose Lane" in written["patient_address"]
    assert "near City Park" in written["patient_address"]
    assert "110001" in written["patient_address"]
    assert written["distance_km"] is not None


def test_an_address_outside_the_radius_is_refused_with_the_distance():
    """A patient could previously book a home visit from a doctor 40km away."""
    far = {**ADDRESS, "lat": 19.0760, "lng": 72.8777}
    db, _ = _book_db(address=far)
    res = _book(db)
    assert res.status_code == 409
    assert "outside this doctor's 3km service area" in res.json()["error"]


def test_a_doctor_with_no_base_location_cannot_take_home_visits():
    db, _ = _book_db(doctor={**DOCTOR_ROW, "base_lat": None, "base_lng": None})
    res = _book(db)
    assert res.status_code == 409
    assert "not finished setting up" in res.json()["error"]


def test_booking_another_patients_address_is_forbidden():
    db, _ = _book_db(address={**ADDRESS, "patient_id": "pat-999"})
    assert _book(db).status_code == 403


def test_a_home_visit_is_refused_if_the_doctor_does_not_offer_it():
    db, _ = _book_db(doctor={**DOCTOR_ROW, "offers_home_visit": False})
    res = _book(db)
    assert res.status_code == 400
    assert "does not offer home visits" in res.json()["error"]


def test_an_online_consult_is_refused_if_the_doctor_does_not_offer_it():
    db, _ = _book_db(doctor={**DOCTOR_ROW, "offers_online_consult": False})
    with patch(BOOK_DB, db), patch(NOTIF_DB, db), patch(JWT) as jw:
        jw.decode.return_value = PATIENT
        res = TestClient(app).post("/bookings/", headers=AUTH, json={
            **BOOK_BODY, "channel": "online_consult", "address_id": None})
    assert res.status_code == 400
    assert "does not offer online consults" in res.json()["error"]


def test_an_online_consult_needs_no_address():
    db, bookings = _book_db()
    with patch(BOOK_DB, db), patch(NOTIF_DB, db), patch(JWT) as jw:
        jw.decode.return_value = PATIENT
        res = TestClient(app).post("/bookings/", headers=AUTH, json={
            "doctor_id": "doc-1", "channel": "online_consult",
            "scheduled_start": "2026-10-01T09:00:00+00:00", "price_confirmed": 500.0})
    assert res.status_code == 201
    assert "address_id" not in bookings.insert.call_args[0][0]
