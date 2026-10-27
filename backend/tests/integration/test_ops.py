"""
Migration 0029 against real Postgres: admin roles, the legal review gate,
audited overrides, the health numbers and dead letters (plan Phase 7).
"""
import uuid
from datetime import datetime, timedelta, timezone

import pytest

from .conftest import AUTH


def _id() -> str:
    return str(uuid.uuid4())


def _paid(db, s, *, minutes_ago=30):
    start = datetime.now(timezone.utc) - timedelta(minutes=minutes_ago)
    return db.table("bookings").insert({
        "id": _id(), "patient_id": s["patient"]["id"], "doctor_id": s["doctor"]["id"],
        "channel": "online_consult", "scheduled_start": start.isoformat(), "status": "paid",
        "price_confirmed": 500, "duration_min": 15,
    }).execute().data[0]


# ── Roles ────────────────────────────────────────────────────────────────────

@pytest.mark.parametrize("role,path,method,allowed", [
    ("support", "/admin/bookings", "get", True),
    ("support", "/admin/incidents", "get", True),
    ("support", "/admin/refunds", "get", False),
    ("support", "/admin/health", "get", True),
    ("support", "/admin/policies", "get", False),
    ("support", "/admin/system/dead-letters", "get", False),
    ("finance", "/admin/refunds", "get", True),
    ("finance", "/admin/payouts/pending-summary", "get", False),   # mounted under /payouts, see below
    ("finance", "/admin/reviews", "get", False),
    ("ops_lead", "/admin/reviews", "get", True),
    ("ops_lead", "/admin/admins", "get", False),
    ("admin", "/admin/admins", "get", True),
])
def test_each_role_reaches_only_what_it_may(client_for, role, path, method, allowed):
    if path.startswith("/admin/payouts"):
        path = "/payouts/pending-summary"
        allowed = role in ("finance", "ops_lead", "admin")
    res = getattr(client_for(_id(), "ops", admin_role=role), method)(path, headers=AUTH)
    assert (res.status_code != 403) == allowed, (role, path, res.status_code, res.text)


def test_a_token_from_before_roles_is_least_privileged(client_for):
    """No admin_role claim (issued before 0029): support until they sign in again."""
    import time
    import jwt
    from .conftest import TEST_JWT_SECRET
    from fastapi.testclient import TestClient
    from app.main import app
    token = jwt.encode({"sub": _id(), "role": "ops", "iat": int(time.time()) - 5}, TEST_JWT_SECRET, algorithm="HS256")
    client_for(_id())                                              # applies the test secret
    c = TestClient(app, headers={"Authorization": f"Bearer {token}"})
    assert c.get("/admin/me", headers=AUTH).json()["role"] == "support"
    assert c.get("/admin/bookings", headers=AUTH).status_code == 200
    assert c.get("/admin/refunds", headers=AUTH).status_code == 403


def test_support_can_read_a_case_but_not_decide_it(seed, client_for, db):
    s = seed()
    b = _paid(db, s)
    inc = db.table("incidents").insert({
        "booking_id": b["id"], "doctor_id": s["doctor"]["id"], "patient_id": s["patient"]["id"],
        "type": "other", "reported_by_role": "patient"}).execute().data[0]
    support = client_for(_id(), "ops", admin_role="support")
    assert support.get("/admin/incidents", headers=AUTH).status_code == 200
    res = support.post(f"/admin/incidents/{inc['id']}/decide", headers=AUTH,
                       json={"status": "dismissed", "cause": "patient", "reason": "Patient joined late"})
    assert res.status_code == 403 and "support" in res.json()["error"]


def test_role_changes_are_audited_and_you_cant_demote_yourself(client_for, db):
    target = db.table("admin_users").insert({"email": f"a{_id()[:6]}@charak.care", "password_hash": "x"}) \
        .execute().data[0]
    assert target["role"] == "support"                             # new accounts start low
    me = _id()
    admin = client_for(me, "ops", admin_role="admin")
    res = admin.post(f"/admin/admins/{target['id']}/role", headers=AUTH,
                     json={"role": "ops_lead", "reason": "Runs the incident queue"})
    assert res.status_code == 200 and res.json()["role"] == "ops_lead"
    audit = db.table("audit_log").select("action, metadata").eq("entity_id", target["id"]).execute().data
    assert audit[0]["metadata"] == {"before": "support", "after": "ops_lead"}
    assert admin.post(f"/admin/admins/{me}/role", headers=AUTH,
                      json={"role": "support", "reason": "testing self demotion"}).status_code in (404, 409)


# ── The legal review gate ────────────────────────────────────────────────────

def test_a_new_policy_applies_only_once_approved(client_for, db, seed):
    s = seed()
    patient = client_for(s["patient"]["id"])
    before = patient.get("/legal/cancellation-policy?channel=online_consult", headers=AUTH).json()
    new = db.table("policies").insert({
        "kind": "cancellation", "channel": "online_consult", "version": f"t-{_id()[:6]}",
        "rules": [{"when": {"minutes_before_start_lt": 15}, "refund_pct": 0}, {"when": {}, "refund_pct": 100}],
        "summary": "Free until 15 minutes before.", "effective_from": datetime.now(timezone.utc).isoformat(),
    }).execute().data[0]
    still = patient.get("/legal/cancellation-policy?channel=online_consult", headers=AUTH).json()
    assert still["version"] == before["version"]                    # not reviewed yet

    admin = client_for(_id(), "ops", admin_role="admin")
    listed = admin.get("/admin/policies", headers=AUTH).json()
    assert any(p["id"] == new["id"] and not p["policy_approvals"] for p in listed["policies"])
    assert client_for(_id(), "ops", admin_role="ops_lead").post(
        f"/admin/policies/{new['id']}/approve", headers=AUTH, json={"approved_by": "Me"}).status_code == 403
    res = admin.post(f"/admin/policies/{new['id']}/approve", headers=AUTH,
                     json={"approved_by": "Founder; counsel review", "note": "D3 decided"})
    assert res.status_code == 201
    assert admin.post(f"/admin/policies/{new['id']}/approve", headers=AUTH,
                      json={"approved_by": "Again"}).status_code == 409
    now = patient.get("/legal/cancellation-policy?channel=online_consult", headers=AUTH).json()
    assert now["version"] == new["version"]
    # The SQL picker (used when a booking row is stamped) agrees.
    assert db.rpc("current_cancellation_policy", {"p_channel": "online_consult"}).execute().data == new["id"]
    with pytest.raises(Exception):
        db.table("policy_approvals").delete().eq("policy_id", new["id"]).execute()


def test_an_unapproved_legal_document_is_not_asked_for(client_for, db, seed):
    s = seed()
    doc = db.table("legal_documents").insert({
        "type": "tos", "version": f"2099-{_id()[:4]}", "title": "Terms of Use", "url": "https://x/terms",
        "audience": ["patient", "doctor"], "material": True}).execute().data[0]
    patient = client_for(s["patient"]["id"])
    current = {d["type"]: d["version"] for d in patient.get("/legal/current", headers=AUTH).json()["documents"]}
    assert current["tos"] != doc["version"]
    client_for(_id(), "ops", admin_role="admin").post(
        f"/admin/legal-documents/{doc['id']}/approve", headers=AUTH, json={"approved_by": "Counsel"})
    current = {d["type"]: d["version"] for d in patient.get("/legal/current", headers=AUTH).json()["documents"]}
    assert current["tos"] == doc["version"]


# ── Overrides ────────────────────────────────────────────────────────────────

def test_a_stuck_booking_is_corrected_through_the_state_machine_with_a_reason(seed, client_for, db):
    s = seed()
    b = _paid(db, s)
    lead = client_for(_id(), "ops", admin_role="ops_lead")
    assert lead.post(f"/admin/bookings/{b['id']}/override", headers=AUTH, json={
        "action": "complete", "expected_status": "paid", "reason": "short"}).status_code == 422
    assert lead.post(f"/admin/bookings/{b['id']}/override", headers=AUTH, json={
        "action": "complete", "expected_status": "in_progress",
        "reason": "Doctor confirmed the visit by phone"}).status_code == 409
    res = lead.post(f"/admin/bookings/{b['id']}/override", headers=AUTH, json={
        "action": "complete", "expected_status": "paid", "reason": "Doctor confirmed the visit by phone"})
    assert res.status_code == 200, res.text
    row = db.table("bookings").select("status, completion_source, completed_at").eq("id", b["id"]).execute().data[0]
    assert (row["status"], row["completion_source"]) == ("completed", "ops") and row["completed_at"]
    ev = db.table("booking_events").select("event, actor_role, metadata").eq("booking_id", b["id"]) \
        .eq("event", "ops_complete").execute().data[0]
    assert ev["actor_role"] == "ops" and ev["metadata"]["reason"].startswith("Doctor confirmed")
    audit = db.table("audit_log").select("action, metadata").eq("entity_id", b["id"]).execute().data[0]
    assert audit["action"] == "override_complete" and audit["metadata"]["before"]["status"] == "paid"
    # Support can't.
    b2 = _paid(db, s, minutes_ago=90)
    assert client_for(_id(), "ops", admin_role="support").post(f"/admin/bookings/{b2['id']}/override", headers=AUTH, json={
        "action": "complete", "expected_status": "paid", "reason": "Doctor confirmed the visit"}).status_code == 403


def test_a_mistaken_start_is_reverted_and_nothing_else_is_possible(seed, client_for, db):
    s = seed()
    b = _paid(db, s)
    db.table("bookings").update({"status": "in_progress"}).eq("id", b["id"]).execute()
    lead = client_for(_id(), "ops", admin_role="ops_lead")
    res = lead.post(f"/admin/bookings/{b['id']}/override", headers=AUTH, json={
        "action": "revert", "expected_status": "in_progress", "reason": "Doctor tapped start by mistake"})
    assert res.status_code == 200 and res.json()["status"] == "paid"
    # Revert from paid isn't a thing.
    assert lead.post(f"/admin/bookings/{b['id']}/override", headers=AUTH, json={
        "action": "revert", "expected_status": "paid", "reason": "Trying an invalid move"}).status_code == 400


# ── Health and dead letters ──────────────────────────────────────────────────

def test_health_has_the_numbers_that_drive_action(seed, client_for, db):
    s = seed()
    _paid(db, s)
    h = client_for(_id(), "ops", admin_role="support").get("/admin/health?days=30", headers=AUTH).json()
    assert {"bookings", "attendance", "incidents", "refunds", "prescriptions", "reviews", "money", "system"} <= set(h)
    assert h["bookings"]["requested"] >= 1
    assert client_for(_id(), "ops", admin_role="support").get("/admin/health?days=0", headers=AUTH).status_code == 400


def test_a_dead_job_can_be_seen_and_run_again(client_for, db):
    from app.services import jobs
    job_id = jobs.enqueue("booking.reminder", {"booking_id": _id(), "minutes": 15}, dedupe_key=_id())
    db.table("jobs").update({"status": "dead", "attempts": 8, "last_error": "boom"}).eq("id", job_id).execute()
    lead = client_for(_id(), "ops", admin_role="ops_lead")
    letters = lead.get("/admin/system/dead-letters", headers=AUTH).json()
    assert any(j["id"] == job_id and j["last_error"] == "boom" for j in letters["jobs"])
    res = lead.post(f"/admin/system/jobs/{job_id}/retry", headers=AUTH)
    assert res.status_code == 200 and res.json()["status"] == "queued" and res.json()["attempts"] == 0
    assert lead.post(f"/admin/system/jobs/{job_id}/retry", headers=AUTH).status_code == 404


# ── Directory ────────────────────────────────────────────────────────────────

def test_the_directory_lists_every_doctor_with_a_masked_phone(seed, client_for):
    s = seed()
    rows = client_for(_id(), "ops", admin_role="support").get("/admin/doctors", headers=AUTH)
    assert rows.status_code == 200, rows.text
    mine = next(d for d in rows.json() if d["id"] == s["doctor"]["id"])
    assert {"verification_status", "suspended", "created_at", "category_name", "rating_count"} <= set(mine)
    assert "categories" not in mine
    phone = s["doctor"].get("phone")
    if phone:
        assert mine["phone"] != phone and mine["phone"].endswith(phone[-2:])
