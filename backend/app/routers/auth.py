"""
Phone + OTP authentication.

OTP state lives in the ``otp_codes`` table (see ``services/otp_store.py``), not
in process memory, so login survives restarts and works behind more than one
worker.

SMS delivery falls back to printing the code when MSG91_API_KEY is unset — the
only behaviour that changes when real credentials arrive.
"""
from datetime import datetime, timedelta, timezone

import httpx
from fastapi import APIRouter
from jose import jwt
from pydantic import BaseModel, field_validator

from ..config import (
    JWT_SECRET,
    MSG91_API_KEY,
    MSG91_SENDER_ID,
    MSG91_TEMPLATE_ID,
)
from ..db import supabase
from ..errors import AppError
from ..services import otp_store

router = APIRouter()

TOKEN_TTL_DAYS = 30


class SendOTPRequest(BaseModel):
    phone: str  # E.164, e.g. "+919876543210"
    role: str   # "patient" | "doctor"

    @field_validator("phone")
    @classmethod
    def _check_phone(cls, v: str) -> str:
        v = v.strip().replace(" ", "")
        digits = v.lstrip("+")
        if not v.startswith("+") or not digits.isdigit() or not (10 <= len(digits) <= 15):
            raise ValueError("phone must be E.164, e.g. +919876543210")
        return v

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
        otp_store.consume(req.phone, req.code)
    except otp_store.OTPError as exc:
        raise AppError(exc.message, exc.status_code)

    table = "doctors" if req.role == "doctor" else "users"
    result = (
        supabase.table(table)
        .upsert({"phone": req.phone, "otp_verified": True}, on_conflict="phone")
        .execute()
    )
    if not result.data:
        raise AppError("Could not create your account. Please try again.", 500)

    row = result.data[0]
    return {
        "token": _issue_jwt(row["id"], req.role),
        "user": row,
        "is_new": not row.get("name"),
    }
