"""Tests for the rate_limit_hits cron sweeper (routers/maintenance.py)."""
from unittest.mock import MagicMock, patch

from fastapi.testclient import TestClient

from app.main import app
from tests.conftest import make_chain, make_supabase

MAINT_DB = "app.routers.maintenance.supabase"
CRON_HEADERS = {"X-Cron-Secret": "cron-secret"}


def test_purges_rows_older_than_a_day():
    deleted_rows = [{"id": 1}, {"id": 2}, {"id": 3}]
    db = make_supabase({"rate_limit_hits": make_chain(list_data=deleted_rows)})

    with patch(MAINT_DB, db), patch("app.routers.maintenance.CRON_SECRET", "cron-secret"):
        res = TestClient(app).post("/maintenance/purge-old-rate-limit-hits", headers=CRON_HEADERS)

    assert res.status_code == 200
    assert res.json() == {"deleted": 3}


def test_requires_the_cron_secret():
    with patch("app.routers.maintenance.CRON_SECRET", "cron-secret"):
        res = TestClient(app).post("/maintenance/purge-old-rate-limit-hits",
                                    headers={"X-Cron-Secret": "wrong"})
    assert res.status_code == 401
