"""
Notifications router — the in-app inbox.

Every notifiable event is persisted by ``services/notifications.py`` whether or
not FCM is configured, so these endpoints work today and keep working as a
history once push is live.
"""
from datetime import datetime, timezone

from fastapi import APIRouter, Depends
from pydantic import BaseModel

from ..db import supabase
from ..deps import get_current_user
from ..errors import AppError
from ..services.notifications import push_enabled

router = APIRouter()


class RegisterTokenRequest(BaseModel):
    fcm_token: str
    platform: str  # "android" | "ios"


@router.get("/")
def list_notifications(unread_only: bool = False, limit: int = 50,
                       user: dict = Depends(get_current_user)):
    limit = max(1, min(limit, 200))
    query = (
        supabase.table("notifications")
        .select("*")
        .eq("recipient_id", user["sub"])
        .order("created_at", desc=True)
        .limit(limit)
    )
    if unread_only:
        query = query.is_("read_at", "null")
    return query.execute().data


@router.get("/unread-count")
def unread_count(user: dict = Depends(get_current_user)):
    rows = (
        supabase.table("notifications")
        .select("id")
        .eq("recipient_id", user["sub"])
        .is_("read_at", "null")
        .execute()
        .data
        or []
    )
    return {"count": len(rows), "push_enabled": push_enabled()}


@router.patch("/{notification_id}/read")
def mark_read(notification_id: str, user: dict = Depends(get_current_user)):
    rows = (
        supabase.table("notifications").select("recipient_id")
        .eq("id", notification_id).execute().data or []
    )
    if not rows:
        raise AppError("Notification not found", 404)
    if rows[0]["recipient_id"] != user["sub"]:
        raise AppError("Forbidden", 403)

    return (
        supabase.table("notifications")
        .update({"read_at": datetime.now(timezone.utc).isoformat()})
        .eq("id", notification_id)
        .execute()
        .data[0]
    )


@router.patch("/read-all")
def mark_all_read(user: dict = Depends(get_current_user)):
    result = (
        supabase.table("notifications")
        .update({"read_at": datetime.now(timezone.utc).isoformat()})
        .eq("recipient_id", user["sub"])
        .is_("read_at", "null")
        .execute()
    )
    return {"updated": len(result.data or [])}
