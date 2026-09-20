"""
Tests for phone/OTP authentication and the durable OTP store.

The store moved out of process memory into the ``otp_codes`` table, so these
cover the properties that move gained: hashed codes, shared rate limiting, and
attempt counting that survives a restart.
"""
from datetime import datetime, timedelta, timezone
from unittest.mock import MagicMock, patch

import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.services import otp_store
from tests.conftest import make_chain, make_supabase

STORE_DB = "app.services.otp_store.supabase"
AUTH_DB  = "app.routers.auth.supabase"

client = TestClient(app)


def _iso(dt: datetime) -> str:
    return dt.isoformat()


def _future(**kw) -> str:
    return _iso(datetime.now(timezone.utc) + timedelta(**kw))


def _past(**kw) -> str:
    return _iso(datetime.now(timezone.utc) - timedelta(**kw))


# ── hashing ───────────────────────────────────────────────────────────────────

def test_codes_are_stored_hashed_not_in_plaintext():
    """A database leak must not hand an attacker live OTPs."""
    digest = otp_store.hash_code("+919876543210", "123456")
    assert "123456" not in digest
    assert len(digest) == 64


def test_the_phone_salts_the_hash():
    """The same six digits for two numbers must not produce the same hash."""
    assert otp_store.hash_code("+919876543210", "123456") != \
           otp_store.hash_code("+919999999999", "123456")


def test_generated_codes_are_six_digits():
    for _ in range(20):
        code = otp_store.generate_code()
        assert len(code) == otp_store.CODE_LENGTH and code.isdigit()


# ── consume ───────────────────────────────────────────────────────────────────

def _store_db(row, update_data=None):
    chain = make_chain()
    chain.execute.side_effect = [
        MagicMock(data=[row] if row else []),           # latest_active
        MagicMock(data=[update_data or {"id": "otp-1"}]),  # update
        MagicMock(data=[update_data or {"id": "otp-1"}]),  # possible second update
    ]
    return make_supabase({"otp_codes": chain}), chain


def _row(code="123456", phone="+919876543210", attempts=0, expires_in_minutes=5):
    return {
        "id": "otp-1",
        "phone": phone,
        "role": "patient",
        "code_hash": otp_store.hash_code(phone, code),
        "expires_at": _future(minutes=expires_in_minutes),
        "attempts": attempts,
        "consumed_at": None,
    }


def test_consume_accepts_the_correct_code():
    db, _ = _store_db(_row())
    with patch(STORE_DB, db):
        assert otp_store.consume("+919876543210", "123456")["id"] == "otp-1"


def test_consume_marks_the_code_used_so_it_cannot_be_replayed():
    db, chain = _store_db(_row())
    with patch(STORE_DB, db):
        otp_store.consume("+919876543210", "123456")
    assert "consumed_at" in chain.update.call_args[0][0]


def test_consume_rejects_when_no_code_was_issued():
    db, _ = _store_db(None)
    with patch(STORE_DB, db):
        with pytest.raises(otp_store.OTPError) as exc:
            otp_store.consume("+919876543210", "123456")
    assert "No OTP was sent" in exc.value.message


def test_consume_rejects_an_expired_code():
    row = _row()
    row["expires_at"] = _past(minutes=1)
    db, _ = _store_db(row)
    with patch(STORE_DB, db):
        with pytest.raises(otp_store.OTPError) as exc:
            otp_store.consume("+919876543210", "123456")
    assert "expired" in exc.value.message


def test_a_wrong_code_increments_attempts_and_counts_down():
    db, chain = _store_db(_row(attempts=1))
    with patch(STORE_DB, db):
        with pytest.raises(otp_store.OTPError) as exc:
            otp_store.consume("+919876543210", "000000")

    assert chain.update.call_args[0][0] == {"attempts": 2}
    assert "3 attempt(s) remaining" in exc.value.message


def test_the_final_wrong_attempt_burns_the_code():
    """At the attempt ceiling the code is consumed, so brute force must restart
    from a fresh send — which is itself rate limited."""
    db, chain = _store_db(_row(attempts=otp_store.MAX_VERIFY_ATTEMPTS - 1))
    with patch(STORE_DB, db):
        with pytest.raises(otp_store.OTPError) as exc:
            otp_store.consume("+919876543210", "000000")

    assert "Too many incorrect attempts" in exc.value.message
    assert any("consumed_at" in call[0][0] for call in chain.update.call_args_list)


def test_consume_rejects_once_the_attempt_ceiling_is_already_reached():
    db, _ = _store_db(_row(attempts=otp_store.MAX_VERIFY_ATTEMPTS))
    with patch(STORE_DB, db):
        with pytest.raises(otp_store.OTPError):
            otp_store.consume("+919876543210", "123456")


def test_expiry_parsing_tolerates_microseconds_and_z_suffix():
    """Supabase returns timestamptz in several shapes; none may crash a login."""
    for stamp in (
        "2099-01-01T00:00:00+00:00",
        "2099-01-01T00:00:00.123456+00:00",
        "2099-01-01T00:00:00Z",
        "2099-01-01T00:00:00",
    ):
        row = _row()
        row["expires_at"] = stamp
        db, _ = _store_db(row)
        with patch(STORE_DB, db):
            assert otp_store.consume("+919876543210", "123456")["id"] == "otp-1", stamp


# ── send-otp route ────────────────────────────────────────────────────────────

def test_send_otp_persists_a_code_and_reports_the_ttl():
    otp_chain = make_chain(list_data=[])
    db = make_supabase({"otp_codes": otp_chain})
    with patch(STORE_DB, db), patch("app.routers.auth.MSG91_API_KEY", ""):
        res = client.post("/auth/send-otp", json={"phone": "+919876543210", "role": "patient"})

    assert res.status_code == 200
    assert res.json()["expires_in"] == otp_store.OTP_TTL_SECONDS
    written = otp_chain.insert.call_args[0][0]
    assert written["phone"] == "+919876543210"
    assert "code_hash" in written and "code" not in written


def test_send_otp_rate_limits_per_hour_across_workers():
    """The limit is counted from rows, not a per-process dict, so a second
    uvicorn worker sees the same budget."""
    recent = [{"id": f"o{i}"} for i in range(otp_store.MAX_SENDS_PER_HOUR)]
    db = make_supabase({"otp_codes": make_chain(list_data=recent)})
    with patch(STORE_DB, db), patch("app.routers.auth.MSG91_API_KEY", ""):
        res = client.post("/auth/send-otp", json={"phone": "+919876543210", "role": "patient"})

    assert res.status_code == 429
    assert "Try again in an hour" in res.json()["error"]


@pytest.mark.parametrize("phone", ["9876543210", "+91 98765", "+abcdefghij", "", "+9198765432100000"])
def test_send_otp_rejects_a_non_e164_phone(phone):
    with patch(STORE_DB, make_supabase({})):
        res = client.post("/auth/send-otp", json={"phone": phone, "role": "patient"})
    assert res.status_code == 422


def test_send_otp_rejects_an_unknown_role():
    with patch(STORE_DB, make_supabase({})):
        res = client.post("/auth/send-otp", json={"phone": "+919876543210", "role": "nurse"})
    assert res.status_code == 422


def test_send_otp_surfaces_an_sms_gateway_failure():
    """A patient must not be left on an OTP screen for a code that was never sent."""
    otp_chain = make_chain(list_data=[])
    failing = MagicMock()
    failing.status_code = 502

    class _FakeClient:
        async def __aenter__(self): return self
        async def __aexit__(self, *a): return False
        async def post(self, *a, **kw): return failing

    with patch(STORE_DB, make_supabase({"otp_codes": otp_chain})), \
         patch("app.routers.auth.MSG91_API_KEY", "live-key"), \
         patch("app.routers.auth.httpx.AsyncClient", lambda **kw: _FakeClient()):
        res = client.post("/auth/send-otp", json={"phone": "+919876543210", "role": "patient"})

    assert res.status_code == 502
    assert "Could not send OTP" in res.json()["error"]


# ── verify-otp route ──────────────────────────────────────────────────────────

def _verify_dbs(user_row, otp_row=None):
    otp_chain = make_chain()
    otp_chain.execute.side_effect = [
        MagicMock(data=[otp_row or _row()]),
        MagicMock(data=[{"id": "otp-1"}]),
        MagicMock(data=[{"id": "otp-1"}]),
    ]
    store_db = make_supabase({"otp_codes": otp_chain})
    auth_db = make_supabase({
        "users": make_chain(list_data=[user_row]),
        "doctors": make_chain(list_data=[user_row]),
    })
    return store_db, auth_db


def test_verify_otp_returns_a_token_and_flags_a_new_user():
    store_db, auth_db = _verify_dbs({"id": "usr-1", "phone": "+919876543210", "name": None})
    with patch(STORE_DB, store_db), patch(AUTH_DB, auth_db):
        res = client.post("/auth/verify-otp", json={
            "phone": "+919876543210", "code": "123456", "role": "patient",
        })

    body = res.json()
    assert res.status_code == 200
    assert body["is_new"] is True
    assert body["token"]


def test_verify_otp_flags_a_returning_user_as_not_new():
    store_db, auth_db = _verify_dbs({"id": "usr-1", "phone": "+919876543210", "name": "Asha"})
    with patch(STORE_DB, store_db), patch(AUTH_DB, auth_db):
        res = client.post("/auth/verify-otp", json={
            "phone": "+919876543210", "code": "123456", "role": "patient",
        })
    assert res.json()["is_new"] is False


def test_verify_otp_upserts_a_doctor_into_the_doctors_table():
    store_db, auth_db = _verify_dbs({"id": "doc-1", "phone": "+919876543210", "name": None})
    with patch(STORE_DB, store_db), patch(AUTH_DB, auth_db):
        client.post("/auth/verify-otp", json={
            "phone": "+919876543210", "code": "123456", "role": "doctor",
        })
    auth_db.table.assert_any_call("doctors")


def test_verify_otp_token_carries_the_subject_and_role():
    from jose import jwt
    from app.config import JWT_SECRET

    store_db, auth_db = _verify_dbs({"id": "doc-1", "phone": "+919876543210", "name": "Dr A"})
    with patch(STORE_DB, store_db), patch(AUTH_DB, auth_db):
        token = client.post("/auth/verify-otp", json={
            "phone": "+919876543210", "code": "123456", "role": "doctor",
        }).json()["token"]

    claims = jwt.decode(token, JWT_SECRET, algorithms=["HS256"])
    assert claims["sub"] == "doc-1"
    assert claims["role"] == "doctor"
    assert claims["exp"] > claims["iat"]


def test_verify_otp_rejects_a_wrong_code_with_a_400():
    store_db, auth_db = _verify_dbs({"id": "usr-1", "phone": "+919876543210", "name": None})
    with patch(STORE_DB, store_db), patch(AUTH_DB, auth_db):
        res = client.post("/auth/verify-otp", json={
            "phone": "+919876543210", "code": "000000", "role": "patient",
        })
    assert res.status_code == 400
    assert "Incorrect OTP" in res.json()["error"]


@pytest.mark.parametrize("code", ["12345", "1234567", "abcdef", ""])
def test_verify_otp_rejects_a_malformed_code_before_touching_the_database(code):
    with patch(STORE_DB, make_supabase({})):
        res = client.post("/auth/verify-otp", json={
            "phone": "+919876543210", "code": code, "role": "patient",
        })
    assert res.status_code == 422
