from typing import Optional

from fastapi import APIRouter, Depends
from pydantic import BaseModel

from ..db import supabase
from ..deps import require_doctor
from ..errors import AppError
from ..services.availability import CHANNELS, get_available_slots, now_ist

router = APIRouter()


class ScheduleBlock(BaseModel):
    day_of_week: int   # 0 = Monday, 6 = Sunday
    start_time: str    # "09:00"
    end_time: str      # "17:00"


def _check_channel(channel: Optional[str]) -> None:
    if channel is not None and channel not in CHANNELS:
        raise AppError("channel must be online_consult or home_visit", 400)


@router.get("/me")
def get_my_schedules(channel: Optional[str] = None, user: dict = Depends(require_doctor)):
    """
    The doctor's weekly hours. With ``channel``, only that channel's: its own
    rows plus any from before migration 0035, which serve both. The hours
    editors read this so a doctor changing their hours starts from the ones
    they have, not from a blank week.
    """
    _check_channel(channel)
    rows = (
        supabase.table("doctor_schedules")
        .select("*")
        .eq("doctor_id", user["sub"])
        .order("day_of_week")
        .execute()
        .data
    ) or []
    if channel:
        rows = [r for r in rows if r.get("channel") in (None, channel)]
    return sorted(rows, key=lambda r: (r["day_of_week"], str(r["start_time"])))


def _validate(blocks: list[ScheduleBlock]) -> None:
    for b in blocks:
        if not 0 <= b.day_of_week <= 6:
            raise AppError("day_of_week must be 0 (Monday) to 6 (Sunday)", 400)
        if _minutes(b.end_time) <= _minutes(b.start_time):
            raise AppError(f"{b.start_time}–{b.end_time}: the end must be after the start", 400)


def _minutes(t: str) -> int:
    try:
        h, m = t.split(":")[:2]
        return int(h) * 60 + int(m)
    except (ValueError, AttributeError):
        raise AppError("Times must look like 09:30", 400)


def _replace(doctor_id: str, channel: str, blocks: list[ScheduleBlock]) -> dict:
    """
    Replace one channel's hours and leave the other channel's alone.

    Rows from before migration 0035 have no channel and served both. Saving
    this channel's hours replaces them here, so they are handed to the other
    channel first, where they still apply.
    """
    _validate(blocks)
    other = next(c for c in CHANNELS if c != channel)
    supabase.table("doctor_schedules").update({"channel": other}) \
        .eq("doctor_id", doctor_id).is_("channel", "null").execute()
    supabase.table("doctor_schedules").delete() \
        .eq("doctor_id", doctor_id).eq("channel", channel).execute()
    if blocks:
        rows = [{"doctor_id": doctor_id, "channel": channel, **b.model_dump()} for b in blocks]
        supabase.table("doctor_schedules").insert(rows).execute()
    return {"ok": True}


@router.put("/me")
def replace_schedules(blocks: list[ScheduleBlock], user: dict = Depends(require_doctor)):
    """Replace the online consultation hours."""
    return _replace(user["sub"], "online_consult", blocks)


@router.put("/me/home-visit")
def replace_home_visit_schedules(blocks: list[ScheduleBlock], user: dict = Depends(require_doctor)):
    """Replace the home-visit hours."""
    return _replace(user["sub"], "home_visit", blocks)


@router.get("/me/slots")
def get_my_slots(from_date: str = None, user: dict = Depends(require_doctor)):
    from datetime import date
    d = date.fromisoformat(from_date) if from_date else now_ist().date()
    return get_available_slots(user["sub"], d)
