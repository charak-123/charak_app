from typing import Optional
from fastapi import APIRouter, Depends
from pydantic import BaseModel

from ..db import fetch_one, supabase
from ..deps import get_current_user, require_doctor
from ..errors import AppError
from ..services import geo

router = APIRouter()


# ── Profile ──────────────────────────────────────────────────────────────────

class DoctorProfileUpdate(BaseModel):
    name: Optional[str]                      = None
    category_id: Optional[str]               = None
    bio: Optional[str]                       = None
    photo_url: Optional[str]                 = None
    offers_online_consult: Optional[bool]    = None
    offers_home_visit: Optional[bool]        = None
    base_lat: Optional[float]                = None
    base_lng: Optional[float]                = None
    service_radius_km: Optional[int]         = None
    procedure_review_threshold: Optional[float] = None


@router.get("/me")
def get_me(user: dict = Depends(require_doctor)):
    doctor = fetch_one(supabase.table("doctors").select("*").eq("id", user["sub"]))
    if not doctor:
        raise AppError("Doctor profile not found", 404)
    return doctor


@router.patch("/me")
def update_profile(body: DoctorProfileUpdate, user: dict = Depends(require_doctor)):
    data = body.model_dump(exclude_none=True)
    if not data:
        raise AppError("No fields to update", 400)
    if "service_radius_km" in data and data["service_radius_km"] not in (2, 3, 5):
        raise AppError("service_radius_km must be 2, 3, or 5", 400)
    result = supabase.table("doctors").update(data).eq("id", user["sub"]).execute()
    return result.data[0]


# ── Verification ──────────────────────────────────────────────────────────────

class VerificationSubmit(BaseModel):
    license_number: str
    # Optional: client-side Storage uploads are not yet authorised, so the app
    # may submit a licence number without an attached document. Restore as
    # required once uploads move behind a backend endpoint.
    document_url: Optional[str] = None


@router.post("/me/verification")
def submit_verification(body: VerificationSubmit, user: dict = Depends(require_doctor)):
    update = {
        "license_number": body.license_number,
        "verification_status": "pending",
    }
    # Don't null out a document that a previous submission already attached.
    if body.document_url is not None:
        update["verification_document_url"] = body.document_url
    result = supabase.table("doctors").update(update).eq("id", user["sub"]).execute()
    return result.data[0]


# ── Pricing ───────────────────────────────────────────────────────────────────

class PricingItem(BaseModel):
    channel: str           # "online_consult" | "home_visit"
    price: float
    extra_rate_per_15min: float = 0


@router.get("/me/pricing")
def get_pricing(user: dict = Depends(require_doctor)):
    return supabase.table("doctor_pricing").select("*").eq("doctor_id", user["sub"]).execute().data


@router.put("/me/pricing")
def upsert_pricing(items: list[PricingItem], user: dict = Depends(require_doctor)):
    for item in items:
        if item.channel not in ("online_consult", "home_visit"):
            raise AppError(f"Invalid channel: {item.channel}", 400)
        supabase.table("doctor_pricing").upsert(
            {"doctor_id": user["sub"], **item.model_dump()},
            on_conflict="doctor_id,channel",
        ).execute()
    return supabase.table("doctor_pricing").select("*").eq("doctor_id", user["sub"]).execute().data


# ── Procedures ────────────────────────────────────────────────────────────────

class ProcedureCreate(BaseModel):
    name: str
    price: float


@router.get("/me/procedures")
def list_procedures(user: dict = Depends(require_doctor)):
    return (
        supabase.table("doctor_procedures")
        .select("*")
        .eq("doctor_id", user["sub"])
        .eq("active", True)
        .execute()
        .data
    )


@router.post("/me/procedures")
def add_procedure(proc: ProcedureCreate, user: dict = Depends(require_doctor)):
    if proc.price <= 0:
        raise AppError("Procedure price must be positive", 400)
    return supabase.table("doctor_procedures").insert({
        "doctor_id": user["sub"],
        "name": proc.name.strip(),
        "price": proc.price,
    }).execute().data[0]


@router.delete("/me/procedures/{proc_id}")
def remove_procedure(proc_id: str, user: dict = Depends(require_doctor)):
    supabase.table("doctor_procedures") \
        .update({"active": False}) \
        .eq("id", proc_id) \
        .eq("doctor_id", user["sub"]) \
        .execute()
    return {"ok": True}


# ── Directory search (public, for patients) ───────────────────────────────────

@router.get("/search")
def search_doctors(
    q: str = "",
    category: str = "",
    channel: str = "",        # "online_consult" | "home_visit"
    min_rating: float = 0,
    max_price: float = 0,
    lat: Optional[float] = None,
    lng: Optional[float] = None,
    max_distance_km: Optional[float] = None,
    serviceable_only: bool = False,
    sort: str = "rating",     # "rating" | "distance" | "price"
    limit: int = 20,
    offset: int = 0,
):
    """
    Public directory search.

    Pass the patient's lat/lng to get distance on every result and to sort or
    filter by it — the spec's "sort by price/rating/distance". Without a location
    the endpoint behaves exactly as before, so a patient who declines the location
    permission still gets a usable directory.

    ``serviceable_only`` keeps only doctors whose home-visit radius actually
    covers the given point, which is what makes the home-visit tab honest: a
    doctor 40km away was previously listed as bookable.

    Price, category and distance are filtered in Python because pricing lives in
    a join and distance is computed — see services/geo.py on when that stops
    being the right trade.
    """
    limit = max(1, min(limit, 100))
    offset = max(0, offset)

    if sort not in ("rating", "distance", "price"):
        raise AppError("sort must be rating, distance or price", 400)
    if (lat is None) != (lng is None):
        raise AppError("lat and lng must be provided together", 400)
    if sort == "distance" and lat is None:
        raise AppError("sort=distance requires lat and lng", 400)
    if serviceable_only and lat is None:
        raise AppError("serviceable_only requires lat and lng", 400)
    query = (
        supabase.table("doctors")
        .select("*, categories(name), doctor_pricing(*)")
        .eq("verification_status", "verified")
        .eq("suspended", False)
    )

    if q:
        # Supabase full-text or ilike on name
        query = query.ilike("name", f"%{q}%")

    if channel == "online_consult":
        query = query.eq("offers_online_consult", True)
    elif channel == "home_visit":
        query = query.eq("offers_home_visit", True)

    if min_rating > 0:
        query = query.gte("rating_avg", min_rating)

    results = query.order("rating_avg", desc=True).execute().data

    # Post-filter by category name (Supabase join filter is limited in python SDK)
    if category:
        results = [
            d for d in results
            if (d.get("categories") or {}).get("name", "").lower() == category.lower()
        ]

    # Post-filter by max price
    if max_price > 0:
        results = [d for d in results if _cheapest(d, channel) <= max_price]

    # Distance annotation, filtering and sorting
    results = geo.annotate_distance(results, lat, lng)

    if max_distance_km is not None:
        # An unknown distance is excluded when a limit was asked for: the caller
        # asked for doctors within N km, and "we don't know" is not within N km.
        results = [
            d for d in results
            if d["distance_km"] is not None and d["distance_km"] <= max_distance_km
        ]

    if serviceable_only:
        results = [d for d in results if d.get("in_service_area")]

    if sort == "distance":
        results.sort(key=geo.sort_key_distance)
    elif sort == "price":
        results.sort(key=lambda d: _cheapest(d, channel))
    else:
        results.sort(key=lambda d: float(d.get("rating_avg") or 0), reverse=True)

    page = results[offset: offset + limit]
    return {
        "total": len(results),
        "limit": limit,
        "offset": offset,
        "has_more": offset + len(page) < len(results),
        "sort": sort,
        "located": lat is not None,
        "items": page,
    }


def _cheapest(doctor: dict, channel: str) -> float:
    """Lowest price across the doctor's pricing rows, restricted to a channel when
    one was requested. Doctors with no pricing sort last rather than free."""
    pricing = doctor.get("doctor_pricing") or []
    prices = [p["price"] for p in pricing if not channel or p["channel"] == channel]
    return min(prices) if prices else float("inf")


# ── Directory (public, for patients) ─────────────────────────────────────────

@router.get("/{doctor_id}")
def get_doctor_public(doctor_id: str):
    doctor = fetch_one(
        supabase.table("doctors")
        .select("*, doctor_pricing(*), doctor_procedures(*), categories(name)")
        .eq("id", doctor_id)
        .eq("verification_status", "verified")
        .eq("suspended", False)
    )
    if not doctor:
        raise AppError("Doctor not found or not verified", 404)
    return doctor


@router.get("/{doctor_id}/service-area")
def check_service_area(
    doctor_id: str,
    address_id: Optional[str] = None,
    lat: Optional[float] = None,
    lng: Optional[float] = None,
    user: dict = Depends(get_current_user),
):
    """
    Whether a home visit to this address is within the doctor's radius.

    Backs the channel-confirm screen, which the spec says should confirm "the
    patient's address falls within the doctor's radius" before booking. Callers
    pass either one of their saved address_ids or a raw lat/lng.

    Booking re-checks this server-side regardless — this endpoint exists so the
    patient finds out before choosing a slot, not after.
    """
    if not address_id and (lat is None or lng is None):
        raise AppError("Provide either address_id or both lat and lng", 400)

    if address_id:
        address = fetch_one(
            supabase.table("patient_addresses").select("*").eq("id", address_id)
        )
        if not address:
            raise AppError("Address not found", 404)
        if address["patient_id"] != user["sub"]:
            raise AppError("Forbidden", 403)
        lat, lng = address["lat"], address["lng"]

    doctor = fetch_one(
        supabase.table("doctors")
        .select("id, base_lat, base_lng, service_radius_km, offers_home_visit")
        .eq("id", doctor_id).eq("verification_status", "verified").eq("suspended", False)
    )
    if not doctor:
        raise AppError("Doctor not found or not verified", 404)
    if not doctor.get("offers_home_visit"):
        return {
            "in_service_area": False,
            "distance_km": None,
            "service_radius_km": None,
            "reason": "This doctor does not offer home visits",
        }

    in_area, distance = geo.within_service_area(doctor, lat, lng)
    reason = None
    if not in_area:
        reason = (
            "This doctor has not finished setting up their home-visit area yet"
            if distance is None
            else f"That address is {distance:.1f}km away, outside their "
                 f"{doctor['service_radius_km']}km service area"
        )

    return {
        "in_service_area": in_area,
        "distance_km": distance,
        "service_radius_km": doctor.get("service_radius_km"),
        "reason": reason,
    }


@router.get("/{doctor_id}/slots")
def get_slots(doctor_id: str, from_date: str = None):
    from datetime import date
    from ..services.availability import get_available_slots
    d = date.fromisoformat(from_date) if from_date else date.today()
    return get_available_slots(doctor_id, d)
