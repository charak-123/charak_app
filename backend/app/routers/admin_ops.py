"""
Operations tooling (plan Phase 7, spec §17, §21). Mounted at /admin.

    GET  /health                          the §21 numbers that drive action
    GET  /policies                        policy and legal document versions, approved or not
    POST /policies/{id}/approve           the legal review gate (D20)
    POST /legal-documents/{id}/approve
    POST /bookings/{id}/override          correct a stuck booking, through the state machine
    GET  /system/dead-letters             jobs, webhooks and notifications that gave up
    POST /system/jobs/{id}/retry
    POST /system/webhooks/{id}/retry
    GET  /admins, POST /admins/{id}/role  who has which role

Every change here needs a reason and is written to the audit log with what
it was before (spec §17.3: no unlogged "edit anything").
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Literal, Optional

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field

from ..db import fetch_one, supabase
from ..deps import require_permission
from ..errors import AppError
from ..services import admin_roles, audit, booking_state

router = APIRouter()


def _now() -> datetime:
    return datetime.now(timezone.utc)


# ── Health ───────────────────────────────────────────────────────────────────

@router.get("/health")
def health(days: int = 30, user: dict = Depends(require_permission("metrics.read"))):
    """Counts only, nothing about any one patient. See ops_metrics() (0029)."""
    if not 1 <= days <= 365:
        raise AppError("days must be between 1 and 365", 400)
    return supabase.rpc("ops_metrics", {"p_days": days}).execute().data


# ── The legal review gate ────────────────────────────────────────────────────

class Approval(BaseModel):
    # Who approved it, in words: "Founder; reviewed by counsel 2026-11-02".
    approved_by: str = Field(min_length=3, max_length=200)
    note: Optional[str] = Field(default=None, max_length=1000)


@router.get("/policies")
def list_policies(user: dict = Depends(require_permission("policies.approve"))):
    """Every cancellation policy and legal document version, newest first,
    with its approval. An unapproved version is never shown to anyone."""
    policies = (supabase.table("policies")
                .select("id, kind, channel, version, summary, decision_ref, effective_from, created_at, "
                        "policy_approvals(approved_by, note, approved_at)")
                .order("created_at", desc=True).execute().data or [])
    documents = (supabase.table("legal_documents")
                 .select("id, type, version, title, url, audience, material, published_at, "
                         "legal_document_approvals(approved_by, note, approved_at)")
                 .order("published_at", desc=True).execute().data or [])
    return {"policies": policies, "documents": documents}


def _approve(table: str, key: str, row_id: str, body: Approval, user: dict, entity: str) -> dict:
    try:
        row = supabase.table(table).insert({
            key: row_id, "approved_by": body.approved_by.strip(), "admin_id": user.get("sub"),
            "note": (body.note or "").strip() or None,
        }).execute().data[0]
    except Exception as exc:                       # noqa: BLE001
        if "23505" in str(exc):
            raise AppError("Already approved", 409)
        if "23503" in str(exc):
            raise AppError("Not found", 404)
        raise
    audit.record_or_refuse(user, entity, row_id, "approved", reason=body.approved_by.strip(),
                           metadata={"note": body.note})
    return row


@router.post("/policies/{policy_id}/approve", status_code=201)
def approve_policy(policy_id: str, body: Approval, user: dict = Depends(require_permission("policies.approve"))):
    """Record the review. From its effective time, new bookings get it."""
    return _approve("policy_approvals", "policy_id", policy_id, body, user, "policy")


@router.post("/legal-documents/{document_id}/approve", status_code=201)
def approve_document(document_id: str, body: Approval,
                     user: dict = Depends(require_permission("policies.approve"))):
    """Record the review. Users are then asked to accept it (material ones block)."""
    return _approve("legal_document_approvals", "document_id", document_id, body, user, "legal_document")


# ── Overrides ────────────────────────────────────────────────────────────────

class Override(BaseModel):
    # complete: the visit happened but nobody closed it.
    # revert: a consultation was started by mistake; back to confirmed.
    action: Literal["complete", "revert"]
    # The status ops saw. If it has moved since, nothing changes.
    expected_status: str
    reason: str = Field(min_length=10, max_length=1000)


@router.post("/bookings/{booking_id}/override")
def override_booking(booking_id: str, body: Override,
                     user: dict = Depends(require_permission("bookings.override"))):
    """
    Correct a stuck booking. Only through the state machine (ops_complete,
    ops_revert in booking_transitions), recorded as a booking event with the
    reason, and in the audit log with before and after. Money follows the
    normal rules: a completed visit's fee becomes withdrawable 48 hours later.
    """
    before = fetch_one(supabase.table("bookings").select("id, status, completed_at, completion_source")
                       .eq("id", booking_id))
    if not before:
        raise AppError("Booking not found", 404)
    event = "ops_complete" if body.action == "complete" else "ops_revert"
    patch = {"completion_source": "ops"} if body.action == "complete" else {}
    after = booking_state.transition(
        booking_id, event, actor_role="ops", actor_id=user.get("sub"),
        expected=body.expected_status, patch=patch,
        metadata={"reason": body.reason.strip()},
    )
    audit.record_or_refuse(user, "booking", booking_id, f"override_{body.action}", reason=body.reason.strip(),
                           metadata={"before": before, "after": {"status": after.get("status")}})
    return after


# ── Dead letters ─────────────────────────────────────────────────────────────

@router.get("/system/dead-letters")
def dead_letters(user: dict = Depends(require_permission("system.read"))):
    """Work that stopped retrying: jobs out of attempts, webhooks that keep
    failing, and pushes that couldn't be delivered this week."""
    week = (_now() - timedelta(days=7)).isoformat()
    return {
        "jobs": supabase.table("jobs").select("id, kind, payload, attempts, max_attempts, last_error, run_at, updated_at")
                .eq("status", "dead").order("updated_at", desc=True).limit(100).execute().data or [],
        "webhooks": supabase.table("webhook_events").select("id, provider, event_id, event_type, attempts, "
                                                            "last_error, received_at")
                    .is_("processed_at", "null").not_.is_("last_error", "null")
                    .order("received_at", desc=True).limit(100).execute().data or [],
        "notifications": supabase.table("notifications").select("id, event, recipient_role, delivery_error, attempts, created_at")
                         .eq("delivery", "failed").gte("created_at", week)
                         .order("created_at", desc=True).limit(100).execute().data or [],
    }


@router.post("/system/jobs/{job_id}/retry")
def retry_job(job_id: int, user: dict = Depends(require_permission("system.retry"))):
    """Run a dead job again from scratch (its handler is idempotent)."""
    rows = (supabase.table("jobs").update({"status": "queued", "attempts": 0, "run_at": _now().isoformat()})
            .eq("id", job_id).eq("status", "dead").execute().data or [])
    if not rows:
        raise AppError("No dead job with that id", 404)
    audit.record(user, "job", None, "job_retried", metadata={"job_id": job_id, "kind": rows[0].get("kind")})
    return rows[0]


@router.post("/system/webhooks/{webhook_id}/retry")
def retry_webhook(webhook_id: int, user: dict = Depends(require_permission("system.retry"))):
    """Process a stored webhook again, as if it had just arrived (processing
    is idempotent: a payment already captured stays captured once)."""
    row = fetch_one(supabase.table("webhook_events").select("*").eq("id", webhook_id))
    if not row or row.get("processed_at"):
        raise AppError("No failed webhook with that id", 404)
    if row["provider"] != "razorpay":
        raise AppError("Only Razorpay webhooks can be retried here", 400)
    from .payments import _process_webhook
    try:
        result = _process_webhook(row["event_id"], row["payload"], None)
    except Exception as exc:                       # noqa: BLE001
        raise AppError(f"It failed again: {str(exc)[:200]}", 409)
    audit.record(user, "webhook", None, "webhook_retried", metadata={"webhook_id": webhook_id})
    return result


# ── Admin accounts ───────────────────────────────────────────────────────────

@router.get("/admins")
def list_admins(user: dict = Depends(require_permission("admins.manage"))):
    return (supabase.table("admin_users").select("id, email, role, totp_enabled, created_at, last_login_at")
            .order("created_at").execute().data or [])


class RoleChange(BaseModel):
    role: Literal["support", "ops_lead", "finance", "admin"]
    reason: str = Field(min_length=5, max_length=500)


@router.post("/admins/{admin_id}/role")
def set_admin_role(admin_id: str, body: RoleChange, user: dict = Depends(require_permission("admins.manage"))):
    """Takes effect at their next sign-in (tokens carry the role they were
    issued with); revoke their sessions to apply it at once."""
    if admin_id == user.get("sub") and body.role != "admin":
        raise AppError("You can't lower your own role; ask another admin", 409)
    before = fetch_one(supabase.table("admin_users").select("id, email, role").eq("id", admin_id))
    if not before:
        raise AppError("Admin not found", 404)
    row = (supabase.table("admin_users").update({"role": body.role}).eq("id", admin_id)
           .execute().data or [None])[0]
    audit.record_or_refuse(user, "admin_user", admin_id, "role_changed", reason=body.reason,
                           metadata={"before": before["role"], "after": body.role})
    return {k: row.get(k) for k in ("id", "email", "role")}


__all__ = ["router", "admin_roles"]
