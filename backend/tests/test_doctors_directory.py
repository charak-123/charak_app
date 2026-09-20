"""
Tests for the public directory — specifically that a suspended listing disappears
from every patient-facing path, and that search pagination reports honestly.
"""
from unittest.mock import patch

from fastapi.testclient import TestClient

from app.main import app
from tests.conftest import make_chain, make_supabase

DOCTORS_DB = "app.routers.doctors.supabase"

client = TestClient(app)

VERIFIED = {
    "id": "doc-1", "name": "Dr Rao", "verification_status": "verified",
    "suspended": False, "rating_avg": 4.5,
    "categories": {"name": "Cardiology"},
    "doctor_pricing": [{"channel": "online_consult", "price": 500}],
    "offers_online_consult": True, "offers_home_visit": False,
}


def test_search_excludes_suspended_listings():
    """A suspended doctor keeps their account but leaves the directory."""
    doctors = make_chain(list_data=[VERIFIED])
    with patch(DOCTORS_DB, make_supabase({"doctors": doctors})):
        res = client.get("/doctors/search")
    assert res.status_code == 200
    doctors.eq.assert_any_call("suspended", False)
    doctors.eq.assert_any_call("verification_status", "verified")


def test_a_direct_profile_link_to_a_suspended_doctor_404s():
    """Suspension must not be bypassable by holding on to a deep link."""
    doctors = make_chain(data=None)
    with patch(DOCTORS_DB, make_supabase({"doctors": doctors})):
        res = client.get("/doctors/doc-1")
    assert res.status_code == 404
    doctors.eq.assert_any_call("suspended", False)


def test_search_reports_pagination_honestly():
    results = [{**VERIFIED, "id": f"doc-{i}"} for i in range(25)]
    with patch(DOCTORS_DB, make_supabase({"doctors": make_chain(list_data=results)})):
        body = client.get("/doctors/search?limit=10&offset=0").json()

    assert body["total"] == 25
    assert len(body["items"]) == 10
    assert body["has_more"] is True


def test_the_last_page_reports_no_more_results():
    results = [{**VERIFIED, "id": f"doc-{i}"} for i in range(25)]
    with patch(DOCTORS_DB, make_supabase({"doctors": make_chain(list_data=results)})):
        body = client.get("/doctors/search?limit=10&offset=20").json()

    assert len(body["items"]) == 5
    assert body["has_more"] is False


def test_an_absurd_page_size_is_clamped():
    results = [{**VERIFIED, "id": f"doc-{i}"} for i in range(150)]
    with patch(DOCTORS_DB, make_supabase({"doctors": make_chain(list_data=results)})):
        body = client.get("/doctors/search?limit=100000").json()
    assert len(body["items"]) == 100


def test_a_negative_offset_is_clamped_to_zero():
    results = [{**VERIFIED, "id": f"doc-{i}"} for i in range(5)]
    with patch(DOCTORS_DB, make_supabase({"doctors": make_chain(list_data=results)})):
        body = client.get("/doctors/search?offset=-10").json()
    assert body["offset"] == 0
    assert len(body["items"]) == 5


def test_category_filtering_is_case_insensitive():
    with patch(DOCTORS_DB, make_supabase({"doctors": make_chain(list_data=[VERIFIED])})):
        body = client.get("/doctors/search?category=cardiology").json()
    assert body["total"] == 1


def test_max_price_filters_on_the_cheapest_matching_channel():
    cheap = {**VERIFIED, "id": "cheap", "doctor_pricing": [{"channel": "online_consult", "price": 300}]}
    dear  = {**VERIFIED, "id": "dear",  "doctor_pricing": [{"channel": "online_consult", "price": 2000}]}
    with patch(DOCTORS_DB, make_supabase({"doctors": make_chain(list_data=[cheap, dear])})):
        body = client.get("/doctors/search?max_price=500").json()

    assert [d["id"] for d in body["items"]] == ["cheap"]
