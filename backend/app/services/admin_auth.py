"""
Per-admin accounts with mandatory TOTP.

Replaces the single shared ADMIN_PASSWORD: each row in `admin_users`
(migration 0018) is one person, with a bcrypt password hash and a TOTP secret.
There is no HTTP endpoint that creates an admin account — that surface would
let anyone who could reach the API mint themselves ops access. Accounts are
created with `scripts/create_admin.py`, which talks to Supabase directly with
the service-role key, the same way a `createsuperuser`-style script would.

Login is a single endpoint called 1 or 2 times:

1. POST /admin/login {email, password} — password alone is never enough.
   * Wrong email/password: 401, generic message (don't reveal which was wrong).
   * Correct, and TOTP already enrolled: 428 {"next": "totp"} — resubmit with
     totp_code.
   * Correct, and this is the account's first login (just created by the
     script): 428 {"next": "totp_setup", "provisioning_uri": ...} — the admin
     scans the QR code in their authenticator app, then resubmits with the
     6-digit code it generates. That same call both verifies the code and
     flips totp_enabled on, so enrollment and first login are one step.
2. POST /admin/login {email, password, totp_code} — verifies the code against
   the stored secret (or, if not yet enrolled, confirms it and enrolls) and
   issues the session JWT.

No separate "pending session" state is kept between step 1 and step 2; both
calls re-verify the password, which is cheap and means there's no setup token
to expire, leak, or clean up.
"""
from __future__ import annotations

import logging
from datetime import datetime, timezone
from typing import Optional

import bcrypt
import pyotp

from ..db import supabase

logger = logging.getLogger(__name__)

_ISSUER = "Charak Admin"


class AdminAuthError(Exception):
    """Carries a status code distinct from AppError's so routes can tell apart
    'wrong credentials' (401) from 'need another step' (428) cleanly."""
    def __init__(self, message: str, status_code: int, **extra):
        self.message = message
        self.status_code = status_code
        self.extra = extra
        super().__init__(message)


def _get_admin(email: str) -> Optional[dict]:
    rows = (
        supabase.table("admin_users")
        .select("id, email, password_hash, totp_secret, totp_enabled")
        .eq("email", email.strip().lower())
        .execute()
        .data
    )
    return rows[0] if rows else None


def authenticate(email: str, password: str, totp_code: Optional[str]) -> dict:
    """
    Returns the admin row on full success. Raises AdminAuthError at any other
    point — bad credentials (401) or "submit the next step" (428).
    """
    admin = _get_admin(email)
    # Hash a dummy password even when the email doesn't exist, so a login
    # attempt against an unknown address takes the same time as a wrong
    # password against a real one — the response time itself must not reveal
    # which emails have accounts.
    stored_hash = admin["password_hash"] if admin else bcrypt.hashpw(b"x", bcrypt.gensalt())
    password_ok = bcrypt.checkpw(password.encode(), stored_hash if isinstance(stored_hash, bytes) else stored_hash.encode())

    if not admin or not password_ok:
        raise AdminAuthError("Invalid email or password", 401)

    if not admin["totp_enabled"]:
        # First login after the account was created by the script. The secret
        # already exists (the script generates it up front); this step shows
        # it as a QR code and the next call both verifies and enrolls.
        if not totp_code:
            uri = pyotp.TOTP(admin["totp_secret"]).provisioning_uri(
                name=admin["email"], issuer_name=_ISSUER
            )
            raise AdminAuthError(
                "Set up two-factor authentication to finish signing in.",
                428,
                next="totp_setup",
                provisioning_uri=uri,
            )
        if not pyotp.TOTP(admin["totp_secret"]).verify(totp_code, valid_window=1):
            raise AdminAuthError("Invalid code. Check your authenticator app and try again.", 401)
        supabase.table("admin_users").update({"totp_enabled": True}) \
            .eq("id", admin["id"]).execute()
        admin["totp_enabled"] = True
    else:
        if not totp_code:
            raise AdminAuthError("Enter your two-factor code.", 428, next="totp")
        if not pyotp.TOTP(admin["totp_secret"]).verify(totp_code, valid_window=1):
            raise AdminAuthError("Invalid code. Check your authenticator app and try again.", 401)

    try:
        supabase.table("admin_users").update(
            {"last_login_at": datetime.now(timezone.utc).isoformat()}
        ).eq("id", admin["id"]).execute()
    except Exception as exc:  # pragma: no cover
        logger.error("could not record last_login_at for admin %s: %s", admin["id"], exc)

    return admin
