"""
Weekly hours per channel (migration 0035) and when a doctor is listed
(services/listing.py).

Before: saving home-visit hours replaced the online ones, the hours editors
opened on a blank week, and a doctor verified before setting prices or hours
was listed in the directory with nothing to book.
"""
from unittest.mock import patch

from fastapi.testclient import TestClient

from app.main import app
from app.services import listing
from tests.fakedb import FakeSupabase

client = TestClient(app)
DOCTOR = {"sub": "doc-1", "role": "doctor"}
AUTH = {"Authorization": "Bearer t"}


def _db(rows):
    return FakeSupabase({"doctor_schedules": [dict(r) for r in rows]})


def _put(db, path, blocks):
    with patch("app.routers.schedules.supabase", db), patch("app.deps.jwt") as jw:
        jw.decode.return_value = DOCTOR
        return client.put(path, json=blocks, headers=AUTH)


def _get(db, query=""):
    with patch("app.routers.schedules.supabase", db), patch("app.deps.jwt") as jw:
        jw.decode.return_value = DOCTOR
        return client.get(f"/schedules/me{query}", headers=AUTH)


ONLINE = {"doctor_id": "doc-1", "day_of_week": 0, "start_time": "09:00", "end_time": "12:00",
          "channel": "online_consult"}
HOME = {"doctor_id": "doc-1", "day_of_week": 2, "start_time": "16:00", "end_time": "19:00",
        "channel": "home_visit"}


def test_saving_home_visit_hours_keeps_the_online_hours():
    db = _db([ONLINE, HOME])
    res = _put(db, "/schedules/me/home-visit",
               [{"day_of_week": 5, "start_time": "10:00", "end_time": "13:00"}])
    assert res.status_code == 200
    rows = db.rows("doctor_schedules")
    assert [r for r in rows if r["channel"] == "online_consult"] == [ONLINE]
    assert [(r["day_of_week"], r["start_time"]) for r in rows if r["channel"] == "home_visit"] == [(5, "10:00")]


def test_hours_from_before_0035_move_to_the_channel_not_being_saved():
    legacy = {**ONLINE, "channel": None}
    db = _db([legacy])
    _put(db, "/schedules/me", [{"day_of_week": 1, "start_time": "08:00", "end_time": "09:00"}])
    rows = db.rows("doctor_schedules")
    assert {(r["channel"], r["day_of_week"]) for r in rows} == {("home_visit", 0), ("online_consult", 1)}


def test_an_editor_opens_on_its_own_channels_hours():
    db = _db([ONLINE, HOME, {**ONLINE, "day_of_week": 4, "channel": None}])
    days = [r["day_of_week"] for r in _get(db, "?channel=home_visit").json()]
    assert days == [2, 4]


def test_a_block_that_ends_before_it_starts_is_refused():
    res = _put(_db([]), "/schedules/me", [{"day_of_week": 0, "start_time": "18:00", "end_time": "09:00"}])
    assert res.status_code == 400


# ── listing ──────────────────────────────────────────────────────────────────

HOURS = [{"day_of_week": 0, "start_time": "09:00", "end_time": "12:00", "channel": None}]
READY = {
    "id": "doc-1", "verification_status": "verified", "suspended": False,
    "offers_online_consult": True, "offers_home_visit": True,
    "base_lat": 19.0, "base_lng": 73.0,
    "doctor_pricing": [{"channel": "online_consult", "price": 500},
                       {"channel": "home_visit", "price": 900}],
    "doctor_schedules": HOURS,
}


def test_a_doctor_with_price_hours_and_location_is_bookable_on_both():
    assert listing.bookable_channels(READY) == ["online_consult", "home_visit"]
    assert listing.summary(READY)["visible"] is True


def test_no_hours_means_not_listed():
    doctor = {**READY, "doctor_schedules": []}
    assert listing.bookable_channels(doctor) == []
    s = listing.summary(doctor)
    assert s["visible"] is False
    assert s["channels"]["online_consult"]["missing"] == ["hours"]


def test_no_price_hides_only_that_channel():
    doctor = {**READY, "doctor_pricing": [{"channel": "online_consult", "price": 500}]}
    masked = listing.mask(doctor)
    assert masked["offers_online_consult"] is True
    assert masked["offers_home_visit"] is False


def test_home_visits_need_a_base_location():
    doctor = {**READY, "base_lat": None}
    assert listing.missing(doctor, "home_visit") == ["base_location"]
    assert listing.bookable_channels(doctor) == ["online_consult"]


def test_hours_for_the_other_channel_dont_count():
    doctor = {**READY, "doctor_schedules": [{**HOURS[0], "channel": "online_consult"}]}
    assert listing.missing(doctor, "home_visit") == ["hours"]


def test_search_leaves_out_a_verified_doctor_who_hasnt_finished_setup():
    from tests.conftest import make_chain, make_supabase
    half = {**READY, "id": "doc-2", "doctor_pricing": [], "doctor_schedules": []}
    with patch("app.routers.doctors.supabase",
               make_supabase({"doctors": make_chain(list_data=[READY, half])})):
        ids = [d["id"] for d in client.get("/doctors/search").json()["items"]]
    assert ids == ["doc-1"]


def test_the_home_visit_filter_needs_a_bookable_home_visit():
    from tests.conftest import make_chain, make_supabase
    online_only = {**READY, "id": "doc-2", "base_lat": None}
    with patch("app.routers.doctors.supabase",
               make_supabase({"doctors": make_chain(list_data=[READY, online_only])})):
        ids = [d["id"] for d in client.get("/doctors/search?channel=home_visit").json()["items"]]
    assert ids == ["doc-1"]
