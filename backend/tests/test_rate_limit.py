"""Tests for the generic sliding-window rate limiter."""
from unittest.mock import MagicMock, patch

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.errors import AppError, app_error_handler
from app.services.rate_limit import rate_limiter
from tests.conftest import make_chain, make_supabase

RL_DB = "app.services.rate_limit.supabase"


def _app_with_limit(max_hits: int, window_seconds: int, key=None):
    app = FastAPI()
    app.add_exception_handler(AppError, app_error_handler)

    @app.post("/ping")
    def ping(_rl: None = rate_limiter("test-scope", max_hits, window_seconds, key=key)):
        return {"ok": True}

    return app


def test_allows_requests_under_the_limit():
    db = make_supabase({"rate_limit_hits": make_chain(list_data=[])})
    with patch(RL_DB, db):
        client = TestClient(_app_with_limit(3, 60))
        for _ in range(3):
            res = client.post("/ping")
            assert res.status_code == 200


def test_blocks_once_the_limit_is_reached():
    # Three prior hits already in the window — the fourth request is the one
    # that pushes past max_hits=3.
    chain = make_chain(list_data=[{"id": 1}, {"id": 2}, {"id": 3}])
    db = make_supabase({"rate_limit_hits": chain})
    with patch(RL_DB, db):
        client = TestClient(_app_with_limit(3, 60))
        res = client.post("/ping")

    assert res.status_code == 429
    assert "Too many attempts" in res.json()["error"]


def test_each_identifier_has_its_own_budget():
    """Two different keys (e.g. two different emails) never share a bucket."""
    seen_identifiers = []

    def fake_select(*a, **kw):
        return chain

    chain = MagicMock()
    chain.select.return_value = chain
    chain.eq.side_effect = lambda field, value: (
        seen_identifiers.append(value) if field == "identifier" else None
    ) or chain
    chain.gte.return_value = chain
    chain.insert.return_value = chain
    chain.execute.return_value = MagicMock(data=[])

    db = MagicMock()
    db.table.return_value = chain

    with patch(RL_DB, db):
        client = TestClient(_app_with_limit(1, 60, key=lambda r: r.headers.get("x-id", "")))
        res_a = client.post("/ping", headers={"x-id": "a@example.com"})
        res_b = client.post("/ping", headers={"x-id": "b@example.com"})

    assert res_a.status_code == 200
    assert res_b.status_code == 200
    assert "a@example.com" in seen_identifiers
    assert "b@example.com" in seen_identifiers


def test_records_a_hit_even_when_rejecting():
    """A caller hammering a blocked endpoint keeps resetting its own cooldown
    rather than finding a free pass by continuing to retry."""
    chain = make_chain(list_data=[{"id": 1}])
    db = make_supabase({"rate_limit_hits": chain})
    with patch(RL_DB, db):
        client = TestClient(_app_with_limit(1, 60))
        client.post("/ping")

    assert chain.insert.called
