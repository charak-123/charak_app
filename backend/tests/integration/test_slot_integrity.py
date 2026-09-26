"""
Slot integrity against real SQL.

The mocked suite can assert that the handler turns a 23505 into a 409, but it
cannot assert that Postgres raises 23505 in the first place — the guarantee lives
in uq_booking_doctor_slot_active (migration 0010), and only a real database can
say whether that index exists and covers the right rows.
"""
from datetime import datetime, timedelta, timezone

from .conftest import AUTH

SLOT = (datetime.now(timezone.utc) + timedelta(days=3)).replace(
    minute=0, second=0, microsecond=0
).isoformat()


def _book(client, doctor_id, slot=SLOT, channel="online_consult"):
    return client.post(
        "/bookings/",
        json={"doctor_id": doctor_id, "channel": channel, "scheduled_start": slot},
        headers=AUTH,
    )


def test_two_patients_cannot_hold_the_same_slot(seed, client_for):
    s = seed()
    first = _book(client_for(s["patient"]["id"]), s["doctor"]["id"])
    assert first.status_code == 201, first.text

    second = _book(client_for(s["other_patient"]["id"]), s["doctor"]["id"])
    assert second.status_code == 409
    assert second.json()["error"] == "Slot already booked"


def test_the_constraint_and_not_the_check_is_what_refuses(seed, client_for, db):
    """
    Bypass the handler's pre-insert check by writing straight to the table, the way
    a concurrent request effectively does, and confirm the database still refuses.
    """
    s = seed()
    assert _book(client_for(s["patient"]["id"]), s["doctor"]["id"]).status_code == 201

    try:
        db.table("bookings").insert({
            "patient_id": s["other_patient"]["id"],
            "doctor_id": s["doctor"]["id"],
            "channel": "online_consult",
            "scheduled_start": SLOT,
            "status": "requested",
        }).execute()
        raised = None
    except Exception as exc:                                   # noqa: BLE001
        raised = exc

    assert raised is not None, "the unique index did not refuse a duplicate insert"
    assert "uq_booking_doctor_slot_active" in str(raised)


def test_a_cancelled_booking_frees_its_slot(seed, client_for, db):
    """The index is partial; a released slot must be bookable again."""
    s = seed()
    first = _book(client_for(s["patient"]["id"]), s["doctor"]["id"])
    booking_id = first.json()["id"]

    db.table("bookings").update({"status": "cancelled"}).eq("id", booking_id).execute()

    again = _book(client_for(s["other_patient"]["id"]), s["doctor"]["id"])
    assert again.status_code == 201, again.text


def test_the_lifecycle_does_not_collide_with_itself(seed, client_for, db):
    """requested -> accepted -> paid stays inside the index without violating it."""
    s = seed()
    booking_id = _book(client_for(s["patient"]["id"]), s["doctor"]["id"]).json()["id"]

    for status in ("accepted", "paid"):
        db.table("bookings").update({"status": status}).eq("id", booking_id).execute()

    row = db.table("bookings").select("status").eq("id", booking_id).execute().data[0]
    assert row["status"] == "paid"


def test_different_slots_for_the_same_doctor_are_independent(seed, client_for):
    s = seed()
    later = (datetime.fromisoformat(SLOT) + timedelta(hours=1)).isoformat()

    assert _book(client_for(s["patient"]["id"]), s["doctor"]["id"]).status_code == 201
    assert _book(client_for(s["other_patient"]["id"]), s["doctor"]["id"],
                 slot=later).status_code == 201
