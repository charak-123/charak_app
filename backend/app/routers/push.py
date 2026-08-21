"""
FCM push notification router.

FCM is stubbed when GOOGLE_APPLICATION_CREDENTIALS or FCM_SERVER_KEY is not set.
Wire real credentials in Day 49.
"""
import os
import httpx

from fastapi import APIRouter, Depends
from pydantic import BaseModel

from ..db import supabase
from ..deps import get_current_user
from ..errors import AppError

router = APIRouter()

FCM_SERVER_KEY = os.getenv("FCM_SERVER_KEY", "")
FCM_SEND_URL = "https://fcm.googleapis.com/fcm/send"


class RegisterTokenRequest(BaseModel):
    fcm_token: str
    platform: str  # "android" | "ios"


@router.post("/register")
def register_token(body: RegisterTokenRequest, user: dict = Depends(get_current_user)):
    """Store FCM token for this user so we can push to them."""
    if body.platform not in ("android", "ios"):
        raise AppError("platform must be 'android' or 'ios'", 400)

    table = "doctors" if user.get("role") == "doctor" else "users"
    supabase.table(table).update({
        "fcm_token": body.fcm_token,
        "fcm_platform": body.platform,
    }).eq("id", user["sub"]).execute()

    return {"ok": True}


# ── Internal helper called by other routers ───────────────────────────────────

async def send_push(to_user_id: str, title: str, body: str, data: dict = None):
    """
    Look up the FCM token for a user (doctor or patient) and send a push.
    Silently skips if no token or FCM key not configured.
    """
    if not FCM_SERVER_KEY:
        print(f"[FCM STUB] to={to_user_id} title={title!r} body={body!r}")
        return

    # Try doctors first, then users
    row = supabase.table("doctors").select("fcm_token").eq("id", to_user_id).execute().data
    if not row:
        row = supabase.table("users").select("fcm_token").eq("id", to_user_id).execute().data
    if not row or not row[0].get("fcm_token"):
        return  # no token registered yet

    token = row[0]["fcm_token"]
    payload = {
        "to": token,
        "notification": {"title": title, "body": body},
        "data": data or {},
    }
    try:
        async with httpx.AsyncClient() as client:
            await client.post(
                FCM_SEND_URL,
                json=payload,
                headers={"Authorization": f"key={FCM_SERVER_KEY}"},
                timeout=5,
            )
    except Exception:
        pass  # push is best-effort; never let it crash the main flow
