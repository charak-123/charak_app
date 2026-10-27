"""
The pricing matrix (migration 0026, spec §8).

A doctor prices each channel by duration, separately for a first visit and a
follow-up. Each price is a ``doctor_price_rules`` row; a change closes the
row and adds a new one, so bookings made before keep what they were charged
(they snapshot the rule) and the rows are the history.

A follow-up price applies only when the booking really is a follow-up
(spec §8.3): it names a consultation of the patient's own with the same
doctor whose prescription has been sent, it starts within the doctor's
follow-up validity window (extended to the doctor's recommended follow-up date
when that is later), and that consultation hasn't had its follow-up already.
Nothing is inferred from what the patient typed.

The price is always the server's. The app sends back the price it showed;
if it no longer matches, nothing is booked and the patient sees the new price.
"""
from __future__ import annotations

from datetime import date, datetime, time, timedelta, timezone
from typing import Optional

from ..db import fetch_one, supabase
from ..errors import AppError

CHANNELS = ("online_consult", "home_visit")
CATEGORIES = ("initial", "follow_up")
DURATIONS = (10, 15, 20, 30, 45, 60)
MAX_PRICE_PAISE = 50_000 * 100
MAX_DURATIONS_PER_LIST = 4
VALIDITY_DAYS = range(1, 61)
# A doctor's recommended follow-up date stays bookable at the follow-up price
# for this long after it, even when it's beyond their validity window.
RECOMMENDATION_GRACE = timedelta(days=3)

IST = timezone(timedelta(hours=5, minutes=30))
FOLLOW_UP_SOURCE_STATUSES = ("consulted", "completed")

_RULE_COLUMNS = "id, doctor_id, channel, visit_category, duration_min, price_paise, " \
                "effective_from, effective_until"


def _ts(value) -> Optional[datetime]:
    if not value:
        return None
    return datetime.fromisoformat(str(value).replace("Z", "+00:00"))


def public_rule(rule: dict) -> dict:
    return {k: rule[k] for k in ("id", "channel", "visit_category", "duration_min", "price_paise")}


# ── Reading prices ───────────────────────────────────────────────────────────

def current_rules(doctor_id: str) -> list[dict]:
    return (
        supabase.table("doctor_price_rules").select(_RULE_COLUMNS)
        .eq("doctor_id", doctor_id).is_("effective_until", "null")
        .order("channel").order("visit_category").order("duration_min")
        .execute().data or []
    )


def price_list(doctor_id: str, doctor: Optional[dict] = None) -> dict:
    """What the patient can book: each offered channel's first-visit options,
    shortest first. Follow-up prices are shown only against a consultation
    that qualifies (follow_up_options)."""
    doctor = doctor or fetch_one(
        supabase.table("doctors").select("offers_online_consult, offers_home_visit, "
                                         "follow_up_validity_days").eq("id", doctor_id)) or {}
    offered = {"online_consult": doctor.get("offers_online_consult"),
               "home_visit": doctor.get("offers_home_visit")}
    rules = [r for r in current_rules(doctor_id) if offered.get(r["channel"])]
    return {
        "channels": {
            c: [public_rule(r) for r in rules if r["channel"] == c and r["visit_category"] == "initial"]
            for c in CHANNELS if offered.get(c)
        },
        "follow_up_validity_days": doctor.get("follow_up_validity_days"),
        "offers_follow_up_prices": any(r["visit_category"] == "follow_up" for r in rules),
    }


# ── Follow-ups ───────────────────────────────────────────────────────────────

def follow_up_window(original: dict, validity_days: Optional[int],
                     recommended: Optional[date] = None) -> Optional[datetime]:
    """When the follow-up price stops applying for this consultation, or None
    if the doctor offers no follow-up window."""
    if not validity_days:
        return None
    anchor = (_ts(original.get("prescription_sent_at")) or _ts(original.get("completed_at"))
              or _ts(original["scheduled_start"]))
    until = anchor + timedelta(days=validity_days)
    if recommended is not None:
        until = max(until, datetime.combine(recommended, time(23, 59, 59), IST) + RECOMMENDATION_GRACE)
    return until


def check_follow_up(original_id: str, patient_id: str, doctor_id: Optional[str] = None,
                    start: Optional[datetime] = None) -> dict:
    """
    The consultation a follow-up continues, with the window it can be booked
    in. Raises AppError (409) saying why when it doesn't qualify.
    """
    original = fetch_one(
        supabase.table("bookings")
        .select("id, patient_id, doctor_id, channel, status, scheduled_start, prescription_sent_at, "
                "completed_at, doctors(follow_up_validity_days)")
        .eq("id", original_id)
    )
    if not original or original["patient_id"] != patient_id:
        raise AppError("That consultation wasn't found", 404)
    if doctor_id and original["doctor_id"] != doctor_id:
        raise AppError("A follow-up is with the doctor you saw for that consultation", 409)
    if original["status"] not in FOLLOW_UP_SOURCE_STATUSES:
        raise AppError("A follow-up can be booked once that consultation is over", 409)

    validity = (original.get("doctors") or {}).get("follow_up_validity_days")
    rec = fetch_one(
        supabase.table("follow_up_recommendations").select("recommended_date")
        .eq("booking_id", original_id).eq("status", "open")
    )
    recommended = date.fromisoformat(rec["recommended_date"]) if rec else None
    until = follow_up_window(original, validity, recommended)
    if until is None:
        raise AppError("This doctor doesn't offer follow-up prices", 409)
    if start is not None and start > until:
        raise AppError("The follow-up price applies until "
                       f"{until.astimezone(IST).strftime('%-d %b')}. Pick an earlier day, "
                       "or book a regular consultation.", 409, follow_up_until=until.isoformat())

    taken = (
        supabase.table("bookings").select("id")
        .eq("follow_up_of", original_id)
        .in_("status", ["requested", "accepted", "paid", "in_progress", "consulted", "completed"])
        .execute().data or []
    )
    if taken:
        raise AppError("A follow-up for that consultation is already booked", 409)
    return {**original, "follow_up_until": until.isoformat()}


def follow_up_options(original_id: str, patient_id: str) -> dict:
    """For the patient's "Book follow-up": the follow-up prices the doctor
    offers and until when, or why not."""
    original = check_follow_up(original_id, patient_id)
    rules = [r for r in current_rules(original["doctor_id"]) if r["visit_category"] == "follow_up"]
    doctor = fetch_one(supabase.table("doctors").select("offers_online_consult, offers_home_visit")
                       .eq("id", original["doctor_id"])) or {}
    offered = {"online_consult": doctor.get("offers_online_consult"),
               "home_visit": doctor.get("offers_home_visit")}
    return {
        "follow_up_of": original_id,
        "doctor_id": original["doctor_id"],
        "until": original["follow_up_until"],
        "channels": {
            c: [public_rule(r) for r in rules if r["channel"] == c]
            for c in CHANNELS if offered.get(c)
        },
    }


# ── Resolving a booking's price ──────────────────────────────────────────────

def resolve(doctor_id: str, channel: str, *, patient_id: str, start: datetime,
            rule_id: Optional[str] = None, duration_min: Optional[int] = None,
            follow_up_of: Optional[str] = None) -> dict:
    """
    The rule a new booking is charged by. Always a current rule of this
    doctor and channel; a follow-up rule only when the booking qualifies.

    App builds from before 0026 send neither a rule nor a duration: they get
    the first-visit price they were shown (doctor_pricing, kept in step).
    """
    rules = [r for r in current_rules(doctor_id) if r["channel"] == channel]
    category = "follow_up" if follow_up_of else "initial"
    if follow_up_of:
        check_follow_up(follow_up_of, patient_id, doctor_id, start)

    if rule_id:
        rule = next((r for r in rules if r["id"] == rule_id), None)
        if rule is None:
            raise AppError("That price is no longer offered. Please choose again.", 409,
                           code="price_changed")
        if rule["visit_category"] != category:
            raise AppError("That price is for a different kind of visit", 409, code="price_changed")
        return rule

    candidates = [r for r in rules if r["visit_category"] == category]
    if duration_min is not None:
        rule = next((r for r in candidates if r["duration_min"] == duration_min), None)
        if rule is None:
            raise AppError(f"This doctor doesn't offer a {duration_min}-minute "
                           f"{'follow-up' if follow_up_of else 'consultation'} here", 409,
                           code="price_changed")
        return rule
    legacy = fetch_one(supabase.table("doctor_pricing").select("price, base_duration_min")
                       .eq("doctor_id", doctor_id).eq("channel", channel))
    if not candidates:
        # A price saved through a backend from before migration 0026 (the
        # deploy window) has no rule yet. It is still the doctor's published
        # first-visit price for this channel.
        if category == "initial" and legacy and legacy.get("price"):
            return {"id": None, "channel": channel, "visit_category": "initial",
                    "duration_min": legacy.get("base_duration_min") or 15,
                    "price_paise": int(round(float(legacy["price"]) * 100))}
        raise AppError("This doctor has not published a price for this consultation type yet", 409)
    if legacy:
        match = next((r for r in candidates if r["duration_min"] == legacy["base_duration_min"]), None)
        if match:
            return match
    return candidates[0]


# ── Saving the matrix ────────────────────────────────────────────────────────

def validate(rules: list[dict], validity_days: Optional[int], offered: dict) -> list[dict]:
    """The doctor's price list, checked; returns it normalised."""
    seen = set()
    out = []
    for r in rules:
        channel, category = r.get("channel"), r.get("visit_category")
        duration, paise = r.get("duration_min"), r.get("price_paise")
        if channel not in CHANNELS or category not in CATEGORIES:
            raise AppError("Each price needs a channel and whether it's a first visit or a follow-up", 400)
        if duration not in DURATIONS:
            raise AppError(f"Lengths can be {', '.join(map(str, DURATIONS))} minutes", 400)
        if not isinstance(paise, int) or paise < 0 or paise > MAX_PRICE_PAISE or paise % 100:
            raise AppError("Prices are whole rupees, up to ₹50,000", 400)
        if category == "initial" and paise == 0:
            raise AppError("A first visit can't be free. Only follow-ups can.", 400)
        key = (channel, category, duration)
        if key in seen:
            raise AppError(f"The {duration}-minute price is listed twice", 400)
        seen.add(key)
        out.append({"channel": channel, "visit_category": category,
                    "duration_min": duration, "price_paise": paise})

    for channel in CHANNELS:
        for category in CATEGORIES:
            n = sum(1 for c, k, _ in seen if c == channel and k == category)
            if n > MAX_DURATIONS_PER_LIST:
                raise AppError(f"At most {MAX_DURATIONS_PER_LIST} lengths for each price list", 400)
        if offered.get(channel) and not any(c == channel and k == "initial" for c, k, _ in seen):
            label = "online consultations" if channel == "online_consult" else "home visits"
            raise AppError(f"Set at least one price for {label}, or turn them off", 400)

    has_follow_up = any(k == "follow_up" for _, k, _ in seen)
    if has_follow_up and validity_days not in VALIDITY_DAYS:
        raise AppError("Say for how many days (1–60) a follow-up price applies", 400)
    return out


def save(doctor_id: str, rules: list[dict], validity_days: Optional[int]) -> dict:
    doctor = fetch_one(supabase.table("doctors").select("offers_online_consult, offers_home_visit")
                       .eq("id", doctor_id))
    if not doctor:
        raise AppError("Doctor profile not found", 404)
    clean = validate(rules, validity_days,
                     {"online_consult": doctor.get("offers_online_consult"),
                      "home_visit": doctor.get("offers_home_visit")})
    has_follow_up = any(r["visit_category"] == "follow_up" for r in clean)
    result = supabase.rpc("set_doctor_prices", {
        "p_doctor_id": doctor_id,
        "p_rules": clean,
        "p_follow_up_validity_days": validity_days if has_follow_up else None,
        "p_actor_id": doctor_id,
    }).execute().data or {}
    if result.get("outcome") != "ok":
        raise AppError("Doctor profile not found", 404)
    return my_prices(doctor_id)


def my_prices(doctor_id: str) -> dict:
    doctor = fetch_one(supabase.table("doctors").select("follow_up_validity_days").eq("id", doctor_id)) or {}
    return {"rules": [public_rule(r) for r in current_rules(doctor_id)],
            "follow_up_validity_days": doctor.get("follow_up_validity_days"),
            "durations": list(DURATIONS)}


def history(doctor_id: str, limit: int = 200) -> list[dict]:
    """Every price the doctor has had, newest first: what support needs to
    answer "what was I charged, and was that the price then?"."""
    return (
        supabase.table("doctor_price_rules").select(_RULE_COLUMNS + ", created_at")
        .eq("doctor_id", doctor_id).order("effective_from", desc=True).limit(limit)
        .execute().data or []
    )
