"""
Reviewing a visit (services/reviews.py, migration 0027).

    POST  /bookings/{id}/review   the patient's review: overall + optional
                                  sub-ratings + optional comment
    PATCH /bookings/{id}/review   changes, within 48 hours of posting
    GET   /bookings/{id}/review   the patient's own, or (anonymous) the doctor's

``/bookings/{id}/rate`` is what app builds from before 0027 call: one star
value and a comment. It writes a review with just the overall rating.
"""
from typing import Optional

from fastapi import APIRouter, BackgroundTasks, Depends
from pydantic import BaseModel, Field

from ..db import fetch_one, supabase
from ..deps import get_current_user, require_patient
from ..errors import AppError
from ..services import notifications, reviews

router = APIRouter()


class ReviewBody(BaseModel):
    overall: int = Field(ge=1, le=5)
    professionalism: Optional[int] = Field(default=None, ge=1, le=5)
    communication: Optional[int] = Field(default=None, ge=1, le=5)
    punctuality: Optional[int] = Field(default=None, ge=1, le=5)
    comment: Optional[str] = Field(default=None, max_length=1000)


def _shape(review: Optional[dict], viewer_is_patient: bool) -> Optional[dict]:
    if review is None:
        return None
    out = {k: review.get(k) for k in ("id", "overall", *reviews.DIMENSIONS, "comment", "status",
                                      "created_at", "edited_at", "editable_until")}
    # Older patient app builds read `stars`.
    out["stars"] = review["overall"]
    if not viewer_is_patient:
        out.pop("editable_until", None)
    return out


@router.post("/{booking_id}/review", status_code=201)
def create_review(booking_id: str, body: ReviewBody, background: BackgroundTasks,
                  user: dict = Depends(require_patient)):
    row = reviews.create(booking_id, user["sub"], body.model_dump(), user)
    notifications.rating_received(row["doctor_id"], row["overall"], booking_id, background)
    return _shape(row, True)


@router.patch("/{booking_id}/review")
def edit_review(booking_id: str, body: ReviewBody, user: dict = Depends(require_patient)):
    return _shape(reviews.edit(booking_id, user["sub"], body.model_dump(), user), True)


@router.get("/{booking_id}/review")
def get_review(booking_id: str, user: dict = Depends(get_current_user)):
    booking = fetch_one(supabase.table("bookings")
                        .select("patient_id, doctor_id, status, completed_at, scheduled_start")
                        .eq("id", booking_id))
    if not booking:
        raise AppError("Booking not found", 404)
    if user["sub"] not in (booking["patient_id"], booking["doctor_id"]):
        raise AppError("Forbidden", 403)
    is_patient = user["sub"] == booking["patient_id"]
    review = reviews.for_booking(booking_id)
    if review and not is_patient and review["status"] == "hidden":
        review = None
    until = reviews.review_window_end(booking)
    return {
        # Reviews are anonymous: a doctor knows which patient each booking was,
        # so handing them the review by booking would name the author. They see
        # reviews only in the doctor-wide list (reviews.doctor_view).
        "review": _shape(review, True) if is_patient else None,
        # Whether the patient can still write one, and until when.
        "can_review": is_patient and review is None and until is not None
                      and until > reviews._now(),
        "review_until": until.isoformat() if until and is_patient else None,
    }


# ── Older app builds ─────────────────────────────────────────────────────────

class RatingCreate(BaseModel):
    stars: int
    comment: str | None = None


@router.post("/{booking_id}/rate", status_code=201)
def rate_booking(booking_id: str, body: RatingCreate, background: BackgroundTasks,
                 user: dict = Depends(get_current_user)):
    if not 1 <= body.stars <= 5:
        raise AppError("Stars must be between 1 and 5", 400)
    if user.get("role") != "patient":
        raise AppError("Forbidden", 403)
    row = reviews.create(booking_id, user["sub"], {"overall": body.stars, "comment": body.comment}, user)
    notifications.rating_received(row["doctor_id"], row["overall"], booking_id, background)
    return _shape(row, True)


@router.get("/{booking_id}/rate")
def get_rating(booking_id: str, user: dict = Depends(get_current_user)):
    return get_review(booking_id, user)["review"]
