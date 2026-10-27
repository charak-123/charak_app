"""
Migration 0027 against real Postgres: who can review, the windows, the
aggregate (D15), and moderation (spec §12.5, §12.8).
"""
import uuid
from datetime import datetime, timedelta, timezone

import pytest

from .conftest import AUTH


def _id() -> str:
    return str(uuid.uuid4())


def _completed(db, s, *, days_ago=1, patient=None):
    at = datetime.now(timezone.utc) - timedelta(days=days_ago)
    return db.table("bookings").insert({
        "id": _id(), "patient_id": (patient or s["patient"])["id"], "doctor_id": s["doctor"]["id"],
        "channel": "online_consult", "scheduled_start": at.isoformat(), "status": "completed",
        "completed_at": at.isoformat(), "price_confirmed": 500,
    }).execute().data[0]


def _review(client, booking_id, **body):
    return client.post(f"/bookings/{booking_id}/review", json={"overall": 5, **body}, headers=AUTH)


def _doctor(db, s):
    return db.table("doctors").select("rating_avg, rating_count, rating_communication") \
        .eq("id", s["doctor"]["id"]).execute().data[0]


def test_only_the_patient_of_a_completed_visit_reviews_it_once(seed, client_for, db):
    s = seed()
    b = _completed(db, s)
    patient = client_for(s["patient"]["id"])
    assert _review(client_for(s["other_patient"]["id"]), b["id"]).status_code == 403
    assert _review(client_for(s["doctor"]["id"], "doctor"), b["id"]).status_code == 403

    res = _review(patient, b["id"], communication=4, comment="Explained everything clearly.")
    assert res.status_code == 201, res.text
    assert _review(patient, b["id"]).status_code == 409

    paid = db.table("bookings").insert({
        "id": _id(), "patient_id": s["patient"]["id"], "doctor_id": s["doctor"]["id"],
        "channel": "online_consult", "status": "paid", "price_confirmed": 500,
        "scheduled_start": (datetime.now(timezone.utc) + timedelta(days=1)).isoformat(),
    }).execute().data[0]
    assert _review(patient, paid["id"]).status_code == 409


def test_reviews_close_after_14_days(seed, client_for, db):
    s = seed()
    old = _completed(db, s, days_ago=15)
    res = _review(client_for(s["patient"]["id"]), old["id"])
    assert res.status_code == 409 and "14 days" in res.json()["error"]


def test_a_review_can_be_edited_for_48_hours_and_the_old_text_is_kept(seed, client_for, db):
    s = seed()
    b = _completed(db, s)
    patient = client_for(s["patient"]["id"])
    rid = _review(patient, b["id"], overall=2, comment="Late.").json()["id"]
    res = patient.patch(f"/bookings/{b['id']}/review", json={"overall": 4, "comment": "Late, but thorough."},
                        headers=AUTH)
    assert res.status_code == 200 and res.json()["overall"] == 4
    audit = db.table("audit_log").select("action, metadata").eq("entity_id", rid) \
        .eq("action", "review_edited").execute().data
    assert audit[0]["metadata"]["before"]["comment"] == "Late."

    # Who wrote it and about what can't change, and nothing is deleted.
    with pytest.raises(Exception):
        db.table("reviews").update({"booking_id": _id()}).eq("id", rid).execute()
    with pytest.raises(Exception):
        db.table("reviews").delete().eq("id", rid).execute()


def test_an_edit_after_the_window_is_refused(seed, client_for, db):
    s = seed()
    b = _completed(db, s)
    # Written 3 days ago, so its window has closed.
    created = datetime.now(timezone.utc) - timedelta(days=3)
    db.table("reviews").insert({
        "booking_id": b["id"], "doctor_id": s["doctor"]["id"], "patient_id": s["patient"]["id"],
        "overall": 3, "editable_until": (created + timedelta(hours=48)).isoformat(),
        "created_at": created.isoformat()}).execute()
    res = client_for(s["patient"]["id"]).patch(f"/bookings/{b['id']}/review", json={"overall": 5}, headers=AUTH)
    assert res.status_code == 409
    with pytest.raises(Exception):
        db.table("reviews").update({"overall": 5}).eq("booking_id", b["id"]).execute()


def test_a_doctor_is_new_until_five_reviews_then_shows_the_average(seed, client_for, db):
    s = seed()
    patients = [db.table("users").insert({"id": _id(), "phone": f"+9193{_id().replace('-', '')[:8]}",
                                          "name": f"P{i}", "otp_verified": True}).execute().data[0]
                for i in range(5)]
    stars = [5, 4, 4, 3, 5]
    for i, (p, n) in enumerate(zip(patients[:4], stars[:4])):
        b = _completed(db, s, patient=p)
        _review(client_for(p["id"]), b["id"], overall=n, communication=4 if i % 2 else None)

    public = client_for(s["patient"]["id"]).get(f"/doctors/{s['doctor']['id']}/reviews", headers=AUTH).json()
    assert (public["count"], public["overall"], public["is_new"]) == (4, None, True)
    assert client_for(s["patient"]["id"]).get(f"/doctors/{s['doctor']['id']}", headers=AUTH) \
        .json()["rating_avg"] is None

    b = _completed(db, s, patient=patients[4])
    _review(client_for(patients[4]["id"]), b["id"], overall=stars[4], comment="Kind and on time.")
    row = _doctor(db, s)
    assert row["rating_count"] == 5 and float(row["rating_avg"]) == 4.2
    assert float(row["rating_communication"]) == 4.0          # blanks don't count
    public = client_for(s["patient"]["id"]).get(f"/doctors/{s['doctor']['id']}/reviews", headers=AUTH).json()
    assert (public["overall"], public["is_new"]) == (4.2, False)
    # Comments are shown, their authors never.
    assert public["reviews"][0]["comment"] == "Kind and on time."
    assert "patient_id" not in public["reviews"][0]


def test_a_reported_review_stays_up_until_ops_hides_it_with_a_reason(seed, client_for, db):
    s = seed()
    b = _completed(db, s)
    rid = _review(client_for(s["patient"]["id"]), b["id"], overall=1,
                  comment="Rude. His phone number is 98xxxxxx.").json()["id"]
    doctor = client_for(s["doctor"]["id"], "doctor")

    mine = doctor.get("/doctors/me/reviews", headers=AUTH).json()
    assert mine["reviews"][0]["id"] == rid and "patient_id" not in mine["reviews"][0]
    assert doctor.post(f"/doctors/me/reviews/{rid}/report", headers=AUTH,
                       json={"reason": "privacy", "note": "Contains a phone number"}).status_code == 201
    assert doctor.post(f"/doctors/me/reviews/{rid}/report", headers=AUTH,
                       json={"reason": "privacy"}).status_code == 409
    other = seed()
    assert client_for(other["doctor"]["id"], "doctor").post(
        f"/doctors/me/reviews/{rid}/report", headers=AUTH, json={"reason": "abusive"}).status_code == 404
    # Reporting alone changes nothing.
    assert _doctor(db, s)["rating_count"] == 1

    ops_id = _id()
    ops = client_for(ops_id, "ops")
    queue = ops.get("/admin/reviews", headers=AUTH).json()
    assert queue[0]["id"] == rid and queue[0]["reports"][0]["reason"] == "privacy"
    assert ops.post(f"/admin/reviews/{rid}/moderate", headers=AUTH,
                    json={"action": "hide", "reason": "x"}).status_code == 422
    res = ops.post(f"/admin/reviews/{rid}/moderate", headers=AUTH,
                   json={"action": "hide", "reason": "Shares a phone number"})
    assert res.status_code == 200 and res.json()["status"] == "hidden"
    assert _doctor(db, s)["rating_count"] == 0
    assert db.table("review_reports").select("status").eq("review_id", rid).execute().data[0]["status"] == "upheld"
    assert doctor.get("/doctors/me/reviews", headers=AUTH).json()["reviews"] == []

    ops.post(f"/admin/reviews/{rid}/moderate", headers=AUTH,
             json={"action": "restore", "reason": "Number was removed on appeal"})
    assert _doctor(db, s)["rating_count"] == 1
    actions = [r["action"] for r in db.table("audit_log").select("action").eq("entity_id", rid).execute().data]
    assert {"review_created", "review_reported", "review_hide", "review_restore"} <= set(actions)


def test_old_ratings_and_the_old_endpoint_become_reviews(seed, client_for, db):
    s = seed()
    b = _completed(db, s)
    res = client_for(s["patient"]["id"]).post(f"/bookings/{b['id']}/rate", headers=AUTH,
                                              json={"stars": 4, "comment": "Good"})
    assert res.status_code == 201 and res.json()["stars"] == 4
    got = client_for(s["patient"]["id"]).get(f"/bookings/{b['id']}/rate", headers=AUTH).json()
    assert got["stars"] == 4 and got["overall"] == 4
