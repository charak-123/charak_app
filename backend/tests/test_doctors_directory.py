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


# ── private-column exposure (strix finding) ───────────────────────────────────

SENSITIVE = {
    **VERIFIED,
    "phone": "+919999999999",
    "fcm_token": "fcm-secret",
    "commission_pct": 12.5,
    "license_number": "MH-12345",
    "verification_document_url": "https://x/doc.pdf",
    "verification_document_path": "doctors/doc-1/verification",
    "base_lat": 19.07, "base_lng": 72.87,
}
_LEAKS = {"phone", "fcm_token", "commission_pct", "license_number",
          "verification_document_url", "verification_document_path",
          "base_lat", "base_lng"}


def test_public_search_does_not_leak_private_doctor_columns():
    doctors = make_chain(list_data=[SENSITIVE])
    with patch(DOCTORS_DB, make_supabase({"doctors": doctors})):
        res = client.get("/doctors/search")
    assert res.status_code == 200
    item = res.json()["items"][0]
    assert _LEAKS.isdisjoint(item.keys())
    assert item["name"] == "Dr Rao"          # public fields still present


def test_public_profile_does_not_leak_private_doctor_columns():
    doctors = make_chain(data=SENSITIVE)
    with patch(DOCTORS_DB, make_supabase({"doctors": doctors})):
        res = client.get("/doctors/doc-1")
    assert res.status_code == 200
    assert _LEAKS.isdisjoint(res.json().keys())


def test_distance_search_applies_a_bounding_box_prefilter_in_sql():
    """A radius-constrained search must narrow base_lat/base_lng in SQL, not
    pull every doctor into Python."""
    doctors = make_chain(list_data=[VERIFIED])
    with patch(DOCTORS_DB, make_supabase({"doctors": doctors})):
        res = client.get("/doctors/search?lat=19.07&lng=72.87&max_distance_km=5")
    assert res.status_code == 200
    bounded = {c.args[0] for c in doctors.gte.call_args_list} | \
              {c.args[0] for c in doctors.lte.call_args_list}
    assert {"base_lat", "base_lng"}.issubset(bounded)
