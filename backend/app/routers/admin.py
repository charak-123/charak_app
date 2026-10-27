import logging
from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import APIRouter, BackgroundTasks, Depends
import jwt
from pydantic import BaseModel, Field

from ..config import ADMIN_TOKEN_TTL_HOURS, JWT_SECRET
from ..db import supabase
from ..deps import require_ops, require_permission
from ..errors import AppError
from ..services import (
    admin_auth, admin_roles, audit, booking_state, erasure, incidents, notifications, payouts, prescriptions,
    pricing, refunds, remedies, reviews, visits,
)
from ..services.admin_auth import AdminAuthError
from ..services.rate_limit import enforce as enforce_rate_limit, rate_limiter

logger = logging.getLogger(__name__)

router = APIRouter()

# PostgREST (and so supabase-py) caps a single response at 1000 rows by
# default. A query with no .range() silently truncates past that — the
# dashboard numbers would look plausible and just be wrong. Page through in
# fixed-size chunks instead so metrics stay correct as the tables grow.
_PAGE_SIZE = 1000

# Bookings the patient has paid for, at any stage after payment.
PAID_STATUSES = ("paid", "in_progress", "consulted", "completed")


def _fetch_all(build_query) -> list[dict]:
    """
    Run `build_query()` repeatedly over successive .range() windows, collecting
    every row. `build_query` must return a fresh query builder each call (the
    supabase-py client mutates it range-to-range).
    """
    rows: list[dict] = []
    offset = 0
    while True:
        page = build_query().range(offset, offset + _PAGE_SIZE - 1).execute().data or []
        rows.extend(page)
        if len(page) < _PAGE_SIZE:
            return rows
        offset += _PAGE_SIZE


# ── Models ────────────────────────────────────────────────────────────────────

class AdminLoginRequest(BaseModel):
    email: str
    password: str
    totp_code: Optional[str] = None


class VerifyDoctorRequest(BaseModel):
    action: str  # "approve" | "reject"
    reason: Optional[str] = None


class ComplaintStatusUpdate(BaseModel):
    status: str  # "open" | "in_review" | "resolved" | "closed"


VALID_COMPLAINT_STATUSES = {"open", "in_review", "resolved", "closed"}


# ── 1. Admin Login (no auth required) ────────────────────────────────────────

@router.post("/login", dependencies=[rate_limiter("admin-login", 5, 900)])
def admin_login(body: AdminLoginRequest):
    """
    Per-admin account + mandatory TOTP. See services/admin_auth.py for the
    two-call protocol (password, then password+code).

    Rate-limited twice: 5 attempts per 15 minutes per IP, and 10 per 15
    minutes per account. The per-account cap is what stops a distributed guess
    — many addresses, one target — which a per-IP limit alone never sees.
    """
    email = body.email.strip().lower()
    enforce_rate_limit("admin-login-account", email, 10, 900)
    try:
        admin = admin_auth.authenticate(email, body.password, body.totp_code)
    except AdminAuthError as exc:
        raise AppError(exc.message, exc.status_code, **exc.extra) from exc

    now = datetime.now(timezone.utc)
    payload = {
        "sub": admin["id"],
        "email": admin["email"],
        "role": "ops",
        # What this admin may do (services/admin_roles.py). Accounts from
        # before roles existed are 'admin' (migration 0029).
        "admin_role": admin.get("role") or "admin",
        "iat": now,
        "exp": now + timedelta(hours=ADMIN_TOKEN_TTL_HOURS),
    }
    token = jwt.encode(payload, JWT_SECRET, algorithm="HS256")
    return {"token": token, "role": payload["admin_role"],
            "permissions": sorted(admin_roles.PERMISSIONS.get(payload["admin_role"], ()))}


@router.get("/me")
def admin_me(user: dict = Depends(require_ops)):
    """Who is signed in and what they may do: the console shows only what
    the role allows (the API enforces it regardless)."""
    return {"email": user.get("email"), "role": admin_roles.role_of(user),
            "permissions": admin_roles.permissions_of(user)}


# ── 2. Pending doctors ────────────────────────────────────────────────────────

@router.get("/doctors/pending")
def list_pending_doctors(user: dict = Depends(require_permission("doctors.read"))):
    """
    Everything ops needs to decide approve/reject without leaving the page:
    the application details the doctor filled in (specialty, bio, channels,
    contact), plus enough about the submitted document (mime type; the file
    itself is read on demand through GET /uploads/doctor/{id}/verification-
    document, which mints a short-lived signed URL rather than a durable one).
    """
    result = (
        supabase.table("doctors")
        .select(
            "id, name, phone, email, license_number, bio, "
            "offers_online_consult, offers_home_visit, "
            "verification_document_path, verification_document_mime, "
            "photo_url, created_at, categories(name), application_details"
        )
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
    user: dict = Depends(require_permission("doctors.verify")),
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
    user: dict = Depends(require_permission("doctors.suspend")),
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


# ── 3b. Force-expire a doctor's or patient's existing sessions ────────────────
#
# A shorter token lifetime (TOKEN_TTL_DAYS, routers/auth.py) bounds how long a
# forgotten phone works for; this is the other half — a *reported* lost or
# stolen phone, where waiting out even a 14-day window is not acceptable.
# Every token issued before this moment stops working immediately
# (deps.get_current_user checks it on every request); a fresh sign-in is
# unaffected.

@router.patch("/doctors/{doctor_id}/revoke-sessions")
def revoke_doctor_sessions(doctor_id: str, user: dict = Depends(require_permission("sessions.revoke"))):
    doctor = supabase.table("doctors").select("id").eq("id", doctor_id).execute().data
    if not doctor:
        raise AppError("Doctor not found", 404)
    supabase.table("doctors").update(
        {"sessions_revoked_at": datetime.now(timezone.utc).isoformat()}
    ).eq("id", doctor_id).execute()
    _audit(user, "doctors", doctor_id, "sessions_revoked")
    return {"ok": True}


@router.patch("/users/{user_id}/revoke-sessions")
def revoke_patient_sessions(user_id: str, user: dict = Depends(require_permission("sessions.revoke"))):
    patient = supabase.table("users").select("id").eq("id", user_id).execute().data
    if not patient:
        raise AppError("Patient not found", 404)
    supabase.table("users").update(
        {"sessions_revoked_at": datetime.now(timezone.utc).isoformat()}
    ).eq("id", user_id).execute()
    _audit(user, "users", user_id, "sessions_revoked")
    return {"ok": True}


# ── 3c. Full doctor list for directory management ─────────────────────────────

@router.get("/doctors")
def list_doctors(
    status: Optional[str] = None,
    suspended: Optional[bool] = None,
    user: dict = Depends(require_permission("doctors.read")),
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


def _mask_phone(phone: Optional[str]) -> Optional[str]:
    """Keep the last 2 digits, same idea as a card-number mask. Ops can still
    pull the full number per-booking via the reveal endpoint when they need to
    act on it; the list view doesn't need it in the clear by default."""
    if not phone or len(phone) < 4:
        return phone
    return "•" * (len(phone) - 2) + phone[-2:]


# ── 4. All bookings ───────────────────────────────────────────────────────────

@router.get("/bookings")
def list_all_bookings(status: Optional[str] = None, user: dict = Depends(require_permission("bookings.read"))):
    query = (
        supabase.table("bookings")
        .select("*, users(name, phone), doctors(name)")
        .order("created_at", desc=True)
    )
    if status:
        query = query.eq("status", status)

    result = query.execute()
    rows = result.data or []
    for row in rows:
        if row.get("users"):
            row["users"]["phone"] = _mask_phone(row["users"].get("phone"))
    return rows


@router.get("/bookings/{booking_id}/timeline")
def booking_timeline(booking_id: str, user: dict = Depends(require_permission("bookings.read"))):
    """Every recorded event for a booking, with actors and metadata."""
    exists = supabase.table("bookings").select("id").eq("id", booking_id).execute().data
    if not exists:
        raise AppError("Booking not found", 404)
    return booking_state.timeline(booking_id)


@router.get("/bookings/{booking_id}/phone")
def reveal_booking_patient_phone(booking_id: str, user: dict = Depends(require_permission("patient_phone.reveal"))):
    """Explicit, audited reveal of one patient's number. Separate from the list
    endpoint so looking at the book doesn't put every patient's phone number on
    screen (or in the browser's memory/devtools) by default."""
    row = (
        supabase.table("bookings")
        .select("id, users(phone)")
        .eq("id", booking_id)
        .execute()
        .data
    )
    if not row:
        raise AppError("Booking not found", 404)

    _audit(user, "booking", booking_id, "revealed_patient_phone")
    return {"phone": (row[0].get("users") or {}).get("phone")}


# ── Incidents ────────────────────────────────────────────────────────────────

@router.get("/incidents")
def incident_queue(view: str = "open", user: dict = Depends(require_permission("incidents.read"))):
    """'open': reported or under review, oldest first. 'appealed': appeals
    waiting. 'all': everything recent. Each with its full event history."""
    if view not in ("open", "appealed", "all"):
        raise AppError("view must be open, appealed or all", 400)
    return incidents.ops_queue(view)


class IncidentDecision(BaseModel):
    status: str                    # confirmed | dismissed | undetermined
    cause: str                     # doctor | patient | platform | mutual | undetermined
    reason: str = Field(min_length=5, max_length=1000)
    # Let the patient choose a refund or another doctor now.
    offer_remedy: bool = False


@router.post("/incidents/{incident_id}/decide")
def decide_incident(incident_id: str, body: IncidentDecision, background: BackgroundTasks,
                    user: dict = Depends(require_permission("incidents.decide"))):
    row = incidents.decide(incident_id, user, body.status, body.cause, body.reason,
                           body.offer_remedy, background)
    audit.record(user, "incident", incident_id, f"incident_{body.status}", reason=body.reason,
                 metadata={"cause": body.cause, "offer_remedy": body.offer_remedy})
    return row


class AppealDecision(BaseModel):
    outcome: str                   # upheld | reversed
    reason: str = Field(min_length=5, max_length=1000)


@router.post("/incidents/{incident_id}/appeal-decision")
def decide_incident_appeal(incident_id: str, body: AppealDecision, background: BackgroundTasks,
                           user: dict = Depends(require_permission("incidents.decide"))):
    row = incidents.decide_appeal(incident_id, user, body.outcome, body.reason, background)
    audit.record(user, "incident", incident_id, f"appeal_{body.outcome}", reason=body.reason)
    return row


@router.post("/incidents/{incident_id}/refund")
def refund_incident(incident_id: str, background: BackgroundTasks, user: dict = Depends(require_permission("refunds.manage"))):
    """Refund the patient now (the case must be open to a remedy)."""
    out = remedies.refund(incident_id, "ops", user.get("sub"), background)
    audit.record(user, "incident", incident_id, "remedy_refund_by_ops")
    return out


# ── Review moderation ────────────────────────────────────────────────────────

@router.get("/reviews")
def review_queue(status: str = "reported", user: dict = Depends(require_permission("reviews.read"))):
    """'reported': published reviews with an open report, oldest first.
    'hidden': reviews ops has hidden, newest first."""
    if status not in ("reported", "hidden"):
        raise AppError("status must be reported or hidden", 400)
    return reviews.moderation_queue(status)


class ModerationRequest(BaseModel):
    action: str        # hide | restore | dismiss
    reason: str = Field(min_length=5, max_length=500)


@router.post("/reviews/{review_id}/moderate")
def moderate_review(review_id: str, body: ModerationRequest, user: dict = Depends(require_permission("reviews.moderate"))):
    """Hide (abusive, irrelevant or private details; never for being
    negative), restore, or dismiss the reports and leave it up."""
    return reviews.moderate(review_id, body.action, body.reason, user)


# ── Pricing history ──────────────────────────────────────────────────────────

@router.get("/pricing/{doctor_id}/history")
def pricing_history(doctor_id: str, user: dict = Depends(require_permission("pricing.read"))):
    """Every price this doctor has had, newest first, with when each applied.
    A booking's own price_rule_id points at the row it was charged by."""
    doctor = supabase.table("doctors").select("id, follow_up_validity_days") \
        .eq("id", doctor_id).execute().data
    if not doctor:
        raise AppError("Doctor not found", 404)
    return {"follow_up_validity_days": doctor[0].get("follow_up_validity_days"),
            "rules": pricing.history(doctor_id, limit=500)}


# ── Visits: exception queues and prescription access ─────────────────────────

@router.get("/visits/queues")
def visit_queues(user: dict = Depends(require_permission("visits.read"))):
    """Home visits with no journey near their time, consultations with nothing
    sent to the patient, and prescriptions not opened after a day. Flags for a
    person to look at, not verdicts (nothing here is marked a no-show)."""
    queues = visits.ops_queues()
    for rows in queues.values():
        for row in rows:
            row["patient_name"] = (row.pop("users", None) or {}).get("name")
            row["doctor_name"] = (row.pop("doctors", None) or {}).get("name")
            row.pop("patient_id", None)
    return queues


@router.get("/bookings/{booking_id}/prescriptions")
def booking_prescriptions(booking_id: str, user: dict = Depends(require_permission("visits.read"))):
    """Every version's status and timestamps, without its clinical content.
    Enough to answer "was it sent, when, and did the patient open it"."""
    return (
        supabase.table("prescriptions")
        .select("id, version, kind, status, submitted_at, first_viewed_at, superseded_at, "
                "created_at")
        .eq("booking_id", booking_id).order("version").execute().data or []
    )


class BreakGlassRequest(BaseModel):
    # Why ops needs to read a patient's prescription: a complaint, a pharmacy
    # query, a legal request. Recorded with the access.
    reason: str = Field(min_length=10, max_length=500)


@router.post("/prescriptions/{prescription_id}/access",
             dependencies=[rate_limiter("admin-rx-access", 20, 3600)])
def break_glass_prescription(prescription_id: str, body: BreakGlassRequest,
                             user: dict = Depends(require_permission("prescriptions.break_glass"))):
    """
    Ops reads one prescription's content (spec §9.3: admin access restricted to
    operational need). Every read is recorded with its reason first; if that
    record can't be written, nothing is shown. Reading it never counts as the
    patient's view.
    """
    rx = prescriptions.get(prescription_id)
    if not rx or rx["status"] == "draft":
        raise AppError("Prescription not found", 404)
    try:
        audit.record_or_refuse(user, "prescription", prescription_id, "break_glass_read",
                               reason=body.reason.strip(),
                               metadata={"booking_id": rx["booking_id"], "version": rx["version"]})
    except Exception:
        raise AppError("Access can't be recorded right now, so it isn't allowed. Try again.", 503)
    return {**prescriptions.public(rx), **prescriptions.files(rx)}


# ── 5. Procedure bills under review ──────────────────────────────────────────

@router.get("/procedure-bills/review")
def list_procedure_bills_under_review(user: dict = Depends(require_permission("procedure_bills.review"))):
    result = (
        supabase.table("procedure_bills")
        .select("*, bookings(id, doctor_id, doctors(name))")
        .eq("status", "under_review")
        .execute()
    )
    return result.data


# ── 6. All complaints ─────────────────────────────────────────────────────────

@router.get("/complaints")
def list_all_complaints(status: Optional[str] = None, user: dict = Depends(require_permission("complaints.read"))):
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
    user: dict = Depends(require_permission("complaints.update")),
):
    if body.status not in VALID_COMPLAINT_STATUSES:
        raise AppError(f"Invalid status '{body.status}'", 400)

    complaint = supabase.table("complaints").select("id").eq("id", complaint_id).execute().data
    if not complaint:
        raise AppError("Complaint not found", 404)

    result = supabase.table("complaints").update({"status": body.status}) \
        .eq("id", complaint_id).execute()
    _audit(user, "complaints", complaint_id, f"status_{body.status}")
    return result.data[0]


# ── 7b. Refunds ───────────────────────────────────────────────────────────────

_REFUND_STATUSES = ("pending", "processing", "processed", "failed")


@router.get("/refunds")
def list_refunds(status: Optional[str] = None, user: dict = Depends(require_permission("refunds.manage"))):
    """
    The refunds queue. With no filter, everything Razorpay hasn't confirmed yet
    (pending, processing, failed). 'failed' is the one that needs a person.
    """
    if status is not None and status not in _REFUND_STATUSES:
        raise AppError(f"status must be one of {', '.join(_REFUND_STATUSES)}", 400)
    statuses = [status] if status else list(refunds.OPEN_STATUSES)
    return (
        supabase.table("refunds")
        .select("*, bookings(id, channel, scheduled_start, cancelled_by, "
                "doctors(name), users(name))")
        .in_("status", statuses)
        .order("created_at", desc=True)
        .limit(200)
        .execute()
        .data
        or []
    )


@router.post("/refunds/{refund_id}/retry")
def retry_refund(refund_id: str, user: dict = Depends(require_permission("refunds.manage"))):
    """Send a failed refund to Razorpay again. Audited."""
    row = refunds.retry(refund_id)
    _audit(user, "refunds", refund_id, "refund_retry")
    return row


# ── 8. Dashboard metrics ──────────────────────────────────────────────────────

@router.get("/metrics")
def dashboard_metrics(user: dict = Depends(require_permission("metrics.read"))):
    """
    The numbers the admin landing page needs, in one round trip rather than the
    six the dashboard was making.

    Each table is paged through in full (see `_fetch_all`) rather than fetched
    in one `.execute()` — past 1000 rows, an unpaged query is silently
    truncated by PostgREST and every count/sum below would quietly undercount.
    """
    doctors = _fetch_all(lambda: supabase.table("doctors").select("verification_status, suspended"))
    bookings = _fetch_all(lambda: supabase.table("bookings").select("status, price_confirmed"))
    complaints = _fetch_all(lambda: supabase.table("complaints").select("status"))
    bills = _fetch_all(lambda: supabase.table("procedure_bills").select("status, total"))
    ledger = _fetch_all(
        lambda: supabase.table("doctor_ledger_entries")
        .select("net_amount, commission_amount, status")
    )
    open_refunds = _fetch_all(
        lambda: supabase.table("refunds").select("status")
        .in_("status", list(refunds.OPEN_STATUSES))
    )

    def count(rows, field, value):
        return len([r for r in rows if r.get(field) == value])

    paid_bookings = [b for b in bookings if b.get("status") in PAID_STATUSES]

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
            "in_progress": count(bookings, "status", "in_progress"),
            "consulted": count(bookings, "status", "consulted"),
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
            "refunds_failed": count(open_refunds, "status", "failed"),
            "refunds_in_flight": len([r for r in open_refunds if r.get("status") != "failed"]),
        },
    }



@router.get("/metrics/timeseries")
def dashboard_timeseries(days: int = 30, user: dict = Depends(require_permission("metrics.read"))):
    """
    Daily booking counts and consult revenue for the overview's trend chart.

    Bucketed here rather than in SQL because the table client has no date_trunc;
    the window is capped so this stays a bounded scan.
    """
    days = max(7, min(days, 90))
    start = (datetime.now(timezone.utc) - timedelta(days=days - 1)).date()

    rows = (
        supabase.table("bookings")
        .select("created_at, status, price_confirmed")
        .gte("created_at", start.isoformat())
        .execute()
        .data
        or []
    )

    buckets = {
        (start + timedelta(days=i)).isoformat(): {"bookings": 0, "completed": 0, "revenue": 0.0}
        for i in range(days)
    }

    for r in rows:
        created = r.get("created_at")
        if not created:
            continue
        day = str(created)[:10]
        bucket = buckets.get(day)
        if bucket is None:
            continue
        bucket["bookings"] += 1
        if r.get("status") in PAID_STATUSES:
            bucket["completed"] += 1
            bucket["revenue"] += float(r.get("price_confirmed") or 0)

    return [
        {"date": day, **{**v, "revenue": round(v["revenue"], 2)}}
        for day, v in sorted(buckets.items())
    ]

# ── 9. Audit log ──────────────────────────────────────────────────────────────

@router.get("/audit-log")
def read_audit_log(limit: int = 100, user: dict = Depends(require_permission("audit.read"))):
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
    """Record an ops action. See services/audit.py."""
    audit.record(user, entity, entity_id, action)


# ── Doctor account-deletion requests (ops fulfils) ───────────────────────────

@router.get("/doctors/deletion-requests")
def list_doctor_deletion_requests(user: dict = Depends(require_permission("deletions.fulfil"))):
    """Doctors who have asked to delete their account, oldest request first."""
    return (
        supabase.table("doctors")
        .select("id, name, phone, deletion_requested_at, deletion_status")
        .eq("deletion_status", "requested")
        .order("deletion_requested_at", desc=False)
        .execute()
        .data
    )


@router.post("/doctors/{doctor_id}/deletion/fulfill")
def fulfill_doctor_deletion(doctor_id: str, user: dict = Depends(require_permission("deletions.fulfil"))):
    """
    Complete a doctor's account deletion after settling their account.

    Refused while the doctor is still owed a payout or has active/upcoming paid
    bookings — those must be resolved before their identity can be erased.
    """
    doctor = supabase.table("doctors").select("deletion_status") \
        .eq("id", doctor_id).execute().data
    if not doctor:
        raise AppError("Doctor not found", 404)
    if doctor[0].get("deletion_status") != "requested":
        raise AppError("No pending deletion request for this doctor", 409)

    owed = payouts.balance(doctor_id).get("payable_net", 0)
    if owed and owed > 0:
        raise AppError(
            f"Doctor is still owed {owed:.2f}. Settle the payout before deleting.", 409
        )

    active = (
        supabase.table("bookings").select("id")
        .eq("doctor_id", doctor_id).in_("status", ["accepted", "paid", "in_progress", "consulted"])
        .execute().data or []
    )
    if active:
        raise AppError(
            f"Doctor has {len(active)} active/upcoming booking(s). Resolve them first.",
            409,
        )

    erasure.purge_doctor(doctor_id)
    _audit(user, "doctors", doctor_id, "deletion_fulfilled")
    return {"ok": True, "doctor_id": doctor_id, "status": "fulfilled"}
