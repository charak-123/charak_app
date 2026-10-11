"""
Tests for Firebase ID token sign-in (POST /auth/firebase) — a separate path
from Google Sign-In (POST /auth/google, see test_google_auth.py), which
verifies a raw Google OAuth token rather than a Firebase one.
"""
from unittest.mock import patch

from fastapi.testclient import TestClient

from app.main import app
from app.services.firebase_auth import FirebaseTokenError
from tests.conftest import make_chain, make_supabase

AUTH_DB = "app.routers.auth.supabase"
ENABLED = "app.routers.auth.firebase_auth.enabled"
VERIFY  = "app.routers.auth.firebase_auth.verify"

client = TestClient(app)

GOOGLE_CLAIMS = {
    "sub": "fb-123",
    "email": "asha@example.com",
    "email_verified": True,
    "firebase": {"sign_in_provider": "google.com"},
}

PHONE_CLAIMS = {
    "sub": "fb-456",
    "phone_number": "+919876543210",
    "firebase": {"sign_in_provider": "phone"},
}


def _db(row):
    users = make_chain(list_data=[row])
    return make_supabase({"users": users, "doctors": make_chain(list_data=[row])}), users


def test_rejected_when_firebase_is_not_configured():
    with patch(ENABLED, return_value=False):
        res = client.post("/auth/firebase", json={"id_token": "t", "role": "patient"})
    assert res.status_code == 503


def test_an_invalid_token_is_a_401():
    with patch(ENABLED, return_value=True), patch(VERIFY, side_effect=FirebaseTokenError("bad")):
        res = client.post("/auth/firebase", json={"id_token": "t", "role": "patient"})
    assert res.status_code == 401


def test_an_unrecognised_provider_is_refused():
    claims = {"sub": "fb-1", "firebase": {"sign_in_provider": "anonymous"}}
    with patch(ENABLED, return_value=True), patch(VERIFY, return_value=claims):
        res = client.post("/auth/firebase", json={"id_token": "t", "role": "patient"})
    assert res.status_code == 401


def test_google_provider_with_unverified_email_is_refused():
    claims = {**GOOGLE_CLAIMS, "email_verified": False}
    with patch(ENABLED, return_value=True), patch(VERIFY, return_value=claims):
        res = client.post("/auth/firebase", json={"id_token": "t", "role": "patient"})
    assert res.status_code == 401


def test_the_account_is_keyed_by_firebase_uid():
    db, users = _db({"id": "usr-1"})
    with patch(ENABLED, return_value=True), patch(VERIFY, return_value=GOOGLE_CLAIMS), patch(AUTH_DB, db):
        res = client.post("/auth/firebase", json={"id_token": "t", "role": "patient"})
    assert res.status_code == 200
    payload = users.upsert.call_args
    assert payload.args[0]["firebase_uid"] == "fb-123"
    assert payload.args[0]["email"] == "asha@example.com"
    assert payload.kwargs["on_conflict"] == "firebase_uid"


def test_google_provider_never_writes_a_phone():
    db, users = _db({"id": "usr-1"})
    with patch(ENABLED, return_value=True), patch(VERIFY, return_value=GOOGLE_CLAIMS), patch(AUTH_DB, db):
        client.post("/auth/firebase", json={"id_token": "t", "role": "patient"})
    assert "phone" not in users.upsert.call_args.args[0]


def test_phone_provider_writes_the_confirmed_number_and_marks_it_verified():
    db, users = _db({"id": "usr-1"})
    with patch(ENABLED, return_value=True), patch(VERIFY, return_value=PHONE_CLAIMS), patch(AUTH_DB, db):
        res = client.post("/auth/firebase", json={"id_token": "t", "role": "patient"})
    assert res.status_code == 200
    payload = users.upsert.call_args.args[0]
    assert payload["firebase_uid"] == "fb-456"
    assert payload["phone"] == "+919876543210"
    assert payload["otp_verified"] is True


def test_phone_provider_never_writes_an_email():
    db, users = _db({"id": "usr-1"})
    with patch(ENABLED, return_value=True), patch(VERIFY, return_value=PHONE_CLAIMS), patch(AUTH_DB, db):
        client.post("/auth/firebase", json={"id_token": "t", "role": "patient"})
    assert "email" not in users.upsert.call_args.args[0]


def test_doctors_sign_in_against_the_doctors_table():
    users = make_chain(list_data=[{"id": "x"}])
    doctors = make_chain(list_data=[{"id": "doc-1"}])
    db = make_supabase({"users": users, "doctors": doctors})
    with patch(ENABLED, return_value=True), patch(VERIFY, return_value=GOOGLE_CLAIMS), patch(AUTH_DB, db):
        res = client.post("/auth/firebase", json={"id_token": "t", "role": "doctor"})
    assert res.status_code == 200
    doctors.upsert.assert_called_once()
    users.upsert.assert_not_called()


def test_rejects_an_unknown_role():
    res = client.post("/auth/firebase", json={"id_token": "t", "role": "nurse"})
    assert res.status_code == 422


# ── application_details on the profile step ───────────────────────────────────
# Supports the website registration's richer fields (see migration 0019) —
# tested here since this is the flow that actually needs it.

def test_profile_update_accepts_application_details():
    from app.routers.auth import _issue_jwt
    doctors = make_chain(list_data=[{"id": "doc-1"}])
    db = make_supabase({"doctors": doctors})
    with patch("app.routers.doctors.supabase", db):
        res = client.patch(
            "/doctors/me",
            json={"application_details": {"practitionerType": "yoga", "qualification": "RYT 200"}},
            headers={"Authorization": f"Bearer {_issue_jwt('doc-1', 'doctor')}"},
        )
    assert res.status_code == 200
    written = doctors.update.call_args[0][0]
    assert written["application_details"] == {"practitionerType": "yoga", "qualification": "RYT 200"}
