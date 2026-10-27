"""
When a visit goes wrong (migration 0028): reporting a problem, the patient's
remedy, the doctor's response and appeal, and reschedules. Mounted in main.py:

    router            /bookings/{id}/help, /issues, /reschedule-request(s)
    incidents_router  /incidents/{id}/remedy/refund, /respond, /appeal
    reschedule_router /reschedule-requests/{id}/accept, /decline
"""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Literal, Optional

from fastapi import APIRouter, BackgroundTasks, Depends
from pydantic import BaseModel, Field

from ..db import fetch_one, supabase
from ..deps import get_current_user, require_doctor, require_patient
from ..errors import AppError
from ..services import incidents, remedies, reschedules
from ..services.rate_limit import rate_limiter

router = APIRouter()
incidents_router = APIRouter()
reschedule_router = APIRouter()


def _reschedule_view(req: Optional[dict]) -> Optional[dict]:
    if not req:
        return None
    return {k: req.get(k) for k in ("id", "booking_id", "cause", "note", "options", "status", "expires_at")}


# ── The patient: help with a booking ─────────────────────────────────────────

@router.get("/{booking_id}/help")
def booking_help(booking_id: str, user: dict = Depends(get_current_user)):
    """
    What the patient can do about a visit going wrong right now: when "Doctor
    hasn't arrived/joined?" opens, any case already open (with its remedy
    options), and any new times the doctor has proposed.
    """
    b = fetch_one(supabase.table("bookings").select("*").eq("id", booking_id))
    if not b:
        raise AppError("Booking not found", 404)
    if user["sub"] not in (b["patient_id"], b["doctor_id"]):
        raise AppError("Forbidden", 403)
    inc = incidents.open_for_booking(booking_id)
    is_patient = user["sub"] == b["patient_id"]
    opens = incidents.help_opens_at(b)
    now = datetime.now(timezone.utc)
    can = []
    if is_patient and not (inc and inc["status"] in ("reported", "under_review") and inc["reported_by_role"] == "patient"):
        if b["status"] == "paid" and now >= opens:
            can.append("doctor_not_arrived" if b["channel"] == "home_visit" else "doctor_not_joined")
        if b["channel"] == "online_consult" and b["status"] in ("paid", "in_progress"):
            can.append("call_failed")
        if b["status"] in ("paid", "in_progress", "consulted"):
            can.append("other")
    view = None
    if inc:
        view = incidents.public(inc)
        if not is_patient:
            view.pop("patient_note", None)
        if is_patient:
            view["remedies"] = remedies.options(inc)
    return {
        "help_opens_at": opens.isoformat(),
        "grace_minutes": incidents.grace_minutes(b["channel"]),
        "can_report": can,
        "incident": view,
        "reschedule_request": _reschedule_view(reschedules.open_for_booking(booking_id)),
    }


class IssueReport(BaseModel):
    reported_as: Literal["doctor_not_arrived", "doctor_not_joined", "call_failed", "other"]
    note: Optional[str] = Field(default=None, max_length=1000)


@router.post("/{booking_id}/issues", status_code=201, dependencies=[rate_limiter("report-issue", 10, 3600)])
def report_issue(booking_id: str, body: IssueReport, background: BackgroundTasks,
                 user: dict = Depends(require_patient)):
    """Report a problem. Returns the case (CHK-…), and if the evidence already
    supports it, the refund or another doctor the patient can choose now."""
    inc = incidents.report(booking_id, user["sub"], body.reported_as, body.note, background)
    return {**incidents.public(inc), "remedies": remedies.options(inc)}


# ── The doctor: moving a visit ───────────────────────────────────────────────

class RescheduleProposal(BaseModel):
    cause: Literal["doctor_unavailable", "doctor_device", "patient_device", "platform", "mutual", "other"]
    options: list[str] = Field(min_length=1, max_length=3)
    note: Optional[str] = Field(default=None, max_length=500)


@router.post("/{booking_id}/reschedule-requests", status_code=201,
             dependencies=[rate_limiter("reschedule", 10, 3600)])
def propose_reschedule(booking_id: str, body: RescheduleProposal, background: BackgroundTasks,
                       user: dict = Depends(require_doctor)):
    """Can't make it, or the call failed: offer up to three new times. The
    patient picks one, or takes a full refund."""
    return reschedules.propose(booking_id, user["sub"], body.cause, body.options, body.note, background)


@router.get("/{booking_id}/reschedule-request")
def get_reschedule(booking_id: str, user: dict = Depends(get_current_user)):
    b = fetch_one(supabase.table("bookings").select("patient_id, doctor_id").eq("id", booking_id))
    if not b:
        raise AppError("Booking not found", 404)
    if user["sub"] not in (b["patient_id"], b["doctor_id"]):
        raise AppError("Forbidden", 403)
    return _reschedule_view(reschedules.open_for_booking(booking_id))


# ── Incidents ────────────────────────────────────────────────────────────────

@incidents_router.post("/{incident_id}/remedy/refund")
def choose_refund(incident_id: str, background: BackgroundTasks, user: dict = Depends(require_patient)):
    """A full refund of what the patient paid for that visit."""
    return remedies.refund(incident_id, "patient", user["sub"], background)


class Note(BaseModel):
    note: str = Field(min_length=5, max_length=1000)


@incidents_router.post("/{incident_id}/respond")
def respond(incident_id: str, body: Note, user: dict = Depends(require_doctor)):
    """The doctor's account of what happened. Ops reads it before deciding."""
    return incidents.public(incidents.respond(incident_id, user["sub"], body.note))


@incidents_router.post("/{incident_id}/appeal")
def appeal(incident_id: str, body: Note, user: dict = Depends(require_doctor)):
    """Contest a confirmed case that counts against you (once, within 7 days)."""
    return incidents.public(incidents.appeal(incident_id, user["sub"], body.note))


# ── Reschedule answers ───────────────────────────────────────────────────────

class RescheduleChoice(BaseModel):
    start: str


@reschedule_router.post("/{request_id}/accept")
def accept_reschedule(request_id: str, body: RescheduleChoice, background: BackgroundTasks,
                      user: dict = Depends(require_patient)):
    return reschedules.accept(request_id, user["sub"], body.start, background)


@reschedule_router.post("/{request_id}/decline")
def decline_reschedule(request_id: str, background: BackgroundTasks, user: dict = Depends(require_patient)):
    """None of the new times work: a full refund."""
    return reschedules.decline(request_id, user["sub"], background)
