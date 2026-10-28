"""
Reviews (migration 0027, spec §12, decisions D15 and D16 at their
recommended defaults).

* Only the patient of a completed booking can review it, once, within
  ``REVIEW_WINDOW`` of completion, and can edit it for ``EDIT_WINDOW``.
* An overall 1–5 rating is required; three sub-ratings are optional:
  courtesy (professionalism), explanation (communication) and punctuality.
  Nothing asks the patient to judge clinical correctness.
* The doctor's public rating is the mean of the last 200 published reviews
  (refresh_doctor_rating(), run by a trigger). It's shown once there are
  ``MIN_REVIEWS_SHOWN`` reviews; before that the doctor is "New". The count
  is always shown.
* Doctors never edit or delete a review and never see who wrote it. They can
  report one; ops hides it only for a stated reason (abuse, irrelevance,
  private details), never for being negative, and can restore it. Every
  moderation step is in the audit log.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Optional

from ..db import fetch_one, supabase
from ..errors import AppError
from . import audit

REVIEW_WINDOW = timedelta(days=14)
EDIT_WINDOW = timedelta(hours=48)
MIN_REVIEWS_SHOWN = 5
DIMENSIONS = ("professionalism", "communication", "punctuality")
REPORT_REASONS = ("abusive", "irrelevant", "privacy", "other")

_PATIENT_FIELDS = ("overall", *DIMENSIONS, "comment")


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _ts(value) -> Optional[datetime]:
    if not value:
        return None
    return datetime.fromisoformat(str(value).replace("Z", "+00:00"))


def _clean(fields: dict) -> dict:
    overall = fields.get("overall")
    if not isinstance(overall, int) or not 1 <= overall <= 5:
        raise AppError("Choose an overall rating from 1 to 5 stars", 400)
    out = {"overall": overall}
    for d in DIMENSIONS:
        v = fields.get(d)
        if v is not None and (not isinstance(v, int) or not 1 <= v <= 5):
            raise AppError("Ratings are from 1 to 5 stars", 400)
        out[d] = v
    comment = (fields.get("comment") or "").strip()
    if len(comment) > 1000:
        raise AppError("Keep the comment under 1,000 characters", 400)
    out["comment"] = comment or None
    return out


# ── The patient ──────────────────────────────────────────────────────────────

def review_window_end(booking: dict) -> Optional[datetime]:
    """Until when this booking can be reviewed (None: it can't be)."""
    if booking.get("status") != "completed":
        return None
    done = _ts(booking.get("completed_at")) or _ts(booking.get("scheduled_start"))
    return done + REVIEW_WINDOW if done else None


def create(booking_id: str, patient_id: str, fields: dict, actor: dict) -> dict:
    booking = fetch_one(supabase.table("bookings")
                        .select("id, patient_id, doctor_id, status, completed_at, scheduled_start")
                        .eq("id", booking_id))
    if not booking:
        raise AppError("Booking not found", 404)
    if booking["patient_id"] != patient_id:
        raise AppError("Forbidden", 403)
    until = review_window_end(booking)
    if until is None:
        raise AppError("You can review a visit once it's complete", 409)
    if _now() > until:
        raise AppError("Reviews are open for 14 days after a visit, and this one has closed", 409)

    values = _clean(fields)
    now = _now()
    try:
        row = supabase.table("reviews").insert({
            "booking_id": booking_id, "doctor_id": booking["doctor_id"], "patient_id": patient_id,
            **values, "editable_until": (now + EDIT_WINDOW).isoformat(),
        }).execute().data[0]
    except Exception as exc:                       # noqa: BLE001
        if "23505" in str(exc):
            raise AppError("You've already reviewed this visit", 409)
        raise
    audit.record(actor, "review", row["id"], "review_created",
                 metadata={"booking_id": booking_id, "overall": values["overall"]})
    return row


def edit(booking_id: str, patient_id: str, fields: dict, actor: dict) -> dict:
    review = fetch_one(supabase.table("reviews").select("*").eq("booking_id", booking_id))
    if not review or review["patient_id"] != patient_id:
        raise AppError("Review not found", 404)
    if _now() > _ts(review["editable_until"]):
        raise AppError("A review can be changed for 48 hours after it's posted", 409)
    values = _clean(fields)
    rows = (
        supabase.table("reviews").update({**values, "edited_at": _now().isoformat()})
        .eq("id", review["id"]).execute().data or []
    )
    if not rows:
        raise AppError("This review can no longer be edited", 409)
    # What it said before stays on record (spec §12.5: no invisible changes).
    audit.record(actor, "review", review["id"], "review_edited",
                 metadata={"before": {k: review.get(k) for k in _PATIENT_FIELDS}})
    return rows[0]


def for_booking(booking_id: str) -> Optional[dict]:
    return fetch_one(supabase.table("reviews").select("*").eq("booking_id", booking_id))


# ── What others see ──────────────────────────────────────────────────────────

def _summary(doctor: dict) -> dict:
    count = int(doctor.get("rating_count") or 0)
    shown = count >= MIN_REVIEWS_SHOWN
    return {
        "count": count,
        "overall": float(doctor["rating_avg"]) if shown and doctor.get("rating_avg") is not None else None,
        "is_new": not shown,
        "dimensions": {
            d: (float(doctor[f"rating_{d}"]) if shown and doctor.get(f"rating_{d}") is not None else None)
            for d in DIMENSIONS
        },
        "min_reviews_shown": MIN_REVIEWS_SHOWN,
        "explanation": "The average of up to the last 200 reviews from patients who completed a "
                       f"visit. Shown once a doctor has {MIN_REVIEWS_SHOWN} reviews.",
    }


def _month(timestamp) -> str:
    """The first of the month. An exact time lets a doctor match a review to the
    visit they did that day; marketplaces that promise anonymous reviews
    (Airbnb, Uber, Zocdoc) show the reviewee nothing finer than the aggregate."""
    parsed = datetime.fromisoformat(str(timestamp).replace("Z", "+00:00"))
    return parsed.replace(day=1, hour=0, minute=0, second=0, microsecond=0).isoformat()


def _public(review: dict) -> dict:
    """A review as anyone but its author sees it: never who wrote it, and never
    when to the day."""
    return {
        "id": review["id"],
        "overall": review["overall"],
        **{d: review.get(d) for d in DIMENSIONS},
        "comment": review.get("comment"),
        "created_at": _month(review["created_at"]),
        "edited": bool(review.get("edited_at")),
    }


def doctor_summary(doctor_id: str) -> dict:
    doctor = fetch_one(supabase.table("doctors").select(
        "rating_avg, rating_count, rating_professionalism, rating_communication, rating_punctuality"
    ).eq("id", doctor_id))
    if not doctor:
        raise AppError("Doctor not found", 404)
    return _summary(doctor)


def public_reviews(doctor_id: str, limit: int = 10) -> dict:
    """For the patient's view of a doctor: the summary and recent comments."""
    rows = (
        supabase.table("reviews").select("*")
        .eq("doctor_id", doctor_id).eq("status", "published").not_.is_("comment", "null")
        .order("created_at", desc=True).limit(limit).execute().data or []
    )
    return {**doctor_summary(doctor_id), "reviews": [_public(r) for r in rows]}


def doctor_view(doctor_id: str, limit: int = 50) -> dict:
    """The doctor's own: summary, every published review (anonymous), and
    which ones they've reported."""
    rows = (
        supabase.table("reviews").select("*")
        .eq("doctor_id", doctor_id).eq("status", "published")
        .order("created_at", desc=True).limit(limit).execute().data or []
    )
    reported = {
        r["review_id"]: r["status"] for r in (
            supabase.table("review_reports").select("review_id, status")
            .eq("reporter_id", doctor_id).execute().data or []
        )
    }
    return {
        **doctor_summary(doctor_id),
        "reviews": [{**_public(r), "report_status": reported.get(r["id"])} for r in rows],
    }


# ── Reports and moderation ───────────────────────────────────────────────────

def report(review_id: str, reporter: dict, reason: str, note: Optional[str]) -> dict:
    """A doctor flags a review about them. It stays up until ops decides."""
    if reason not in REPORT_REASONS:
        raise AppError("Say why: abusive, irrelevant, private details, or other", 400)
    review = fetch_one(supabase.table("reviews").select("id, doctor_id").eq("id", review_id))
    if not review or review["doctor_id"] != reporter["sub"]:
        raise AppError("Review not found", 404)
    try:
        row = supabase.table("review_reports").insert({
            "review_id": review_id, "reporter_role": reporter.get("role", "doctor"),
            "reporter_id": reporter["sub"], "reason": reason,
            "note": (note or "").strip()[:500] or None,
        }).execute().data[0]
    except Exception as exc:                       # noqa: BLE001
        if "23505" in str(exc):
            raise AppError("You've already reported this review", 409)
        raise
    audit.record(reporter, "review", review_id, "review_reported", reason=reason)
    return row


def moderation_queue(status: str = "reported", limit: int = 100) -> list[dict]:
    """For ops. 'reported': published reviews with an open report; 'hidden'."""
    if status == "hidden":
        rows = (supabase.table("reviews").select("*, doctors(name)").eq("status", "hidden")
                .order("hidden_at", desc=True).limit(limit).execute().data or [])
        return rows
    reports = (supabase.table("review_reports").select("*, reviews(*, doctors(name))")
               .eq("status", "open").order("created_at").limit(limit).execute().data or [])
    by_review: dict[str, dict] = {}
    for rep in reports:
        review = rep.pop("reviews", None) or {}
        entry = by_review.setdefault(review.get("id"), {**review, "reports": []})
        entry["reports"].append(rep)
    return list(by_review.values())


def moderate(review_id: str, action: str, reason: str, ops: dict) -> dict:
    """Hide a review (its open reports are upheld), restore a hidden one, or
    dismiss the reports and leave it up. Always with a reason, always audited."""
    reason = (reason or "").strip()
    if len(reason) < 5:
        raise AppError("Give the reason for this decision", 400)
    review = fetch_one(supabase.table("reviews").select("id, status").eq("id", review_id))
    if not review:
        raise AppError("Review not found", 404)
    now = _now().isoformat()
    if action == "hide":
        supabase.table("reviews").update({"status": "hidden", "hidden_reason": reason,
                                          "hidden_at": now, "hidden_by": ops.get("sub")}) \
            .eq("id", review_id).execute()
        resolved = "upheld"
    elif action == "restore":
        if review["status"] != "hidden":
            raise AppError("This review isn't hidden", 409)
        supabase.table("reviews").update({"status": "published", "hidden_reason": None,
                                          "hidden_at": None, "hidden_by": None}) \
            .eq("id", review_id).execute()
        resolved = None
    elif action == "dismiss":
        resolved = "dismissed"
    else:
        raise AppError("action must be hide, restore or dismiss", 400)
    if resolved:
        supabase.table("review_reports").update({"status": resolved, "resolved_at": now,
                                                 "resolved_by": ops.get("sub")}) \
            .eq("review_id", review_id).eq("status", "open").execute()
    audit.record(ops, "review", review_id, f"review_{action}", reason=reason)
    return fetch_one(supabase.table("reviews").select("*").eq("id", review_id))
