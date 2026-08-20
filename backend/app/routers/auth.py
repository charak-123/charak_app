import random
import string
from datetime import datetime, timedelta, timezone

import httpx
from fastapi import APIRouter
from pydantic import BaseModel

from ..config import JWT_SECRET, MSG91_API_KEY, MSG91_SENDER_ID, MSG91_TEMPLATE_ID
from ..db import supabase
from ..errors import AppError
from jose import jwt

router = APIRouter()

# In-memory OTP store — replace with Redis/DB for multi-process prod
# Structure: {phone: {"code": str, "expires_at": datetime, "attempts": int, "sends": [datetime, ...]}}
_otp_store: dict = {}

OTP_TTL_SECONDS    = 600   # 10 minutes
MAX_SENDS_PER_HOUR = 3
MAX_VERIFY_ATTEMPTS = 5


class SendOTPRequest(BaseModel):
    phone: str  # E.164, e.g. "+919876543210"
    role: str   # "patient" | "doctor"


class VerifyOTPRequest(BaseModel):
    phone: str
    code: str
    role: str   # "patient" | "doctor"


def _issue_jwt(user_id: str, role: str) -> str:
    payload = {
        "sub": user_id,
        "role": role,
        "exp": datetime.now(timezone.utc) + timedelta(days=30),
        "iat": datetime.now(timezone.utc),
    }
    return jwt.encode(payload, JWT_SECRET, algorithm="HS256")


async def _send_sms(phone: str, code: str) -> None:
    if not MSG91_API_KEY:
        # Dev stub — OTP printed to console
        print(f"\n{'='*40}\n[OTP STUB]  {phone}  →  {code}\n{'='*40}\n")
        return

    async with httpx.AsyncClient() as client:
        await client.post(
            "https://api.msg91.com/api/v5/otp",
            headers={"authkey": MSG91_API_KEY, "accept": "application/json", "content-type": "application/json"},
            json={
                "template_id": MSG91_TEMPLATE_ID,
                "mobile": phone.lstrip("+"),
                "authkey": MSG91_API_KEY,
                "otp": code,
                "sender": MSG91_SENDER_ID,
            },
            timeout=10,
        )


@router.post("/send-otp")
async def send_otp(req: SendOTPRequest):
    now = datetime.now(timezone.utc)
    entry = _otp_store.get(req.phone, {})

    # Rate limit: max 3 sends per rolling hour
    sends = [t for t in entry.get("sends", []) if (now - t).total_seconds() < 3600]
    if len(sends) >= MAX_SENDS_PER_HOUR:
        raise AppError("Too many OTP requests. Try again in an hour.", 429)

    code = "".join(random.choices(string.digits, k=6))
    _otp_store[req.phone] = {
        "code": code,
        "expires_at": now + timedelta(seconds=OTP_TTL_SECONDS),
        "attempts": 0,
        "sends": sends + [now],
    }
    await _send_sms(req.phone, code)
    return {"message": "OTP sent"}


@router.post("/verify-otp")
async def verify_otp(req: VerifyOTPRequest):
    now = datetime.now(timezone.utc)
    entry = _otp_store.get(req.phone)

    if not entry:
        raise AppError("No OTP was sent to this number. Request a new one.", 400)
    if now > entry["expires_at"]:
        _otp_store.pop(req.phone, None)
        raise AppError("OTP expired. Request a new one.", 400)
    if entry["attempts"] >= MAX_VERIFY_ATTEMPTS:
        _otp_store.pop(req.phone, None)
        raise AppError("Too many incorrect attempts. Request a new OTP.", 400)
    if entry["code"] != req.code:
        entry["attempts"] += 1
        remaining = MAX_VERIFY_ATTEMPTS - entry["attempts"]
        raise AppError(f"Incorrect OTP. {remaining} attempt(s) remaining.", 400)

    # Correct — clean up
    _otp_store.pop(req.phone, None)

    # Upsert user/doctor record
    table = "doctors" if req.role == "doctor" else "users"
    result = (
        supabase.table(table)
        .upsert({"phone": req.phone, "otp_verified": True}, on_conflict="phone")
        .execute()
    )
    row = result.data[0]
    token = _issue_jwt(row["id"], req.role)

    is_new = not row.get("name")
    return {"token": token, "user": row, "is_new": is_new}
