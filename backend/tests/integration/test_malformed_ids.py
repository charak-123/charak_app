"""
Malformed path ids must not become 500s.

FastAPI declares path ids as ``str``, so anything at all reaches the query layer
and lands in a comparison against a uuid column. Postgres raises 22P02, and before
db_error_handler existed nothing caught it — every ``{id}`` route in the app
answered a junk id with an unhandled 500.

This can only be tested against real SQL. The mocked suite's MagicMock accepts
"not-a-uuid" exactly as readily as a real id, which is why the whole class of bug
sat undetected across 78 routes.
"""
import pytest

from .conftest import AUTH

JUNK = ["not-a-uuid", "123", "patient", "doctor", "%20", "null"]

PATIENT_ROUTES = [
    "/bookings/{id}",
    "/bookings/{id}/intake",
    "/bookings/{id}/clarification-calls",
    "/bookings/{id}/procedure-bill",
    "/payments/{id}",
    "/doctors/{id}",
    "/doctors/{id}/slots?date=2026-11-01",
    "/doctors/{id}/service-area?lat=19.07&lng=72.87",
]


@pytest.mark.parametrize("route", PATIENT_ROUTES)
def test_a_junk_id_is_a_client_error_not_a_crash(route, seed, client_for):
    s = seed()
    client = client_for(s["patient"]["id"])
    res = client.get(route.format(id="not-a-uuid"), headers=AUTH)

    assert res.status_code < 500, (
        f"{route} returned {res.status_code} for a malformed id: {res.text[:200]}"
    )
    assert 400 <= res.status_code < 500


@pytest.mark.parametrize("junk", JUNK)
def test_every_shape_of_junk_id_is_handled(junk, seed, client_for):
    """Route collisions matter too: /bookings/patient once hit {booking_id}."""
    s = seed()
    res = client_for(s["patient"]["id"]).get(f"/bookings/{junk}", headers=AUTH)
    assert res.status_code < 500, f"id={junk!r} → {res.status_code}: {res.text[:160]}"


def test_the_error_body_does_not_leak_schema_detail(seed, client_for):
    """
    The driver's message names the column type and the offending value. That is
    log material, not something to hand a caller.
    """
    s = seed()
    res = client_for(s["patient"]["id"]).get("/bookings/not-a-uuid", headers=AUTH)
    body = res.text.lower()

    assert res.status_code == 404
    for leak in ("uuid", "syntax", "22p02", "postgres", "column"):
        assert leak not in body, f"error body leaks {leak!r}: {res.text[:200]}"


def test_a_well_formed_but_absent_id_is_still_a_clean_404(seed, client_for):
    """The handler must not mask the ordinary not-found path."""
    s = seed()
    res = client_for(s["patient"]["id"]).get(
        "/bookings/99999999-9999-4999-8999-999999999999", headers=AUTH
    )
    assert res.status_code == 404
