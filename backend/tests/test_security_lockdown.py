"""
Regression tests for the 2026-10 security review.

Each block pins one finding so it cannot quietly come back: the public
directory leaking private columns, phone numbers claimed without proof,
rate limits keyed on a client-supplied header, admin TOTP replay, the senior
review ceiling, erasure leaving sign-in links behind, and the smaller items.
"""
from datetime import datetime, timedelta, timezone
from unittest.mock import MagicMock, patch

import bcrypt
import jwt
import pyotp
from fastapi import FastAPI, Request
from fastapi.testclient import TestClient

from app.config import JWT_SECRET, PROCEDURE_REVIEW_THRESHOLD_MAX
from app.main import app
from app.services import erasure, identity
from app.services.rate_limit import client_ip
from tests.conftest import make_chain, make_chain_seq, make_supabase

client = TestClient(app)
AUTH = {"Authorization": "Bearer t"}
JWT = "app.deps.jwt"


def _as(payload):
    """Patch token decoding so every request is made as `payload`."""
    jw = patch(JWT)
    mock = jw.start()
    mock.decode.return_value = payload
    return jw


# ── Public directory: an allowlist, not a denylist ────────────────────────────

_FULL_DOCTOR_ROW = {
    "id": "doc-1", "name": "Dr Rao", "bio": "MBBS", "photo_url": "https://x/p.jpg",
    "category_id": "cat-1", "categories": {"name": "Cardiology"}, "rating_avg": 4.5,
    "offers_online_consult": True, "offers_home_visit": False,
    "online_consult_mode": "scheduled", "service_radius_km": 5, "accepting_requests": True,
    "verification_status": "verified", "suspended": False,
    "doctor_pricing": [{"channel": "online_consult", "price": 500}],
    "doctor_procedures": [
        {"name": "Dressing", "price": 200, "active": True},
        {"name": "Removed", "price": 900, "active": False},
    ],
    "procedure_review_threshold": None,
    # Everything below is private and must never reach an anonymous caller.
    "phone": "+919876543210", "email": "rao@example.com", "google_sub": "g-1",
    "firebase_uid": "fb-1", "application_details": {"nuid": "N-123", "hprId": "H-9"},
    "license_number": "L-1", "fcm_token": "tok", "commission_pct": 0,
    "base_lat": 18.5, "base_lng": 73.8, "verification_document_path": "d/x.pdf",
    "otp_verified": True, "sessions_revoked_at": None, "deletion_status": None,
}

_PRIVATE = {
    "phone", "email", "google_sub", "firebase_uid", "application_details",
    "license_number", "fcm_token", "commission_pct", "base_lat", "base_lng",
    "verification_document_path", "otp_verified", "sessions_revoked_at",
    "deletion_status", "verification_status", "suspended",
}


def test_search_returns_only_public_fields():
    db = make_supabase({"doctors": make_chain(list_data=[_FULL_DOCTOR_ROW])})
    with patch("app.routers.doctors.supabase", db):
        item = client.get("/doctors/search").json()["items"][0]

    assert not _PRIVATE & item.keys(), _PRIVATE & item.keys()
    assert item["name"] == "Dr Rao" and item["doctor_pricing"]


def test_a_profile_page_returns_only_public_fields():
    db = make_supabase({"doctors": make_chain(data=_FULL_DOCTOR_ROW)})
    with patch("app.routers.doctors.supabase", db):
        body = client.get("/doctors/doc-1").json()

    assert not _PRIVATE & body.keys(), _PRIVATE & body.keys()
    # A removed procedure is no longer offered.
    assert [p["name"] for p in body["doctor_procedures"]] == ["Dressing"]
    # Patients are told the threshold that actually applies.
    assert body["procedure_review_threshold"] == PROCEDURE_REVIEW_THRESHOLD_MAX


# ── Doctor profile edits ──────────────────────────────────────────────────────

DOCTOR = {"sub": "doc-1", "role": "doctor"}
PATIENT = {"sub": "pat-1", "role": "patient"}


def _patch_doctor(body, current):
    doctors = make_chain_seq(current, [{"id": "doc-1"}])
    jw = _as(DOCTOR)
    try:
        with patch("app.routers.doctors.supabase", make_supabase({"doctors": doctors})):
            res = client.patch("/doctors/me", json=body, headers=AUTH)
    finally:
        jw.stop()
    written = doctors.update.call_args[0][0] if doctors.update.called else None
    return res, written


_VERIFIED_CURRENT = {
    "phone": "+919876543210", "verification_status": "verified",
    "name": "Dr Rao", "category_id": "cat-1", "application_details": {"nuid": "N-1"},
}


def test_a_doctor_cannot_point_their_photo_at_an_arbitrary_url():
    res, written = _patch_doctor(
        {"bio": "hi", "photo_url": "https://tracker.example/pixel.gif"}, _VERIFIED_CURRENT
    )
    assert res.status_code == 200
    assert "photo_url" not in written


def test_renaming_a_verified_profile_sends_it_back_to_review():
    res, written = _patch_doctor({"name": "Dr Somebody Famous"}, _VERIFIED_CURRENT)
    assert res.status_code == 200
    assert written["verification_status"] == "pending"


def test_resaving_the_same_name_does_not_unverify():
    _, written = _patch_doctor({"name": "Dr Rao", "bio": "new bio"}, _VERIFIED_CURRENT)
    assert "verification_status" not in written


def test_changing_the_registration_details_sends_it_back_to_review():
    _, written = _patch_doctor({"application_details": {"nuid": "N-999"}}, _VERIFIED_CURRENT)
    assert written["verification_status"] == "pending"


def test_a_typed_in_phone_change_is_not_verified():
    _, written = _patch_doctor({"phone": "+919000000009"}, _VERIFIED_CURRENT)
    assert written["otp_verified"] is False


def test_a_doctor_cannot_raise_their_own_review_threshold_past_the_ceiling():
    res, written = _patch_doctor(
        {"procedure_review_threshold": PROCEDURE_REVIEW_THRESHOLD_MAX + 1}, _VERIFIED_CURRENT
    )
    assert res.status_code == 400
    assert written is None


# ── Patient profile edits ─────────────────────────────────────────────────────

def _patch_patient(body, current_phone):
    users = make_chain_seq({"phone": current_phone}, [{"id": "pat-1"}])
    jw = _as(PATIENT)
    try:
        with patch("app.routers.users.supabase", make_supabase({"users": users})):
            res = client.patch("/users/me", json=body, headers=AUTH)
    finally:
        jw.stop()
    return res, users.update.call_args[0][0]


def test_a_patient_changing_their_phone_loses_verification():
    res, written = _patch_patient({"phone": "+919000000009"}, "+919876543210")
    assert res.status_code == 200
    assert written["otp_verified"] is False


def test_resubmitting_the_same_phone_keeps_verification():
    _, written = _patch_patient({"phone": "+919876543210", "name": "A"}, "+919876543210")
    assert "otp_verified" not in written


def test_a_doctor_token_cannot_edit_a_patient_profile():
    jw = _as(DOCTOR)
    try:
        res = client.patch("/users/me", json={"name": "x"}, headers=AUTH)
    finally:
        jw.stop()
    assert res.status_code == 403


# ── Proof of a phone number beats a claim to it ───────────────────────────────

def test_proving_a_number_releases_it_from_rows_that_only_claimed_it():
    users = make_chain(list_data=[
        {"id": "squatter", "firebase_uid": None},
        {"id": "returning", "firebase_uid": "fb-me"},
    ])
    with patch("app.services.identity.supabase", make_supabase({"users": users})):
        released = identity.release_unproven_phone("users", "+919876543210",
                                                   keep_firebase_uid="fb-me")

    assert released == 1
    users.eq.assert_any_call("otp_verified", False)
    users.update.assert_called_once_with({"phone": None})
    users.eq.assert_any_call("id", "squatter")


def test_verify_otp_releases_the_number_before_signing_in_by_it():
    otp = make_chain()
    otp.execute.side_effect = [
        MagicMock(data=[{"id": "otp-1", "role": "patient", "attempts": 0,
                         "code_hash": __import__("app.services.otp_store", fromlist=["x"])
                         .hash_code("+919876543210", "123456"),
                         "expires_at": (datetime.now(timezone.utc) + timedelta(minutes=5)).isoformat()}]),
        MagicMock(data=[{"id": "otp-1"}]),
    ]
    users = make_chain(list_data=[{"id": "u-1", "phone": "+919876543210", "name": "A"}])
    order = []
    users.upsert.side_effect = lambda *a, **k: order.append("upsert") or users
    with patch("app.services.otp_store.supabase", make_supabase({"otp_codes": otp})), \
         patch("app.routers.auth.supabase", make_supabase({"users": users})), \
         patch("app.routers.auth.identity.release_unproven_phone",
               side_effect=lambda *a, **k: order.append(("release", a))) as release:
        res = client.post("/auth/verify-otp", json={
            "phone": "+919876543210", "code": "123456", "role": "patient"})

    assert res.status_code == 200
    release.assert_called_once_with("users", "+919876543210")
    assert order[0] == ("release", ("users", "+919876543210")) and order[1] == "upsert"


def test_firebase_phone_sign_in_releases_the_number_but_keeps_its_own_row():
    claims = {"sub": "fb-456", "phone_number": "+919876543210",
              "firebase": {"sign_in_provider": "phone"}}
    users = make_chain(list_data=[{"id": "u-1", "name": "A", "phone": "+919876543210"}])
    with patch("app.routers.auth.firebase_auth.enabled", return_value=True), \
         patch("app.routers.auth.firebase_auth.verify", return_value=claims), \
         patch("app.routers.auth.supabase", make_supabase({"users": users})), \
         patch("app.routers.auth.identity.release_unproven_phone") as release:
        res = client.post("/auth/firebase", json={"id_token": "t", "role": "patient"})

    assert res.status_code == 200
    release.assert_called_once_with("users", "+919876543210", keep_firebase_uid="fb-456")


def test_otp_is_only_sent_to_allowed_country_codes():
    with patch("app.routers.auth.ALLOW_OTP_STUB", True):
        res = client.post("/auth/send-otp", json={"phone": "+447700900123", "role": "patient"})
    assert res.status_code == 400


# ── Rate-limit identity ──────────────────────────────────────────────────────

def _ip_of(headers, host="10.0.0.1"):
    scope = {
        "type": "http", "method": "GET", "path": "/", "query_string": b"",
        "headers": [(k.lower().encode(), v.encode()) for k, v in headers.items()],
        "client": (host, 1234),
    }
    return client_ip(Request(scope))


def test_a_spoofed_forwarded_for_entry_is_ignored():
    # The client sent "1.2.3.4"; Google's front end appended the real address.
    assert _ip_of({"X-Forwarded-For": "1.2.3.4, 203.0.113.7"}) == "203.0.113.7"


def test_rotating_spoofed_entries_all_count_against_one_caller():
    seen = {_ip_of({"X-Forwarded-For": f"9.9.9.{i}, 203.0.113.7"}) for i in range(50)}
    assert seen == {"203.0.113.7"}


def test_ipv6_callers_are_counted_per_64():
    a = _ip_of({"X-Forwarded-For": "2001:db8:1:2::1"})
    b = _ip_of({"X-Forwarded-For": "2001:db8:1:2:ffff::9"})
    assert a == b == "2001:db8:1:2::/64"


def test_without_a_proxy_header_the_socket_address_is_used():
    assert _ip_of({}, host="198.51.100.4") == "198.51.100.4"


# ── Admin login ──────────────────────────────────────────────────────────────

_SECRET = pyotp.random_base32()
_ADMIN = {
    "id": "00000000-0000-0000-0000-0000000000a1", "email": "ops@charak.care",
    "password_hash": bcrypt.hashpw(b"pw-correct", bcrypt.gensalt()).decode(),
    "totp_secret": _SECRET, "totp_enabled": True,
}


def _admin_login(body, hits_by_scope):
    def table(name):
        if name != "rate_limit_hits":
            return make_chain()
        chain = make_chain()
        scope = {}
        chain.eq.side_effect = lambda col, val: (scope.__setitem__(col, val), chain)[1]
        chain.execute.side_effect = lambda: MagicMock(
            data=[{"id": 1}] * hits_by_scope.get(scope.get("scope"), 0))
        return chain

    rl_db = MagicMock()
    rl_db.table.side_effect = table
    admin_db = make_supabase({"admin_users": make_chain(list_data=[_ADMIN])})
    with patch("app.services.admin_auth.supabase", admin_db), \
         patch("app.services.rate_limit.supabase", rl_db):
        return client.post("/admin/login", json=body)


def test_admin_login_is_capped_per_account_not_just_per_ip():
    res = _admin_login({"email": "ops@charak.care", "password": "pw-correct"},
                       {"admin-login-account": 10})
    assert res.status_code == 429


def test_a_totp_code_works_once():
    code = pyotp.TOTP(_SECRET).now()
    body = {"email": "ops@charak.care", "password": "pw-correct", "totp_code": code}

    assert _admin_login(body, {}).status_code == 200
    replay = _admin_login(body, {"admin-totp-used": 1})
    assert replay.status_code == 401
    assert "already been used" in replay.json()["error"]


def test_an_admin_token_carries_its_issue_time():
    code = pyotp.TOTP(_SECRET).now()
    res = _admin_login({"email": "ops@charak.care", "password": "pw-correct",
                        "totp_code": code}, {})
    claims = jwt.decode(res.json()["token"], JWT_SECRET, algorithms=["HS256"])
    assert "iat" in claims


# ── Senior review of procedure bills ─────────────────────────────────────────

_COMPLETED = {"id": "bk-1", "doctor_id": "doc-1", "patient_id": "pat-1",
              "channel": "home_visit", "status": "completed"}


def _bill(total, doctor_threshold):
    bills = make_chain_seq([], [{"id": "bill-1", "booking_id": "bk-1"}])
    db = make_supabase({
        "bookings": make_chain(data=_COMPLETED),
        "procedure_bills": bills,
        "doctors": make_chain(data={"procedure_review_threshold": doctor_threshold}),
    })
    jw = _as(DOCTOR)
    try:
        with patch("app.routers.procedure_bills.supabase", db):
            res = client.post("/bookings/bk-1/procedure-bill", headers=AUTH,
                              json={"items": [{"name": "Procedure", "price": total}]})
    finally:
        jw.stop()
    return res.json()


def test_a_doctor_with_no_threshold_is_still_reviewed_above_the_ceiling():
    assert _bill(PROCEDURE_REVIEW_THRESHOLD_MAX + 1, None)["needs_review"] is True


def test_a_threshold_set_above_the_ceiling_is_capped():
    assert _bill(PROCEDURE_REVIEW_THRESHOLD_MAX + 1, 10_000_000)["needs_review"] is True


def test_a_doctor_may_still_ask_for_stricter_review():
    assert _bill(600, 500)["needs_review"] is True
    assert _bill(400, 500)["needs_review"] is False


# ── Erasure ──────────────────────────────────────────────────────────────────

def test_purging_a_patient_unlinks_their_firebase_identity():
    users = make_chain()
    db = make_supabase({"users": users})
    with patch("app.services.erasure.supabase", db), \
         patch("app.services.erasure.storage.remove"):
        erasure.purge_patient("pat-1")

    written = users.update.call_args[0][0]
    assert written["firebase_uid"] is None and written["google_sub"] is None


def test_purging_a_doctor_erases_registration_details_and_sign_in_links():
    doctors = make_chain(list_data=[{"photo_path": None, "verification_document_path": None}])
    db = make_supabase({"doctors": doctors})
    with patch("app.services.erasure.supabase", db):
        erasure.purge_doctor("doc-1")

    written = doctors.update.call_args[0][0]
    assert written["application_details"] is None
    assert written["firebase_uid"] is None


def test_deleting_an_account_ends_its_existing_sessions():
    users, doctors = make_chain(), make_chain()
    db = make_supabase({"users": users, "doctors": doctors})
    with patch("app.services.erasure.supabase", db):
        erasure.request_patient_deletion("pat-1")
        erasure.request_doctor_deletion("doc-1")

    assert "sessions_revoked_at" in users.update.call_args_list[0][0][0]
    assert "sessions_revoked_at" in doctors.update.call_args[0][0]


def test_signing_in_the_same_second_as_a_revocation_still_works():
    """iat is whole seconds; the revocation stamp is not."""
    from app.deps import _session_revoked

    now = datetime.now(timezone.utc).replace(microsecond=0)
    revoked_at = (now + timedelta(microseconds=600_000)).isoformat()
    db = make_supabase({"users": make_chain(list_data=[{"sessions_revoked_at": revoked_at}])})
    with patch("app.deps.supabase", db):
        assert _session_revoked("patient", "pat-1", int(now.timestamp())) is False
        assert _session_revoked("patient", "pat-1", int(now.timestamp()) - 1) is True


# ── Smaller items ────────────────────────────────────────────────────────────

def test_api_docs_are_not_published_by_default():
    for path in ("/docs", "/redoc", "/openapi.json"):
        assert client.get(path).status_code == 404


def test_readiness_does_not_echo_database_errors():
    broken = MagicMock()
    broken.table.side_effect = RuntimeError("password authentication failed for user postgres")
    with patch("app.db.supabase", broken):
        body = client.get("/readyz").json()
    assert body["database"]["ok"] is False
    assert "password" not in str(body)


def test_a_call_channel_is_the_whole_booking_id():
    """Two bookings sharing an 8-character prefix must not share a channel."""
    booking_id = "0a1b2c3d-1111-2222-3333-444455556666"
    booking = {"id": booking_id, "doctor_id": "doc-1", "patient_id": "pat-1",
               "status": "accepted"}
    db = make_supabase({
        "bookings": make_chain(data=booking),
        "clarification_calls": make_chain_seq([], [{"id": "call-1"}]),
    })
    jw = _as(DOCTOR)
    try:
        with patch("app.routers.calls.supabase", db):
            res = client.post(f"/bookings/{booking_id}/clarification-call", headers=AUTH)
    finally:
        jw.stop()
    assert res.json()["agora_channel"] == f"charak_{booking_id}"


def test_ledger_adjustments_are_audited():
    OPS = {"sub": "00000000-0000-0000-0000-0000000000a1", "role": "ops"}
    ledger = make_chain(list_data=[{"id": "00000000-0000-0000-0000-00000000e001"}])
    audit_db = make_supabase({"audit_log": make_chain()})
    jw = _as(OPS)
    try:
        with patch("app.routers.payouts.supabase", make_supabase({"doctor_ledger_entries": ledger})), \
             patch("app.services.audit.supabase", audit_db):
            res = client.post("/payouts/adjustments", headers=AUTH, json={
                "doctor_id": "doc-1", "amount": 500, "note": "goodwill"})
    finally:
        jw.stop()

    assert res.status_code == 201
    written = audit_db.table("audit_log").insert.call_args[0][0]
    assert written["action"] == "ledger_adjustment"
    assert written["actor_id"] == OPS["sub"]


# ── Booking times must come from the doctor's real calendar ──────────────────

from app.routers.bookings import _assert_bookable as _real_assert_bookable  # noqa: E402
from app.services.availability import IST  # noqa: E402

_FUTURE_DAY = (datetime.now(IST) + timedelta(days=3)).date()


def _bookable(start, open_starts):
    grid = {str(_FUTURE_DAY): [{"start": s} for s in open_starts]}
    with patch("app.routers.bookings.availability.get_available_slots", return_value=grid):
        _real_assert_bookable("doc-1", start)


def _at(hh, mm, ss=0):
    return datetime.combine(_FUTURE_DAY, datetime.min.time(), IST).replace(
        hour=hh, minute=mm, second=ss)


def test_an_open_slot_can_be_booked():
    _bookable(_at(9, 0), ["09:00", "09:15"])


def test_a_time_outside_the_grid_is_refused():
    import pytest
    from app.errors import AppError
    with pytest.raises(AppError) as exc:
        _bookable(_at(3, 0), ["09:00", "09:15"])
    assert exc.value.status_code == 409


def test_an_off_grid_second_is_refused():
    import pytest
    from app.errors import AppError
    with pytest.raises(AppError):
        _bookable(_at(9, 0, 30), ["09:00"])


def test_the_same_instant_in_utc_is_accepted():
    """The grid is IST; a client sending UTC for the same moment is fine."""
    _bookable(_at(9, 0).astimezone(timezone.utc), ["09:00"])


def test_a_past_time_is_refused_before_the_grid_is_consulted():
    import pytest
    from app.errors import AppError
    past = datetime.now(IST) - timedelta(days=1)
    with patch("app.routers.bookings.availability.get_available_slots") as grid, \
         pytest.raises(AppError) as exc:
        _real_assert_bookable("doc-1", past)
    assert exc.value.status_code == 409
    grid.assert_not_called()


def test_a_booking_time_without_an_offset_is_refused():
    doctor = {"id": "doc-1", "verification_status": "verified", "suspended": False,
              "offers_online_consult": True}
    db = make_supabase({"doctors": make_chain(data=doctor)})
    jw = _as(PATIENT)
    try:
        with patch("app.routers.bookings.supabase", db):
            res = client.post("/bookings/", headers=AUTH, json={
                "doctor_id": "doc-1", "channel": "online_consult",
                "scheduled_start": "2026-12-01T09:00:00"})
    finally:
        jw.stop()
    assert res.status_code == 400
    assert "timezone" in res.json()["error"]


# ── Status changes are compare-and-set ───────────────────────────────────────

def test_a_cancel_that_loses_a_race_changes_nothing_and_refunds_nothing():
    booking = {"id": "bk-1", "patient_id": "pat-1", "doctor_id": "doc-1",
               "status": "paid", "channel": "online_consult"}
    bookings = make_chain_seq(booking, [])      # read: paid; conditional write: no row
    jw = _as(PATIENT)
    try:
        with patch("app.routers.bookings.supabase", make_supabase({"bookings": bookings})), \
             patch("app.routers.payments.refund_completed_payments") as refund:
            res = client.patch("/bookings/bk-1/cancel", headers=AUTH)
    finally:
        jw.stop()

    assert res.status_code == 409
    refund.assert_not_called()
    bookings.eq.assert_any_call("status", "paid")


def test_the_hold_sweeper_only_releases_bookings_still_unpaid():
    expired = [{"id": "bk-1", "status": "accepted"}, {"id": "bk-2", "status": "accepted"}]
    # bk-2 was paid between the sweeper's read and its write.
    bookings = make_chain_seq(expired, [{"id": "bk-1"}])
    notified = []
    with patch("app.routers.maintenance.CRON_SECRET", "s"), \
         patch("app.routers.maintenance.supabase", make_supabase({"bookings": bookings})), \
         patch("app.routers.maintenance.notifications.booking_hold_expired",
               side_effect=lambda b: notified.append(b["id"])):
        res = client.post("/maintenance/release-expired-holds", headers={"X-Cron-Secret": "s"})

    assert res.json() == {"released": 1, "booking_ids": ["bk-1"]}
    assert notified == ["bk-1"]
    bookings.eq.assert_any_call("status", "accepted")


def test_a_capture_that_loses_a_race_to_a_cancel_is_refunded():
    from app.routers import payments

    booking = {"id": "bk-1", "doctor_id": "doc-1", "patient_id": "pat-1", "status": "accepted"}
    payment = {"id": "pay-1", "booking_id": "bk-1", "amount": 500, "type": "consult_fee"}
    # read: accepted → conditional flip: no row → re-read: cancelled
    bookings = make_chain_seq(booking, [], {"status": "cancelled"})
    db = make_supabase({"bookings": bookings, "payments": make_chain()})
    with patch("app.routers.payments.supabase", db), \
         patch("app.routers.payments.payouts.credit"), \
         patch("app.routers.payments._refund_orphaned_payment") as refund, \
         patch("app.routers.payments.notifications"):
        out = payments._confirm_payment(payment, "rzp_pay_1", "upi")

    assert out == {"ok": True, "refunded": True}
    refund.assert_called_once()
    # The flip to `paid` is conditional on the booking still being accepted.
    bookings.eq.assert_any_call("status", "accepted")
