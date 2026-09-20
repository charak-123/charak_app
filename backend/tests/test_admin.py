"""
Tests for the admin router — doctor verification, directory suspension, and the
dashboard metrics the ops panel reads.
"""
from unittest.mock import MagicMock, patch

from fastapi.testclient import TestClient

from app.main import app
from tests.conftest import make_chain, make_supabase

OPS     = {"sub": "admin", "role": "ops"}
DOCTOR  = {"sub": "doc-1", "role": "doctor"}
AUTH    = {"Authorization": "Bearer t"}

ADMIN_DB = "app.routers.admin.supabase"
NOTIF_DB = "app.services.notifications.supabase"
JWT      = "app.deps.jwt"


def _client(payload, db):
    with patch(ADMIN_DB, db), patch(NOTIF_DB, db), patch(JWT) as jw:
        jw.decode.return_value = payload
        yield TestClient(app)


# ── login ─────────────────────────────────────────────────────────────────────

def test_admin_login_issues_an_ops_token():
    from jose import jwt as jose_jwt
    from app.config import JWT_SECRET

    with patch("app.routers.admin.ADMIN_PASSWORD", "secret"):
        res = TestClient(app).post("/admin/login", json={"password": "secret"})

    assert res.status_code == 200
    assert jose_jwt.decode(res.json()["token"], JWT_SECRET, algorithms=["HS256"])["role"] == "ops"


def test_admin_login_rejects_a_wrong_password():
    with patch("app.routers.admin.ADMIN_PASSWORD", "secret"):
        res = TestClient(app).post("/admin/login", json={"password": "guess"})
    assert res.status_code == 401


# ── verification ──────────────────────────────────────────────────────────────

def _doctor_db(doctor_row=None):
    doctors = make_chain()
    doctors.execute.side_effect = [
        MagicMock(data=[{"id": "doc-1"}]),                       # existence check
        MagicMock(data=[doctor_row or {"id": "doc-1", "verification_status": "verified"}]),
    ]
    return make_supabase({
        "doctors": doctors,
        "notifications": make_chain(list_data=[{"id": "n-1"}]),
        "audit_log": make_chain(list_data=[{"id": "a-1"}]),
    }), doctors


def test_approving_a_doctor_sets_them_verified_and_clears_any_rejection_reason():
    db, doctors = _doctor_db()
    for c in _client(OPS, db):
        res = c.patch("/admin/doctors/doc-1/verify", headers=AUTH, json={"action": "approve"})

    assert res.status_code == 200
    written = doctors.update.call_args[0][0]
    assert written["verification_status"] == "verified"
    assert written["verification_rejection_reason"] is None


def test_approving_a_doctor_notifies_them():
    """Day 21 of the plan requires the doctor to be told the moment they go live."""
    db, _ = _doctor_db()
    with patch(ADMIN_DB, db), patch(NOTIF_DB, db), patch(JWT) as jw:
        jw.decode.return_value = OPS
        TestClient(app).patch("/admin/doctors/doc-1/verify", headers=AUTH,
                              json={"action": "approve"})

    events = [call[0][0]["event"] for call in db.table("notifications").insert.call_args_list]
    assert "doctor.verified" in events


def test_rejecting_a_doctor_requires_a_reason():
    db, _ = _doctor_db()
    for c in _client(OPS, db):
        res = c.patch("/admin/doctors/doc-1/verify", headers=AUTH, json={"action": "reject"})
    assert res.status_code == 400
    assert "reason is required" in res.json()["error"]


def test_rejecting_a_doctor_stores_the_reason():
    db, doctors = _doctor_db({"id": "doc-1", "verification_status": "rejected"})
    for c in _client(OPS, db):
        res = c.patch("/admin/doctors/doc-1/verify", headers=AUTH,
                      json={"action": "reject", "reason": "Licence unreadable"})
    assert res.status_code == 200
    assert doctors.update.call_args[0][0]["verification_rejection_reason"] == "Licence unreadable"


def test_verify_rejects_an_unknown_action():
    db, _ = _doctor_db()
    for c in _client(OPS, db):
        res = c.patch("/admin/doctors/doc-1/verify", headers=AUTH, json={"action": "maybe"})
    assert res.status_code == 400


def test_verify_404s_on_an_unknown_doctor():
    db = make_supabase({"doctors": make_chain(list_data=[])})
    for c in _client(OPS, db):
        res = c.patch("/admin/doctors/nope/verify", headers=AUTH, json={"action": "approve"})
    assert res.status_code == 404


def test_a_doctor_cannot_verify_themselves():
    db, _ = _doctor_db()
    for c in _client(DOCTOR, db):
        res = c.patch("/admin/doctors/doc-1/verify", headers=AUTH, json={"action": "approve"})
    assert res.status_code == 403


# ── suspension ────────────────────────────────────────────────────────────────

def test_suspending_a_doctor_records_the_reason_and_timestamp():
    db, doctors = _doctor_db({"id": "doc-1", "suspended": True})
    for c in _client(OPS, db):
        res = c.patch("/admin/doctors/doc-1/suspend", headers=AUTH,
                      json={"suspended": True, "reason": "Repeated no-shows"})

    assert res.status_code == 200
    written = doctors.update.call_args[0][0]
    assert written["suspended"] is True
    assert written["suspended_reason"] == "Repeated no-shows"
    assert written["suspended_at"] is not None


def test_suspending_requires_a_reason():
    db, _ = _doctor_db()
    for c in _client(OPS, db):
        res = c.patch("/admin/doctors/doc-1/suspend", headers=AUTH, json={"suspended": True})
    assert res.status_code == 400


def test_reinstating_clears_the_suspension_fields():
    db, doctors = _doctor_db({"id": "doc-1", "suspended": False})
    for c in _client(OPS, db):
        res = c.patch("/admin/doctors/doc-1/suspend", headers=AUTH, json={"suspended": False})

    assert res.status_code == 200
    written = doctors.update.call_args[0][0]
    assert written["suspended"] is False
    assert written["suspended_reason"] is None
    assert written["suspended_at"] is None


def test_suspension_notifies_the_doctor():
    db, _ = _doctor_db({"id": "doc-1", "suspended": True})
    with patch(ADMIN_DB, db), patch(NOTIF_DB, db), patch(JWT) as jw:
        jw.decode.return_value = OPS
        TestClient(app).patch("/admin/doctors/doc-1/suspend", headers=AUTH,
                              json={"suspended": True, "reason": "Under investigation"})

    events = [call[0][0]["event"] for call in db.table("notifications").insert.call_args_list]
    assert "doctor.suspended" in events


# ── listings ──────────────────────────────────────────────────────────────────

def test_the_doctor_list_can_be_filtered_by_verification_status():
    doctors = make_chain(list_data=[{"id": "doc-1", "verification_status": "verified"}])
    db = make_supabase({"doctors": doctors})
    for c in _client(OPS, db):
        res = c.get("/admin/doctors?status=verified", headers=AUTH)
    assert res.status_code == 200
    doctors.eq.assert_any_call("verification_status", "verified")


def test_the_doctor_list_rejects_a_nonsense_status():
    db = make_supabase({"doctors": make_chain(list_data=[])})
    for c in _client(OPS, db):
        res = c.get("/admin/doctors?status=banned", headers=AUTH)
    assert res.status_code == 400


def test_pending_doctors_lists_only_the_verification_queue():
    doctors = make_chain(list_data=[{"id": "doc-2", "name": "Dr B"}])
    db = make_supabase({"doctors": doctors})
    for c in _client(OPS, db):
        res = c.get("/admin/doctors/pending", headers=AUTH)
    assert res.status_code == 200
    doctors.eq.assert_any_call("verification_status", "pending")


# ── metrics ───────────────────────────────────────────────────────────────────

def test_dashboard_metrics_aggregates_every_queue_and_total():
    db = make_supabase({
        "doctors": make_chain(list_data=[
            {"verification_status": "verified", "suspended": False},
            {"verification_status": "verified", "suspended": True},
            {"verification_status": "pending",  "suspended": False},
        ]),
        "bookings": make_chain(list_data=[
            {"status": "completed", "price_confirmed": 800},
            {"status": "paid",      "price_confirmed": 500},
            {"status": "no_show",   "price_confirmed": 500},
            {"status": "requested", "price_confirmed": None},
        ]),
        "complaints": make_chain(list_data=[{"status": "open"}, {"status": "resolved"}]),
        "procedure_bills": make_chain(list_data=[
            {"status": "paid", "total": 2000},
            {"status": "under_review", "total": 5000},
        ]),
        "doctor_ledger_entries": make_chain(list_data=[
            {"net_amount": 680, "commission_amount": 120, "status": "payable"},
            {"net_amount": 1700, "commission_amount": 300, "status": "paid"},
            {"net_amount": 100, "commission_amount": 20, "status": "reversed"},
        ]),
    })
    for c in _client(OPS, db):
        m = c.get("/admin/metrics", headers=AUTH).json()

    assert m["doctors"] == {"total": 3, "pending": 1, "verified": 2, "rejected": 0, "suspended": 1}
    assert m["bookings"]["no_show"] == 1
    assert m["bookings"]["completed"] == 1
    # Only paid/completed bookings count toward consult revenue.
    assert m["revenue"]["consult_gross"] == 1300.0
    assert m["revenue"]["procedure_gross"] == 2000.0
    # Reversed ledger entries are excluded from both commission and what is owed.
    assert m["revenue"]["commission_earned"] == 420.0
    assert m["revenue"]["owed_to_doctors"] == 680.0
    assert m["queues"]["bills_under_review"] == 1
    assert m["queues"]["complaints_open"] == 1


def test_metrics_requires_ops():
    db = make_supabase({})
    for c in _client(DOCTOR, db):
        assert c.get("/admin/metrics", headers=AUTH).status_code == 403


# ── complaints ────────────────────────────────────────────────────────────────

def test_complaint_status_can_be_advanced():
    complaints = make_chain()
    complaints.execute.side_effect = [
        MagicMock(data=[{"id": "c-1"}]),
        MagicMock(data=[{"id": "c-1", "status": "resolved"}]),
    ]
    db = make_supabase({"complaints": complaints})
    for c in _client(OPS, db):
        res = c.patch("/admin/complaints/c-1", headers=AUTH, json={"status": "resolved"})
    assert res.status_code == 200
    assert res.json()["status"] == "resolved"


def test_an_invalid_complaint_status_is_rejected():
    db = make_supabase({})
    for c in _client(OPS, db):
        res = c.patch("/admin/complaints/c-1", headers=AUTH, json={"status": "escalated"})
    assert res.status_code == 400


# ── audit log ─────────────────────────────────────────────────────────────────

def test_ops_actions_are_written_to_the_audit_log():
    db, _ = _doctor_db()
    for c in _client(OPS, db):
        c.patch("/admin/doctors/doc-1/verify", headers=AUTH, json={"action": "approve"})

    written = db.table("audit_log").insert.call_args[0][0]
    assert written["entity"] == "doctors"
    assert written["action"] == "verification_approve"


def test_the_audit_log_read_is_capped():
    audit = make_chain(list_data=[])
    db = make_supabase({"audit_log": audit})
    for c in _client(OPS, db):
        c.get("/admin/audit-log?limit=99999", headers=AUTH)
    audit.limit.assert_called_with(500)
