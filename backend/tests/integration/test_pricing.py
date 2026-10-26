"""
Migration 0026 against real Postgres: the pricing matrix, the price snapshot,
follow-up eligibility, and the constraint that refuses overlapping bookings
of different lengths (spec §8.5, plan Phase 4).
"""
import uuid
from datetime import date, datetime, timedelta, timezone

import pytest

from .conftest import AUTH

IST = timezone(timedelta(hours=5, minutes=30))


def _id() -> str:
    return str(uuid.uuid4())


def _tomorrow(h: int, m: int = 0) -> datetime:
    d = datetime.now(IST).date() + timedelta(days=1)
    return datetime(d.year, d.month, d.day, h, m, tzinfo=IST)


MATRIX = {
    "rules": [
        {"channel": "online_consult", "visit_category": "initial", "duration_min": 15, "price_paise": 60000},
        {"channel": "online_consult", "visit_category": "initial", "duration_min": 30, "price_paise": 100000},
        {"channel": "online_consult", "visit_category": "follow_up", "duration_min": 10, "price_paise": 30000},
    ],
    "follow_up_validity_days": 7,
}


def _set(client, matrix=MATRIX):
    res = client.put("/doctors/me/prices", json=matrix, headers=AUTH)
    assert res.status_code == 200, res.text
    return res.json()


def _options(client, doctor_id):
    return client.get(f"/doctors/{doctor_id}/prices", headers=AUTH).json()["channels"]["online_consult"]


def _book(client, doctor_id, start, **extra):
    return client.post("/bookings/", headers=AUTH, json={
        "doctor_id": doctor_id, "channel": "online_consult", "scheduled_start": start.isoformat(), **extra})


def _consulted(db, s, *, days_ago=1):
    """A finished consultation of this patient with this doctor."""
    at = datetime.now(timezone.utc) - timedelta(days=days_ago)
    return db.table("bookings").insert({
        "id": _id(), "patient_id": s["patient"]["id"], "doctor_id": s["doctor"]["id"],
        "channel": "online_consult", "scheduled_start": at.isoformat(), "status": "consulted",
        "price_confirmed": 600, "prescription_sent_at": at.isoformat(),
    }).execute().data[0]


# ── The doctor's matrix ──────────────────────────────────────────────────────

def test_first_and_follow_up_prices_are_set_independently(seed, client_for, db):
    s = seed()
    doctor = client_for(s["doctor"]["id"], "doctor")
    saved = _set(doctor)
    assert {(r["visit_category"], r["duration_min"], r["price_paise"]) for r in saved["rules"]} == {
        ("initial", 15, 60000), ("initial", 30, 100000), ("follow_up", 10, 30000)}
    assert saved["follow_up_validity_days"] == 7
    # The patient's list shows first-visit prices only.
    opts = _options(client_for(s["patient"]["id"]), s["doctor"]["id"])
    assert [(o["duration_min"], o["price_paise"]) for o in opts] == [(15, 60000), (30, 100000)]
    # Older app builds and the directory read the shortest first-visit price.
    legacy = db.table("doctor_pricing").select("price, base_duration_min") \
        .eq("doctor_id", s["doctor"]["id"]).eq("channel", "online_consult").execute().data[0]
    assert (float(legacy["price"]), legacy["base_duration_min"]) == (600.0, 15)


@pytest.mark.parametrize("bad,why", [
    ({"rules": [{"channel": "online_consult", "visit_category": "initial", "duration_min": 25,
                 "price_paise": 50000}]}, "Lengths"),
    ({"rules": [{"channel": "online_consult", "visit_category": "initial", "duration_min": 15,
                 "price_paise": 0}]}, "can't be free"),
    ({"rules": [{"channel": "online_consult", "visit_category": "initial", "duration_min": 15,
                 "price_paise": 50050}]}, "whole rupees"),
    ({"rules": MATRIX["rules"], "follow_up_validity_days": None}, "how many days"),
    ({"rules": [MATRIX["rules"][0], MATRIX["rules"][0]]}, "twice"),
    ({"rules": [MATRIX["rules"][2]], "follow_up_validity_days": 7}, "at least one price"),
])
def test_an_invalid_price_list_is_refused_whole(seed, client_for, db, bad, why):
    s = seed()
    doctor = client_for(s["doctor"]["id"], "doctor")
    _set(doctor)
    res = doctor.put("/doctors/me/prices", json=bad, headers=AUTH)
    assert res.status_code == 400 and why in res.json()["error"]
    assert len(doctor.get("/doctors/me/prices", headers=AUTH).json()["rules"]) == 3


def test_a_price_change_is_history_and_rules_cant_be_edited(seed, client_for, db):
    s = seed()
    doctor = client_for(s["doctor"]["id"], "doctor")
    _set(doctor)
    changed = {**MATRIX, "rules": [{**MATRIX["rules"][0], "price_paise": 70000}, *MATRIX["rules"][1:]]}
    _set(doctor, changed)
    _set(doctor, changed)                                   # unchanged: no new row

    history = doctor.get("/doctors/me/prices/history", headers=AUTH).json()
    fifteen = [r for r in history if r["visit_category"] == "initial" and r["duration_min"] == 15]
    assert [(r["price_paise"], r["effective_until"] is None) for r in fifteen] == [(70000, True), (60000, False)]
    ops = client_for(_id(), "ops").get(f"/admin/pricing/{s['doctor']['id']}/history", headers=AUTH).json()
    assert len(ops["rules"]) == len(history)

    with pytest.raises(Exception):
        db.table("doctor_price_rules").update({"price_paise": 1}).eq("id", fifteen[0]["id"]).execute()
    with pytest.raises(Exception):
        db.table("doctor_price_rules").delete().eq("id", fifteen[1]["id"]).execute()


def test_an_old_doctor_app_still_saves_a_price(seed, client_for, db):
    s = seed()
    doctor = client_for(s["doctor"]["id"], "doctor")
    _set(doctor)
    res = doctor.put("/doctors/me/pricing", headers=AUTH, json=[
        {"channel": "online_consult", "price": 800, "base_duration_min": 20}])
    assert res.status_code == 200, res.text
    rules = doctor.get("/doctors/me/prices", headers=AUTH).json()["rules"]
    assert {(r["visit_category"], r["duration_min"], r["price_paise"]) for r in rules} == {
        ("initial", 20, 80000), ("follow_up", 10, 30000)}


# ── Booking at a price ───────────────────────────────────────────────────────

def test_the_booking_keeps_its_price_when_the_doctor_changes_it(seed, client_for, db):
    s = seed()
    doctor = client_for(s["doctor"]["id"], "doctor")
    _set(doctor)
    patient = client_for(s["patient"]["id"])
    thirty = next(o for o in _options(patient, s["doctor"]["id"]) if o["duration_min"] == 30)

    res = _book(patient, s["doctor"]["id"], _tomorrow(10), price_rule_id=thirty["id"],
                expected_price_paise=100000)
    assert res.status_code == 201, res.text
    b = res.json()
    assert (b["price_paise"], b["duration_min"], b["price_rule_id"], float(b["price_confirmed"])) == \
        (100000, 30, thirty["id"], 1000.0)
    assert datetime.fromisoformat(b["scheduled_end"]) - datetime.fromisoformat(b["scheduled_start"]) \
        == timedelta(minutes=30)

    _set(doctor, {**MATRIX, "rules": [MATRIX["rules"][0], {**MATRIX["rules"][1], "price_paise": 150000}]})
    kept = db.table("bookings").select("price_paise, price_confirmed").eq("id", b["id"]).execute().data[0]
    assert (kept["price_paise"], float(kept["price_confirmed"])) == (100000, 1000.0)
    with pytest.raises(Exception):
        db.table("bookings").update({"price_paise": 1}).eq("id", b["id"]).execute()


def test_a_price_the_patient_wasnt_shown_is_never_charged(seed, client_for, db):
    s = seed()
    doctor = client_for(s["doctor"]["id"], "doctor")
    _set(doctor)
    patient = client_for(s["patient"]["id"])
    fifteen = next(o for o in _options(patient, s["doctor"]["id"]) if o["duration_min"] == 15)

    # The doctor raised it after the patient looked.
    _set(doctor, {**MATRIX, "rules": [{**MATRIX["rules"][0], "price_paise": 90000}, *MATRIX["rules"][1:]]})
    stale = _book(patient, s["doctor"]["id"], _tomorrow(11), price_rule_id=fifteen["id"],
                  expected_price_paise=60000)
    assert stale.status_code == 409 and stale.json()["code"] == "price_changed"

    fresh = next(o for o in _options(patient, s["doctor"]["id"]) if o["duration_min"] == 15)
    wrong = _book(patient, s["doctor"]["id"], _tomorrow(11), price_rule_id=fresh["id"],
                  expected_price_paise=100)
    assert wrong.status_code == 409 and wrong.json()["price_paise"] == 90000
    # A price in the body is ignored; the server's is charged.
    ok = _book(patient, s["doctor"]["id"], _tomorrow(11), price_rule_id=fresh["id"],
               price_confirmed=1, price_paise=100)
    assert ok.status_code == 201 and ok.json()["price_paise"] == 90000
    assert db.table("bookings").select("id").eq("doctor_id", s["doctor"]["id"]).execute().data.__len__() == 1


def test_another_doctors_or_a_follow_up_price_cant_be_used_for_a_first_visit(seed, client_for, db):
    s, other = seed(), seed()
    _set(client_for(s["doctor"]["id"], "doctor"))
    _set(client_for(other["doctor"]["id"], "doctor"))
    patient = client_for(s["patient"]["id"])
    theirs = _options(patient, other["doctor"]["id"])[0]
    assert _book(patient, s["doctor"]["id"], _tomorrow(12), price_rule_id=theirs["id"]).status_code == 409
    follow = db.table("doctor_price_rules").select("id").eq("doctor_id", s["doctor"]["id"]) \
        .eq("visit_category", "follow_up").execute().data[0]
    assert _book(patient, s["doctor"]["id"], _tomorrow(12), price_rule_id=follow["id"]).status_code == 409
    assert _book(patient, s["doctor"]["id"], _tomorrow(12), duration_min=45).status_code == 409


def test_an_old_patient_app_books_at_the_shortest_first_visit_price(seed, client_for, db):
    s = seed()
    _set(client_for(s["doctor"]["id"], "doctor"))
    patient = client_for(s["patient"]["id"])
    grid = patient.get(f"/doctors/{s['doctor']['id']}/slots?days=2", headers=AUTH).json()
    day = str(_tomorrow(9).date())
    assert "09:30" in [x["start"] for x in grid[day]] and "09:15" not in [x["start"] for x in grid[day]]
    res = _book(patient, s["doctor"]["id"], _tomorrow(9, 30))
    assert res.status_code == 201, res.text
    assert (res.json()["price_paise"], res.json()["duration_min"]) == (60000, 15)


# ── Overlaps ─────────────────────────────────────────────────────────────────

def test_the_database_refuses_overlapping_bookings_of_different_lengths(seed, db):
    s = seed()
    base = dict(patient_id=s["patient"]["id"], doctor_id=s["doctor"]["id"],
                channel="online_consult", status="paid", price_confirmed=500)
    db.table("bookings").insert({**base, "id": _id(), "scheduled_start": _tomorrow(10).isoformat(),
                                 "duration_min": 30,
                                 "scheduled_end": _tomorrow(10, 30).isoformat()}).execute()
    with pytest.raises(Exception) as exc:
        db.table("bookings").insert({**base, "id": _id(), "scheduled_start": _tomorrow(10, 15).isoformat(),
                                     "duration_min": 10,
                                     "scheduled_end": _tomorrow(10, 25).isoformat()}).execute()
    assert "23P01" in str(exc.value) or "ex_bookings_doctor_overlap" in str(exc.value)
    # Back to back is fine, and so is a cancelled one underneath.
    db.table("bookings").insert({**base, "id": _id(), "scheduled_start": _tomorrow(10, 30).isoformat(),
                                 "duration_min": 15}).execute()
    db.table("bookings").insert({**base, "id": _id(), "status": "cancelled",
                                 "scheduled_start": _tomorrow(10, 15).isoformat(), "duration_min": 10}).execute()


def test_slots_follow_the_length_and_respect_longer_bookings(seed, client_for, db):
    s = seed()
    _set(client_for(s["doctor"]["id"], "doctor"))
    patient = client_for(s["patient"]["id"])
    thirty = next(o for o in _options(patient, s["doctor"]["id"]) if o["duration_min"] == 30)
    assert _book(patient, s["doctor"]["id"], _tomorrow(10), price_rule_id=thirty["id"]).status_code == 201

    day = str(_tomorrow(10).date())
    starts = [x["start"] for x in patient.get(
        f"/doctors/{s['doctor']['id']}/slots?days=2&duration_min=15", headers=AUTH).json()[day]]
    assert "09:45" in starts and "10:00" not in starts and "10:15" not in starts and "10:30" in starts
    # A 15-minute visit at 10:15 overlaps the 30-minute one; refused.
    other = client_for(s["other_patient"]["id"])
    fifteen = next(o for o in _options(other, s["doctor"]["id"]) if o["duration_min"] == 15)
    assert _book(other, s["doctor"]["id"], _tomorrow(10, 15), price_rule_id=fifteen["id"]).status_code == 409
    assert _book(other, s["doctor"]["id"], _tomorrow(10, 30), price_rule_id=fifteen["id"]).status_code == 201


# ── Follow-ups ───────────────────────────────────────────────────────────────

def test_a_follow_up_is_priced_as_one_only_for_a_real_prior_consultation(seed, client_for, db):
    s = seed()
    _set(client_for(s["doctor"]["id"], "doctor"))
    original = _consulted(db, s)
    patient = client_for(s["patient"]["id"])

    opts = patient.get(f"/bookings/{original['id']}/follow-up-options", headers=AUTH)
    assert opts.status_code == 200, opts.text
    follow = opts.json()["channels"]["online_consult"][0]
    assert (follow["duration_min"], follow["price_paise"]) == (10, 30000)

    # Not someone else's consultation.
    other = client_for(s["other_patient"]["id"])
    assert other.get(f"/bookings/{original['id']}/follow-up-options", headers=AUTH).status_code == 404
    assert _book(other, s["doctor"]["id"], _tomorrow(9), price_rule_id=follow["id"],
                 follow_up_of=original["id"]).status_code == 404

    # Not a follow-up price without naming the consultation.
    assert _book(patient, s["doctor"]["id"], _tomorrow(9), price_rule_id=follow["id"]).status_code == 409

    res = _book(patient, s["doctor"]["id"], _tomorrow(9), price_rule_id=follow["id"],
                follow_up_of=original["id"], expected_price_paise=30000)
    assert res.status_code == 201, res.text
    assert (res.json()["visit_category"], res.json()["follow_up_of"], res.json()["price_paise"]) == \
        ("follow_up", original["id"], 30000)
    # One follow-up per consultation.
    again = _book(patient, s["doctor"]["id"], _tomorrow(11), price_rule_id=follow["id"],
                  follow_up_of=original["id"])
    assert again.status_code == 409


def test_follow_up_eligibility_has_a_window(seed, client_for, db):
    s = seed()
    doctor = client_for(s["doctor"]["id"], "doctor")
    _set(doctor)
    patient = client_for(s["patient"]["id"])

    old = _consulted(db, s, days_ago=10)                    # past the 7-day window
    assert patient.get(f"/bookings/{old['id']}/follow-up-options", headers=AUTH).status_code == 200
    follow = db.table("doctor_price_rules").select("id").eq("doctor_id", s["doctor"]["id"]) \
        .eq("visit_category", "follow_up").execute().data[0]
    late = _book(patient, s["doctor"]["id"], _tomorrow(9), price_rule_id=follow["id"], follow_up_of=old["id"])
    assert late.status_code == 409 and "follow-up price applies until" in late.json()["error"]

    # The doctor recommended a later date: the window reaches it.
    db.table("prescriptions").insert({
        "id": (rx := _id()), "booking_id": old["id"], "doctor_id": s["doctor"]["id"],
        "patient_id": s["patient"]["id"]}).execute()
    db.table("follow_up_recommendations").insert({
        "booking_id": old["id"], "prescription_id": rx, "doctor_id": s["doctor"]["id"],
        "patient_id": s["patient"]["id"], "recommended_date": str(date.today() + timedelta(days=1)),
        "channel": "either"}).execute()
    ok = _book(patient, s["doctor"]["id"], _tomorrow(9), price_rule_id=follow["id"], follow_up_of=old["id"])
    assert ok.status_code == 201, ok.text

    # Before the consultation is over, there's nothing to follow up.
    paid = db.table("bookings").insert({
        "id": _id(), "patient_id": s["patient"]["id"], "doctor_id": s["doctor"]["id"],
        "channel": "online_consult", "scheduled_start": _tomorrow(15).isoformat(), "status": "paid",
        "price_confirmed": 600}).execute().data[0]
    assert patient.get(f"/bookings/{paid['id']}/follow-up-options", headers=AUTH).status_code == 409


def test_a_free_follow_up_is_confirmed_when_accepted(seed, client_for, db):
    s = seed()
    doctor = client_for(s["doctor"]["id"], "doctor")
    _set(doctor, {**MATRIX, "rules": [*MATRIX["rules"][:2], {**MATRIX["rules"][2], "price_paise": 0}]})
    original = _consulted(db, s)
    patient = client_for(s["patient"]["id"])
    follow = patient.get(f"/bookings/{original['id']}/follow-up-options", headers=AUTH) \
        .json()["channels"]["online_consult"][0]
    assert follow["price_paise"] == 0

    start = datetime.now(IST) + timedelta(days=2)
    start = start.replace(hour=9, minute=0, second=0, microsecond=0)
    b = _book(patient, s["doctor"]["id"], start, price_rule_id=follow["id"],
              follow_up_of=original["id"]).json()
    res = doctor.patch(f"/bookings/{b['id']}/accept", headers=AUTH)
    assert res.status_code == 200, res.text
    row = db.table("bookings").select("status, price_paise").eq("id", b["id"]).execute().data[0]
    assert row == {"status": "paid", "price_paise": 0}
    assert db.table("payments").select("id").eq("booking_id", b["id"]).execute().data == []
    assert db.table("notifications").select("event").eq("booking_id", b["id"]) \
        .eq("event", "booking.confirmed").execute().data
