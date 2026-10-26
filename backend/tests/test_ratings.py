"""Reviewing a visit (routers/ratings.py, services/reviews.py). Window, edit
and aggregate rules run against real Postgres in tests/integration/test_reviews.py."""
from datetime import datetime, timedelta, timezone
from unittest.mock import MagicMock, patch

from fastapi.testclient import TestClient

from app.main import app
from tests.conftest import make_chain, make_supabase

PATIENT = {"sub": "patient-1", "role": "patient"}
DOCTOR = {"sub": "doctor-1", "role": "doctor"}
BOOKING_ID = "booking-abc"
NOW = datetime.now(timezone.utc)

COMPLETED = {"id": BOOKING_ID, "patient_id": "patient-1", "doctor_id": "doctor-1",
             "status": "completed", "completed_at": (NOW - timedelta(days=1)).isoformat(),
             "scheduled_start": (NOW - timedelta(days=1)).isoformat()}
REVIEW = {"id": "rev-1", "booking_id": BOOKING_ID, "doctor_id": "doctor-1", "patient_id": "patient-1",
          "overall": 5, "professionalism": None, "communication": 4, "punctuality": None,
          "comment": "Great!", "status": "published", "created_at": NOW.isoformat(),
          "edited_at": None, "editable_until": (NOW + timedelta(hours=48)).isoformat()}


def _post(payload, tables, path, body):
    with patch("app.routers.ratings.supabase", make_supabase(tables)), patch("app.deps.jwt") as jw:
        jw.decode.return_value = payload
        return TestClient(app).post(path, json=body, headers={"Authorization": "Bearer t"})


def _get(payload, tables, path):
    with patch("app.routers.ratings.supabase", make_supabase(tables)), patch("app.deps.jwt") as jw:
        jw.decode.return_value = payload
        return TestClient(app).get(path, headers={"Authorization": "Bearer t"})


def test_a_review_has_an_overall_and_optional_sub_ratings():
    reviews = make_chain(list_data=[REVIEW])
    res = _post(PATIENT, {"bookings": make_chain(data=COMPLETED), "reviews": reviews},
                f"/bookings/{BOOKING_ID}/review", {"overall": 5, "communication": 4, "comment": " Great! "})
    assert res.status_code == 201, res.text
    inserted = reviews.insert.call_args[0][0]
    assert (inserted["overall"], inserted["communication"], inserted["professionalism"],
            inserted["comment"]) == (5, 4, None, "Great!")
    assert res.json()["stars"] == 5                                # older apps read `stars`


def test_the_old_rate_endpoint_writes_a_review():
    reviews = make_chain(list_data=[REVIEW])
    res = _post(PATIENT, {"bookings": make_chain(data=COMPLETED), "reviews": reviews},
                f"/bookings/{BOOKING_ID}/rate", {"stars": 5, "comment": "Great!"})
    assert res.status_code == 201
    assert reviews.insert.call_args[0][0]["overall"] == 5


def test_ratings_out_of_range_are_refused():
    for body in ({"overall": 6}, {"overall": 4, "punctuality": 0}):
        res = _post(PATIENT, {"bookings": make_chain(data=COMPLETED)}, f"/bookings/{BOOKING_ID}/review", body)
        assert res.status_code in (400, 422)
    assert _post(PATIENT, {}, f"/bookings/{BOOKING_ID}/rate", {"stars": 6}).status_code == 400


def test_only_a_completed_visit_of_your_own_within_14_days():
    paid = {**COMPLETED, "status": "paid"}
    assert _post(PATIENT, {"bookings": make_chain(data=paid)}, f"/bookings/{BOOKING_ID}/review",
                 {"overall": 4}).status_code == 409
    other = {**COMPLETED, "patient_id": "someone-else"}
    assert _post(PATIENT, {"bookings": make_chain(data=other)}, f"/bookings/{BOOKING_ID}/review",
                 {"overall": 4}).status_code == 403
    old = {**COMPLETED, "completed_at": (NOW - timedelta(days=15)).isoformat()}
    res = _post(PATIENT, {"bookings": make_chain(data=old)}, f"/bookings/{BOOKING_ID}/review", {"overall": 4})
    assert res.status_code == 409 and "14 days" in res.json()["error"]
    # A doctor can't post one.
    assert _post(DOCTOR, {"bookings": make_chain(data=COMPLETED)}, f"/bookings/{BOOKING_ID}/review",
                 {"overall": 5}).status_code == 403


def test_a_second_review_is_refused():
    reviews = make_chain()
    reviews.execute.side_effect = Exception('duplicate key value violates unique constraint (23505)')
    res = _post(PATIENT, {"bookings": make_chain(data=COMPLETED), "reviews": reviews},
                f"/bookings/{BOOKING_ID}/review", {"overall": 4})
    assert res.status_code == 409


def test_the_doctor_reads_the_review_without_its_edit_window():
    res = _get(DOCTOR, {"bookings": make_chain(data=COMPLETED), "reviews": make_chain(data=REVIEW)},
               f"/bookings/{BOOKING_ID}/review")
    body = res.json()
    assert body["review"]["overall"] == 5 and "editable_until" not in body["review"]
    assert body["can_review"] is False


def _none():
    """What maybe_single() gives for no row: no response at all."""
    c = make_chain()
    c.execute.return_value = None
    return c


def test_the_patient_is_told_when_they_can_still_review():
    res = _get(PATIENT, {"bookings": make_chain(data=COMPLETED), "reviews": _none()},
               f"/bookings/{BOOKING_ID}/review")
    assert res.json()["can_review"] is True and res.json()["review_until"]


def test_a_stranger_cant_read_it():
    other = {**COMPLETED, "patient_id": "x", "doctor_id": "y"}
    assert _get(PATIENT, {"bookings": make_chain(data=other)}, f"/bookings/{BOOKING_ID}/review").status_code == 403
