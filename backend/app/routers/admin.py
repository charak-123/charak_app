import os
from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import APIRouter
from jose import jwt
from pydantic import BaseModel

from ..config import JWT_SECRET
from ..db import supabase
from ..deps import require_ops
from ..errors import AppError
from fastapi import Depends

router = APIRouter()

ADMIN_PASSWORD = os.getenv("ADMIN_PASSWORD", "charak-admin-2024")


# ── Models ────────────────────────────────────────────────────────────────────

class AdminLoginRequest(BaseModel):
    password: str


class VerifyDoctorRequest(BaseModel):
    action: str  # "approve" | "reject"
    reason: Optional[str] = None


class ComplaintStatusUpdate(BaseModel):
    status: str  # "open" | "in_review" | "resolved" | "closed"


VALID_COMPLAINT_STATUSES = {"open", "in_review", "resolved", "closed"}


# ── 1. Admin Login (no auth required) ────────────────────────────────────────

@router.post("/login")
def admin_login(body: AdminLoginRequest):
    if body.password != ADMIN_PASSWORD:
        raise AppError("Invalid admin password", 401)

    payload = {
        "sub": "admin",
        "role": "ops",
        "exp": datetime.now(timezone.utc) + timedelta(days=30),
    }
    token = jwt.encode(payload, JWT_SECRET, algorithm="HS256")
    return {"token": token}


# ── 2. Pending doctors ────────────────────────────────────────────────────────

@router.get("/doctors/pending")
def list_pending_doctors(user: dict = Depends(require_ops)):
    result = (
        supabase.table("doctors")
        .select("id, name, phone, license_number, verification_document_url, created_at")
        .eq("verification_status", "pending")
        .order("created_at", desc=False)
        .execute()
    )
    return result.data


# ── 3. Verify / reject a doctor ───────────────────────────────────────────────

@router.patch("/doctors/{doctor_id}/verify")
def verify_doctor(doctor_id: str, body: VerifyDoctorRequest, user: dict = Depends(require_ops)):
    if body.action not in ("approve", "reject"):
        raise AppError("action must be 'approve' or 'reject'", 400)

    doctor = supabase.table("doctors").select("id").eq("id", doctor_id).execute().data
    if not doctor:
        raise AppError("Doctor not found", 404)

    if body.action == "approve":
        update_data = {"verification_status": "verified"}
    else:
        if not body.reason:
            raise AppError("reason is required when rejecting", 400)
        update_data = {
            "verification_status": "rejected",
            "verification_rejection_reason": body.reason,
        }

    result = supabase.table("doctors").update(update_data).eq("id", doctor_id).execute()
    return result.data[0]


# ── 4. All bookings ───────────────────────────────────────────────────────────

@router.get("/bookings")
def list_all_bookings(status: Optional[str] = None, user: dict = Depends(require_ops)):
    query = (
        supabase.table("bookings")
        .select("*, users(name, phone), doctors(name)")
        .order("created_at", desc=True)
    )
    if status:
        query = query.eq("status", status)

    result = query.execute()
    return result.data


# ── 5. Procedure bills under review ──────────────────────────────────────────

@router.get("/procedure-bills/review")
def list_procedure_bills_under_review(user: dict = Depends(require_ops)):
    result = (
        supabase.table("procedure_bills")
        .select("*, bookings(id, doctor_id, doctors(name))")
        .eq("status", "under_review")
        .execute()
    )
    return result.data


# ── 6. All complaints ─────────────────────────────────────────────────────────

@router.get("/complaints")
def list_all_complaints(status: Optional[str] = None, user: dict = Depends(require_ops)):
    query = (
        supabase.table("complaints")
        .select("*, bookings(id, patient_id, doctor_id)")
        .order("created_at", desc=True)
    )
    if status:
        query = query.eq("status", status)

    result = query.execute()
    return result.data


# ── 7. Update complaint status ────────────────────────────────────────────────

@router.patch("/complaints/{complaint_id}")
def update_complaint_status(
    complaint_id: str,
    body: ComplaintStatusUpdate,
    user: dict = Depends(require_ops),
):
    if body.status not in VALID_COMPLAINT_STATUSES:
        raise AppError(f"Invalid status '{body.status}'", 400)

    complaint = supabase.table("complaints").select("id").eq("id", complaint_id).execute().data
    if not complaint:
        raise AppError("Complaint not found", 404)

    result = supabase.table("complaints").update({"status": body.status}) \
        .eq("id", complaint_id).execute()
    return result.data[0]
