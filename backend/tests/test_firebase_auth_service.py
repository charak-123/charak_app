"""
Tests for services/firebase_auth.py's own logic — lazy SDK init and the
enabled()/verify() contract, independent of the /auth/firebase route.
"""
import importlib
from unittest.mock import MagicMock, patch

from app.services import firebase_auth as fb


def _reset():
    """The module caches _app/_init_failed across calls; each test needs a
    clean slate rather than whatever a previous test left behind."""
    fb._app = None
    fb._init_failed = False


def test_disabled_when_no_credential_is_configured():
    _reset()
    with patch("app.services.firebase_auth.FIREBASE_ADMIN_CREDENTIALS_JSON", ""):
        assert fb.enabled() is False


def test_enabled_when_init_succeeds():
    _reset()
    with patch("app.services.firebase_auth.FIREBASE_ADMIN_CREDENTIALS_JSON", '{"type": "service_account"}'), \
         patch("app.services.firebase_auth.credentials.Certificate", return_value=MagicMock()), \
         patch("app.services.firebase_auth.firebase_admin.initialize_app", return_value=MagicMock()):
        assert fb.enabled() is True


def test_a_bad_credential_disables_rather_than_crashes():
    """Malformed JSON or a bad key must not take the whole process down on
    import/first use — it should behave exactly like 'not configured'."""
    _reset()
    with patch("app.services.firebase_auth.FIREBASE_ADMIN_CREDENTIALS_JSON", "not-json"):
        assert fb.enabled() is False


def test_verify_raises_when_not_configured():
    _reset()
    with patch("app.services.firebase_auth.FIREBASE_ADMIN_CREDENTIALS_JSON", ""):
        try:
            fb.verify("sometoken")
            assert False, "expected FirebaseTokenError"
        except fb.FirebaseTokenError:
            pass


def test_verify_wraps_sdk_errors():
    _reset()
    with patch("app.services.firebase_auth.FIREBASE_ADMIN_CREDENTIALS_JSON", '{"type": "service_account"}'), \
         patch("app.services.firebase_auth.credentials.Certificate", return_value=MagicMock()), \
         patch("app.services.firebase_auth.firebase_admin.initialize_app", return_value=MagicMock()), \
         patch("app.services.firebase_auth.firebase_auth_sdk.verify_id_token", side_effect=ValueError("expired")):
        try:
            fb.verify("sometoken")
            assert False, "expected FirebaseTokenError"
        except fb.FirebaseTokenError:
            pass


def test_verify_returns_claims_on_success():
    _reset()
    claims = {"sub": "fb-1", "firebase": {"sign_in_provider": "google.com"}}
    with patch("app.services.firebase_auth.FIREBASE_ADMIN_CREDENTIALS_JSON", '{"type": "service_account"}'), \
         patch("app.services.firebase_auth.credentials.Certificate", return_value=MagicMock()), \
         patch("app.services.firebase_auth.firebase_admin.initialize_app", return_value=MagicMock()), \
         patch("app.services.firebase_auth.firebase_auth_sdk.verify_id_token", return_value=claims):
        assert fb.verify("sometoken") == claims
