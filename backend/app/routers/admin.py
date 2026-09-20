from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import APIRouter, BackgroundTasks, Depends
from jose import jwt
from pydantic import BaseModel, Field

from ..config import ADMIN_PASSWORD, JWT_SECRET
from ..db import supabase
from ..deps import require_ops
from ..errors import AppError
from ..services import notifications

router = APIRouter()


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
def verify_doctor(
    doctor_id: str,
    body: VerifyDoctorRequest,
    background: BackgroundTasks,
    user: dict = Depends(require_ops),
):
    """Approve or reject a doctor. An approved doctor goes live immediately."""
    if body.action not in ("approve", "reject"):
        raise AppError("action must be 'approve' or 'reject'", 400)

    doctor = supabase.table("doctors").select("id").eq("id", doctor_id).execute().data
    if not doctor:
        raise AppError("Doctor not found", 404)

    if body.action == "approve":
        update_data = {
            "verification_status": "verified",
            "verification_rejection_reason": None,
        }
    else:
        if not body.reason:
            raise AppError("reason is required when rejecting", 400)
        update_data = {
            "verification_status": "rejected",
            "verification_rejection_reason": body.reason,
        }

    result = supabase.table("doctors").update(update_data).eq("id", doctor_id).execute()

    if body.action == "approve":
        notifications.doctor_verified(doctor_id, background)
    else:
        notifications.doctor_rejected(doctor_id, body.reason, background)

    _audit(user, "doctors", doctor_id, f"verification_{body.action}")

    return result.data[0]


# ── 3b. Directory management: suspend / reinstate a listing ───────────────────

class SuspendRequest(BaseModel):
    suspended: bool
    reason: Optional[str] = Field(default=None, max_length=300)


@router.patch("/doctors/{doctor_id}/suspend")
def suspend_doctor(
    doctor_id: str,
    body: SuspendRequest,
    background: BackgroundTasks,
    user: dict = Depends(require_ops),
):
    """
    Pull a listing from the directory without destroying the account.

    A suspended doctor keeps their history, earnings and pending payouts; they
    simply stop appearing in search and cannot receive new bookings.
    """
    doctor = supabase.table("doctors").select("id").eq("id", doctor_id).execute().data
    if not doctor:
        raise AppError("Doctor not found", 404)

    if body.suspended and not body.reason:
        raise AppError("reason is required when suspending", 400)

    update_data = {
        "suspended": body.suspended,
        "suspended_reason": body.reason if body.suspended else None,
        "suspended_at": datetime.now(timezone.utc).isoformat() if body.suspended else None,
    }
    result = supabase.table("doctors").update(update_data).eq("id", doctor_id).execute()

    if body.suspended:
        notifications.doctor_suspended(doctor_id, body.reason, background)

    _audit(user, "doctors", doctor_id, "suspended" if body.suspended else "reinstated")

    return result.data[0]


# ── 3c. Full doctor list for directory management ─────────────────────────────

@router.get("/doctors")
def list_doctors(
    status: Optional[str] = None,
    suspended: Optional[bool] = None,
    user: dict = Depends(require_ops),
):
    query = (
        supabase.table("doctors")
        .select("*, categories(name)")
        .order("created_at", desc=True)
    )
    if status:
        if status not in ("pending", "verified", "rejected"):
            raise AppError("status must be pending, verified or rejected", 400)
        query = query.eq("verification_status", status)
    if suspended is not None:
        query = query.eq("suspended", suspended)
    return query.execute().data


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


# ── 8. Dashboard metrics ──────────────────────────────────────────────────────

@router.get("/metrics")
def dashboard_metrics(user: dict = Depends(require_ops)):
    """
    The numbers the admin landing page needs, in one round trip rather than the
    six the dashboard was making.
    """
    doctors = supabase.table("doctors").select("verification_status, suspended").execute().data or []
    bookings = supabase.table("bookings").select("status, price_confirmed").execute().data or []
    complaints = supabase.table("complaints").select("status").execute().data or []
    bills = supabase.table("procedure_bills").select("status, total").execute().data or []
    ledger = (
        supabase.table("doctor_ledger_entries")
        .select("net_amount, commission_amount, status")
        .execute()
        .data
        or []
    )

    def count(rows, field, value):
        return len([r for r in rows if r.get(field) == value])

    paid_bookings = [b for b in bookings if b.get("status") in ("paid", "completed")]

    return {
        "doctors": {
            "total": len(doctors),
            "pending": count(doctors, "verification_status", "pending"),
            "verified": count(doctors, "verification_status", "verified"),
            "rejected": count(doctors, "verification_status", "rejected"),
            "suspended": len([d for d in doctors if d.get("suspended")]),
        },
        "bookings": {
            "total": len(bookings),
            "requested": count(bookings, "status", "requested"),
            "accepted": count(bookings, "status", "accepted"),
            "paid": count(bookings, "status", "paid"),
            "completed": count(bookings, "status", "completed"),
            "cancelled": count(bookings, "status", "cancelled"),
            "declined": count(bookings, "status", "declined"),
            "no_show": count(bookings, "status", "no_show"),
        },
        "revenue": {
            "consult_gross": round(
                sum(float(b.get("price_confirmed") or 0) for b in paid_bookings), 2
            ),
            "procedure_gross": round(
                sum(float(b["total"]) for b in bills if b.get("status") == "paid"), 2
            ),
            "commission_earned": round(
                sum(
                    float(e["commission_amount"] or 0)
                    for e in ledger
                    if e.get("status") in ("payable", "paid")
                ),
                2,
            ),
            "owed_to_doctors": round(
                sum(float(e["net_amount"] or 0) for e in ledger if e.get("status") == "payable"),
                2,
            ),
        },
        "queues": {
            "bills_under_review": count(bills, "status", "under_review"),
            "complaints_open": count(complaints, "status", "open"),
            "complaints_in_review": count(complaints, "status", "in_review"),
        },
    }


# ── 9. Audit log ──────────────────────────────────────────────────────────────

@router.get("/audit-log")
def read_audit_log(limit: int = 100, user: dict = Depends(require_ops)):
    limit = max(1, min(limit, 500))
    return (
        supabase.table("audit_log")
        .select("*")
        .order("at", desc=True)
        .limit(limit)
        .execute()
        .data
    )


def _audit(user: dict, entity: str, entity_id: Optional[str], action: str) -> None:
    """
    Record an ops action. Best-effort: an audit write must never be the reason a
    verification fails, but every ops mutation should leave a trace.
    """
    try:
        supabase.table("audit_log").insert({
            "actor_id": None,          # admin login is a shared account, not a user row
            "actor_role": user.get("role", "ops"),
            "entity": entity,
            "entity_id": entity_id,
            "action": action,
        }).execute()
    except Exception as exc:  # pragma: no cover
        print(f"[audit] failed to record {action} on {entity}/{entity_id}: {exc}")
