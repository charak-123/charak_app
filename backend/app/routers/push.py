"""
Device token registration.

Sending lives in ``services/notifications.py`` — this router only records where a
user's device can be reached. ``send_push`` is kept as a thin alias so any caller
written against the old name still works.
"""
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


@router.post("/register")
def register_token(body: RegisterTokenRequest, user: dict = Depends(get_current_user)):
    """Store the FCM token for this user so notifications can reach their device."""
    if body.platform not in ("android", "ios"):
        raise AppError("platform must be 'android' or 'ios'", 400)
    if not body.fcm_token.strip():
        raise AppError("fcm_token is required", 400)

    table = "doctors" if user.get("role") == "doctor" else "users"
    supabase.table(table).update({
        "fcm_token": body.fcm_token.strip(),
        "fcm_platform": body.platform,
    }).eq("id", user["sub"]).execute()

    return {"ok": True, "push_enabled": notifications.push_enabled()}


@router.delete("/register")
def unregister_token(user: dict = Depends(get_current_user)):
    """Clear the token — called on logout so the next user of the device is not
    sent someone else's medical notifications."""
    table = "doctors" if user.get("role") == "doctor" else "users"
    supabase.table(table).update({
        "fcm_token": None,
        "fcm_platform": None,
    }).eq("id", user["sub"]).execute()
    return {"ok": True}


def send_push(to_user_id: str, title: str, body: str, data: dict = None,
              role: str = "patient"):
    """Backwards-compatible alias for ``services.notifications.notify``."""
    return notifications.notify(to_user_id, role, "legacy.push", title, body, data)
