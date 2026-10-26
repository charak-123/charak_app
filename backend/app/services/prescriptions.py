"""
Prescriptions: written by the doctor, sent once, opened by the patient
(migration 0025).

    draft ──submit──▶ submitted ──correct──▶ (new draft, version + 1)
                         │                         │ submit
                         └────── superseded ◀──────┘

* **Drafts** are free to change. A draft holds the structured fields, the
  medicines and, optionally, a handwritten prescription upload.
* **Sending** renders the PDF from the record (services/prescription_pdf.py),
  stores it privately, then calls ``submit_prescription()``, which in one
  transaction marks it sent, supersedes the version it corrects, moves the
  booking to 'consulted', and records the follow-up. After that the content
  can't change (a database trigger refuses).
* **Opening** it is the patient's own session reading it. The first time is
  stamped once, and completes the booking if it was waiting (the product rule).
  A prescription nobody opens completes its booking 72 hours after it was sent
  (a queued job; decision D13).
"""
from __future__ import annotations

import logging
from datetime import date, datetime, time, timedelta, timezone
from typing import Optional

from ..db import fetch_one, supabase
from ..errors import AppError
from . import app_config, jobs, notifications, prescription_pdf, storage, visits

logger = logging.getLogger(__name__)

IST = timezone(timedelta(hours=5, minutes=30))
WRITABLE_STATUSES = ("paid", "in_progress", "consulted", "completed")
MAX_ITEMS = 30

_RX_COLUMNS = (
    "id, booking_id, doctor_id, patient_id, version, kind, status, patient_age, patient_sex, "
    "complaints, diagnosis, investigations, advice, tpg_attested, upload_path, upload_mime, "
    "pdf_path, submitted_at, first_viewed_at, supersedes_id, superseded_at, created_at, updated_at"
)
_ITEM_FIELDS = ("medicine", "strength", "form", "dose", "route", "frequency", "duration", "instructions")
_DRAFT_FIELDS = ("kind", "patient_age", "patient_sex", "complaints", "diagnosis",
                 "investigations", "advice", "tpg_attested")


def _now() -> datetime:
    return datetime.now(timezone.utc)


# ── Reads ────────────────────────────────────────────────────────────────────

def get(prescription_id: str) -> Optional[dict]:
    return fetch_one(supabase.table("prescriptions").select(_RX_COLUMNS).eq("id", prescription_id))


def for_booking(booking_id: str, *, status: Optional[str] = None) -> Optional[dict]:
    """The draft (if ``status='draft'``), the sent one (``'submitted'``), or with
    no status the one that matters to the doctor: a draft in progress, else
    the sent one."""
    query = supabase.table("prescriptions").select(_RX_COLUMNS).eq("booking_id", booking_id)
    rows = (query.eq("status", status) if status else query.in_("status", ["draft", "submitted"])) \
        .execute().data or []
    if status or not rows:
        return rows[0] if rows else None
    drafts = [r for r in rows if r["status"] == "draft"]
    return drafts[0] if drafts else rows[0]


def items(prescription_id: str) -> list[dict]:
    return (
        supabase.table("prescription_items").select("*")
        .eq("prescription_id", prescription_id).order("position").execute().data or []
    )


def follow_up_for(prescription_id: str) -> Optional[dict]:
    return fetch_one(
        supabase.table("follow_up_recommendations")
        .select("id, recommended_date, channel, note, status")
        .eq("prescription_id", prescription_id)
    )


def public(rx: dict, *, with_items: bool = True) -> dict:
    """What the apps get: the record, its medicines and its follow-up. Storage
    paths stay server-side."""
    out = {k: rx.get(k) for k in (
        "id", "booking_id", "version", "kind", "status", "patient_age", "patient_sex",
        "complaints", "diagnosis", "investigations", "advice", "tpg_attested",
        "submitted_at", "first_viewed_at", "supersedes_id",
    )}
    out["has_upload"] = bool(rx.get("upload_path"))
    out["has_pdf"] = bool(rx.get("pdf_path"))
    if with_items:
        out["items"] = [{k: i.get(k) for k in ("position", *_ITEM_FIELDS)} for i in items(rx["id"])]
        if rx.get("status") != "draft":
            out["follow_up"] = follow_up_for(rx["id"])
        elif rx.get("supersedes_id"):
            # A correction starts from the recommendation already sent.
            out["follow_up"] = follow_up_for(rx["supersedes_id"])
        else:
            out["follow_up"] = None
    return out


# ── Drafts ───────────────────────────────────────────────────────────────────

def _booking_for_doctor(booking_id: str, doctor_id: str) -> dict:
    b = fetch_one(supabase.table("bookings").select("*").eq("id", booking_id))
    if not b:
        raise AppError("Booking not found", 404)
    if b["doctor_id"] != doctor_id:
        raise AppError("Forbidden", 403)
    if b["status"] not in WRITABLE_STATUSES:
        raise AppError(f"A prescription can't be written for a '{b['status']}' booking", 409)
    return b


_SAVE_REFUSALS = {
    "not_found": ("Booking not found", 404),
    "forbidden": ("Forbidden", 403),
    "sent": ("This prescription has been sent. Issue a correction to change it.", 409),
}


def save_draft(booking_id: str, doctor_id: str, fields: dict, medicines: list[dict]) -> dict:
    """Create or replace the draft for this booking: its fields and its whole
    medicine list, in one transaction (save_prescription_draft, 0025)."""
    if len(medicines) > MAX_ITEMS:
        raise AppError(f"At most {MAX_ITEMS} medicines on one prescription", 400)
    result = supabase.rpc("save_prescription_draft", {
        "p_booking_id": booking_id,
        "p_doctor_id": doctor_id,
        "p_fields": {k: fields.get(k) for k in _DRAFT_FIELDS},
        "p_items": [{k: m.get(k) for k in _ITEM_FIELDS} for m in medicines],
    }).execute().data or {}
    outcome = result.get("outcome")
    if outcome == "ok":
        return result["prescription"]
    if outcome == "wrong_status":
        raise AppError(f"A prescription can't be written for a '{result.get('status')}' booking", 409)
    message, code = _SAVE_REFUSALS.get(outcome, ("Couldn't save the prescription. Try again.", 409))
    raise AppError(message, code)


def attach_upload(booking_id: str, doctor_id: str, content: bytes, extension: str,
                  content_type: str) -> dict:
    """A handwritten prescription, stored privately on the draft."""
    _booking_for_doctor(booking_id, doctor_id)
    draft = for_booking(booking_id, status="draft") or save_draft(booking_id, doctor_id, {}, [])
    path = storage.build_path("bookings", booking_id, "prescriptions", draft["id"], extension=extension)
    storage.upload(storage.BUCKET_PRESCRIPTIONS, path, content, content_type)
    previous = draft.get("upload_path")
    rows = supabase.table("prescriptions").update({"upload_path": path, "upload_mime": content_type}) \
        .eq("id", draft["id"]).eq("status", "draft").execute().data or []
    if not rows:                                   # sent in the meantime
        storage.remove(storage.BUCKET_PRESCRIPTIONS, path)
        raise AppError("This prescription has been sent. Issue a correction to change it.", 409)
    # A correction's draft starts with the sent version's file, which belongs to
    # that version too and stays.
    sent = get(draft["supersedes_id"]) if draft.get("supersedes_id") else None
    if previous and previous != path and (not sent or sent.get("upload_path") != previous):
        storage.remove(storage.BUCKET_PRESCRIPTIONS, previous)
    return rows[0]


# ── Send ─────────────────────────────────────────────────────────────────────

def _validate(rx: dict, medicines: list[dict], booking: dict, follow_up: Optional[dict]) -> None:
    if rx.get("kind") == "notes":
        if not any((rx.get(k) or "").strip() for k in ("advice", "complaints", "diagnosis")):
            raise AppError("Consultation notes need some advice or findings for the patient", 400)
    elif not medicines and not rx.get("upload_path"):
        raise AppError("Add at least one medicine, upload a handwritten prescription, "
                       "or send consultation notes instead", 400)
    if (rx.get("kind") != "notes" and booking.get("channel") == "online_consult"
            and not rx.get("tpg_attested")):
        raise AppError("Confirm you prescribed within the Telemedicine Practice Guidelines "
                       "for an online consultation", 400)
    if follow_up:
        when = follow_up.get("date")
        try:
            parsed = date.fromisoformat(str(when))
        except ValueError:
            raise AppError("Follow-up date must look like 2026-11-02", 400)
        if parsed < datetime.now(IST).date():
            raise AppError("The follow-up date is in the past", 400)
        if follow_up.get("channel") not in ("online_consult", "home_visit", "either"):
            raise AppError("Follow-up channel must be online_consult, home_visit or either", 400)


def submit(booking_id: str, doctor_id: str, follow_up: Optional[dict] = None,
           background=None) -> dict:
    """Send the draft to the patient. Returns the sent prescription."""
    booking = _booking_for_doctor(booking_id, doctor_id)
    draft = for_booking(booking_id, status="draft")
    if draft is None:
        raise AppError("There is no draft to send. Write the prescription first.", 409)
    medicines = items(draft["id"])
    _validate(draft, medicines, booking, follow_up)

    submitted_at = _now()
    doctor = fetch_one(
        supabase.table("doctors").select("name, license_number, application_details, "
                                         "signature_path, categories(name)").eq("id", doctor_id)
    ) or {}
    patient = fetch_one(supabase.table("users").select("name").eq("id", booking["patient_id"])) or {}
    previous = get(draft["supersedes_id"]) if draft.get("supersedes_id") else None
    signature = (storage.download(storage.BUCKET_PRESCRIPTIONS, doctor["signature_path"])
                 if doctor.get("signature_path") else None)

    pdf, sha = prescription_pdf.render(
        {**draft, "submitted_at": submitted_at.isoformat()}, medicines, doctor, patient, booking,
        follow_up={"recommended_date": follow_up["date"], "channel": follow_up["channel"],
                   "note": follow_up.get("note")} if follow_up else None,
        signature=signature,
        supersedes_version=(previous or {}).get("version"),
    )
    path = storage.build_path("bookings", booking_id, "prescriptions", draft["id"], extension="pdf")
    storage.upload(storage.BUCKET_PRESCRIPTIONS, path, pdf, "application/pdf")

    result = supabase.rpc("submit_prescription", {
        "p_prescription_id": draft["id"],
        "p_doctor_id": doctor_id,
        "p_submitted_at": submitted_at.isoformat(),
        "p_pdf_path": path,
        "p_pdf_sha256": sha,
        "p_follow_up": follow_up,
        # The PDF shows the draft as read above; if it was saved again since,
        # nothing is sent.
        "p_draft_updated_at": draft["updated_at"],
    }).execute().data or {}
    if result.get("outcome") != "ok":
        storage.remove(storage.BUCKET_PRESCRIPTIONS, path)
        if result.get("outcome") == "changed":
            raise AppError("The prescription changed while it was being sent. Check it and send again.", 409)
        if result.get("outcome") == "not_draft":
            raise AppError("This prescription has already been sent.", 409)
        raise AppError("This prescription couldn't be sent: the booking has moved on. Refresh.", 409)
    rx = result["prescription"]

    _schedule_after_submit(rx, booking, follow_up)
    if previous:
        notifications.prescription_updated(booking, rx["id"], background)
    else:
        notifications.prescription_ready(booking, rx["id"], background)
    return rx


def _schedule_after_submit(rx: dict, booking: dict, follow_up: Optional[dict]) -> None:
    """The timers a sent prescription starts. Each job checks state again when
    it runs, so a correction or an early open just makes it a no-op."""
    sent = datetime.fromisoformat(str(rx["submitted_at"]).replace("Z", "+00:00"))
    fallback_hours = int(app_config.get("completion_fallback_hours", 72) or 72)
    try:
        # Anchored to the first send: a correction doesn't restart the clock
        # (the dedupe key is the booking's, so only the first one is queued).
        jobs.enqueue("booking.complete_fallback", {"booking_id": rx["booking_id"]},
                     run_at=sent + timedelta(hours=fallback_hours),
                     dedupe_key=f"complete-fallback:{rx['booking_id']}")
        jobs.enqueue("prescription.view_reminder", {"prescription_id": rx["id"]},
                     run_at=sent + timedelta(hours=24), dedupe_key=f"rx-reminder:{rx['id']}")
        if follow_up:
            for when, key in follow_up_reminder_times(date.fromisoformat(follow_up["date"])):
                jobs.enqueue("follow_up.reminder", {"prescription_id": rx["id"], "kind": key},
                             run_at=when, dedupe_key=f"follow-up:{rx['id']}:{key}")
    except Exception as exc:                      # noqa: BLE001 — the prescription is sent
        logger.error("could not schedule follow-ups for prescription %s: %r", rx["id"], exc)


def follow_up_reminder_times(on: date, now: Optional[datetime] = None) -> list[tuple[datetime, str]]:
    """When to remind about a follow-up (decision D17, recommended default):
    at ``hour_ist`` on the day, and ``advance_days`` before when the date is at
    least ``advance_if_days_away`` days off. Times already past are skipped."""
    cfg = app_config.get("follow_up_reminders", {}) or {}
    hour = int(cfg.get("hour_ist", 9))
    advance, threshold = int(cfg.get("advance_days", 2)), int(cfg.get("advance_if_days_away", 7))
    now = now or _now()
    times = [(datetime.combine(on, time(hour), IST), "on_day")]
    if (on - now.astimezone(IST).date()).days >= threshold:
        times.append((datetime.combine(on - timedelta(days=advance), time(hour), IST), "advance"))
    return [(t, k) for t, k in times if t > now]


# ── Corrections ──────────────────────────────────────────────────────────────

def correct(prescription_id: str, doctor_id: str) -> dict:
    """Start a correction: a new draft copying the sent prescription, made in
    one transaction (start_prescription_correction, 0025). Sending it
    supersedes the original, which stays on record unchanged."""
    result = supabase.rpc("start_prescription_correction", {
        "p_prescription_id": prescription_id, "p_doctor_id": doctor_id,
    }).execute().data or {}
    outcome = result.get("outcome")
    if outcome == "ok":
        return result["prescription"]
    if outcome in ("not_found", "forbidden"):
        raise AppError("Prescription not found", 404)
    if outcome == "draft_exists":
        raise AppError("A correction is already being written for this prescription", 409)
    raise AppError("Only the prescription the patient has can be corrected", 409)


# ── The patient opens it ─────────────────────────────────────────────────────

def view(prescription_id: str, patient_id: str) -> dict:
    """Record the patient's open (completing the booking if it was waiting) and
    return the prescription."""
    result = supabase.rpc("record_prescription_view", {
        "p_prescription_id": prescription_id, "p_patient_id": patient_id,
    }).execute().data or {}
    outcome = result.get("outcome")
    if outcome == "forbidden":
        raise AppError("Forbidden", 403)
    if outcome != "ok":
        # A draft is "not found" to the patient: it doesn't exist for them yet.
        raise AppError("Prescription not found", 404)
    rx = get(prescription_id)
    if result.get("completed"):
        visits.after_completion({"id": rx["booking_id"]}, "patient_viewed")
    out = public(rx)
    if rx["status"] == "superseded":
        current = for_booking(rx["booking_id"], status="submitted")
        out["replaced_by_id"] = current["id"] if current else None
    return out


def files(rx: dict) -> dict:
    """Short-lived links to the PDF and any handwritten upload. The caller has
    already checked this person may see this prescription."""
    return {
        "pdf_url": storage.signed_url(storage.BUCKET_PRESCRIPTIONS, rx["pdf_path"])
        if rx.get("pdf_path") else None,
        "upload_url": storage.signed_url(storage.BUCKET_PRESCRIPTIONS, rx["upload_path"])
        if rx.get("upload_path") else None,
        "expires_in": storage.SIGNED_URL_TTL_SECONDS,
    }


# ── Scheduled work (registered with the job queue) ───────────────────────────

@jobs.handler("booking.complete_fallback")
def _complete_fallback(payload: dict) -> None:
    result = supabase.rpc("complete_unviewed_booking", {"p_booking_id": payload["booking_id"]}) \
        .execute().data or {}
    # 'invalid' / 'conflict' mean it's no longer waiting (opened, or completed
    # another way): nothing to do.
    if result.get("outcome") == "ok":
        logger.info("booking %s completed by the 72 h fallback", payload["booking_id"])
        visits.after_completion(result.get("booking") or {"id": payload["booking_id"]}, "fallback")


@jobs.handler("prescription.view_reminder")
def _view_reminder(payload: dict) -> None:
    rx = get(payload["prescription_id"])
    if not rx or rx["status"] != "submitted" or rx.get("first_viewed_at"):
        return
    booking = fetch_one(supabase.table("bookings").select("id, patient_id, doctor_id")
                        .eq("id", rx["booking_id"]))
    if booking:
        notifications.prescription_reminder(booking, rx["id"])


@jobs.handler("follow_up.reminder")
def _follow_up_reminder(payload: dict) -> None:
    rec = fetch_one(
        supabase.table("follow_up_recommendations").select("*")
        .eq("prescription_id", payload["prescription_id"])
    )
    if not rec or rec["status"] != "open":
        return
    notifications.follow_up_reminder(rec, payload.get("kind", "on_day"))
