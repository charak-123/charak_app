"""
Verifies Firebase Auth ID tokens.

Separate from Google's own OAuth verification (routers/auth.py's
google_login, using the google-auth library against GOOGLE_CLIENT_IDS) —
that path verifies a raw Google ID token the apps mint directly with the
google_sign_in package. This path verifies a *Firebase* ID token: the
website's Google sign-in already goes through Firebase (so its token looks
like this), and Firebase Phone Auth (the website today, both apps later)
issues the same shape of token regardless of provider. One verification path
here covers both, now and later.

The SDK is initialized lazily, once, from FIREBASE_ADMIN_CREDENTIALS_JSON —
the full service-account JSON as a string, not a file path, because Cloud Run
secrets mount as env vars.
"""
from __future__ import annotations

import json
import logging
from typing import Optional

import firebase_admin
from firebase_admin import auth as firebase_auth_sdk
from firebase_admin import credentials

from ..config import FIREBASE_ADMIN_CREDENTIALS_JSON

logger = logging.getLogger(__name__)

_app: Optional[firebase_admin.App] = None
_init_failed = False


def _get_app() -> Optional[firebase_admin.App]:
    global _app, _init_failed
    if _app is not None or _init_failed:
        return _app
    if not FIREBASE_ADMIN_CREDENTIALS_JSON:
        _init_failed = True
        return None
    try:
        cred = credentials.Certificate(json.loads(FIREBASE_ADMIN_CREDENTIALS_JSON))
        _app = firebase_admin.initialize_app(cred, name="charak-firebase-auth")
        return _app
    except Exception as exc:  # pragma: no cover — bad/missing credential at startup
        logger.error("could not initialize Firebase Admin SDK: %s", exc)
        _init_failed = True
        return None


def enabled() -> bool:
    return _get_app() is not None


class FirebaseTokenError(Exception):
    pass


def verify(id_token: str) -> dict:
    """
    Verifies a Firebase ID token and returns its decoded claims.

    Raises FirebaseTokenError on anything wrong with the token (expired,
    malformed, wrong project, revoked) or if no credential is configured.
    Never trust `sub`/`uid` from an unverified token — this is the only
    place in the codebase that is allowed to read one as real.
    """
    app = _get_app()
    if app is None:
        raise FirebaseTokenError("Firebase sign-in is not configured on this server")
    try:
        return firebase_auth_sdk.verify_id_token(id_token, app=app, check_revoked=True)
    except Exception as exc:
        raise FirebaseTokenError("Invalid or expired sign-in token") from exc
