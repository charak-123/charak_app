from fastapi import APIRouter, Depends
from pydantic import BaseModel
from ..db import fetch_one, supabase
from ..deps import get_current_user, require_patient
from ..services import erasure

router = APIRouter()


class UserUpdate(BaseModel):
    name: str | None = None


@router.get("/me")
def get_me(user: dict = Depends(get_current_user)):
    return fetch_one(supabase.table("users").select("*").eq("id", user["sub"]))


@router.patch("/me")
def update_me(body: UserUpdate, user: dict = Depends(get_current_user)):
    data = body.model_dump(exclude_none=True)
    result = supabase.table("users").update(data).eq("id", user["sub"]).execute()
    return result.data[0]


@router.delete("/me")
def delete_me(user: dict = Depends(require_patient)):
    """
    Delete the patient's own account (DPDP erasure / App Store & Play requirement).

    Soft-deletes immediately — login is blocked and all outbound contact stops —
    and schedules the personal-data purge after the grace window. Financial and
    de-identified clinical records are retained. Logging back in before the purge
    cancels the deletion.
    """
    return erasure.request_patient_deletion(user["sub"])
