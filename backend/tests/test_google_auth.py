"""
Tests for Google Sign-In (POST /auth/google) and the phone captured afterwards
on the profile step.
"""
from unittest.mock import MagicMock, patch

from fastapi.testclient import TestClient
from postgrest.exceptions import APIError

from app.main import app
from tests.conftest import make_chain, make_supabase

AUTH_DB = "app.routers.auth.supabase"
VERIFY  = "app.routers.auth.google_id_token.verify_oauth2_token"
CLIENTS = "app.routers.auth.GOOGLE_CLIENT_IDS"

client = TestClient(app)

CLAIMS = {"sub": "g-123", "email": "asha@example.com", "email_verified": True}


def _db(row):
    users = make_chain(list_data=[row])
    return make_supabase({"users": users, "doctors": make_chain(list_data=[row])}), users


def test_rejected_when_no_client_id_is_configured():
    with patch(CLIENTS, []):
        res = client.post("/auth/google", json={"id_token": "t", "role": "patient"})
    assert res.status_code == 503


def test_an_invalid_token_is_a_401():
    with patch(CLIENTS, ["web"]), patch(VERIFY, side_effect=ValueError("bad aud")):
        res = client.post("/auth/google", json={"id_token": "t", "role": "patient"})
    assert res.status_code == 401


def test_the_token_is_checked_against_our_client_ids():
    db, _ = _db({"id": "usr-1"})
    with patch(CLIENTS, ["web"]), patch(VERIFY, return_value=CLAIMS) as verify, \
         patch(AUTH_DB, db):
        client.post("/auth/google", json={"id_token": "t", "role": "patient"})
    assert verify.call_args.kwargs["audience"] == ["web"]


def test_an_unverified_email_is_refused():
    with patch(CLIENTS, ["web"]), \
         patch(VERIFY, return_value={**CLAIMS, "email_verified": False}):
        res = client.post("/auth/google", json={"id_token": "t", "role": "patient"})
    assert res.status_code == 401


def test_the_account_is_keyed_by_google_sub_not_email():
    db, users = _db({"id": "usr-1"})
    with patch(CLIENTS, ["web"]), patch(VERIFY, return_value=CLAIMS), patch(AUTH_DB, db):
        res = client.post("/auth/google", json={"id_token": "t", "role": "patient"})
    assert res.status_code == 200
    payload = users.upsert.call_args
    assert payload.args[0]["google_sub"] == "g-123"
    assert payload.kwargs["on_conflict"] == "google_sub"


def test_a_new_google_account_owes_the_profile_step():
    db, _ = _db({"id": "usr-1", "name": None, "phone": None})
    with patch(CLIENTS, ["web"]), patch(VERIFY, return_value=CLAIMS), patch(AUTH_DB, db):
        body = client.post("/auth/google", json={"id_token": "t", "role": "patient"}).json()
    assert body["is_new"] is True and body["token"]


def test_a_named_account_without_phone_still_owes_the_profile_step():
    db, _ = _db({"id": "usr-1", "name": "Asha", "phone": None})
    with patch(CLIENTS, ["web"]), patch(VERIFY, return_value=CLAIMS), patch(AUTH_DB, db):
        body = client.post("/auth/google", json={"id_token": "t", "role": "patient"}).json()
    assert body["is_new"] is True


def test_a_complete_account_goes_straight_in():
    db, _ = _db({"id": "usr-1", "name": "Asha", "phone": "+919876543210"})
    with patch(CLIENTS, ["web"]), patch(VERIFY, return_value=CLAIMS), patch(AUTH_DB, db):
        body = client.post("/auth/google", json={"id_token": "t", "role": "patient"}).json()
    assert body["is_new"] is False


def test_doctors_sign_in_against_the_doctors_table():
    users = make_chain(list_data=[{"id": "x"}])
    doctors = make_chain(list_data=[{"id": "doc-1"}])
    db = make_supabase({"users": users, "doctors": doctors})
    with patch(CLIENTS, ["web"]), patch(VERIFY, return_value=CLAIMS), patch(AUTH_DB, db):
        res = client.post("/auth/google", json={"id_token": "t", "role": "doctor"})
    assert res.status_code == 200
    doctors.upsert.assert_called_once()
    users.upsert.assert_not_called()


# ── phone on the profile step ─────────────────────────────────────────────────

def _patient_token():
    from app.routers.auth import _issue_jwt
    return {"Authorization": f"Bearer {_issue_jwt('usr-1', 'patient')}"}


def test_profile_phone_must_be_e164():
    res = client.patch("/users/me", json={"phone": "98765"}, headers=_patient_token())
    assert res.status_code == 422


def test_profile_phone_taken_by_another_account_is_a_409():
    users = make_chain()
    users.execute.side_effect = APIError({"code": "23505", "message": "dup"})
    db = make_supabase({"users": users})
    with patch("app.routers.users.supabase", db):
        res = client.patch("/users/me", json={"phone": "+919876543210"},
                           headers=_patient_token())
    assert res.status_code == 409
