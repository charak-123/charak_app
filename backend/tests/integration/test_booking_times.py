"""
Booking times against real SQL.

The mocked suite cannot see how Postgres hands a timestamptz back, and that is
where the slot grid went wrong: PostgREST returns UTC, the grid read the hour
straight off the string, and a booked 09:00 IST slot stayed on offer.
"""
from datetime import datetime, timedelta

from app.services.availability import IST

from .conftest import AUTH

DAY = (datetime.now(IST) + timedelta(days=3)).date()


def _ist(hh, mm):
    return datetime.combine(DAY, datetime.min.time(), IST).replace(hour=hh, minute=mm)


def _book(client, doctor_id, start):
    return client.post(
        "/bookings/",
        json={"doctor_id": doctor_id, "channel": "online_consult",
              "scheduled_start": start.isoformat()},
        headers=AUTH,
    )


def _open_starts(client, doctor_id):
    slots = client.get(f"/doctors/{doctor_id}/slots?from_date={DAY}&days=1").json()
    return {s["start"] for s in slots.get(str(DAY), [])}


def test_a_booked_ist_slot_leaves_the_grid(seed, client_for):
    s = seed()
    patient = client_for(s["patient"]["id"])
    assert "09:00" in _open_starts(patient, s["doctor"]["id"])

    assert _book(patient, s["doctor"]["id"], _ist(9, 0)).status_code == 201

    starts = _open_starts(patient, s["doctor"]["id"])
    assert "09:00" not in starts
    # And the UTC reading of the same instant (03:30) was not removed instead.
    assert "03:30" in starts


def test_a_time_off_the_grid_is_refused(seed, client_for):
    s = seed()
    res = _book(client_for(s["patient"]["id"]), s["doctor"]["id"], _ist(9, 7))
    assert res.status_code == 409


def test_a_past_time_is_refused(seed, client_for):
    s = seed()
    res = _book(client_for(s["patient"]["id"]), s["doctor"]["id"],
                datetime.now(IST) - timedelta(hours=2))
    assert res.status_code == 409


def test_a_cancel_against_a_stale_status_changes_nothing(seed, client_for, db):
    """The conditional write, run by real PostgREST: no row matches, none changes."""
    s = seed()
    patient = client_for(s["patient"]["id"])
    booking = _book(patient, s["doctor"]["id"], _ist(10, 0)).json()

    # Someone else moved it on since the caller read it.
    db.table("bookings").update({"status": "declined"}).eq("id", booking["id"]).execute()
    rows = (
        db.table("bookings").update({"status": "cancelled"})
        .eq("id", booking["id"]).eq("status", "requested").execute().data
    )

    assert rows == []
    status = db.table("bookings").select("status").eq("id", booking["id"]).execute().data
    assert status[0]["status"] == "declined"
