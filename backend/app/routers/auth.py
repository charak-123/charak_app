"""
Authentication: Google Sign-In, and phone + OTP.

Google Sign-In is the live path until DLT approval lets MSG91 deliver SMS; the
OTP endpoints stay so phone login can come back without a migration.

OTP state lives in the ``otp_codes`` table (see ``services/otp_store.py``), not
in process memory, so login survives restarts and works behind more than one
worker.

SMS delivery falls back to printing the code when MSG91_API_KEY is unset — the
only behaviour that changes when real credentials arrive.
"""
from datetime import datetime, timedelta, timezone

import httpx
from fastapi import APIRouter
from google.auth.transport import requests as google_requests
from google.oauth2 import id_token as google_id_token
from jose import jwt
from pydantic import BaseModel, field_validator

from ..config import (
    DEMO_LOGIN_ENABLED,
    GOOGLE_CLIENT_IDS,
    JWT_SECRET,
    MSG91_API_KEY,
    MSG91_SENDER_ID,
    MSG91_TEMPLATE_ID,
)
from ..db import supabase
from ..errors import AppError
from ..phone import normalize_e164
from ..services import otp_store, erasure

router = APIRouter()

TOKEN_TTL_DAYS = 30


class SendOTPRequest(BaseModel):
    phone: str  # E.164, e.g. "+919876543210"
    role: str   # "patient" | "doctor"

    @field_validator("phone")
    @classmethod
    def _check_phone(cls, v: str) -> str:
        return normalize_e164(v)

    @field_validator("role")
    @classmethod
    def _check_role(cls, v: str) -> str:
        if v not in ("patient", "doctor"):
            raise ValueError("role must be 'patient' or 'doctor'")
        return v


class VerifyOTPRequest(SendOTPRequest):
    code: str

    @field_validator("code")
    @classmethod
    def _check_code(cls, v: str) -> str:
        v = v.strip()
        if not v.isdigit() or len(v) != otp_store.CODE_LENGTH:
            raise ValueError(f"code must be {otp_store.CODE_LENGTH} digits")
        return v


def _issue_jwt(user_id: str, role: str) -> str:
    now = datetime.now(timezone.utc)
    return jwt.encode(
        {
            "sub": user_id,
            "role": role,
            "exp": now + timedelta(days=TOKEN_TTL_DAYS),
            "iat": now,
        },
        JWT_SECRET,
        algorithm="HS256",
    )


async def _send_sms(phone: str, code: str) -> None:
    if not MSG91_API_KEY:
        print(f"\n{'=' * 40}\n[OTP STUB]  {phone}  →  {code}\n{'=' * 40}\n")
        return

    async with httpx.AsyncClient(timeout=10) as client:
        res = await client.post(
            "https://api.msg91.com/api/v5/otp",
            headers={
                "authkey": MSG91_API_KEY,
                "accept": "application/json",
                "content-type": "application/json",
            },
            json={
                "template_id": MSG91_TEMPLATE_ID,
                "mobile": phone.lstrip("+"),
                "otp": code,
                "sender": MSG91_SENDER_ID,
            },
        )
        # A non-2xx means the patient will never receive the code, so surface it
        # rather than leaving them staring at an OTP screen that cannot succeed.
        if res.status_code >= 400:
            raise AppError("Could not send OTP right now. Please try again.", 502)


@router.post("/send-otp")
async def send_otp(req: SendOTPRequest):
    if otp_store.sends_in_last_hour(req.phone) >= otp_store.MAX_SENDS_PER_HOUR:
        raise AppError("Too many OTP requests. Try again in an hour.", 429)

    code = otp_store.issue(req.phone, req.role)
    await _send_sms(req.phone, code)
    return {"message": "OTP sent", "expires_in": otp_store.OTP_TTL_SECONDS}


@router.post("/verify-otp")
def verify_otp(req: VerifyOTPRequest):
    try:
        otp_row = otp_store.consume(req.phone, req.code)
    except otp_store.OTPError as exc:
        raise AppError(exc.message, exc.status_code)

    # The role is whatever the code was *issued* for, never what the verify call
    # claims. Trusting req.role let a code requested in the patient app be
    # redeemed as a doctor, minting a doctor-scoped token on any phone.
    role = otp_row.get("role") or req.role
    if role != req.role:
        raise AppError(
            "This code was sent for a different app. Request a new one here.", 400
        )

    table = "doctors" if role == "doctor" else "users"
    result = (
        supabase.table(table)
        .upsert({"phone": req.phone, "otp_verified": True}, on_conflict="phone")
        .execute()
    )
    if not result.data:
        raise AppError("Could not create your account. Please try again.", 500)

    return _session(result.data[0], role)


def _session(row: dict, role: str) -> dict:
    """The login response shared by every sign-in method."""
    # Logging back in during the grace window cancels a pending self-deletion.
    reactivated = False
    if role == "patient" and row.get("deleted_at"):
        erasure.reactivate_patient(row["id"])
        row = {**row, "deleted_at": None, "deletion_requested_at": None}
        reactivated = True

    return {
        "token": _issue_jwt(row["id"], role),
        "user": row,
        # A Google account arrives without a phone, so the profile step (name +
        # phone) is still owed until both are set.
        "is_new": not row.get("name") or not row.get("phone"),
        "reactivated": reactivated,
    }


class GoogleLoginRequest(BaseModel):
    id_token: str
    role: str

    @field_validator("role")
    @classmethod
    def _check_role(cls, v: str) -> str:
        if v not in ("patient", "doctor"):
            raise ValueError("role must be 'patient' or 'doctor'")
        return v


_google_request = google_requests.Request()


@router.post("/google")
def google_login(req: GoogleLoginRequest):
    """
    Sign in with a Google ID token minted by the app for our Web client id.

    The account is keyed by Google's `sub` (stable for the life of the Google
    account), never by email. A token for any other client id is rejected, so a
    token from some unrelated app cannot be replayed here.
    """
    if not GOOGLE_CLIENT_IDS:
        raise AppError("Google sign-in is not configured on this server", 503)
    try:
        claims = google_id_token.verify_oauth2_token(
            req.id_token, _google_request, audience=GOOGLE_CLIENT_IDS
        )
    except ValueError:
        raise AppError("Google sign-in failed. Please try again.", 401)
    if not claims.get("email_verified"):
        raise AppError("Your Google account's email is not verified.", 401)

    table = "doctors" if req.role == "doctor" else "users"
    result = (
        supabase.table(table)
        .upsert({"google_sub": claims["sub"], "email": claims.get("email")},
                on_conflict="google_sub")
        .execute()
    )
    if not result.data:
        raise AppError("Could not create your account. Please try again.", 500)
    return _session(result.data[0], req.role)


class DemoLoginRequest(BaseModel):
    role: str = "patient"

    @field_validator("role")
    @classmethod
    def _check_role(cls, v: str) -> str:
        if v not in ("patient", "doctor"):
            raise ValueError("role must be 'patient' or 'doctor'")
        return v


# Seeded demo accounts for store review. The numbers are reserved test values
# (ITU +99 range) that can never be a real Indian subscriber.
_DEMO_ACCOUNTS = {
    "patient": {"phone": "+999000000001", "name": "Demo Patient"},
    "doctor":  {"phone": "+999000000002", "name": "Demo Doctor"},
}


@router.post("/demo-login")
def demo_login(req: DemoLoginRequest):
    """
    Password-less login to a seeded demo account, for App Store / Play review.

    Disabled unless DEMO_LOGIN_ENABLED is set, so it cannot be used against a
    public production deployment. Reviewers can't receive the SMS OTP; this is
    how they get in. Put the role in the review notes.
    """
    if not DEMO_LOGIN_ENABLED:
        raise AppError("Demo login is not enabled on this deployment", 403)

    demo = _DEMO_ACCOUNTS[req.role]
    table = "doctors" if req.role == "doctor" else "users"
    result = (
        supabase.table(table)
        .upsert({"phone": demo["phone"], "name": demo["name"], "otp_verified": True},
                on_conflict="phone")
        .execute()
    )
    row = result.data[0]
    return {"token": _issue_jwt(row["id"], req.role), "user": row, "is_new": False}
