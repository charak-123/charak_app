from typing import Optional
from fastapi import APIRouter, Depends
from postgrest.exceptions import APIError
from pydantic import BaseModel, field_validator

from ..config import PROCEDURE_REVIEW_THRESHOLD_MAX
from ..db import fetch_one, supabase
from ..deps import get_current_user, require_doctor
from ..errors import AppError
from ..phone import normalize_e164
from ..services import erasure, geo, storage
from .procedure_bills import effective_review_threshold

router = APIRouter()


# ── Profile ──────────────────────────────────────────────────────────────────

class DoctorProfileUpdate(BaseModel):
    name: Optional[str]                      = None
    category_id: Optional[str]               = None
    bio: Optional[str]                       = None
    # No photo_url: the photo is set only by POST /uploads/doctor/photo, which
    # stores the file itself. A client-supplied URL could point anywhere, and
    # every patient browsing the directory would load it.
    offers_online_consult: Optional[bool]    = None
    offers_home_visit: Optional[bool]        = None
    base_lat: Optional[float]                = None
    base_lng: Optional[float]                = None
    service_radius_km: Optional[int]         = None
    procedure_review_threshold: Optional[float] = None
    # The Requests tab's "Accepting requests" switch.
    accepting_requests: Optional[bool]       = None
    # Collected on the profile step after Google sign-in. A contact number, not
    # a proven one: changing it clears otp_verified (see update_profile).
    phone: Optional[str]                     = None
    # The website registration form's fields with no dedicated column
    # (qualification, college, practitioner type, …) — see migration 0019.
    application_details: Optional[dict]      = None

    @field_validator("phone")
    @classmethod
    def _check_phone(cls, v: Optional[str]) -> Optional[str]:
        return normalize_e164(v) if v is not None else None


@router.get("/me")
def get_me(user: dict = Depends(require_doctor)):
    # Pricing and procedures ride along so the profile and the pricing editor
    # show the doctor's saved rates instead of placeholders.
    doctor = fetch_one(
        supabase.table("doctors")
        .select("*, doctor_pricing(*), doctor_procedures(*)")
        .eq("id", user["sub"])
    )
    if not doctor:
        raise AppError("Doctor profile not found", 404)
    return doctor


# What ops checked when they verified a doctor. Changing any of these on a
# verified profile sends it back to the verification queue — otherwise a doctor
# could be approved under one identity and then rename themselves into another.
_VERIFIED_IDENTITY_FIELDS = ("name", "category_id", "application_details")


@router.patch("/me")
def update_profile(body: DoctorProfileUpdate, user: dict = Depends(require_doctor)):
    data = body.model_dump(exclude_none=True)
    if not data:
        raise AppError("No fields to update", 400)
    if "service_radius_km" in data and data["service_radius_km"] not in (2, 3, 5):
        raise AppError("service_radius_km must be 2, 3, or 5", 400)
    threshold = data.get("procedure_review_threshold")
    if threshold is not None and not 0 <= threshold <= PROCEDURE_REVIEW_THRESHOLD_MAX:
        raise AppError(
            f"The senior review threshold can be at most ₹{PROCEDURE_REVIEW_THRESHOLD_MAX:,.0f}",
            400,
        )

    current = fetch_one(
        supabase.table("doctors")
        .select("phone, verification_status, " + ", ".join(_VERIFIED_IDENTITY_FIELDS))
        .eq("id", user["sub"])
    )
    if not current:
        raise AppError("Doctor profile not found", 404)

    # A typed-in number is a claim, not proof. Only OTP / Firebase phone sign-in
    # may mark a number verified; changing it here un-verifies the account.
    if "phone" in data and data["phone"] != current.get("phone"):
        data["otp_verified"] = False

    changed_identity = [
        f for f in _VERIFIED_IDENTITY_FIELDS
        if f in data and data[f] != current.get(f)
    ]
    if current.get("verification_status") == "verified" and changed_identity:
        data["verification_status"] = "pending"
        data["verification_rejection_reason"] = None

    try:
        result = supabase.table("doctors").update(data).eq("id", user["sub"]).execute()
    except APIError as exc:
        if getattr(exc, "code", None) == "23505":
            raise AppError("This phone number is already linked to another account.", 409)
        raise
    return result.data[0]


# ── Verification ──────────────────────────────────────────────────────────────

class VerificationSubmit(BaseModel):
    license_number: str
    # The document itself is submitted separately, to
    # ``POST /uploads/doctor/verification-document`` — it is a file, not a URL
    # the client can mint. This field remains only for the website's doctor
    # registration, which may already hold a link to a document sent by email.
    document_url: Optional[str] = None

    @field_validator("document_url")
    @classmethod
    def _only_http_url(cls, v: Optional[str]) -> Optional[str]:
        # Reject anything that is not an http(s) URL. A stored `javascript:`
        # (or `data:`) URL would later be opened by the admin dashboard and
        # execute in its origin — a stored-XSS path to ops-token theft.
        if v is None or v == "":
            return v
        if not (v.startswith("http://") or v.startswith("https://")):
            raise ValueError("document_url must be an http(s) URL")
        return v


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

# Lengths a doctor can charge for: 5, 10, … 60 min. The base fee covers one
# session; extra time is billed per extra block of extra_duration_min.
SESSION_LENGTHS_MIN = tuple(range(5, 61, 5))


class PricingItem(BaseModel):
    channel: str           # "online_consult" | "home_visit"
    price: float
    base_duration_min: int = 15
    # Rate per extra block of extra_duration_min (column name is historical).
    extra_rate_per_15min: float = 0
    extra_duration_min: int = 15


@router.get("/me/pricing")
def get_pricing(user: dict = Depends(require_doctor)):
    return supabase.table("doctor_pricing").select("*").eq("doctor_id", user["sub"]).execute().data


@router.put("/me/pricing")
def upsert_pricing(items: list[PricingItem], user: dict = Depends(require_doctor)):
    for item in items:
        if item.channel not in ("online_consult", "home_visit"):
            raise AppError(f"Invalid channel: {item.channel}", 400)
        if item.base_duration_min not in SESSION_LENGTHS_MIN \
                or item.extra_duration_min not in SESSION_LENGTHS_MIN:
            raise AppError("Session and extra-time lengths must be 5–60 min, in steps of 5", 400)
        if item.price <= 0 or item.extra_rate_per_15min < 0:
            raise AppError("Fees must be positive", 400)
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

# The only keys of a doctor row an unauthenticated caller may see. An allowlist,
# not a denylist: the directory used to strip a fixed set of private columns
# from `select("*")`, so every column added since (email, google_sub,
# firebase_uid, the registration numbers in application_details, …) went out to
# anyone who asked. A new column now stays private until it is listed here.
# Exact home coordinates (base_lat/base_lng) are deliberately absent: distance
# is computed server-side and returned as distance_km.
_PUBLIC_DOCTOR_FIELDS = (
    "id",
    "name",
    "bio",
    "photo_url",
    "category_id",
    "categories",
    "rating_avg",
    "offers_online_consult",
    "offers_home_visit",
    "online_consult_mode",
    "service_radius_km",
    "accepting_requests",
    "doctor_pricing",
    "doctor_procedures",
    # Added by geo.annotate_distance on search results.
    "distance_km",
    "in_service_area",
)


def _public_doctor(doctor: dict) -> dict:
    """Keep only the public keys of a doctor row, adding a small photo thumbnail."""
    out = {k: doctor[k] for k in _PUBLIC_DOCTOR_FIELDS if k in doctor}
    # What patients are told: bills above this amount go to senior review.
    out["procedure_review_threshold"] = effective_review_threshold(
        doctor.get("procedure_review_threshold")
    )
    if isinstance(out.get("doctor_procedures"), list):
        # A removed procedure is soft-deleted (active = false); it is no
        # longer offered, so patients should not see it.
        out["doctor_procedures"] = [
            p for p in out["doctor_procedures"] if p.get("active", True) is not False
        ]
    if doctor.get("photo_path"):
        out["photo_thumb_url"] = storage.thumb_url(
            storage.BUCKET_DOCTOR_PHOTOS, doctor["photo_path"]
        )
    return out


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

    # Push a bounding-box pre-filter into SQL for distance-constrained searches,
    # so Postgres (using idx_doctors_base_latlng) returns only doctors near the
    # patient instead of every verified doctor for Python to filter. The box is
    # deliberately over-selective — exact distance is still refined below — and
    # is only applied when a radius is given, so the plain directory is unchanged.
    if lat is not None and max_distance_km is not None:
        box = geo.bounding_box(lat, lng, max_distance_km)
        query = (
            query.gte("base_lat", box["lat_min"]).lte("base_lat", box["lat_max"])
                 .gte("base_lng", box["lng_min"]).lte("base_lng", box["lng_max"])
        )

    results = query.order("rating_avg", desc=True).execute().data

    # A doctor who paused "Accepting requests" is hidden from search. Filtered
    # here rather than in SQL so search keeps working on a database that has
    # not had migration 0016 yet (the column is simply absent there).
    results = [d for d in results if d.get("accepting_requests", True) is not False]

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

    page = [_public_doctor(d) for d in results[offset: offset + limit]]
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
    return _public_doctor(doctor)


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
def get_slots(doctor_id: str, from_date: str = None, days: int = 14):
    """
    Open slots for a doctor, grouped by date.

    ``days`` is honoured rather than ignored: the patient app asks for six and
    used to be handed fourteen, because the parameter stopped at the route and
    never reached get_available_slots.
    """
    from datetime import date
    from ..services.availability import get_available_slots

    if not 1 <= days <= 60:
        raise AppError("days must be between 1 and 60", 400)
    try:
        d = date.fromisoformat(from_date) if from_date else date.today()
    except ValueError:
        raise AppError("from_date must be ISO format, e.g. 2026-10-01", 400)
    return get_available_slots(doctor_id, d, days=days)


@router.delete("/me")
def request_doctor_account_deletion(user: dict = Depends(require_doctor)):
    """
    File a doctor account-deletion request (App Store & Play requirement).

    Doctors are not purged automatically — outstanding payouts, active bookings
    and bank details must be settled by ops first. This locks the account and
    records the request; ops completes the erasure from the admin console.
    """
    return erasure.request_doctor_deletion(user["sub"])
