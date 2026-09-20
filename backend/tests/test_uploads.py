"""
Tests for backend-mediated uploads and private-object reads.

Client-side Storage writes can never work here — the apps hold a JWT this API
issues, not a Supabase Auth session, so auth.uid() is null inside any Storage
policy. These endpoints are the only working path, which makes their
authorisation and validation the whole of the security boundary.
"""
from unittest.mock import MagicMock, patch

import pytest
from fastapi.testclient import TestClient

from app.errors import AppError
from app.main import app
from app.services import storage
from tests.conftest import make_chain, make_supabase

PATIENT = {"sub": "pat-1", "role": "patient"}
DOCTOR  = {"sub": "doc-1", "role": "doctor"}
OPS     = {"sub": "admin", "role": "ops"}
AUTH    = {"Authorization": "Bearer t"}

UP_DB   = "app.routers.uploads.supabase"
JWT     = "app.deps.jwt"

PNG = (b"\x89PNG\r\n\x1a\n" + b"\x00" * 200, "image/png")


def _client(payload, db):
    with patch(UP_DB, db), patch(JWT) as jw:
        jw.decode.return_value = payload
        yield TestClient(app)


# ── validation ────────────────────────────────────────────────────────────────

def test_validate_accepts_a_known_type_and_returns_its_extension():
    assert storage.validate("photo", "image/png", 1000) == "png"
    assert storage.validate("document", "application/pdf", 1000) == "pdf"
    assert storage.validate("intake_audio", "audio/mp4", 1000) == "m4a"


def test_validate_strips_charset_parameters():
    """Browsers and Dart http clients both append parameters to content types."""
    assert storage.validate("photo", "image/png; charset=binary", 1000) == "png"


def test_validate_rejects_a_disallowed_type_with_415():
    with pytest.raises(AppError) as exc:
        storage.validate("photo", "application/pdf", 1000)
    assert exc.value.status_code == 415


def test_a_pdf_is_a_valid_document_but_not_a_valid_photo():
    """Licences are often PDFs; directory photos never are."""
    assert storage.validate("document", "application/pdf", 1000)
    with pytest.raises(AppError):
        storage.validate("photo", "application/pdf", 1000)


def test_validate_rejects_an_oversized_file_with_413_and_a_usable_message():
    with pytest.raises(AppError) as exc:
        storage.validate("photo", "image/png", 9 * storage.MB)
    assert exc.value.status_code == 413
    assert "the limit is 5MB" in exc.value.message


def test_validate_rejects_an_empty_file():
    with pytest.raises(AppError) as exc:
        storage.validate("photo", "image/png", 0)
    assert exc.value.status_code == 400


def test_validate_rejects_a_missing_content_type():
    with pytest.raises(AppError):
        storage.validate("photo", None, 1000)


def test_video_limits_are_larger_than_photo_limits():
    """A phone-shot video of a wound is legitimately large; a profile photo is not."""
    assert storage.LIMITS["intake_video"][1] > storage.LIMITS["photo"][1]


# ── paths ─────────────────────────────────────────────────────────────────────

def test_paths_are_prefixed_by_owner_and_randomly_suffixed():
    p1 = storage.build_path("doctors", "doc-1", "photo", extension="png")
    p2 = storage.build_path("doctors", "doc-1", "photo", extension="png")
    assert p1.startswith("doctors/doc-1/photo/")
    assert p1.endswith(".png")
    assert p1 != p2          # one upload never silently overwrites another


def test_path_traversal_in_a_prefix_cannot_escape():
    """A caller-influenced component must not be able to climb out of its prefix."""
    path = storage.build_path("doctors", "../../etc", "photo", extension="png")
    assert ".." not in path
    assert path.startswith("doctors/etc/photo/")


def test_a_private_bucket_refuses_to_produce_a_public_url():
    with pytest.raises(AppError):
        storage.public_url(storage.BUCKET_VERIFICATION, "doctors/doc-1/x.pdf")


# ── doctor photo ──────────────────────────────────────────────────────────────

def _photo_db(previous_path=None):
    doctors = make_chain()
    doctors.execute.side_effect = [
        MagicMock(data={"photo_path": previous_path}),   # fetch_one
        MagicMock(data=[{"id": "doc-1", "photo_url": "https://cdn/x.png"}]),
    ]
    return make_supabase({"doctors": doctors}), doctors


def test_a_doctor_photo_upload_stores_the_path_and_the_public_url():
    db, doctors = _photo_db()
    content, ct = PNG
    with patch("app.services.storage.upload", lambda *a: a[1]), \
         patch("app.services.storage.public_url", lambda b, p: f"https://cdn/{p}"), \
         patch("app.services.storage.remove") as rm:
        for c in _client(DOCTOR, db):
            res = c.post("/uploads/doctor/photo", headers=AUTH,
                         files={"file": ("whatever.png", content, ct)})

    assert res.status_code == 201
    written = doctors.update.call_args[0][0]
    assert written["photo_path"].startswith("doctors/doc-1/photo/")
    assert written["photo_url"].startswith("https://cdn/")
    rm.assert_not_called()          # nothing previous to clean up


def test_replacing_a_photo_deletes_the_previous_object_after_writing_the_new_row():
    db, _ = _photo_db(previous_path="doctors/doc-1/photo/old.png")
    content, ct = PNG
    with patch("app.services.storage.upload", lambda *a: a[1]), \
         patch("app.services.storage.public_url", lambda b, p: f"https://cdn/{p}"), \
         patch("app.services.storage.remove") as rm:
        for c in _client(DOCTOR, db):
            c.post("/uploads/doctor/photo", headers=AUTH,
                   files={"file": ("x.png", content, ct)})
    rm.assert_called_once()
    assert rm.call_args[0][1] == "doctors/doc-1/photo/old.png"


def test_a_patient_cannot_upload_a_doctor_photo():
    db, _ = _photo_db()
    content, ct = PNG
    for c in _client(PATIENT, db):
        res = c.post("/uploads/doctor/photo", headers=AUTH,
                     files={"file": ("x.png", content, ct)})
    assert res.status_code == 403


def test_an_oversized_photo_is_refused_before_anything_is_stored():
    db, _ = _photo_db()
    big = b"\x89PNG" + b"\x00" * (6 * storage.MB)
    with patch("app.services.storage.upload") as up:
        for c in _client(DOCTOR, db):
            res = c.post("/uploads/doctor/photo", headers=AUTH,
                         files={"file": ("big.png", big, "image/png")})
    assert res.status_code == 413
    up.assert_not_called()


# ── verification document ─────────────────────────────────────────────────────

def test_submitting_a_document_returns_the_doctor_to_pending():
    """Re-submitting after a rejection must re-enter the queue rather than sit in
    a rejected state with a new document attached."""
    doctors = make_chain()
    doctors.execute.side_effect = [
        MagicMock(data={"verification_document_path": None}),
        MagicMock(data=[{"id": "doc-1", "verification_status": "pending"}]),
    ]
    db = make_supabase({"doctors": doctors})
    with patch("app.services.storage.upload", lambda *a: a[1]):
        for c in _client(DOCTOR, db):
            res = c.post("/uploads/doctor/verification-document", headers=AUTH,
                         files={"file": ("licence.pdf", b"%PDF-1.4 fake", "application/pdf")})

    assert res.status_code == 201
    written = doctors.update.call_args[0][0]
    assert written["verification_status"] == "pending"
    assert written["verification_rejection_reason"] is None
    assert written["verification_document_path"].startswith("doctors/doc-1/verification/")


def test_ops_can_read_a_verification_document():
    db = make_supabase({"doctors": make_chain(data={
        "verification_document_path": "doctors/doc-1/verification/x.pdf",
        "verification_document_mime": "application/pdf",
    })})
    with patch("app.services.storage.signed_url", lambda b, p, **k: "https://signed/x"):
        for c in _client(OPS, db):
            res = c.get("/uploads/doctor/doc-1/verification-document", headers=AUTH)
    assert res.status_code == 200
    assert res.json()["url"] == "https://signed/x"
    assert res.json()["expires_in"] == storage.SIGNED_URL_TTL_SECONDS


def test_a_doctor_can_read_their_own_document():
    db = make_supabase({"doctors": make_chain(data={
        "verification_document_path": "doctors/doc-1/verification/x.pdf",
        "verification_document_mime": "application/pdf"})})
    with patch("app.services.storage.signed_url", lambda b, p, **k: "https://signed/x"):
        for c in _client(DOCTOR, db):
            assert c.get("/uploads/doctor/doc-1/verification-document",
                         headers=AUTH).status_code == 200


def test_a_patient_cannot_read_a_doctors_identity_documents():
    db = make_supabase({})
    for c in _client(PATIENT, db):
        res = c.get("/uploads/doctor/doc-1/verification-document", headers=AUTH)
    assert res.status_code == 403


def test_another_doctor_cannot_read_someone_elses_document():
    db = make_supabase({})
    for c in _client({"sub": "doc-999", "role": "doctor"}, db):
        assert c.get("/uploads/doctor/doc-1/verification-document",
                     headers=AUTH).status_code == 403


def test_reading_a_document_that_was_never_submitted_is_a_404():
    db = make_supabase({"doctors": make_chain(data={"verification_document_path": None})})
    for c in _client(OPS, db):
        assert c.get("/uploads/doctor/doc-1/verification-document",
                     headers=AUTH).status_code == 404


# ── intake media ──────────────────────────────────────────────────────────────

BOOKING = {"patient_id": "pat-1", "doctor_id": "doc-1", "status": "requested"}


def _intake_db(booking=None):
    return make_supabase({
        "bookings": make_chain(data=booking or BOOKING),
        "intake_media": make_chain(list_data=[{"id": "im-1", "media_type": "image"}]),
    })


def test_a_patient_can_attach_an_intake_photo():
    db = _intake_db()
    content, ct = PNG
    with patch("app.services.storage.upload", lambda *a: a[1]):
        for c in _client(PATIENT, db):
            res = c.post("/uploads/bookings/bk-1/intake?media_type=image", headers=AUTH,
                         files={"file": ("wound.png", content, ct)})
    assert res.status_code == 201
    written = db.table("intake_media").insert.call_args[0][0]
    assert written["storage_path"].startswith("bookings/bk-1/image/")
    assert written["size_bytes"] == len(content)
    assert written["transcript_status"] == "none"


def test_a_voice_note_is_queued_for_transcription():
    db = _intake_db()
    with patch("app.services.storage.upload", lambda *a: a[1]), \
         patch("app.services.transcription.transcribe_media") as tr:
        for c in _client(PATIENT, db):
            res = c.post("/uploads/bookings/bk-1/intake?media_type=voice", headers=AUTH,
                         files={"file": ("note.m4a", b"\x00" * 500, "audio/mp4")})
    assert res.status_code == 201
    assert db.table("intake_media").insert.call_args[0][0]["transcript_status"] == "pending"
    tr.assert_called_once()


def test_the_doctor_cannot_add_intake_on_the_patients_behalf():
    """Intake is the patient's description of their own complaint."""
    db = _intake_db()
    content, ct = PNG
    for c in _client(DOCTOR, db):
        res = c.post("/uploads/bookings/bk-1/intake?media_type=image", headers=AUTH,
                     files={"file": ("x.png", content, ct)})
    assert res.status_code == 403


def test_intake_cannot_be_added_to_a_finished_booking():
    db = _intake_db({**BOOKING, "status": "completed"})
    content, ct = PNG
    for c in _client(PATIENT, db):
        res = c.post("/uploads/bookings/bk-1/intake?media_type=image", headers=AUTH,
                     files={"file": ("x.png", content, ct)})
    assert res.status_code == 400


def test_an_unknown_media_type_is_rejected_by_the_route():
    db = _intake_db()
    content, ct = PNG
    for c in _client(PATIENT, db):
        res = c.post("/uploads/bookings/bk-1/intake?media_type=xray", headers=AUTH,
                     files={"file": ("x.png", content, ct)})
    assert res.status_code == 422


def test_an_audio_file_is_refused_when_declared_as_an_image():
    """The declared media_type picks the allowlist, so a mismatch is caught."""
    db = _intake_db()
    for c in _client(PATIENT, db):
        res = c.post("/uploads/bookings/bk-1/intake?media_type=image", headers=AUTH,
                     files={"file": ("note.m4a", b"\x00" * 100, "audio/mp4")})
    assert res.status_code == 415


def test_intake_is_readable_by_the_booking_participants_only():
    media = {"id": "im-1", "media_type": "image", "mime_type": "image/png",
             "storage_path": "bookings/bk-1/image/x.png",
             "bookings": {"patient_id": "pat-1", "doctor_id": "doc-1"}}
    db = make_supabase({"intake_media": make_chain(data=media)})

    with patch("app.services.storage.signed_url", lambda b, p, **k: "https://signed/i"):
        for c in _client(DOCTOR, db):
            assert c.get("/uploads/intake/im-1", headers=AUTH).status_code == 200
        # Ops are deliberately excluded: a complaint needs booking context, not
        # the patient's clinical photographs.
        for c in _client(OPS, db):
            assert c.get("/uploads/intake/im-1", headers=AUTH).status_code == 403
        for c in _client({"sub": "pat-999", "role": "patient"}, db):
            assert c.get("/uploads/intake/im-1", headers=AUTH).status_code == 403


# ── bucket bootstrap ──────────────────────────────────────────────────────────

def test_only_ops_can_create_buckets():
    db = make_supabase({})
    for c in _client(DOCTOR, db):
        assert c.post("/uploads/buckets/ensure", headers=AUTH).status_code == 403
