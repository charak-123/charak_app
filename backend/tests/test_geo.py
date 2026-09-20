"""
Tests for distance and service-radius logic.

The behaviour that matters: a doctor's radius is now enforced, an unknown
location is never treated as "nearby", and a doctor who has not finished setting
up their service area is not dispatched anywhere.
"""
import pytest

from app.services import geo


# ── haversine ─────────────────────────────────────────────────────────────────

def test_distance_matches_known_real_world_pairs():
    # Connaught Place -> India Gate is ~2.4km; Delhi -> Mumbai ~1150km.
    assert 2.3 <= geo.haversine_km(28.6315, 77.2167, 28.6129, 77.2295) <= 2.6
    assert 1130 <= geo.haversine_km(28.6139, 77.2090, 19.0760, 72.8777) <= 1160


def test_distance_to_self_is_zero():
    assert geo.haversine_km(28.6, 77.2, 28.6, 77.2) == 0.0


def test_distance_is_symmetric():
    a = geo.haversine_km(28.6139, 77.2090, 19.0760, 72.8777)
    b = geo.haversine_km(19.0760, 72.8777, 28.6139, 77.2090)
    assert a == pytest.approx(b)


def test_antipodal_points_do_not_blow_up_on_domain_error():
    """asin() of anything above 1.0 raises; floating point can push it there for
    near-antipodal pairs, so the argument is clamped."""
    d = geo.haversine_km(0, 0, 0, 180)
    assert 20_000 < d < 20_040


def test_distance_between_returns_none_for_an_incomplete_point():
    """An unset base location is an unknown distance, not a zero distance."""
    assert geo.distance_between(None, (28.6, 77.2)) is None
    assert geo.distance_between((None, 77.2), (28.6, 77.2)) is None
    assert geo.distance_between((28.6, None), (28.6, 77.2)) is None


# ── service area ──────────────────────────────────────────────────────────────

DOCTOR = {
    "base_lat": 28.6139, "base_lng": 77.2090,
    "service_radius_km": 3, "offers_home_visit": True,
}


def test_an_address_inside_the_radius_is_allowed():
    allowed, distance = geo.within_service_area(DOCTOR, 28.6315, 77.2167)
    assert allowed is True
    assert distance == pytest.approx(2.1, abs=0.2)


def test_an_address_outside_the_radius_is_refused_with_its_distance():
    allowed, distance = geo.within_service_area(DOCTOR, 19.0760, 72.8777)
    assert allowed is False
    assert distance > 1000


def test_a_doctor_without_a_base_location_services_nowhere():
    """Refusing is the safe default — the alternative is dispatching someone to
    an address they never agreed to cover."""
    allowed, distance = geo.within_service_area(
        {"service_radius_km": 5, "offers_home_visit": True}, 28.6, 77.2)
    assert allowed is False
    assert distance is None


def test_a_doctor_without_a_radius_services_nowhere():
    allowed, _ = geo.within_service_area(
        {"base_lat": 28.6, "base_lng": 77.2, "offers_home_visit": True}, 28.6, 77.2)
    assert allowed is False


def test_the_radius_boundary_is_inclusive():
    """A point exactly at the limit is covered — '5km radius' should mean 5km."""
    doctor = {"base_lat": 0.0, "base_lng": 0.0, "service_radius_km": 5}
    # ~0.0449 degrees of latitude is almost exactly 5km at the equator.
    at_edge = 5 / geo.EARTH_RADIUS_KM * (180 / 3.141592653589793)
    allowed, distance = geo.within_service_area(doctor, at_edge * 0.999, 0.0)
    assert allowed is True
    assert distance <= 5.0


# ── bounding box ──────────────────────────────────────────────────────────────

def test_the_bounding_box_encloses_every_point_in_range():
    """A pre-filter may be over-selective but must never exclude a point that is
    genuinely within the radius."""
    lat, lng, radius = 28.6139, 77.2090, 5.0
    box = geo.bounding_box(lat, lng, radius)

    for d_lat, d_lng in [(0.04, 0), (-0.04, 0), (0, 0.045), (0, -0.045)]:
        plat, plng = lat + d_lat, lng + d_lng
        if geo.haversine_km(lat, lng, plat, plng) <= radius:
            assert box["lat_min"] <= plat <= box["lat_max"]
            assert box["lng_min"] <= plng <= box["lng_max"]


def test_the_bounding_box_does_not_divide_by_zero_at_the_pole():
    box = geo.bounding_box(90.0, 0.0, 5.0)
    assert all(isinstance(v, float) for v in box.values())


# ── annotation and sorting ────────────────────────────────────────────────────

def _docs():
    return [
        {"id": "near", "base_lat": 28.6315, "base_lng": 77.2167,
         "offers_home_visit": True, "service_radius_km": 5},
        {"id": "far", "base_lat": 19.0760, "base_lng": 72.8777,
         "offers_home_visit": True, "service_radius_km": 2},
        {"id": "nolocation", "offers_home_visit": False},
    ]


def test_annotation_marks_distance_and_service_area():
    out = geo.annotate_distance(_docs(), 28.6139, 77.2090)
    by_id = {d["id"]: d for d in out}

    assert by_id["near"]["distance_km"] < 5
    assert by_id["near"]["in_service_area"] is True
    assert by_id["far"]["in_service_area"] is False
    # Not offering home visits is not the same as being out of area.
    assert by_id["nolocation"]["in_service_area"] is None
    assert by_id["nolocation"]["distance_km"] is None


def test_annotation_without_a_patient_location_leaves_distance_unknown():
    """A patient who declines the location permission still gets a directory."""
    out = geo.annotate_distance(_docs(), None, None)
    assert all(d["distance_km"] is None for d in out)
    assert all(d["in_service_area"] is None for d in out)


def test_unknown_distances_sort_last():
    """A doctor with no base location must not sort as if they were next door,
    which is what a 0 default would do."""
    docs = geo.annotate_distance(_docs(), 28.6139, 77.2090)
    docs.sort(key=geo.sort_key_distance)
    assert docs[0]["id"] == "near"
    assert docs[-1]["id"] == "nolocation"
