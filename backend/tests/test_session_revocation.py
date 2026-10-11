"""
Tests for app.deps.get_current_user's session-revocation check.

A patient or doctor's sessions_revoked_at lets ops force-expire every token
that account has already been issued — the "my phone was stolen" response
that a fixed-length JWT alone cannot give you (see TOKEN_TTL_DAYS's
docstring in routers/auth.py).
"""
from datetime import datetime, timedelta, timezone
from unittest.mock import MagicMock, patch

from fastapi import Depends, FastAPI
from fastapi.testclient import TestClient
from jose import jwt as jose_jwt

from app.config import JWT_SECRET
from app.deps import get_current_user
from tests.conftest import make_chain, make_supabase

DEPS_DB = "app.deps.supabase"

app = FastAPI()


@app.get("/whoami")
def whoami(user: dict = Depends(get_current_user)):
    return user


client = TestClient(app)


def _token(role: str, sub: str, iat: datetime) -> str:
    return jose_jwt.encode(
        {"sub": sub, "role": role, "iat": iat, "exp": iat + timedelta(days=14)},
        JWT_SECRET,
        algorithm="HS256",
    )


def test_a_token_issued_before_revocation_is_rejected():
    now = datetime.now(timezone.utc)
    issued_at = now - timedelta(days=2)
    revoked_at = (now - timedelta(days=1)).isoformat()   # later than the token's iat
    db = make_supabase({"users": make_chain(list_data=[{"sessions_revoked_at": revoked_at}])})

    with patch(DEPS_DB, db):
        res = client.get("/whoami", headers={
            "Authorization": f"Bearer {_token('patient', 'u-1', issued_at)}"
        })

    assert res.status_code == 401
    assert "revoked" in res.json()["detail"].lower()


def test_a_token_issued_after_revocation_still_works():
    """Signing in again after a revocation issues a fresh, valid session."""
    now = datetime.now(timezone.utc)
    issued_at = now - timedelta(hours=1)
    revoked_at = (now - timedelta(days=1)).isoformat()   # earlier than the token's iat
    db = make_supabase({"users": make_chain(list_data=[{"sessions_revoked_at": revoked_at}])})

    with patch(DEPS_DB, db):
        res = client.get("/whoami", headers={
            "Authorization": f"Bearer {_token('patient', 'u-1', issued_at)}"
        })

    assert res.status_code == 200


def test_an_account_never_revoked_is_unaffected():
    db = make_supabase({"doctors": make_chain(list_data=[{"sessions_revoked_at": None}])})

    with patch(DEPS_DB, db):
        res = client.get("/whoami", headers={
            "Authorization": f"Bearer {_token('doctor', 'd-1', datetime.now(timezone.utc))}"
        })

    assert res.status_code == 200


def test_ops_tokens_are_never_looked_up():
    """admin_users has no sessions_revoked_at column — ops must not even query
    it (it would 500 against the real schema, not just behave oddly)."""
    db = MagicMock()
    with patch(DEPS_DB, db):
        res = client.get("/whoami", headers={
            "Authorization": f"Bearer {_token('ops', 'admin-1', datetime.now(timezone.utc))}"
        })

    assert res.status_code == 200
    db.table.assert_not_called()
