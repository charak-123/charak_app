from fastapi import APIRouter, Depends
from pydantic import BaseModel

from ..db import supabase
from ..deps import require_doctor
from ..errors import AppError

router = APIRouter()


class SlotBlockCreate(BaseModel):
    date: str        # "2026-08-25"
    start_time: str  # "09:00"
    end_time: str    # "17:00"


@router.get("/me")
def get_my_blocks(user: dict = Depends(require_doctor)):
    return (
        supabase.table("doctor_slot_blocks")
        .select("*")
        .eq("doctor_id", user["sub"])
        .order("date")
        .execute()
        .data
    )


@router.post("/me")
def add_block(block: SlotBlockCreate, user: dict = Depends(require_doctor)):
    return supabase.table("doctor_slot_blocks").insert({
        "doctor_id": user["sub"],
        **block.model_dump(),
    }).execute().data[0]


@router.delete("/me/{block_id}")
def delete_block(block_id: str, user: dict = Depends(require_doctor)):
    result = (
        supabase.table("doctor_slot_blocks")
        .delete()
        .eq("id", block_id)
        .eq("doctor_id", user["sub"])
        .execute()
    )
    if not result.data:
        raise AppError("Block not found", 404)
    return {"ok": True}
