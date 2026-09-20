"""
Tests for distance search and the service-area check.

Closes the spec's "sort by price/rating/distance" and the channel-confirm screen's
"confirming the patient's address falls within the doctor's radius".
"""
from unittest.mock import patch

from fastapi.testclient import TestClient

from app.main import app
from tests.conftest import make_chain, make_supabase

PATIENT = {"sub": "pat-1", "role": "patient"}
AUTH    = {"Authorization": "Bearer t"}
DOCTORS_DB = "app.routers.doctors.supabase"
JWT        = "app.deps.jwt"

client = TestClient(app)

# Near = ~2.4km from Connaught Place, mid = ~8km, far = Mumbai.
NEAR = {"id": "near", "name": "Dr Near", "rating_avg": 3.0, "suspended": False,
        "verification_status": "verified", "offers_home_visit": True,
        "base_lat": 28.6315, "base_lng": 77.2167, "service_radius_km": 5,
        "categories": {"name": "Cardiology"},
        "doctor_pricing": [{"channel": "home_visit", "price": 900}]}
MID  = {"id": "mid", "name": "Dr Mid", "rating_avg": 5.0, "suspended": False,
        "verification_status": "verified", "offers_home_visit": True,
        "base_lat": 28.68, "base_lng": 77.25, "service_radius_km": 2,
        "categories": {"name": "Cardiology"},
        "doctor_pricing": [{"channel": "home_visit", "price": 400}]}
FAR  = {"id": "far", "name": "Dr Far", "rating_avg": 4.0, "suspended": False,
        "verification_status": "verified", "offers_home_visit": True,
        "base_lat": 19.0760, "base_lng": 72.8777, "service_radius_km": 5,
        "categories": {"name": "Cardiology"},
        "doctor_pricing": [{"channel": "home_visit", "price": 100}]}
NOLOC = {"id": "noloc", "name": "Dr Online", "rating_avg": 4.5, "suspended": False,
         "verification_status": "verified", "offers_home_visit": False,
         "offers_online_consult": True, "categories": {"name": "Cardiology"},
         "doctor_pricing": [{"channel": "online_consult", "price": 300}]}

HERE = "lat=28.6139&lng=77.2090"


def _db(rows):
    return make_supabase({"doctors": make_chain(list_data=list(rows))})


# ── distance annotation ───────────────────────────────────────────────────────

def test_results_carry_a_distance_when_a_location_is_given():
    with patch(DOCTORS_DB, _db([NEAR, FAR])):
        body = client.get(f"/doctors/search?{HERE}").json()
    by_id = {d["id"]: d for d in body["items"]}
    assert by_id["near"]["distance_km"] < 5
    assert by_id["far"]["distance_km"] > 1000
    assert body["located"] is True


def test_without_a_location_the_directory_still_works():
    """A patient who declines the location permission must still get results."""
    with patch(DOCTORS_DB, _db([NEAR, FAR])):
        body = client.get("/doctors/search").json()
    assert body["total"] == 2
    assert body["located"] is False
    assert all(d["distance_km"] is None for d in body["items"])


def test_lat_without_lng_is_rejected():
    with patch(DOCTORS_DB, _db([])):
        assert client.get("/doctors/search?lat=28.6").status_code == 400
        assert client.get("/doctors/search?lng=77.2").status_code == 400


# ── sorting ───────────────────────────────────────────────────────────────────

def test_sorting_by_distance_orders_nearest_first():
    with patch(DOCTORS_DB, _db([FAR, MID, NEAR])):
        body = client.get(f"/doctors/search?{HERE}&sort=distance").json()
    assert [d["id"] for d in body["items"]] == ["near", "mid", "far"]
    assert body["sort"] == "distance"


def test_sorting_by_distance_puts_doctors_without_a_location_last():
    with patch(DOCTORS_DB, _db([NOLOC, FAR, NEAR])):
        body = client.get(f"/doctors/search?{HERE}&sort=distance").json()
    assert [d["id"] for d in body["items"]][-1] == "noloc"


def test_sorting_by_distance_without_a_location_is_a_400():
    """Better an explicit error than silently returning an arbitrary order."""
    with patch(DOCTORS_DB, _db([NEAR])):
        res = client.get("/doctors/search?sort=distance")
    assert res.status_code == 400
    assert "requires lat and lng" in res.json()["error"]


def test_sorting_by_price_orders_cheapest_first():
    with patch(DOCTORS_DB, _db([NEAR, MID, FAR])):
        body = client.get("/doctors/search?sort=price&channel=home_visit").json()
    assert [d["id"] for d in body["items"]] == ["far", "mid", "near"]


def test_default_sort_remains_rating():
    with patch(DOCTORS_DB, _db([NEAR, MID, FAR])):
        body = client.get("/doctors/search").json()
    assert [d["id"] for d in body["items"]][0] == "mid"     # 5.0
    assert body["sort"] == "rating"


def test_an_unknown_sort_is_rejected():
    with patch(DOCTORS_DB, _db([])):
        assert client.get("/doctors/search?sort=cheapest").status_code == 400


# ── filtering ─────────────────────────────────────────────────────────────────

def test_max_distance_filters_out_distant_doctors():
    with patch(DOCTORS_DB, _db([NEAR, MID, FAR])):
        body = client.get(f"/doctors/search?{HERE}&max_distance_km=5").json()
    assert [d["id"] for d in body["items"]] == ["near"]


def test_max_distance_excludes_doctors_of_unknown_distance():
    """The caller asked for doctors within N km; 'we don't know' is not within N km."""
    with patch(DOCTORS_DB, _db([NEAR, NOLOC])):
        body = client.get(f"/doctors/search?{HERE}&max_distance_km=5").json()
    assert "noloc" not in [d["id"] for d in body["items"]]


def test_serviceable_only_keeps_doctors_whose_radius_covers_the_address():
    """This is what makes the home-visit tab honest — a doctor 8km away with a 2km
    radius was previously listed as bookable."""
    with patch(DOCTORS_DB, _db([NEAR, MID, FAR])):
        body = client.get(f"/doctors/search?{HERE}&serviceable_only=true").json()
    assert [d["id"] for d in body["items"]] == ["near"]


def test_serviceable_only_without_a_location_is_a_400():
    with patch(DOCTORS_DB, _db([NEAR])):
        assert client.get("/doctors/search?serviceable_only=true").status_code == 400


def test_in_service_area_is_null_for_doctors_who_do_not_offer_home_visits():
    """Not offering home visits is different from being out of area."""
    with patch(DOCTORS_DB, _db([NOLOC])):
        body = client.get(f"/doctors/search?{HERE}").json()
    assert body["items"][0]["in_service_area"] is None


# ── service-area check endpoint ───────────────────────────────────────────────

def _sa_client(payload, db):
    with patch(DOCTORS_DB, db), patch(JWT) as jw:
        jw.decode.return_value = payload
        yield TestClient(app)


ADDRESS = {"id": "addr-1", "patient_id": "pat-1", "lat": 28.6315, "lng": 77.2167}


def test_service_area_check_confirms_an_in_range_address():
    db = make_supabase({
        "patient_addresses": make_chain(data=ADDRESS),
        "doctors": make_chain(data=NEAR),
    })
    for c in _sa_client(PATIENT, db):
        body = c.get("/doctors/near/service-area?address_id=addr-1", headers=AUTH).json()
    assert body["in_service_area"] is True
    assert body["reason"] is None


def test_service_area_check_explains_why_an_address_is_out_of_range():
    db = make_supabase({
        "patient_addresses": make_chain(data={**ADDRESS, "lat": 19.0760, "lng": 72.8777}),
        "doctors": make_chain(data=MID),
    })
    for c in _sa_client(PATIENT, db):
        body = c.get("/doctors/mid/service-area?address_id=addr-1", headers=AUTH).json()
    assert body["in_service_area"] is False
    assert "outside their 2km service area" in body["reason"]


def test_service_area_check_accepts_raw_coordinates():
    db = make_supabase({"doctors": make_chain(data=NEAR)})
    for c in _sa_client(PATIENT, db):
        body = c.get("/doctors/near/service-area?lat=28.6139&lng=77.2090",
                     headers=AUTH).json()
    assert body["in_service_area"] is True


def test_service_area_check_needs_an_address_or_coordinates():
    db = make_supabase({})
    for c in _sa_client(PATIENT, db):
        assert c.get("/doctors/near/service-area", headers=AUTH).status_code == 400


def test_service_area_check_refuses_another_patients_address():
    db = make_supabase({"patient_addresses": make_chain(data={**ADDRESS, "patient_id": "x"})})
    for c in _sa_client(PATIENT, db):
        assert c.get("/doctors/near/service-area?address_id=addr-1",
                     headers=AUTH).status_code == 403


def test_service_area_check_says_so_when_home_visits_are_not_offered():
    db = make_supabase({"doctors": make_chain(data=NOLOC)})
    for c in _sa_client(PATIENT, db):
        body = c.get("/doctors/noloc/service-area?lat=28.6&lng=77.2", headers=AUTH).json()
    assert body["in_service_area"] is False
    assert "does not offer home visits" in body["reason"]
