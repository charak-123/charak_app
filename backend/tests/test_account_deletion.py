"""
Account deletion / DPDP erasure: patient self-deletion erases personal data while
retaining de-identified financial + clinical records; doctors file a request that
ops fulfils once payouts/bookings are settled.
"""
from unittest.mock import patch

from fastapi.testclient import TestClient

from app.main import app
from app.services import erasure
from tests.conftest import make_chain, make_supabase, patch_all_supabase

JWT = "app.deps.jwt"
PATIENT = {"sub": "pat-1", "role": "patient"}
DOCTOR = {"sub": "doc-1", "role": "doctor"}
OPS = {"sub": "admin", "role": "ops"}
AUTH = {"Authorization": "Bearer t"}


# ── patient self-deletion ─────────────────────────────────────────────────────

def test_patient_delete_soft_deletes_and_schedules_purge():
    db = make_supabase({"users": make_chain(list_data=[{"phone": "+919000000000"}])})
    with patch_all_supabase(db), patch(JWT) as jw:
        jw.decode.return_value = PATIENT
        res = TestClient(app).delete("/users/me", headers=AUTH)
    assert res.status_code == 200
    body = res.json()
    assert "purge_at" in body and body["grace_days"] == 30


def test_patient_delete_requires_a_patient_token():
    db = make_supabase({})
    with patch_all_supabase(db), patch(JWT) as jw:
        jw.decode.return_value = DOCTOR          # doctor token on patient route
        res = TestClient(app).delete("/users/me", headers=AUTH)
    assert res.status_code == 403


def test_purge_patient_scrubs_pii_but_keeps_the_row():
    users = make_chain()
    addresses = make_chain()
    bookings = make_chain(list_data=[{"id": "bk-1"}])
    intake = make_chain(list_data=[
        {"id": "m-1", "storage_path": "p/raw.jpg", "clinical_hold": False},
        {"id": "m-2", "storage_path": "p/keep.jpg", "clinical_hold": True},
    ])
    db = make_supabase({
        "users": users, "patient_addresses": addresses, "bookings": bookings,
        "intake_media": intake, "ratings": make_chain(), "complaints": make_chain(),
        "dsr_requests": make_chain(), "audit_log": make_chain(),
    })
    removed = []
    with patch("app.services.erasure.supabase", db), \
         patch("app.services.erasure.storage.remove", side_effect=lambda b, p: removed.append(p)):
        erasure.purge_patient("pat-1")

    # identity tombstoned, not deleted
    upd = users.update.call_args[0][0]
    assert upd["phone"] == "deleted:pat-1" and upd["name"] is None
    # saved addresses hard-deleted
    assert addresses.delete.called
    # only the non-held raw media file is removed
    assert removed == ["p/raw.jpg"]


def test_reactivation_on_login_cancels_a_pending_deletion():
    """A patient logging back in during the grace window un-deletes the account."""
    row = {"id": "pat-1", "phone": "+919000000000", "name": "A",
           "deleted_at": "2026-10-01T00:00:00+00:00"}
    db = make_supabase({"users": make_chain(list_data=[row])})
    with patch_all_supabase(db), \
         patch("app.routers.auth.otp_store.consume", return_value={"role": "patient"}), \
         patch("app.routers.auth._issue_jwt", return_value="tok"):
        res = TestClient(app).post(
            "/auth/verify-otp",
            json={"phone": "+919000000000", "code": "123456", "role": "patient"},
        )
    assert res.status_code == 200
    assert res.json()["reactivated"] is True


# ── doctor request → ops fulfils ──────────────────────────────────────────────

def test_doctor_delete_files_a_request_and_locks_the_account():
    db = make_supabase({"doctors": make_chain(list_data=[{"id": "doc-1"}]),
                        "dsr_requests": make_chain(), "audit_log": make_chain()})
    with patch_all_supabase(db), patch(JWT) as jw:
        jw.decode.return_value = DOCTOR
        res = TestClient(app).delete("/doctors/me", headers=AUTH)
    assert res.status_code == 200
    assert res.json()["status"] == "requested"


def test_ops_cannot_fulfill_doctor_deletion_while_a_payout_is_owed():
    db = make_supabase({"doctors": make_chain(list_data=[{"deletion_status": "requested"}])})
    with patch_all_supabase(db), patch(JWT) as jw, \
         patch("app.routers.admin.payouts.balance", return_value={"payable_net": 500.0}):
        jw.decode.return_value = OPS
        res = TestClient(app).post("/admin/doctors/doc-1/deletion/fulfill", headers=AUTH)
    assert res.status_code == 409
    assert "owed" in res.json()["error"].lower()


def test_ops_can_fulfill_doctor_deletion_when_settled():
    db = make_supabase({
        "doctors": make_chain(list_data=[{"deletion_status": "requested",
                                          "photo_path": None,
                                          "verification_document_path": None}]),
        "bookings": make_chain(list_data=[]),
        "doctor_bank_accounts": make_chain(),
        "dsr_requests": make_chain(), "audit_log": make_chain(),
    })
    with patch_all_supabase(db), patch(JWT) as jw, \
         patch("app.routers.admin.payouts.balance", return_value={"payable_net": 0.0}):
        jw.decode.return_value = OPS
        res = TestClient(app).post("/admin/doctors/doc-1/deletion/fulfill", headers=AUTH)
    assert res.status_code == 200
    assert res.json()["status"] == "fulfilled"
