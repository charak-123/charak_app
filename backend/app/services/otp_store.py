"""
Durable OTP storage.

Replaces the in-process dict that used to live in ``routers/auth.py``. That
store broke in two ways the moment the API ran anywhere real: a second uvicorn
worker never saw codes issued by the first, and every deploy or restart
invalidated every in-flight login.

Codes are hashed (SHA-256 over code + phone as salt) so a database leak cannot
be replayed as a login. Rate limiting and attempt counting are enforced against
the same rows, so both are shared across workers too.
"""
import hashlib
import hmac
import random
import string
from datetime import datetime, timedelta, timezone
from typing import Optional

from ..db import supabase

OTP_TTL_SECONDS     = 600   # 10 minutes
MAX_SENDS_PER_HOUR  = 3
MAX_VERIFY_ATTEMPTS = 5
CODE_LENGTH         = 6


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _parse(ts) -> datetime:
    """Parse a Supabase timestamptz, tolerating microsecond precision and 'Z'."""
    if isinstance(ts, datetime):
        return ts if ts.tzinfo else ts.replace(tzinfo=timezone.utc)
    dt = datetime.fromisoformat(str(ts).replace("Z", "+00:00"))
    return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)


def hash_code(phone: str, code: str) -> str:
    """Salted hash — the phone number is the salt, so codes are not comparable
    across numbers even when they happen to be the same six digits."""
    return hashlib.sha256(f"{phone}:{code}".encode()).hexdigest()


def generate_code() -> str:
    return "".join(random.choices(string.digits, k=CODE_LENGTH))


def sends_in_last_hour(phone: str) -> int:
    since = (_now() - timedelta(hours=1)).isoformat()
    rows = (
        supabase.table("otp_codes")
        .select("id")
        .eq("phone", phone)
        .gte("created_at", since)
        .execute()
        .data
        or []
    )
    return len(rows)


def issue(phone: str, role: str) -> str:
    """Create and persist a fresh code, returning the plaintext to send by SMS."""
    code = generate_code()
    supabase.table("otp_codes").insert({
        "phone": phone,
        "role": role,
        "code_hash": hash_code(phone, code),
        "expires_at": (_now() + timedelta(seconds=OTP_TTL_SECONDS)).isoformat(),
    }).execute()
    return code


def latest_active(phone: str) -> Optional[dict]:
    """Most recent unconsumed code row for this phone, or None."""
    rows = (
        supabase.table("otp_codes")
        .select("*")
        .eq("phone", phone)
        .is_("consumed_at", "null")
        .order("created_at", desc=True)
        .limit(1)
        .execute()
        .data
        or []
    )
    return rows[0] if rows else None


class OTPError(Exception):
    """Raised with a patient-facing message; the router maps it to an AppError."""

    def __init__(self, message: str, status_code: int = 400):
        self.message = message
        self.status_code = status_code
        super().__init__(message)


def consume(phone: str, code: str) -> dict:
    """
    Verify a submitted code. Returns the row on success.

    Raises OTPError with a message safe to show the user on any failure, and
    counts the failed attempt so a code cannot be brute-forced.
    """
    row = latest_active(phone)
    if not row:
        raise OTPError("No OTP was sent to this number. Request a new one.")

    if _now() > _parse(row["expires_at"]):
        _mark_consumed(row["id"])
        raise OTPError("OTP expired. Request a new one.")

    if row["attempts"] >= MAX_VERIFY_ATTEMPTS:
        _mark_consumed(row["id"])
        raise OTPError("Too many incorrect attempts. Request a new OTP.")

    if not hmac.compare_digest(row["code_hash"], hash_code(phone, code)):
        attempts = row["attempts"] + 1
        supabase.table("otp_codes").update({"attempts": attempts}) \
            .eq("id", row["id"]).execute()
        remaining = MAX_VERIFY_ATTEMPTS - attempts
        if remaining <= 0:
            _mark_consumed(row["id"])
            raise OTPError("Too many incorrect attempts. Request a new OTP.")
        raise OTPError(f"Incorrect OTP. {remaining} attempt(s) remaining.")

    _mark_consumed(row["id"])
    return row


def _mark_consumed(otp_id: str) -> None:
    supabase.table("otp_codes").update({"consumed_at": _now().isoformat()}) \
        .eq("id", otp_id).execute()


def purge_expired() -> int:
    """Delete rows past their TTL. Called by the maintenance endpoint."""
    cutoff = (_now() - timedelta(hours=24)).isoformat()
    result = supabase.table("otp_codes").delete().lt("expires_at", cutoff).execute()
    return len(result.data or [])
