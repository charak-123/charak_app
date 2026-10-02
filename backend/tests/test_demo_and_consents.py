"""Store-readiness: review demo-login and consent recording."""
from unittest.mock import patch

from fastapi.testclient import TestClient

from app.main import app
from tests.conftest import make_chain, make_supabase, patch_all_supabase

JWT = "app.deps.jwt"
PATIENT = {"sub": "pat-1", "role": "patient"}
AUTH = {"Authorization": "Bearer t"}


def test_demo_login_is_refused_unless_enabled():
    with patch("app.routers.auth.DEMO_LOGIN_ENABLED", False):
        res = TestClient(app).post("/auth/demo-login", json={"role": "patient"})
    assert res.status_code == 403


def test_demo_login_mints_a_session_when_enabled():
    db = make_supabase({"users": make_chain(list_data=[{"id": "demo-1", "name": "Demo Patient"}])})
    with patch("app.routers.auth.supabase", db), \
         patch("app.routers.auth.DEMO_LOGIN_ENABLED", True), \
         patch("app.routers.auth._issue_jwt", return_value="tok"):
        res = TestClient(app).post("/auth/demo-login", json={"role": "patient"})
    assert res.status_code == 200
    assert res.json()["token"] == "tok" and res.json()["is_new"] is False


def test_recording_a_consent_persists_type_and_version():
    db = make_supabase({"consents": make_chain(list_data=[{"id": "c-1", "type": "privacy"}])})
    with patch_all_supabase(db), patch(JWT) as jw:
        jw.decode.return_value = PATIENT
        res = TestClient(app).post(
            "/consents", headers=AUTH, json={"type": "privacy", "version": "2026-10-01"}
        )
    assert res.status_code == 201


def test_consent_type_is_validated():
    db = make_supabase({})
    with patch_all_supabase(db), patch(JWT) as jw:
        jw.decode.return_value = PATIENT
        res = TestClient(app).post(
            "/consents", headers=AUTH, json={"type": "nonsense", "version": "1"}
        )
    assert res.status_code == 422
