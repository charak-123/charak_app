"""
Account deletion / DPDP erasure.

A patient deletion erases *personal data* while retaining the de-identified
financial and clinical records the platform is obliged to keep (tax, payment
dispute, doctor earnings reconciliation, medical-record retention). The flow is:

    request_patient_deletion  → soft-delete, block login, stop comms (reversible)
    purge_patient             → scrub PII (run by the cron after the grace window)
    reactivate_patient        → cancel a pending deletion (user logged back in)

See 0013_account_deletion.sql for the schema and docs/… for the column map.
"""
import logging
from datetime import datetime, timedelta, timezone

from ..config import ACCOUNT_DELETION_GRACE_DAYS
from ..db import supabase
from . import storage

logger = logging.getLogger(__name__)


def _now() -> datetime:
    return datetime.now(timezone.utc)


# ── Patient: request (soft-delete) ────────────────────────────────────────────

def request_patient_deletion(user_id: str) -> dict:
    """
    Soft-delete a patient account and stop all outbound contact immediately.

    Personal data is left in place for the grace window so the user can cancel
    by logging back in; the cron purges it once the window closes.
    """
    now = _now()
    supabase.table("users").update({
        "deleted_at": now.isoformat(),
        "deletion_requested_at": now.isoformat(),
        "fcm_token": None,          # stop push to this device at once
        # End every existing session too. Signing back in (which cancels the
        # deletion) issues a fresh token; an old one on a lost phone does not
        # quietly keep working inside a "deleted" account.
        "sessions_revoked_at": now.isoformat(),
    }).eq("id", user_id).execute()

    # Transient personal data that need not survive the grace window at all.
    user = supabase.table("users").select("phone").eq("id", user_id).execute().data
    if user and user[0].get("phone"):
        supabase.table("otp_codes").delete().eq("phone", user[0]["phone"]).execute()
    supabase.table("notifications").delete().eq("recipient_id", user_id).execute()
    # Push reads device_tokens before the legacy fcm_token column, so clearing
    # the column alone left every registered device receiving this account's
    # notifications.
    supabase.table("device_tokens").delete().eq("owner_id", user_id).execute()

    _record_dsr(user_id, "erasure")
    _audit(user_id, "patient", "account_deletion_requested")

    purge_at = now + timedelta(days=ACCOUNT_DELETION_GRACE_DAYS)
    return {"deleted_at": now.isoformat(), "purge_at": purge_at.isoformat(),
            "grace_days": ACCOUNT_DELETION_GRACE_DAYS}


def reactivate_patient(user_id: str) -> None:
    """Cancel a pending deletion — the user logged back in within the grace window."""
    supabase.table("users").update({
        "deleted_at": None,
        "deletion_requested_at": None,
    }).eq("id", user_id).execute()
    _audit(user_id, "patient", "account_deletion_cancelled")


# ── Patient: purge (erase PII) ────────────────────────────────────────────────

def purge_due() -> dict:
    """Purge every patient whose grace window has closed. Called by the cron."""
    cutoff = (_now() - timedelta(days=ACCOUNT_DELETION_GRACE_DAYS)).isoformat()
    rows = (
        supabase.table("users").select("id")
        .not_.is_("deleted_at", "null")
        .lt("deleted_at", cutoff)
        .execute().data
        or []
    )
    purged = [r["id"] for r in rows]
    for uid in purged:
        purge_patient(uid)
    return {"purged": len(purged), "user_ids": purged}


def purge_patient(user_id: str) -> None:
    """
    Erase a patient's personal data, keeping the de-identified records.

    Scrubs identifying fields rather than deleting the user row, so the booking,
    payment and ledger records that reference it stay intact but can no longer be
    tied back to a person.
    """
    bookings = (
        supabase.table("bookings").select("id").eq("patient_id", user_id)
        .execute().data or []
    )
    booking_ids = [b["id"] for b in bookings]

    # 1. Intake media: drop raw files unless a clinician flagged them for review;
    #    always keep the transcript/summary as the clinical record. A file that
    #    could not be deleted keeps its pointer, so the next cron run retries it
    #    instead of orphaning it with nothing left that names it.
    incomplete = False
    for bid in booking_ids:
        media = (
            supabase.table("intake_media")
            .select("id, storage_path, clinical_hold")
            .eq("booking_id", bid).execute().data or []
        )
        for m in media:
            if m.get("clinical_hold"):
                continue
            if m.get("storage_path") and not storage.remove(storage.BUCKET_INTAKE, m["storage_path"]):
                incomplete = True
                continue
            supabase.table("intake_media").update({
                "storage_path": None,
                "file_url": None,
            }).eq("id", m["id"]).execute()

    # 2. Booking address snapshot (where the patient lives) → cleared.
    for bid in booking_ids:
        supabase.table("bookings").update({
            "patient_address": None,
            "patient_address_lat": None,
            "patient_address_lng": None,
        }).eq("id", bid).execute()

    # 3. Patient-authored free text → redacted. Review comments live in `reviews`
    #    (migration 0027) and need the database function: a review is otherwise
    #    frozen after its edit window. Scores stay; the doctor's rating is built
    #    from them. If the function is missing (migration 0032 not applied) the
    #    erasure is not complete and must say so.
    try:
        supabase.rpc("redact_patient_reviews", {"p_patient_id": user_id}).execute()
    except Exception as exc:                                  # noqa: BLE001
        logger.error("could not erase review comments for %s: %r", user_id, exc)
        incomplete = True
    for bid in booking_ids:
        supabase.table("ratings").update({"comment": None}).eq("booking_id", bid).execute()
        supabase.table("complaints").update(
            {"description": "[redacted on account deletion]"}
        ).eq("booking_id", bid).execute()

    # 4. Saved addresses: pure PII, no retention basis → hard delete.
    supabase.table("patient_addresses").delete().eq("patient_id", user_id).execute()

    # 5. The identity itself. phone becomes a tombstone sentinel that frees the
    #    real number for a fresh signup; the Google and Firebase links and the
    #    email go too, so the same account signs up afresh instead of landing
    #    back on this row (and silently "reactivating" it).
    supabase.table("users").update({
        "phone": f"deleted:{user_id}",
        "email": None,
        "google_sub": None,
        "firebase_uid": None,
        "name": None,
        "fcm_token": None,
        "otp_verified": False,
    }).eq("id", user_id).execute()
    supabase.table("device_tokens").delete().eq("owner_id", user_id).execute()

    if incomplete:
        # Not done: leave the request pending so the next run finishes it.
        logger.error("erasure of %s left files behind; request stays pending", user_id)
        return
    _mark_dsr_fulfilled(user_id)
    _audit(user_id, "patient", "account_purged")


# ── Doctor: request (ops fulfils) ─────────────────────────────────────────────

def request_doctor_deletion(doctor_id: str) -> dict:
    """
    Record a doctor's deletion request and lock the account for ops to fulfil.

    Doctors are not auto-purged: outstanding payouts, active bookings and bank
    details have to be settled by a person first.
    """
    now = _now()
    supabase.table("doctors").update({
        "deletion_requested_at": now.isoformat(),
        "deletion_status": "requested",
        "suspended": True,
        "suspended_reason": "account deletion requested",
        "suspended_at": now.isoformat(),
        "fcm_token": None,
        "sessions_revoked_at": now.isoformat(),
    }).eq("id", doctor_id).execute()
    supabase.table("device_tokens").delete().eq("owner_id", doctor_id).execute()
    _record_dsr(doctor_id, "erasure")
    _audit(doctor_id, "doctor", "account_deletion_requested")
    return {"status": "requested", "requested_at": now.isoformat()}


def purge_doctor(doctor_id: str) -> None:
    """
    Erase a doctor's personal data once ops has settled their account.

    Retains the de-identified doctor row (bookings, ledger entries and payouts
    reference it) but removes identifying details, identity documents and bank
    details. Call only after payouts are cleared and active bookings resolved.
    """
    doctor = (
        supabase.table("doctors")
        .select("photo_path, verification_document_path, signature_path")
        .eq("id", doctor_id).execute().data
    )
    # Pointers are forgotten only for files that are really gone.
    gone = {"photo_path": True, "verification_document_path": True, "signature_path": True}
    if doctor:
        d = doctor[0]
        for column, bucket in (
            ("photo_path", storage.BUCKET_DOCTOR_PHOTOS),
            ("verification_document_path", storage.BUCKET_VERIFICATION),
            ("signature_path", storage.BUCKET_PRESCRIPTIONS),
        ):
            if d.get(column):
                gone[column] = storage.remove(bucket, d[column])

    supabase.table("doctor_bank_accounts").delete().eq("doctor_id", doctor_id).execute()

    supabase.table("doctors").update({
        "phone": f"deleted:{doctor_id}",
        "email": None,
        "google_sub": None,
        "firebase_uid": None,
        "name": None,
        "bio": None,
        # Qualification, college, council registration, NUID, HPR ID.
        "application_details": None,
        "photo_url": None,
        "license_number": None,
        "verification_document_url": None,
        "verification_document_mime": None,
        # The doctor's own location and the free-text reason ops gave on rejection.
        "base_lat": None,
        "base_lng": None,
        "verification_rejection_reason": None,
        "fcm_token": None,
        "otp_verified": False,
        # A token minted after the deletion request would otherwise outlive the purge.
        "sessions_revoked_at": _now().isoformat(),
        "deletion_status": "fulfilled",
        "deletion_requested_at": None,
        **{column: None for column, ok in gone.items() if ok},
    }).eq("id", doctor_id).execute()
    supabase.table("device_tokens").delete().eq("owner_id", doctor_id).execute()

    if not all(gone.values()):
        logger.error("erasure of doctor %s left files behind; request stays pending", doctor_id)
        return
    _mark_dsr_fulfilled(doctor_id)
    _audit(doctor_id, "doctor", "account_purged")


# ── Shared helpers ────────────────────────────────────────────────────────────

def _record_dsr(user_id: str, type_: str) -> None:
    supabase.table("dsr_requests").insert({
        "user_id": user_id, "type": type_, "status": "pending",
    }).execute()


def _mark_dsr_fulfilled(user_id: str) -> None:
    supabase.table("dsr_requests").update(
        {"status": "fulfilled", "fulfilled_at": _now().isoformat()}
    ).eq("user_id", user_id).eq("type", "erasure").eq("status", "pending").execute()


def _audit(actor_id: str, actor_role: str, action: str) -> None:
    supabase.table("audit_log").insert({
        "actor_id": actor_id, "actor_role": actor_role,
        "entity": "account", "entity_id": actor_id, "action": action,
    }).execute()
