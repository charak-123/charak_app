"""
Regression tests: a lookup that finds nothing must return 404, not 500.

PostgREST's ``single()`` raises PGRST116 on zero rows rather than returning
``data=None``. Every router used ``.single().execute()`` followed by
``if not result.data: raise AppError(..., 404)`` — so on a missing row the client
raised first, the check was unreachable, and the caller got an unhandled 500.
``db.fetch_one`` is the fix; these tests pin the behaviour down per endpoint.
"""
from unittest.mock import patch

from fastapi.testclient import TestClient

from app.main import app
from tests.conftest import make_chain, make_supabase

PATIENT = {"sub": "pat-1", "role": "patient"}
DOCTOR  = {"sub": "doc-1", "role": "doctor"}
AUTH    = {"Authorization": "Bearer t"}
JWT     = "app.deps.jwt"

# A chain whose maybe_single() yields no row, which is what fetch_one sees.
EMPTY = lambda: make_chain(data=None)


def _client(module, payload):
    db = make_supabase({
        "bookings": EMPTY(), "doctors": EMPTY(), "users": EMPTY(),
        "procedure_bills": EMPTY(), "clarification_calls": EMPTY(),
        "payments": EMPTY(), "notifications": EMPTY(),
    })
    with patch(f"app.routers.{module}.supabase", db), patch(JWT) as jw:
        jw.decode.return_value = payload
        yield TestClient(app)


def test_fetch_one_returns_none_when_the_response_is_none():
    """The client hands back None for the whole response, not a response with
    data=None — which is why the guard lives in fetch_one rather than at each
    call site."""
    from app.db import fetch_one

    class _Q:
        def maybe_single(self): return self
        def execute(self): return None

    assert fetch_one(_Q()) is None


def test_missing_booking_is_404_on_read():
    for c in _client("bookings", PATIENT):
        assert c.get("/bookings/nope", headers=AUTH).status_code == 404


def test_missing_booking_is_404_on_cancel():
    for c in _client("bookings", PATIENT):
        assert c.patch("/bookings/nope/cancel", headers=AUTH).status_code == 404


def test_missing_booking_is_404_on_accept():
    for c in _client("bookings", DOCTOR):
        assert c.patch("/bookings/nope/accept", headers=AUTH).status_code == 404


def test_missing_booking_is_404_on_complete():
    for c in _client("bookings", DOCTOR):
        assert c.patch("/bookings/nope/complete", headers=AUTH).status_code == 404


def test_missing_booking_is_404_on_no_show():
    for c in _client("bookings", DOCTOR):
        assert c.patch("/bookings/nope/no-show", headers=AUTH).status_code == 404


def test_booking_against_a_missing_doctor_is_404():
    for c in _client("bookings", PATIENT):
        res = c.post("/bookings/", headers=AUTH, json={
            "doctor_id": "nope", "channel": "online_consult",
            "scheduled_start": "2026-10-01T09:00:00+00:00",
        })
        assert res.status_code == 404


def test_missing_doctor_profile_is_404():
    """This is the exact path that returned 500 in the live smoke test."""
    for c in _client("doctors", PATIENT):
        assert c.get("/doctors/nope").status_code == 404


def test_missing_own_doctor_profile_is_404():
    for c in _client("doctors", DOCTOR):
        assert c.get("/doctors/me", headers=AUTH).status_code == 404


def test_missing_booking_is_404_on_payment_order():
    for c in _client("payments", PATIENT):
        assert c.post("/payments/nope/order", headers=AUTH,
                      json={"type": "consult_fee"}).status_code == 404


def test_missing_booking_is_404_on_payment_read():
    for c in _client("payments", PATIENT):
        assert c.get("/payments/nope", headers=AUTH).status_code == 404


def test_missing_booking_is_404_on_payment_failure_report():
    for c in _client("payments", PATIENT):
        assert c.post("/payments/nope/failed", headers=AUTH).status_code == 404


def test_missing_booking_is_404_on_procedure_bill_create():
    for c in _client("procedure_bills", DOCTOR):
        res = c.post("/bookings/nope/procedure-bill", headers=AUTH,
                     json={"items": [{"name": "X", "price": 100}]})
        assert res.status_code == 404


def test_missing_booking_is_404_on_procedure_bill_read():
    for c in _client("procedure_bills", PATIENT):
        assert c.get("/bookings/nope/procedure-bill", headers=AUTH).status_code == 404


def test_missing_booking_is_404_on_rating():
    for c in _client("ratings", PATIENT):
        assert c.post("/bookings/nope/rate", headers=AUTH,
                      json={"stars": 5}).status_code == 404


def test_missing_booking_is_404_on_rating_read():
    for c in _client("ratings", PATIENT):
        assert c.get("/bookings/nope/rate", headers=AUTH).status_code == 404


def test_missing_booking_is_404_on_complaint():
    for c in _client("complaints", PATIENT):
        assert c.post("/bookings/nope/complaint", headers=AUTH,
                      json={"description": "x"}).status_code == 404


def test_missing_booking_is_404_on_complaint_read():
    for c in _client("complaints", PATIENT):
        assert c.get("/bookings/nope/complaint", headers=AUTH).status_code == 404


def test_missing_booking_is_404_on_call_initiate():
    for c in _client("calls", DOCTOR):
        assert c.post("/bookings/nope/clarification-call", headers=AUTH).status_code == 404


def test_missing_booking_is_404_on_call_list():
    for c in _client("calls", PATIENT):
        assert c.get("/bookings/nope/clarification-calls", headers=AUTH).status_code == 404


def test_missing_booking_is_404_on_intake():
    for c in _client("intake", PATIENT):
        assert c.get("/bookings/nope/intake", headers=AUTH).status_code == 404
