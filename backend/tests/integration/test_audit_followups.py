"""
Migration 0032 against real Postgres (audit follow-ups): the replacement remedy
refuses a visit that went ahead, the hold sweeper leaves a paid-for booking
alone, and a patient's review comments can be erased.
"""
import uuid
from datetime import datetime, timedelta, timezone

import pytest

from .conftest import AUTH
from .test_trust import _book_replacement, _paid, _refunds, _replacement_doctor, _report, _tomorrow


def _id() -> str:
    return str(uuid.uuid4())


def test_a_replacement_is_refused_once_the_original_visit_went_ahead(seed, client_for, db):
    """The doctor was late, not absent. The patient reported at the grace
    deadline, the doctor then did the visit; paying a second doctor from the
    same payment would fund two visits and leave the first credit standing."""
    s = seed()
    b, _ = _paid(db, s)
    patient = client_for(s["patient"]["id"])
    inc = _report(patient, b["id"], "doctor_not_joined").json()
    assert inc["remedy_eligible"] is True
    db.table("bookings").update({"status": "in_progress"}).eq("id", b["id"]).execute()

    other = _replacement_doctor(db, seed, price=500.00)
    res = _book_replacement(patient, inc["id"], other["doctor"]["id"], _tomorrow(10))

    assert res.status_code >= 400, res.text
    # Nothing moved: the original is untouched, its credit still payable, no new booking.
    assert db.table("bookings").select("status").eq("id", b["id"]).execute().data[0]["status"] == "in_progress"
    ledger = db.table("doctor_ledger_entries").select("status").eq("booking_id", b["id"]).execute().data
    assert [e["status"] for e in ledger] == ["payable"]
    assert db.table("bookings").select("id").eq("replaces_booking_id", b["id"]).execute().data == []


def test_the_hold_sweeper_does_not_cancel_a_booking_whose_fee_was_captured(seed, db):
    """A capture whose confirmation stopped half way leaves the booking
    `accepted` with a completed payment. Cancelling it would keep the money."""
    s = seed()
    past = (datetime.now(timezone.utc) - timedelta(minutes=30)).isoformat()
    start = (datetime.now(timezone.utc) + timedelta(days=2)).isoformat()

    def accepted(hour):
        return db.table("bookings").insert({
            "id": _id(), "patient_id": s["patient"]["id"], "doctor_id": s["doctor"]["id"],
            "channel": "online_consult", "status": "accepted", "price_confirmed": 500,
            "scheduled_start": (datetime.now(timezone.utc) + timedelta(days=2, hours=hour)).isoformat(),
            "duration_min": 15, "hold_expires_at": past,
        }).execute().data[0]

    captured, unpaid = accepted(0), accepted(3)
    db.table("payments").insert({
        "id": _id(), "booking_id": captured["id"], "amount": 500, "status": "completed",
        "type": "consult_fee", "razorpay_order_id": f"order_{_id()[:12]}",
        "razorpay_payment_id": f"pay_{_id()[:12]}", "method": "upi",
    }).execute()

    expired = db.rpc("expire_payment_holds", {}).execute().data
    assert unpaid["id"] in expired and captured["id"] not in expired
    status = lambda b: db.table("bookings").select("status").eq("id", b["id"]).execute().data[0]["status"]
    assert status(captured) == "accepted" and status(unpaid) == "cancelled"
    assert start  # (the unused local keeps the intent readable)


def test_a_patients_review_comments_can_be_erased_but_the_scores_stay(seed, db):
    s = seed()
    at = datetime.now(timezone.utc) - timedelta(days=20)
    booking = db.table("bookings").insert({
        "id": _id(), "patient_id": s["patient"]["id"], "doctor_id": s["doctor"]["id"],
        "channel": "online_consult", "scheduled_start": at.isoformat(), "status": "completed",
        "completed_at": at.isoformat(), "price_confirmed": 500,
    }).execute().data[0]
    review = db.table("reviews").insert({
        "id": _id(), "booking_id": booking["id"], "doctor_id": s["doctor"]["id"],
        "patient_id": s["patient"]["id"], "overall": 4, "comment": "Dr was kind to my mother Sunita.",
        "status": "published", "editable_until": (at + timedelta(hours=48)).isoformat(),
    }).execute().data[0]

    # The edit window is closed: an ordinary update of the text is still refused.
    with pytest.raises(Exception):
        db.table("reviews").update({"comment": "changed"}).eq("id", review["id"]).execute()

    erased = db.rpc("redact_patient_reviews", {"p_patient_id": s["patient"]["id"]}).execute().data
    assert erased == 1
    row = db.table("reviews").select("comment, overall").eq("id", review["id"]).execute().data[0]
    assert row["comment"] is None and row["overall"] == 4
    # The way back to editing scores is not left open by the erase.
    with pytest.raises(Exception):
        db.table("reviews").update({"overall": 1}).eq("id", review["id"]).execute()
