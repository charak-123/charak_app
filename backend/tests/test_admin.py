"""
Tests for the admin router — doctor verification, directory suspension, and the
dashboard metrics the ops panel reads.
"""
import bcrypt
import pyotp
from unittest.mock import MagicMock, patch

from fastapi.testclient import TestClient

from app.main import app
from tests.conftest import make_chain, make_chain_seq, make_supabase

OPS     = {"sub": "admin-1", "role": "ops", "admin_role": "admin"}
DOCTOR  = {"sub": "doc-1", "role": "doctor"}
AUTH    = {"Authorization": "Bearer t"}

ADMIN_DB = "app.routers.admin.supabase"
NOTIF_DB = "app.services.notifications.supabase"
JWT      = "app.deps.jwt"


AUDIT_DB = "app.services.audit.supabase"


def _client(payload, db):
    with patch(ADMIN_DB, db), patch(NOTIF_DB, db), patch(AUDIT_DB, db), patch(JWT) as jw:
        jw.decode.return_value = payload
        yield TestClient(app)


# ── login ─────────────────────────────────────────────────────────────────────
# admin_auth.py and rate_limit.py each bind their own `supabase` name, so each
# gets patched independently of app.routers.admin's.

AUTH_DB = "app.services.admin_auth.supabase"
RL_DB   = "app.services.rate_limit.supabase"

_SECRET = pyotp.random_base32()


def _admin_row(totp_enabled: bool, password: str = "correct horse battery staple"):
    return {
        "id": "admin-1",
        "email": "ops@charak.care",
        "password_hash": bcrypt.hashpw(password.encode(), bcrypt.gensalt()).decode(),
        "totp_secret": _SECRET,
        "totp_enabled": totp_enabled,
    }


def _login(body, admin_row=None, rl_hits=None):
    admin_db = make_supabase({"admin_users": make_chain(list_data=[admin_row] if admin_row else [])})
    rl_db = make_supabase({"rate_limit_hits": make_chain(list_data=rl_hits or [])})
    with patch(AUTH_DB, admin_db), patch(RL_DB, rl_db):
        return TestClient(app).post("/admin/login", json=body)


def test_admin_login_rejects_an_unknown_email():
    res = _login({"email": "nobody@charak.care", "password": "whatever"})
    assert res.status_code == 401
    assert "Invalid email or password" in res.json()["error"]


def test_admin_login_rejects_a_wrong_password():
    res = _login({"email": "ops@charak.care", "password": "guess"}, admin_row=_admin_row(True))
    assert res.status_code == 401


def test_a_fresh_account_never_reveals_its_totp_secret_to_the_password():
    """Knowing the password must not hand over the second factor: a fresh account
    answers exactly like an enrolled one, with no secret and no setup link."""
    fresh = _login({"email": "ops@charak.care", "password": "correct horse battery staple"},
                   admin_row=_admin_row(False))
    enrolled = _login({"email": "ops@charak.care", "password": "correct horse battery staple"},
                      admin_row=_admin_row(True))
    assert fresh.status_code == 428 and fresh.json() == enrolled.json()
    assert "provisioning_uri" not in fresh.json() and "otpauth" not in fresh.text


def test_admin_login_enrolled_account_asks_for_a_code():
    res = _login({"email": "ops@charak.care", "password": "correct horse battery staple"},
                 admin_row=_admin_row(True))
    assert res.status_code == 428
    assert res.json()["next"] == "totp"


def test_admin_login_completes_setup_and_issues_a_token():
    import jwt
    from app.config import JWT_SECRET

    code = pyotp.TOTP(_SECRET).now()
    res = _login(
        {"email": "ops@charak.care", "password": "correct horse battery staple", "totp_code": code},
        admin_row=_admin_row(False),
    )
    assert res.status_code == 200
    claims = jwt.decode(res.json()["token"], JWT_SECRET, algorithms=["HS256"])
    assert claims["role"] == "ops"
    assert claims["sub"] == "admin-1"


def test_admin_login_with_a_valid_code_issues_a_token():
    code = pyotp.TOTP(_SECRET).now()
    res = _login(
        {"email": "ops@charak.care", "password": "correct horse battery staple", "totp_code": code},
        admin_row=_admin_row(True),
    )
    assert res.status_code == 200
    assert "token" in res.json()


def test_admin_login_rejects_a_wrong_totp_code():
    res = _login(
        {"email": "ops@charak.care", "password": "correct horse battery staple", "totp_code": "000000"},
        admin_row=_admin_row(True),
    )
    assert res.status_code == 401


def test_admin_login_is_rate_limited():
    five_recent_attempts = [{"id": i} for i in range(5)]
    res = _login(
        {"email": "ops@charak.care", "password": "correct horse battery staple"},
        admin_row=_admin_row(True),
        rl_hits=five_recent_attempts,
    )
    assert res.status_code == 429


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


# ── session revocation ─────────────────────────────────────────────────────────

def test_revoking_a_doctors_sessions_stamps_sessions_revoked_at():
    doctors = make_chain()
    doctors.execute.side_effect = [
        MagicMock(data=[{"id": "doc-1"}]),   # existence check
        MagicMock(data=[{"id": "doc-1"}]),   # the update
    ]
    db = make_supabase({"doctors": doctors, "audit_log": make_chain(list_data=[{"id": "a-1"}])})
    for c in _client(OPS, db):
        res = c.patch("/admin/doctors/doc-1/revoke-sessions", headers=AUTH)

    assert res.status_code == 200
    written = doctors.update.call_args[0][0]
    assert written["sessions_revoked_at"] is not None


def test_revoking_sessions_for_an_unknown_doctor_404s():
    db = make_supabase({"doctors": make_chain(list_data=[])})
    for c in _client(OPS, db):
        res = c.patch("/admin/doctors/nope/revoke-sessions", headers=AUTH)
    assert res.status_code == 404


def test_revoking_a_patients_sessions_stamps_sessions_revoked_at():
    users = make_chain()
    users.execute.side_effect = [
        MagicMock(data=[{"id": "u-1"}]),
        MagicMock(data=[{"id": "u-1"}]),
    ]
    db = make_supabase({"users": users, "audit_log": make_chain(list_data=[{"id": "a-1"}])})
    for c in _client(OPS, db):
        res = c.patch("/admin/users/u-1/revoke-sessions", headers=AUTH)

    assert res.status_code == 200
    written = users.update.call_args[0][0]
    assert written["sessions_revoked_at"] is not None


def test_revoke_sessions_requires_ops():
    db = make_supabase({})
    for c in _client(DOCTOR, db):
        assert c.patch("/admin/doctors/doc-1/revoke-sessions", headers=AUTH).status_code == 403
        assert c.patch("/admin/users/u-1/revoke-sessions", headers=AUTH).status_code == 403


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


def test_dashboard_metrics_counts_past_the_1000_row_page_cap():
    """
    PostgREST caps a single response at 1000 rows. A table with more than that
    must not be silently undercounted — the doctors total here spans two pages.
    """
    page1 = [{"verification_status": "verified", "suspended": False}] * 1000
    page2 = [{"verification_status": "verified", "suspended": False}]
    db = make_supabase({
        "doctors": make_chain_seq(page1, page2),
        "bookings": make_chain(list_data=[]),
        "complaints": make_chain(list_data=[]),
        "procedure_bills": make_chain(list_data=[]),
        "doctor_ledger_entries": make_chain(list_data=[]),
    })
    for c in _client(OPS, db):
        m = c.get("/admin/metrics", headers=AUTH).json()

    assert m["doctors"]["total"] == 1001
    assert m["doctors"]["verified"] == 1001


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


# ── metrics timeseries ────────────────────────────────────────────────────────

def test_timeseries_buckets_bookings_and_revenue_by_day():
    from datetime import datetime, timedelta, timezone

    today = datetime.now(timezone.utc)
    yesterday = today - timedelta(days=1)
    db = make_supabase({
        "bookings": make_chain(list_data=[
            {"created_at": today.isoformat(),     "status": "completed", "price_confirmed": 800},
            {"created_at": today.isoformat(),     "status": "paid",      "price_confirmed": 500},
            {"created_at": today.isoformat(),     "status": "requested", "price_confirmed": None},
            {"created_at": yesterday.isoformat(), "status": "completed", "price_confirmed": 300},
        ]),
    })
    for c in _client(OPS, db):
        series = c.get("/admin/metrics/timeseries?days=7", headers=AUTH).json()

    assert len(series) == 7
    assert [d["date"] for d in series] == sorted(d["date"] for d in series)

    by_day = {d["date"]: d for d in series}
    t = by_day[today.date().isoformat()]
    assert (t["bookings"], t["completed"], t["revenue"]) == (3, 2, 1300.0)

    y = by_day[yesterday.date().isoformat()]
    assert (y["bookings"], y["completed"], y["revenue"]) == (1, 1, 300.0)

    # Days with no bookings are still present, so the chart has no gaps.
    assert sum(d["bookings"] for d in series) == 4
    assert all(d["revenue"] == 0 for d in series if d["date"] not in
               (today.date().isoformat(), yesterday.date().isoformat()))


def test_timeseries_clamps_the_window_and_requires_ops():
    db = make_supabase({"bookings": make_chain(list_data=[])})
    for c in _client(OPS, db):
        assert len(c.get("/admin/metrics/timeseries?days=500", headers=AUTH).json()) == 90
        assert len(c.get("/admin/metrics/timeseries?days=1", headers=AUTH).json()) == 7

    db2 = make_supabase({})
    for c in _client(DOCTOR, db2):
        assert c.get("/admin/metrics/timeseries", headers=AUTH).status_code == 403


def test_admin_login_has_no_built_in_default_credential():
    """
    Regression for the original strix finding (a hardcoded fallback password):
    per-account auth has no fallback by construction, but pin it down anyway —
    the old well-known default must not work against an unconfigured instance.
    """
    res = _login({"email": "admin@charak.care", "password": "charak-admin-2024"})
    assert res.status_code == 401
