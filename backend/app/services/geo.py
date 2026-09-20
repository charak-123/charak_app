"""
Distance and service-radius logic.

``doctors.base_lat``, ``base_lng`` and ``service_radius_km`` were stored from the
start but never read, so two things the spec asks for did not happen: the
directory could not "sort by price/rating/distance", and nothing confirmed "the
patient's address falls within the doctor's radius" before a home visit was
booked. A patient could book a home visit from a doctor 40km away.

Distance is computed here in Python rather than in SQL. At V1 scale — doctors
within a city, filtered by specialty and channel before distance is considered —
the candidate set is small enough that the arithmetic is free, and keeping it in
Python means no PostGIS or earthdistance extension to install and no RPC to keep
in sync with the query builder.

That trade stops paying if the directory ever spans many cities with thousands of
verified doctors per specialty. The migration path is a Postgres function over a
geography column with a GiST index, filtering by bounding box before computing
exact distance; ``bounding_box`` below exists so that pre-filter can be applied
at the query level first, and callers already work in the same units.
"""
from __future__ import annotations

from math import asin, cos, degrees, radians, sin, sqrt
from typing import Optional

# Mean Earth radius (km). Haversine on a sphere is accurate to roughly 0.5% —
# metres over a 5km service radius, which is far below the precision of a
# geocoded street address and of how people actually describe where they live.
EARTH_RADIUS_KM = 6371.0088

# The service radii the product offers. Mirrors the CHECK constraint on
# doctors.service_radius_km.
VALID_RADII_KM = (2, 3, 5)


def haversine_km(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """Great-circle distance between two points, in kilometres."""
    p1, p2 = radians(lat1), radians(lat2)
    d_lat = p2 - p1
    d_lng = radians(lng2) - radians(lng1)

    a = sin(d_lat / 2) ** 2 + cos(p1) * cos(p2) * sin(d_lng / 2) ** 2
    return 2 * EARTH_RADIUS_KM * asin(sqrt(min(1.0, a)))


def distance_between(origin: Optional[tuple], dest: Optional[tuple]) -> Optional[float]:
    """
    Distance in km, rounded to 2dp, or None if either point is incomplete.

    Returning None rather than raising keeps the caller honest: a doctor who has
    not set a base location has an unknown distance, which is different from
    being far away, and the directory must be able to say so.
    """
    if not origin or not dest:
        return None
    if any(c is None for c in (*origin, *dest)):
        return None
    return round(haversine_km(float(origin[0]), float(origin[1]),
                              float(dest[0]), float(dest[1])), 2)


def bounding_box(lat: float, lng: float, radius_km: float) -> dict:
    """
    Latitude/longitude bounds enclosing a radius around a point.

    A cheap pre-filter: a bounding box is a `between` on two indexed columns,
    where exact distance is not. Slightly over-selective at the corners, which is
    correct for a pre-filter — it must never exclude a point that is genuinely in
    range. Longitude degrees shrink with latitude, hence the cos() term; it is
    clamped because the division degenerates at the poles.
    """
    lat_delta = degrees(radius_km / EARTH_RADIUS_KM)
    shrink = max(cos(radians(lat)), 0.01)
    lng_delta = degrees(radius_km / (EARTH_RADIUS_KM * shrink))
    return {
        "lat_min": lat - lat_delta, "lat_max": lat + lat_delta,
        "lng_min": lng - lng_delta, "lng_max": lng + lng_delta,
    }


def within_service_area(doctor: dict, lat: float, lng: float) -> tuple[bool, Optional[float]]:
    """
    Whether an address falls inside a doctor's home-visit radius.

    Returns (allowed, distance_km). A doctor who offers home visits without a
    base location or radius is *not* servicing anywhere — refusing is the safe
    default, since the alternative is dispatching someone to an address they
    never agreed to cover.
    """
    base_lat, base_lng = doctor.get("base_lat"), doctor.get("base_lng")
    radius = doctor.get("service_radius_km")

    if base_lat is None or base_lng is None or not radius:
        return False, None

    distance = distance_between((base_lat, base_lng), (lat, lng))
    if distance is None:
        return False, None

    return distance <= float(radius), distance


def annotate_distance(doctors: list[dict], lat: Optional[float],
                      lng: Optional[float]) -> list[dict]:
    """
    Attach ``distance_km`` to each doctor, and ``in_service_area`` for those
    offering home visits. Without a patient location both are None — the
    directory still works, it just cannot sort by distance.
    """
    for doc in doctors:
        if lat is None or lng is None:
            doc["distance_km"] = None
            doc["in_service_area"] = None
            continue

        doc["distance_km"] = distance_between((doc.get("base_lat"), doc.get("base_lng")),
                                              (lat, lng))
        if doc.get("offers_home_visit"):
            doc["in_service_area"] = within_service_area(doc, lat, lng)[0]
        else:
            doc["in_service_area"] = None
    return doctors


def sort_key_distance(doctor: dict) -> float:
    """
    Sort helper placing unknown distances last.

    A doctor who has not set a base location should not sort as if they were
    next door, which is what a 0 default would do.
    """
    d = doctor.get("distance_km")
    return float("inf") if d is None else float(d)
