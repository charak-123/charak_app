"""
Upload endpoints.

Every file the product needs — a doctor's photo, their licence document, a
patient's intake photos, video and voice notes — comes through here. See
``services/storage.py`` for why this cannot be done from the client.

Reads of private objects are also here, because deciding who may see a licence
document or a patient's wound photo is the same decision as deciding who may
write one, and splitting it across modules is how those two drift apart.
"""

from fastapi import APIRouter, BackgroundTasks, Depends, File, Query, UploadFile

from ..db import fetch_one, supabase
from ..deps import get_current_user, require_doctor, require_ops
from ..errors import AppError
from ..services import storage, transcription

router = APIRouter()

INTAKE_KIND_BY_MEDIA = {
    "image": "intake_image",
    "voice": "intake_audio",
    "video": "intake_video",
}


async def _read(file: UploadFile, kind: str) -> tuple[bytes, str, str]:
    """
    Read an upload into memory and validate it.

    Reading fully into memory is deliberate at these size caps (50MB worst case):
    the content type must be validated and, for voice notes, the same bytes handed
    to transcription, and streaming to Storage twice is worse than holding one
    copy briefly.
    """
    content = await file.read()
    extension = storage.validate(kind, file.content_type, len(content))
    return content, extension, (file.content_type or "").split(";")[0].strip().lower()


# ── Doctor profile photo ─────────────────────────────────────────────────────

@router.post("/doctor/photo", status_code=201)
async def upload_doctor_photo(
    file: UploadFile = File(...),
    user: dict = Depends(require_doctor),
):
    """
    Replace the doctor's directory photo.

    Public bucket, so the returned URL is durable and the directory can render it
    without minting anything. The previous object is deleted after the new row is
    written — losing an orphaned file is recoverable, losing the live photo is not.
    """
    content, ext, content_type = await _read(file, "photo")

    doctor = fetch_one(supabase.table("doctors").select("photo_path").eq("id", user["sub"]))
    if doctor is None:
        raise AppError("Doctor profile not found", 404)

    path = storage.build_path("doctors", user["sub"], "photo", extension=ext)
    storage.upload(storage.BUCKET_DOCTOR_PHOTOS, path, content, content_type)
    url = storage.public_url(storage.BUCKET_DOCTOR_PHOTOS, path)

    updated = supabase.table("doctors").update({
        "photo_path": path,
        "photo_url": url,
    }).eq("id", user["sub"]).execute().data[0]

    if doctor.get("photo_path") and doctor["photo_path"] != path:
        storage.remove(storage.BUCKET_DOCTOR_PHOTOS, doctor["photo_path"])

    return {"photo_url": url, "photo_path": path, "doctor": updated}


# ── Verification document ────────────────────────────────────────────────────

@router.post("/doctor/verification-document", status_code=201)
async def upload_verification_document(
    file: UploadFile = File(...),
    user: dict = Depends(require_doctor),
):
    """
    Submit a licence or ID for verification.

    Private bucket: this is identity documentation, not directory content. Storing
    it moves the doctor back to 'pending' and clears any prior rejection reason,
    so re-submitting after a rejection re-enters the queue rather than sitting in
    a rejected state with a new document attached.
    """
    content, ext, content_type = await _read(file, "document")

    previous = fetch_one(
        supabase.table("doctors").select("verification_document_path").eq("id", user["sub"])
    )
    if previous is None:
        raise AppError("Doctor profile not found", 404)

    path = storage.build_path("doctors", user["sub"], "verification", extension=ext)
    storage.upload(storage.BUCKET_VERIFICATION, path, content, content_type)

    updated = supabase.table("doctors").update({
        "verification_document_path": path,
        "verification_document_mime": content_type,
        "verification_status": "pending",
        "verification_rejection_reason": None,
    }).eq("id", user["sub"]).execute().data[0]

    if previous.get("verification_document_path") and previous["verification_document_path"] != path:
        storage.remove(storage.BUCKET_VERIFICATION, previous["verification_document_path"])

    return {
        "verification_document_path": path,
        "verification_status": "pending",
        "doctor": updated,
    }


@router.get("/doctor/{doctor_id}/verification-document")
def read_verification_document(doctor_id: str, user: dict = Depends(get_current_user)):
    """
    Signed URL for a doctor's verification document.

    Readable by ops — this is what the admin verification queue previews — and by
    the doctor themselves, so they can confirm what they submitted. Nobody else:
    patients have no business reading a doctor's identity documents.
    """
    if user.get("role") != "ops" and user.get("sub") != doctor_id:
        raise AppError("Forbidden", 403)

    doctor = fetch_one(
        supabase.table("doctors")
        .select("verification_document_path, verification_document_mime")
        .eq("id", doctor_id)
    )
    if not doctor:
        raise AppError("Doctor not found", 404)
    if not doctor.get("verification_document_path"):
        raise AppError("No verification document has been submitted", 404)

    return {
        "url": storage.signed_url(storage.BUCKET_VERIFICATION,
                                  doctor["verification_document_path"]),
        "mime_type": doctor.get("verification_document_mime"),
        "expires_in": storage.SIGNED_URL_TTL_SECONDS,
    }


# ── Intake media ─────────────────────────────────────────────────────────────

@router.post("/bookings/{booking_id}/intake", status_code=201)
async def upload_intake_media(
    booking_id: str,
    background: BackgroundTasks,
    media_type: str = Query(..., pattern="^(image|voice|video)$"),
    file: UploadFile = File(...),
    user: dict = Depends(get_current_user),
):
    """
    Attach a photo, video or voice note to a booking's intake.

    Only the patient may add intake — it is their description of their own
    complaint. Voice notes are queued for transcription so the doctor can read
    them; the upload is acknowledged immediately rather than waiting on it.
    """
    booking = fetch_one(
        supabase.table("bookings").select("patient_id, doctor_id, status").eq("id", booking_id)
    )
    if not booking:
        raise AppError("Booking not found", 404)
    if booking["patient_id"] != user["sub"]:
        raise AppError("Only the patient may add intake media", 403)
    if booking["status"] in ("completed", "cancelled", "declined", "no_show"):
        raise AppError(f"Cannot add intake to a {booking['status']} booking", 400)

    content, ext, content_type = await _read(file, INTAKE_KIND_BY_MEDIA[media_type])

    path = storage.build_path("bookings", booking_id, media_type, extension=ext)
    storage.upload(storage.BUCKET_INTAKE, path, content, content_type)

    row = supabase.table("intake_media").insert({
        "booking_id": booking_id,
        "media_type": media_type,
        "storage_path": path,
        "mime_type": content_type,
        "size_bytes": len(content),
        "transcript_status": "pending" if media_type == "voice" else "none",
    }).execute().data[0]

    if media_type == "voice":
        background.add_task(
            transcription.transcribe_media, row["id"], content, f"voice.{ext}", content_type
        )

    return {
        **row,
        "transcription_enabled": transcription.enabled(),
    }


@router.get("/intake/{media_id}")
def read_intake_media(media_id: str, user: dict = Depends(get_current_user)):
    """
    Signed URL for one intake attachment.

    Readable by the booking's patient and doctor only. Ops are deliberately
    excluded: a complaint needs the booking's context, not the patient's clinical
    photographs, and the narrower grant is the right default for health data.
    """
    media = fetch_one(
        supabase.table("intake_media").select("*, bookings(patient_id, doctor_id)")
        .eq("id", media_id)
    )
    if not media:
        raise AppError("Intake media not found", 404)

    booking = media.get("bookings") or {}
    if user["sub"] not in (booking.get("patient_id"), booking.get("doctor_id")):
        raise AppError("Forbidden", 403)
    if not media.get("storage_path"):
        raise AppError("This intake item has no stored file", 404)

    return {
        "url": storage.signed_url(storage.BUCKET_INTAKE, media["storage_path"]),
        "media_type": media["media_type"],
        "mime_type": media.get("mime_type"),
        "expires_in": storage.SIGNED_URL_TTL_SECONDS,
    }


# ── Ops bootstrap ────────────────────────────────────────────────────────────

@router.post("/buckets/ensure")
def ensure_buckets(user: dict = Depends(require_ops)):
    """
    Create any missing Storage bucket.

    Deliberately an explicit ops action rather than something a process does on
    startup: creating buckets changes shared infrastructure, and it should happen
    because somebody asked, once, not on every deploy.
    """
    return storage.ensure_buckets()
