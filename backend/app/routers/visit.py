"""
The visit (migration 0025): Start Journey, the consultation, prescriptions and
follow-ups. Three routers, mounted in main.py:

    router         /bookings/{id}/journey/start, /consultation/start, /prescription…
    rx_router      /prescriptions/{id}…
    me_router      /me/follow-ups…

Who may see a prescription: its patient and its doctor. Ops read one only
through the audited break-glass endpoint in routers/admin.py.
"""
from __future__ import annotations

from datetime import date
from typing import Literal, Optional

from fastapi import APIRouter, BackgroundTasks, Depends, File, UploadFile
from pydantic import BaseModel, Field

from ..db import fetch_one, supabase
from ..deps import get_current_user, require_doctor, require_patient
from ..errors import AppError
from ..services import prescriptions, storage, visits
from ..services.rate_limit import rate_limiter
from .uploads import _read

router = APIRouter()
rx_router = APIRouter()
me_router = APIRouter()


def _booking(booking_id: str) -> dict:
    b = fetch_one(supabase.table("bookings").select("*").eq("id", booking_id))
    if not b:
        raise AppError("Booking not found", 404)
    return b


def _own_booking_as_doctor(booking_id: str, doctor_id: str) -> dict:
    b = _booking(booking_id)
    if b["doctor_id"] != doctor_id:
        raise AppError("Forbidden", 403)
    return b


# ── Journey and consultation ─────────────────────────────────────────────────

@router.post("/{booking_id}/journey/start")
def start_journey(booking_id: str, background: BackgroundTasks,
                  user: dict = Depends(require_doctor)):
    """
    The doctor has left for a home visit. The server records the time (it
    can't be backdated); a second tap returns the first journey. From now a
    patient cancellation refunds nothing (LD-005), and the patient is told
    their doctor is on the way.
    """
    return visits.start_journey(booking_id, user["sub"], background)


@router.post("/{booking_id}/consultation/start")
def start_consultation(booking_id: str, user: dict = Depends(require_doctor)):
    """The consultation has begun (the doctor is with the patient, or on the
    call). For online consults joining the call does this too."""
    return visits.start_consultation(_own_booking_as_doctor(booking_id, user["sub"]), user["sub"])


# ── Prescription: the doctor writes it ───────────────────────────────────────

class Medicine(BaseModel):
    medicine: str = Field(min_length=1, max_length=200)
    strength: Optional[str] = Field(default=None, max_length=80)
    form: Optional[str] = Field(default=None, max_length=60)
    dose: Optional[str] = Field(default=None, max_length=80)
    route: Optional[str] = Field(default=None, max_length=60)
    frequency: Optional[str] = Field(default=None, max_length=80)
    duration: Optional[str] = Field(default=None, max_length=80)
    instructions: Optional[str] = Field(default=None, max_length=500)


class PrescriptionDraft(BaseModel):
    kind: Literal["prescription", "notes"] = "prescription"
    patient_age: Optional[int] = Field(default=None, ge=0, le=130)
    patient_sex: Optional[Literal["female", "male", "other"]] = None
    complaints: Optional[str] = Field(default=None, max_length=2000)
    diagnosis: Optional[str] = Field(default=None, max_length=2000)
    investigations: Optional[str] = Field(default=None, max_length=2000)
    advice: Optional[str] = Field(default=None, max_length=4000)
    tpg_attested: bool = False
    items: list[Medicine] = Field(default_factory=list, max_length=prescriptions.MAX_ITEMS)


class FollowUp(BaseModel):
    date: date
    channel: Literal["online_consult", "home_visit", "either"]
    note: Optional[str] = Field(default=None, max_length=500)


class SubmitRequest(BaseModel):
    # None: no follow-up recommended.
    follow_up: Optional[FollowUp] = None


@router.get("/{booking_id}/prescription")
def get_booking_prescription(booking_id: str, user: dict = Depends(get_current_user)):
    """
    The doctor gets the prescription they're working on (a draft, else the
    sent one) in full, plus ``sent`` when a correction is being written.

    The patient gets only whether one is waiting and its id: its content comes
    from POST /prescriptions/{id}/view, so reading it always records the view.
    """
    b = _booking(booking_id)
    if user["sub"] == b["doctor_id"]:
        rx = prescriptions.for_booking(booking_id)
        if rx is None:
            return {"prescription": None, "sent": None}
        sent = (prescriptions.for_booking(booking_id, status="submitted")
                if rx["status"] == "draft" else None)
        return {"prescription": prescriptions.public(rx),
                "sent": prescriptions.public(sent, with_items=False) if sent else None}
    if user["sub"] == b["patient_id"]:
        rx = prescriptions.for_booking(booking_id, status="submitted")
        return {"prescription": {k: rx[k] for k in ("id", "version", "kind", "submitted_at",
                                                     "first_viewed_at")} if rx else None}
    raise AppError("Forbidden", 403)


@router.put("/{booking_id}/prescription", dependencies=[rate_limiter("rx-draft", 120, 600)])
def save_prescription_draft(booking_id: str, body: PrescriptionDraft,
                            user: dict = Depends(require_doctor)):
    """Create or replace the draft. Nothing reaches the patient until it's sent."""
    fields = body.model_dump(exclude={"items"})
    rx = prescriptions.save_draft(booking_id, user["sub"], fields,
                                  [m.model_dump() for m in body.items])
    return prescriptions.public(rx)


@router.post("/{booking_id}/prescription/upload", status_code=201,
             dependencies=[rate_limiter("rx-upload", 20, 600)])
async def upload_handwritten_prescription(booking_id: str, file: UploadFile = File(...),
                                          user: dict = Depends(require_doctor)):
    """A photo or PDF of a handwritten prescription, attached to the draft."""
    content, ext, content_type = await _read(file, "prescription_upload")
    rx = prescriptions.attach_upload(booking_id, user["sub"], content, ext, content_type)
    return prescriptions.public(rx)


@router.delete("/{booking_id}/prescription/upload")
def remove_handwritten_prescription(booking_id: str, user: dict = Depends(require_doctor)):
    _own_booking_as_doctor(booking_id, user["sub"])
    draft = prescriptions.for_booking(booking_id, status="draft")
    if not draft:
        raise AppError("There is no draft to change", 409)
    if draft.get("upload_path"):
        supabase.table("prescriptions").update({"upload_path": None, "upload_mime": None}) \
            .eq("id", draft["id"]).eq("status", "draft").execute()
        # A correction's draft shares the sent version's file; that one stays.
        sent = prescriptions.get(draft["supersedes_id"]) if draft.get("supersedes_id") else None
        if not sent or sent.get("upload_path") != draft["upload_path"]:
            storage.remove(storage.BUCKET_PRESCRIPTIONS, draft["upload_path"])
    return prescriptions.public(prescriptions.get(draft["id"]))


@router.post("/{booking_id}/prescription/submit",
             dependencies=[rate_limiter("rx-submit", 10, 600)])
def submit_prescription(booking_id: str, background: BackgroundTasks,
                        body: Optional[SubmitRequest] = None,
                        user: dict = Depends(require_doctor)):
    """
    Send the draft to the patient. After this it can't change; a mistake is
    fixed with POST /prescriptions/{id}/correct. The booking moves to
    'consulted' and completes when the patient opens it, or 72 hours later.
    """
    follow_up = body.follow_up if body else None
    rx = prescriptions.submit(
        booking_id, user["sub"],
        follow_up={"date": follow_up.date.isoformat(), "channel": follow_up.channel,
                   "note": (follow_up.note or "").strip() or None} if follow_up else None,
        background=background,
    )
    return prescriptions.public(rx)


# ── Prescription by id ───────────────────────────────────────────────────────

def _rx_for(prescription_id: str, user: dict) -> dict:
    rx = prescriptions.get(prescription_id)
    if not rx:
        raise AppError("Prescription not found", 404)
    if user["sub"] == rx["doctor_id"]:
        return rx
    if user["sub"] == rx["patient_id"] and rx["status"] != "draft":
        return rx
    if user["sub"] == rx["patient_id"]:
        raise AppError("Prescription not found", 404)
    raise AppError("Forbidden", 403)


@rx_router.get("/{prescription_id}")
def get_prescription(prescription_id: str, user: dict = Depends(require_doctor)):
    """The doctor's own record. (Patients read it through /view.)"""
    return prescriptions.public(_rx_for(prescription_id, user))


@rx_router.post("/{prescription_id}/view")
def view_prescription(prescription_id: str, user: dict = Depends(require_patient)):
    """
    The patient opens their prescription. The first open is recorded once, by
    the server, and completes the booking if it was waiting on it. Only the
    patient's own session can do this; anyone else gets 403 and nothing changes.
    """
    return prescriptions.view(prescription_id, user["sub"])


@rx_router.get("/{prescription_id}/files", dependencies=[rate_limiter("rx-files", 60, 600)])
def prescription_files(prescription_id: str, user: dict = Depends(get_current_user)):
    """Short-lived links to the PDF and any handwritten upload. Downloading
    isn't a view: only opening it in the app (POST /view) is."""
    return prescriptions.files(_rx_for(prescription_id, user))


@rx_router.post("/{prescription_id}/correct", status_code=201)
def correct_prescription(prescription_id: str, user: dict = Depends(require_doctor)):
    """Start a correction: a new draft copying the sent prescription. The sent
    one stays with the patient until the correction is sent."""
    return prescriptions.public(prescriptions.correct(prescription_id, user["sub"]))


# ── Follow-ups (the patient) ─────────────────────────────────────────────────

@me_router.get("/follow-ups")
def my_follow_ups(user: dict = Depends(require_patient)):
    """Open follow-up recommendations, soonest first. Nothing here is booked
    or charged: each is the doctor's recommendation with a Book button."""
    rows = (
        supabase.table("follow_up_recommendations")
        .select("id, booking_id, doctor_id, recommended_date, channel, note, status, created_at, "
                "doctors(name, photo_url, categories(name))")
        .eq("patient_id", user["sub"]).eq("status", "open")
        .order("recommended_date").execute().data or []
    )
    return rows


@me_router.post("/follow-ups/{follow_up_id}/dismiss")
def dismiss_follow_up(follow_up_id: str, user: dict = Depends(require_patient)):
    rec = fetch_one(supabase.table("follow_up_recommendations").select("id, patient_id, status")
                    .eq("id", follow_up_id))
    if not rec or rec["patient_id"] != user["sub"]:
        raise AppError("Follow-up not found", 404)
    if rec["status"] == "open":
        supabase.table("follow_up_recommendations").update({"status": "dismissed"}) \
            .eq("id", follow_up_id).eq("status", "open").execute()
    return {"id": follow_up_id, "status": "dismissed" if rec["status"] == "open" else rec["status"]}
