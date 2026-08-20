from fastapi import APIRouter, Depends
from pydantic import BaseModel

from ..db import supabase
from ..deps import require_doctor
from ..services.availability import get_available_slots

router = APIRouter()


class ScheduleBlock(BaseModel):
    day_of_week: int   # 0 = Monday, 6 = Sunday
    start_time: str    # "09:00"
    end_time: str      # "17:00"


@router.get("/me")
def get_my_schedules(user: dict = Depends(require_doctor)):
    return (
        supabase.table("doctor_schedules")
        .select("*")
        .eq("doctor_id", user["sub"])
        .order("day_of_week")
        .execute()
        .data
    )


@router.put("/me")
def replace_schedules(blocks: list[ScheduleBlock], user: dict = Depends(require_doctor)):
    """Replace entire schedule for online consult channel."""
    supabase.table("doctor_schedules").delete().eq("doctor_id", user["sub"]).execute()
    if blocks:
        rows = [{"doctor_id": user["sub"], **b.model_dump()} for b in blocks]
        supabase.table("doctor_schedules").insert(rows).execute()
    return {"ok": True}


@router.put("/me/home-visit")
def replace_home_visit_schedules(blocks: list[ScheduleBlock], user: dict = Depends(require_doctor)):
    """For simplicity in V1, home visit uses the same doctor_schedules table.
    Replace all — client merges online+home blocks before calling."""
    return replace_schedules(blocks, user)


@router.get("/me/slots")
def get_my_slots(from_date: str = None, user: dict = Depends(require_doctor)):
    from datetime import date
    d = date.fromisoformat(from_date) if from_date else date.today()
    return get_available_slots(user["sub"], d)
