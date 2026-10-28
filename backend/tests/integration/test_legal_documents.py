"""
Migrations 0030/0031 against real Postgres: legal documents carry their full
text, the database fingerprints it, people sign a version against that
fingerprint, and the latest approved version decides who is asked.

Test versions are named t-… so stack.sh's test_forget_test_versions() can
remove them (approvals are append-only, so nothing else can).
"""
import hashlib
import importlib.util
import uuid
from pathlib import Path

import pytest

from .conftest import AUTH

ROOT = Path(__file__).resolve().parents[3]


def _id() -> str:
    return str(uuid.uuid4())


def _publish():
    spec = importlib.util.spec_from_file_location("publish", ROOT / "docs" / "legal" / "publish.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@pytest.fixture
def forget(db):
    yield
    db.rpc("test_forget_test_versions", {}).execute()


def _doc(db, doc_type="tos", audience=("patient",), body="## One\n\nThe text.\n", approve=True, **extra):
    row = db.table("legal_documents").insert({
        "type": doc_type, "version": f"t-{_id()[:8]}", "title": "Test document",
        "url": "https://www.charak.care/terms", "audience": list(audience), "body": body,
        "summary": "A test.", "highlights": ["The point."], **extra,
    }).execute().data[0]
    if approve:
        db.table("legal_document_approvals").insert(
            {"document_id": row["id"], "approved_by": "Integration test"}).execute()
    return row


def test_the_database_sets_the_fingerprint_from_the_text(db, forget):
    body = "## Section\n\nWhat people sign.\n"
    row = _doc(db, body=body, sha256="not-the-real-one", approve=False)
    assert row["sha256"] == hashlib.sha256(body.encode()).hexdigest()


def test_the_published_documents_are_exactly_their_sources(db):
    """0031 was generated from docs/legal/2026-10-28: what's in the database
    is what's in the repo, byte for byte."""
    publish = _publish()
    for source in publish.documents("2026-10-28"):
        row = db.table("legal_documents").select("sha256, body, audience, highlights") \
            .eq("type", source["type"]).eq("version", "2026-10-28").execute().data[0]
        assert row["body"] == source["body"]
        assert row["sha256"] == publish.fingerprint(source["body"])
        assert row["audience"] == source["audience"] and row["highlights"] == source["highlights"]


def test_a_version_is_signed_against_its_fingerprint(seed, client_for, db, forget):
    s = seed()
    doc = _doc(db)
    patient = client_for(s["patient"]["id"])

    listed = {d["type"]: d for d in patient.get("/legal/current", headers=AUTH).json()["documents"]}
    tos = listed["tos"]
    assert (tos["version"], tos["has_text"], tos["required"], tos["accepted"]) == (doc["version"], True, True, False)
    assert tos["highlights"] == ["The point."] and "body" not in tos

    res = patient.post("/legal/accept", headers=AUTH, json={
        "documents": [{"type": "tos", "version": doc["version"]}], "method": "signup_checkbox"})
    assert res.status_code == 201, res.text
    signed = db.table("consents").select("document_sha256, method").eq("user_id", s["patient"]["id"]) \
        .eq("version", doc["version"]).execute().data
    assert signed == [{"document_sha256": doc["sha256"], "method": "signup_checkbox"}]

    again = {d["type"]: d for d in patient.get("/legal/current", headers=AUTH).json()["documents"]}["tos"]
    assert again["accepted"] and again["accepted_at"]


def test_the_latest_version_decides_who_is_asked(seed, client_for, db, forget):
    """Terms that became patients-only stop being asked of doctors, rather than
    doctors being held to the older version that named them."""
    s = seed()
    _doc(db, doc_type="tos", audience=("patient",))
    doctor = client_for(s["doctor"]["id"], "doctor")
    patient = client_for(s["patient"]["id"])
    assert "tos" not in {d["type"] for d in doctor.get("/legal/current", headers=AUTH).json()["documents"]}
    assert "tos" in {d["type"] for d in patient.get("/legal/current", headers=AUTH).json()["documents"]}


def test_each_role_signs_its_own_set(seed, client_for, db, forget):
    s = seed()
    _doc(db, doc_type="practitioner_terms", audience=("doctor",))
    _doc(db, doc_type="refund_policy", audience=("patient", "doctor"))
    doctor = client_for(s["doctor"]["id"], "doctor").get("/legal/current", headers=AUTH).json()
    patient = client_for(s["patient"]["id"]).get("/legal/current", headers=AUTH).json()
    assert [d["type"] for d in doctor["missing"]] == ["practitioner_terms", "privacy", "refund_policy"]
    assert [d["type"] for d in patient["missing"]] == ["tos", "privacy", "refund_policy"]
    # The Legal screen's order: the main agreement first.
    assert [d["type"] for d in doctor["documents"]][0] == "practitioner_terms"


def test_the_full_text_is_public_once_approved(client_for, db, forget):
    from fastapi.testclient import TestClient
    from app.main import app
    client_for(_id())                                              # applies the suite's settings
    anyone = TestClient(app)
    draft = _doc(db, body="## Draft\n\nNot yet.\n", approve=False)
    assert anyone.get(f"/legal/documents/tos?version={draft['version']}").status_code == 404

    approved = _doc(db, body="## Final\n\nThe agreed text.\n")
    res = anyone.get(f"/legal/documents/tos?version={approved['version']}")
    assert res.status_code == 200
    assert res.json()["body"] == "## Final\n\nThe agreed text.\n" and res.json()["sha256"] == approved["sha256"]
    assert anyone.get("/legal/documents/tos").json()["version"] == approved["version"]   # the current one
    assert anyone.get("/legal/documents/cookies").status_code == 404


def test_a_doctor_signs_before_accepting_when_switched_on(seed, client_for, db, forget):
    from app.services import app_config
    s = seed()
    doc = _doc(db, doc_type="practitioner_terms", audience=("doctor",))
    booking = db.table("bookings").insert({
        "id": _id(), "patient_id": s["patient"]["id"], "doctor_id": s["doctor"]["id"],
        "channel": "online_consult", "status": "requested", "price_confirmed": 500, "duration_min": 15,
        "scheduled_start": "2099-01-01T10:00:00+00:00",
    }).execute().data[0]
    doctor = client_for(s["doctor"]["id"], "doctor")
    db.table("app_config").update({"value": True}).eq("key", "require_legal_acceptance").execute()
    app_config.clear_cache()
    try:
        refused = doctor.patch(f"/bookings/{booking['id']}/accept", json={}, headers=AUTH)
        assert refused.status_code == 428
        assert "practitioner_terms" in {d["type"] for d in refused.json()["consent_required"]}

        needed = [{"type": d["type"], "version": d["version"]} for d in refused.json()["consent_required"]]
        assert doctor.post("/legal/accept", headers=AUTH, json={"documents": needed}).status_code == 201
        assert doctor.patch(f"/bookings/{booking['id']}/accept", json={}, headers=AUTH).status_code == 200
        signed = db.table("consents").select("document_sha256").eq("user_id", s["doctor"]["id"]) \
            .eq("type", "practitioner_terms").execute().data
        assert signed == [{"document_sha256": doc["sha256"]}]
    finally:
        db.table("app_config").update({"value": False}).eq("key", "require_legal_acceptance").execute()
        app_config.clear_cache()
