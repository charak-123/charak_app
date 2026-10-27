"""
Device token registration.

Sending lives in ``services/notifications.py`` — this router only records where a
user's device can be reached. ``send_push`` is kept as a thin alias so any caller
written against the old name still works.
"""
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends
from pydantic import BaseModel

from ..db import supabase
from ..deps import get_current_user
from ..errors import AppError
from ..services import notifications

router = APIRouter()


class RegisterTokenRequest(BaseModel):
    fcm_token: str
    platform: str  # "android" | "ios"


# A person rarely has more than two or three devices; anything beyond this is
# stale installs, and every extra token is a wasted FCM call per notification.
MAX_DEVICES = 10


@router.post("/register")
def register_token(body: RegisterTokenRequest, user: dict = Depends(get_current_user)):
    """
    Record that this device can reach this user. One row per device
    (device_tokens, migration 0023), so a doctor signed in on two phones gets
    pushes on both. A token re-registered by a different account moves to that
    account: a shared phone notifies whoever is signed in now.
    """
    if body.platform not in ("android", "ios"):
        raise AppError("platform must be 'android' or 'ios'", 400)
    token = body.fcm_token.strip()
    if not token:
        raise AppError("fcm_token is required", 400)
    if len(token) > 4096:
        raise AppError("fcm_token is too long", 400)
    role = "doctor" if user.get("role") == "doctor" else "patient"

    supabase.table("device_tokens").upsert({
        "owner_id": user["sub"],
        "owner_role": role,
        "token": token,
        "platform": body.platform,
        "last_seen_at": datetime.now(timezone.utc).isoformat(),
    }, on_conflict="token").execute()

    # Oldest devices beyond the cap are dropped.
    devices = (
        supabase.table("device_tokens").select("id")
        .eq("owner_id", user["sub"]).order("last_seen_at", desc=True)
        .execute().data or []
    )
    stale = [d["id"] for d in devices[MAX_DEVICES:]]
    if stale:
        supabase.table("device_tokens").delete().in_("id", stale).execute()

    # The single legacy column is still written, so a rollback to a backend
    # without device_tokens keeps reaching the latest device.
    table = "doctors" if role == "doctor" else "users"
    supabase.table(table).update({
        "fcm_token": token,
        "fcm_platform": body.platform,
    }).eq("id", user["sub"]).execute()

    return {"ok": True, "push_enabled": notifications.push_enabled()}


@router.delete("/register")
def unregister_token(token: Optional[str] = None, user: dict = Depends(get_current_user)):
    """
    Forget a device on sign-out, so the next person using it isn't sent someone
    else's medical notifications. With ``?token=`` only that device is
    forgotten. Without it (older app builds) every device of this account is,
    which is safe, if broader.
    """
    query = supabase.table("device_tokens").delete().eq("owner_id", user["sub"])
    if token:
        query = query.eq("token", token.strip())
    query.execute()

    table = "doctors" if user.get("role") == "doctor" else "users"
    clear = supabase.table(table).update({"fcm_token": None, "fcm_platform": None}) \
        .eq("id", user["sub"])
    if token:
        clear = clear.eq("fcm_token", token.strip())
    clear.execute()
    return {"ok": True}


def send_push(to_user_id: str, title: str, body: str, data: dict = None,
              role: str = "patient"):
    """Backwards-compatible alias for ``services.notifications.notify``."""
    return notifications.notify(to_user_id, role, "legacy.push", title, body, data)
