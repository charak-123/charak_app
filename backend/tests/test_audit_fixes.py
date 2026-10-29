"""
Regression tests for the security audit (run-1). Each test failed before its fix.
"""
from datetime import datetime, timedelta, timezone
from unittest.mock import MagicMock, patch

import jwt
from fastapi.testclient import TestClient

from app.config import JWT_SECRET
from app.main import app
from tests.conftest import make_chain, make_supabase
from tests.fakedb import FakeSupabase

AUTH = {"Authorization": "Bearer t"}
DOCTOR = {"sub": "doc-1", "role": "doctor"}
FULL = "12 Rose Lane, Flat 3, near City Park, New Delhi, 110001"
ROW = {"id": "bk-1", "patient_id": "pat-1", "doctor_id": "doc-1", "channel": "home_visit",
       "status": "requested", "scheduled_start": "2026-10-01T09:00:00+00:00",
       "patient_address": FULL, "patient_address_lat": 28.6315, "patient_address_lng": 77.2167,
       "address_released_at": None}


def ops_headers(admin_role: str, sub: str = "admin-9") -> dict:
    now = datetime.now(timezone.utc)
    token = jwt.encode(
        {"sub": sub, "role": "ops", "admin_role": admin_role, "iat": now, "exp": now + timedelta(hours=12)},
        JWT_SECRET, algorithm="HS256",
    )
    return {"Authorization": f"Bearer {token}"}


def admin_db(db_role: str):
    return make_supabase({"admin_users": make_chain(list_data=[{"id": "admin-9", "role": db_role}])})


# ── A doctor does not get the address back from a decline or a cancel ─────────

def _rpc_db():
    db = make_supabase({"bookings": make_chain(data=ROW),
                        "doctors": make_chain(list_data=[{"name": "Dr X"}])})
    sdb = MagicMock()

    def rpc(name, params):
        r = MagicMock()
        if name == "transition_booking":      # the SQL returns to_jsonb(the whole row)
            r.execute.return_value = MagicMock(data={"outcome": "ok", "booking": {**ROW, "status": "declined"}})
        else:
            r.execute.return_value = MagicMock(data={"outcome": "cancelled", "booking": {**ROW, "status": "cancelled"},
                                                      "quote": {}, "refunds": []})
        return r
    sdb.rpc.side_effect = rpc
    db.rpc.side_effect = rpc
    return db, sdb


def test_decline_and_cancel_do_not_return_the_withheld_address():
    db, sdb = _rpc_db()
    with patch("app.routers.bookings.supabase", db), patch("app.services.booking_state.supabase", sdb), \
         patch("app.services.notifications.supabase", db), patch("app.deps.jwt") as jw, \
         patch("app.routers.bookings.notifications"), patch("app.routers.bookings.incidents"):
        jw.decode.return_value = DOCTOR
        c = TestClient(app)
        declined = c.patch("/bookings/bk-1/decline", headers=AUTH)
        cancelled = c.patch("/bookings/bk-1/cancel", headers=AUTH)
    for res in (declined, cancelled):
        assert res.status_code == 200, res.text
        body = res.json()
        assert body["patient_address"] is None
        assert body["patient_address_lat"] is None and body["patient_address_lng"] is None
        assert body["address_withheld"] is True


# ── A suspended or rejected doctor cannot accept a request already open ───────

def test_a_suspended_doctor_cannot_accept_an_open_request():
    for standing in ({"verification_status": "verified", "suspended": True},
                     {"verification_status": "rejected", "suspended": False}):
        db = make_supabase({"bookings": make_chain(data=ROW), "doctors": make_chain(list_data=[standing])})
        with patch("app.routers.bookings.supabase", db), patch("app.deps.jwt") as jw, \
             patch("app.services.booking_state.supabase") as bs:
            jw.decode.return_value = DOCTOR
            res = TestClient(app).patch("/bookings/bk-1/accept", headers=AUTH)
        assert res.status_code == 403
        bs.rpc.assert_not_called()                  # nothing was released or held


def test_suspending_a_doctor_ends_their_sessions():
    doctors = make_chain(list_data=[{"id": "doc-1"}])
    db = make_supabase({"doctors": doctors, "admin_users": make_chain(list_data=[{"id": "admin-9", "role": "ops_lead"}])})
    with patch("app.routers.admin.supabase", db), patch("app.deps.supabase", db), \
         patch("app.routers.admin.notifications"), patch("app.routers.admin._audit"):
        res = TestClient(app).patch("/admin/doctors/doc-1/suspend", headers=ops_headers("ops_lead"),
                                    json={"suspended": True, "reason": "complaint"})
    assert res.status_code == 200, res.text
    assert "sessions_revoked_at" in doctors.update.call_args[0][0]


# ── Incident: the patient's own words stay with ops ───────────────────────────

def test_respond_and_appeal_do_not_return_the_patients_note():
    incident = {"id": "i1", "patient_note": "PRIVATE patient words", "status": "under_review"}
    with patch("app.deps.jwt") as jw, patch("app.routers.trust.incidents") as inc:
        jw.decode.return_value = DOCTOR
        inc.respond.return_value = incident
        inc.appeal.return_value = incident
        inc.public.side_effect = lambda row: dict(row)
        c = TestClient(app)
        responded = c.post("/incidents/i1/respond", headers=AUTH, json={"note": "my side of it"})
        appealed = c.post("/incidents/i1/appeal", headers=AUTH, json={"note": "my side of it"})
    for res in (responded, appealed):
        assert res.status_code == 200
        assert "patient_note" not in res.json()


# ── Admin: a changed role takes effect on a token already issued ─────────────

def test_a_demoted_admin_token_is_revoked():
    with patch("app.deps.supabase", admin_db("support")), patch("app.routers.admin_ops.supabase", admin_db("support")):
        res = TestClient(app).get("/admin/admins", headers=ops_headers("admin"))
    assert res.status_code == 401


def test_an_admin_token_with_an_unchanged_role_still_works():
    db = make_supabase({"admin_users": make_chain(list_data=[{"id": "admin-9", "role": "admin"}])})
    with patch("app.deps.supabase", db), patch("app.routers.admin_ops.supabase", db):
        res = TestClient(app).get("/admin/admins", headers=ops_headers("admin"))
    assert res.status_code != 401


# ── Verification documents need doctors.verify and are audited ───────────────

def _doc_db():
    return make_supabase({"doctors": make_chain(data={"verification_document_path": "p/x.pdf",
                                                      "verification_document_mime": "application/pdf"})})


def test_finance_cannot_read_a_doctors_identity_document():
    with patch("app.deps.supabase", admin_db("finance")), patch("app.routers.uploads.supabase", _doc_db()), \
         patch("app.services.storage.signed_url", lambda b, p: "https://signed/" + p):
        res = TestClient(app).get("/uploads/doctor/doc-1/verification-document", headers=ops_headers("finance"))
    assert res.status_code == 403


def test_an_ops_lead_can_read_it_and_the_read_is_audited():
    with patch("app.deps.supabase", admin_db("ops_lead")), patch("app.routers.uploads.supabase", _doc_db()), \
         patch("app.routers.uploads.audit.record_or_refuse") as audit, \
         patch("app.services.storage.signed_url", lambda b, p: "https://signed/" + p):
        res = TestClient(app).get("/uploads/doctor/doc-1/verification-document", headers=ops_headers("ops_lead"))
    assert res.status_code == 200
    audit.assert_called_once()


def test_a_doctor_can_still_read_their_own_document_without_an_audit_row():
    with patch("app.deps.jwt") as jw, patch("app.routers.uploads.supabase", _doc_db()), \
         patch("app.routers.uploads.audit.record_or_refuse") as audit, \
         patch("app.services.storage.signed_url", lambda b, p: "https://signed/" + p):
        jw.decode.return_value = DOCTOR
        res = TestClient(app).get("/uploads/doctor/doc-1/verification-document", headers=AUTH)
    assert res.status_code == 200
    audit.assert_not_called()


# ── Admin booking list: the address is as private as the phone ───────────────

def test_finance_does_not_see_patient_addresses_in_the_booking_list():
    row = {"id": "bk-1", "patient_address": FULL, "patient_address_lat": 1.0, "patient_address_lng": 2.0,
           "users": {"name": "Asha", "phone": "+919811112222"}, "doctors": {"name": "Dr X"}}
    for role, sees in (("finance", False), ("support", True)):
        db = make_supabase({"bookings": make_chain(list_data=[dict(row, users=dict(row["users"]))]),
                            "admin_users": make_chain(list_data=[{"id": "admin-9", "role": role}])})
        with patch("app.deps.supabase", db), patch("app.routers.admin.supabase", db):
            res = TestClient(app).get("/admin/bookings", headers=ops_headers(role))
        assert res.status_code == 200
        assert ("patient_address" in res.json()[0]) is sees


# ── stub-complete is dead whenever live keys are present ─────────────────────

def test_stub_complete_is_refused_in_live_mode_even_if_the_dev_flag_is_set():
    with patch("app.deps.jwt") as jw, patch("app.routers.payments.ALLOW_INSECURE_PAYMENTS", True), \
         patch("app.routers.payments.live_mode", return_value=True):
        jw.decode.return_value = {"sub": "pat-1", "role": "patient"}
        res = TestClient(app).post("/payments/bk-1/stub-complete", headers=AUTH, json={"type": "consult_fee"})
    assert res.status_code == 403


# ── Erasure ───────────────────────────────────────────────────────────────────

U = "u-1"


def _erasure_db():
    return FakeSupabase(tables={
        "users": [{"id": U, "phone": "+911", "fcm_token": "TOK", "deleted_at": None}],
        "device_tokens": [{"id": "d1", "owner_id": U, "owner_role": "patient", "token": "TOK", "platform": "android"}],
        "notifications": [], "otp_codes": [], "dsr_requests": [{"id": "r1", "user_id": U, "type": "erasure", "status": "pending"}],
        "audit_log": [], "bookings": [{"id": "b1", "patient_id": U}],
        "intake_media": [{"id": "m1", "booking_id": "b1", "storage_path": "p/x.jpg", "clinical_hold": False}],
        "ratings": [], "complaints": [], "patient_addresses": [],
    })


def test_deleting_an_account_removes_its_push_devices():
    from app.services import erasure
    db = _erasure_db()
    with patch("app.services.erasure.supabase", db):
        erasure.request_patient_deletion(U)
    assert db.rows("device_tokens") == []


def test_a_failed_file_delete_keeps_the_pointer_and_leaves_the_request_pending():
    from app.services import erasure
    db = _erasure_db()
    with patch("app.services.erasure.supabase", db), patch("app.services.erasure.storage.remove", return_value=False):
        erasure.purge_patient(U)
    assert db.rows("intake_media")[0]["storage_path"] == "p/x.jpg"       # still findable, so retried
    assert not any(r.get("status") == "fulfilled" for r in db.rows("dsr_requests"))


def test_a_successful_purge_clears_the_pointer_and_fulfils_the_request():
    from app.services import erasure
    db = _erasure_db()
    with patch("app.services.erasure.supabase", db), patch("app.services.erasure.storage.remove", return_value=True):
        erasure.purge_patient(U)
    assert db.rows("intake_media")[0]["storage_path"] is None
    assert db.rows("device_tokens") == []


# ── Incidents: a doctor who showed up is not auto-confirmed at fault ──────────

def test_auto_confirm_sends_the_case_to_review_when_the_doctor_joined_after_the_report():
    from app.services import incidents
    incident = make_chain(list_data=[{"id": "i1", "booking_id": "bk-1"}])
    db = make_supabase({
        "incidents": incident,
        "bookings": make_chain(list_data=[{"status": "completed"}]),
        "call_joins": make_chain(list_data=[]),
        "incident_events": make_chain(list_data=[]),
    })
    with patch("app.services.incidents.supabase", db):
        incidents.auto_confirm_due()
    updates = [c[0][0] for c in incident.update.call_args_list]
    assert updates and all(u.get("status") == "under_review" for u in updates)
    assert not any(u.get("status") == "confirmed" for u in updates)


# ── Payments: a redelivery finishes a confirm that stopped half way ──────────

def test_a_redelivered_capture_finishes_a_booking_left_accepted():
    from app.routers import payments
    payment = {"id": "pay-1", "booking_id": "bk-1", "status": "completed", "type": "consult_fee", "amount": 500}
    event = {"event": "payment.captured",
             "payload": {"payment": {"entity": {"order_id": "o1", "id": "rzp_1", "method": "upi"}}}}
    db = make_supabase({"payments": make_chain(list_data=[payment]),
                        "bookings": make_chain(data={"id": "bk-1", "status": "accepted"})})
    with patch("app.routers.payments.supabase", db), \
         patch("app.routers.payments._confirm_payment", return_value={"ok": True}) as confirm:
        out = payments._handle_event(event, None)
    assert out == {"ok": True}
    confirm.assert_called_once()


# ── Location: distances cannot be intersected to find a doctor's base ────────

def test_public_distance_is_measured_from_a_grid_cell_not_the_exact_base():
    from app.services import geo
    base = (19.07609, 72.87771)
    doctors = [{"id": "d1", "base_lat": base[0], "base_lng": base[1], "offers_home_visit": True,
                "service_radius_km": 10}]
    origins = [(19.20, 72.80), (19.00, 73.00), (18.95, 72.75)]
    seen = []
    for lat, lng in origins:
        shown = geo.annotate_distance([dict(doctors[0])], lat, lng)[0]
        seen.append((lat, lng, shown["distance_km"]))

    # Whatever point those three distances intersect at, it is the cell centre,
    # about a kilometre from the base, not the base itself.
    best = min(
        ((a / 4000 + 18.9, b / 4000 + 72.7) for a in range(0, 1200) for b in range(0, 1200, 3)),
        key=lambda p: sum((geo.distance_between(p, (la, ln)) - d) ** 2 for la, ln, d in seen),
    )
    snapped = geo.snapped(doctors[0])
    assert (snapped["base_lat"], snapped["base_lng"]) != base
    assert geo.haversine_km(*best, *base) > 0.3        # not recovered to ~10 m


def test_the_exact_base_is_still_used_to_decide_whether_a_booking_is_in_area():
    from app.services import geo
    doc = {"base_lat": 19.07609, "base_lng": 72.87771, "service_radius_km": 5}
    assert geo.within_service_area(doc, 19.07609, 72.87771) == (True, 0.0)


# ── Payouts: a changed destination is held ───────────────────────────────────

def test_a_payout_is_held_after_the_destination_changed():
    from app.services import payouts
    from app.errors import AppError
    entry = {"id": "e1", "status": "payable", "net_amount": 100, "gross_amount": 120,
             "commission_amount": 20, "bookings": {}}
    recent = datetime.now(timezone.utc).isoformat()
    db = make_supabase({
        "doctor_ledger_entries": make_chain(list_data=[entry]),
        "doctor_bank_accounts": make_chain(list_data=[{"id": "b1", "updated_at": recent}]),
    })
    with patch("app.services.payouts.supabase", db), patch("app.services.payouts.is_payout_eligible", return_value=True):
        try:
            payouts.create_payout("doc-1", "2026-01-01", "2026-12-31")
            raised = None
        except AppError as exc:
            raised = exc
    assert raised is not None and raised.status_code == 409


# ── Webhook payloads: personal fields are stripped after reconciliation ──────

def test_webhook_redaction_keeps_reconciliation_fields_and_drops_the_payer():
    from app.services import webhook_inbox
    event = {"event": "payment.captured", "created_at": 1,
             "payload": {"payment": {"entity": {
                 "id": "pay_1", "order_id": "o1", "amount": 50000, "currency": "INR", "status": "captured",
                 "contact": "+919811112222", "email": "a@b.in", "vpa": "a@upi", "notes": {"x": "y"},
                 "card": {"last4": "1111"}}}}}
    out = webhook_inbox.redact_payload(event)
    entity = out["payload"]["payment"]["entity"]
    assert entity == {"id": "pay_1", "order_id": "o1", "amount": 50000, "currency": "INR", "status": "captured"}
    assert out["redacted"] is True and "9811112222" not in str(out)


# ── Legacy complete: a visit that never started cannot be closed ─────────────

def test_a_paid_booking_that_never_started_cannot_be_completed_by_the_doctor():
    row = {**ROW, "status": "paid", "channel": "online_consult", "started_at": None}
    db = make_supabase({"bookings": make_chain(data=row)})
    with patch("app.routers.bookings.supabase", db), patch("app.deps.jwt") as jw, \
         patch("app.services.booking_state.supabase") as bs:
        jw.decode.return_value = DOCTOR
        res = TestClient(app).patch("/bookings/bk-1/complete", headers=AUTH)
    assert res.status_code == 409
    bs.rpc.assert_not_called()                      # no transition, so no fee release clock


def test_purge_erases_review_comments_through_the_database_function():
    from app.services import erasure
    db = _erasure_db()
    with patch("app.services.erasure.supabase", db), patch("app.services.erasure.storage.remove", return_value=True):
        erasure.purge_patient(U)
    assert ("redact_patient_reviews", {"p_patient_id": U}) in db.rpc_calls
    assert any(r.get("status") == "fulfilled" for r in db.rows("dsr_requests"))


def test_a_purge_that_could_not_erase_reviews_stays_pending():
    """If migration 0032 is not applied the function is missing: say so by
    leaving the request open, not by reporting an erasure that did not happen."""
    from app.services import erasure
    db = _erasure_db()

    def missing(_params):
        raise RuntimeError("function redact_patient_reviews does not exist")
    db.rpc_handlers["redact_patient_reviews"] = missing
    with patch("app.services.erasure.supabase", db), patch("app.services.erasure.storage.remove", return_value=True):
        erasure.purge_patient(U)
    assert not any(r.get("status") == "fulfilled" for r in db.rows("dsr_requests"))


def test_phone_numbers_must_be_ascii_digits():
    import pytest
    from app.phone import normalize_e164
    assert normalize_e164("+91 98765 43210") == "+919876543210"
    for bad in ("+91٩٨٧٦٥٤٣٢١٠", "+٩١٩٨٧٦٥٤٣٢١٠", "+0919876543210", "+91²8765432100"):
        with pytest.raises(ValueError):
            normalize_e164(bad)
