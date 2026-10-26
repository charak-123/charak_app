"""
Unit tests for the platform pieces from migration 0023: HTTP idempotency, the
job runner, app config and minimum versions, the webhook inbox, the state
machine's error mapping, and the tick endpoint.

The SQL behind them (claims, SKIP LOCKED, append-only history) is tested
against Postgres in tests/integration/test_state_machine.py.
"""
from datetime import datetime, timedelta, timezone
from unittest.mock import MagicMock, patch

import jwt
import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.main import app
from app.services import app_config, booking_state, idempotency, jobs
from tests.fakedb import FakeSupabase

SECRET = "unit-idempotency-secret-0123456789abcdef"


# ── HTTP idempotency ─────────────────────────────────────────────────────────

def _idem_app():
    """A tiny app behind the real middleware, counting how often each route runs."""
    mini = FastAPI()
    mini.add_middleware(idempotency.IdempotencyMiddleware)
    runs = {"create": 0, "boom": 0}

    @mini.post("/things")
    def create(body: dict):
        runs["create"] += 1
        return {"n": runs["create"], **body}

    @mini.post("/boom")
    def boom():
        runs["boom"] += 1
        raise RuntimeError("database fell over")

    @mini.post("/refused", status_code=403)
    def refused():
        return {"error": "Forbidden"}

    return mini, runs


def _idem_db():
    return FakeSupabase(
        {"idempotency_keys": []},
        defaults={"idempotency_keys": {
            "created_at": datetime.now(timezone.utc).isoformat(),
            "completed_at": None, "status_code": None, "response_body": None,
        }},
        unique={"idempotency_keys": [("user_id", "key")]},
    )


def _headers(key="key-0001-abcd", user="u-1"):
    token = jwt.encode({"sub": user, "role": "patient"}, SECRET, algorithm="HS256")
    return {"Authorization": f"Bearer {token}", "Idempotency-Key": key}


@pytest.fixture
def idem():
    db = _idem_db()
    mini, runs = _idem_app()
    with patch("app.services.idempotency.supabase", db), \
         patch("app.services.idempotency.JWT_SECRET", SECRET):
        yield TestClient(mini, raise_server_exceptions=False), runs, db


def test_a_retry_with_the_same_key_gets_the_first_answer(idem):
    client, runs, _ = idem
    first = client.post("/things", json={"a": 1}, headers=_headers())
    second = client.post("/things", json={"a": 1}, headers=_headers())
    assert first.json() == second.json() == {"n": 1, "a": 1}
    assert second.headers["idempotent-replayed"] == "true"
    assert runs["create"] == 1


def test_the_same_key_for_a_different_request_is_refused(idem):
    client, runs, _ = idem
    client.post("/things", json={"a": 1}, headers=_headers())
    res = client.post("/things", json={"a": 2}, headers=_headers())
    assert res.status_code == 422
    assert runs["create"] == 1


def test_keys_belong_to_one_user(idem):
    client, runs, _ = idem
    client.post("/things", json={"a": 1}, headers=_headers(user="u-1"))
    client.post("/things", json={"a": 1}, headers=_headers(user="u-2"))
    assert runs["create"] == 2


def test_a_request_still_running_is_not_run_again(idem):
    client, runs, db = idem
    db.rows("idempotency_keys").append({
        "user_id": "u-1", "key": "key-0001-abcd", "method": "POST", "path": "/things",
        "request_hash": idempotency.request_hash("POST", "/things", "", b'{"a":1}'),
        "created_at": datetime.now(timezone.utc).isoformat(), "completed_at": None,
    })
    res = client.post("/things", content=b'{"a":1}',
                      headers={**_headers(), "content-type": "application/json"})
    assert res.status_code == 409
    assert res.headers["retry-after"] == "1"
    assert runs["create"] == 0


def test_a_claim_whose_request_died_is_taken_over(idem):
    client, runs, db = idem
    db.rows("idempotency_keys").append({
        "user_id": "u-1", "key": "key-0001-abcd", "method": "POST", "path": "/things",
        "request_hash": idempotency.request_hash("POST", "/things", "", b'{"a":1}'),
        "created_at": (datetime.now(timezone.utc) - timedelta(minutes=5)).isoformat(),
        "completed_at": None,
    })
    res = client.post("/things", content=b'{"a":1}',
                      headers={**_headers(), "content-type": "application/json"})
    assert res.status_code == 200
    assert runs["create"] == 1


@pytest.mark.parametrize("path,code", [("/boom", 500), ("/refused", 403)])
def test_server_errors_and_refusals_are_not_stored(idem, path, code):
    client, runs, db = idem
    assert client.post(path, headers=_headers()).status_code == code
    assert db.rows("idempotency_keys") == []          # released: the retry runs


def test_requests_without_a_key_or_a_session_pass_straight_through(idem):
    client, runs, db = idem
    client.post("/things", json={"a": 1})
    client.post("/things", json={"a": 1}, headers={"Idempotency-Key": "key-0001-abcd"})
    assert runs["create"] == 2
    assert db.rows("idempotency_keys") == []


def test_a_malformed_key_is_rejected(idem):
    client, runs, _ = idem
    res = client.post("/things", json={}, headers=_headers(key="short"))
    assert res.status_code == 400
    assert runs["create"] == 0


def test_a_redirect_is_not_the_answer_and_the_trailing_slash_is_one_request(idem):
    """
    '/things/' redirects (307) to '/things'. The redirect must not be stored as
    the key's answer, or the followed request would look like a different
    request under the same key. Both spellings are one request.
    """
    client, runs, _ = idem
    first = client.post("/things/", json={"a": 1}, headers=_headers())
    retry = client.post("/things", json={"a": 1}, headers=_headers())
    assert first.status_code == 200 and first.json() == {"n": 1, "a": 1}
    assert retry.json() == {"n": 1, "a": 1}
    assert retry.headers["idempotent-replayed"] == "true"
    assert runs["create"] == 1


# ── job runner ───────────────────────────────────────────────────────────────

def _jobs_db(batches):
    calls = []
    remaining = list(batches)

    def rpc(name, params):
        calls.append((name, params))
        data = None
        if name == "claim_jobs":
            data = remaining.pop(0) if remaining else []
        elif name == "fail_job":
            data = "dead" if params["p_id"] == 99 else "queued"
        result = MagicMock()
        result.execute.return_value = MagicMock(data=data)
        return result

    db = MagicMock()
    db.rpc.side_effect = rpc
    return db, calls


def test_the_runner_finishes_jobs_whose_handler_succeeds_and_retries_the_rest():
    seen = []
    db, calls = _jobs_db([[
        {"id": 1, "kind": "t.ok", "payload": {"x": 1}},
        {"id": 2, "kind": "t.bad", "payload": {}},
        {"id": 99, "kind": "t.unknown", "payload": {}},
    ]])

    def bad(payload):
        raise ValueError("nope")

    with patch("app.services.jobs.supabase", db), \
         patch.dict(jobs.HANDLERS, {"t.ok": lambda p: seen.append(p), "t.bad": bad}):
        out = jobs.run_due(budget_seconds=5)

    assert seen == [{"x": 1}]
    assert out == {"done": 1, "retrying": 1, "dead": 1}
    assert ("finish_job", {"p_id": 1}) in calls
    fails = {p["p_id"]: p["p_error"] for n, p in calls if n == "fail_job"}
    assert "nope" in fails[2]
    assert "no handler" in fails[99]


def test_the_runner_stops_when_its_time_budget_is_spent():
    db, calls = _jobs_db([[{"id": 1, "kind": "t.ok", "payload": {}}]] * 10)
    ticks = iter([0, 0, 100, 100, 100])
    with patch("app.services.jobs.supabase", db), patch.dict(jobs.HANDLERS, {"t.ok": lambda p: None}):
        out = jobs.run_due(budget_seconds=10, clock=lambda: next(ticks))
    assert out["done"] == 1


def test_enqueueing_a_kind_with_no_handler_fails_fast():
    with pytest.raises(ValueError):
        jobs.enqueue("nobody.handles.this")


# ── app config and minimum versions ──────────────────────────────────────────

@pytest.mark.parametrize("raw,parsed", [
    ("1.4.2", (1, 4, 2)), ("1.4.2+17", (1, 4, 2)), ("2", (2, 0, 0)), ("1.10", (1, 10, 0)),
    ("", None), ("v1.2", None), ("1.2.x", None), ("1.2 3", None),
])
def test_versions_parse_strictly(raw, parsed):
    assert app_config.parse_version(raw) == parsed


def _config(rows):
    db = MagicMock()
    db.table.return_value.select.return_value.execute.return_value = MagicMock(data=rows)
    return db


MIN = [{"key": "min_app_version", "value": {"patient": "1.10.0", "doctor": "1.0.0"}},
       {"key": "store_urls", "value": {"patient": {"android": "https://play/p", "ios": None}}}]


@pytest.mark.parametrize("version,required", [("1.9.9", True), ("1.10.0", False), ("1.10.1", False)])
def test_update_is_required_only_below_the_minimum(version, required):
    app_config.clear_cache()
    with patch("app.services.app_config.supabase", _config(MIN)):
        res = TestClient(app).get(f"/config/app?app=patient&platform=android&version={version}")
    assert res.json() == {"update_required": required, "min_version": "1.10.0",
                          "store_url": "https://play/p"}


def test_a_broken_minimum_never_locks_anyone_out():
    app_config.clear_cache()
    rows = [{"key": "min_app_version", "value": {"patient": "not-a-version"}}]
    with patch("app.services.app_config.supabase", _config(rows)):
        res = TestClient(app).get("/config/app?app=patient&version=0.0.1")
    assert res.json()["update_required"] is False


@pytest.mark.parametrize("query", [
    "app=nurse&version=1.0.0", "app=patient&version=latest", "app=patient&version=1.0.0&platform=web",
])
def test_config_rejects_bad_input(query):
    assert TestClient(app).get(f"/config/app?{query}").status_code == 400


def test_config_is_cached_between_launches():
    app_config.clear_cache()
    db = _config(MIN)
    with patch("app.services.app_config.supabase", db):
        for _ in range(5):
            app_config.get("min_app_version")
    assert db.table.call_count == 1


# ── webhook inbox ────────────────────────────────────────────────────────────

def _webhook(event_id="evt_1"):
    with patch("app.routers.payments._WEBHOOK_SECRET", ""), \
         patch("app.routers.payments.ALLOW_INSECURE_PAYMENTS", True):
        return TestClient(app, raise_server_exceptions=False).post(
            "/payments/webhook", json={"event": "order.paid", "payload": {}},
            headers={"x-razorpay-event-id": event_id})


def test_a_processed_delivery_is_acknowledged_without_running_again():
    with patch("app.routers.payments.webhook_inbox.claim", return_value=False), \
         patch("app.routers.payments._handle_event") as handle:
        assert _webhook().json() == {"ok": True, "duplicate": True}
    handle.assert_not_called()


def test_a_delivery_that_fails_is_recorded_and_left_for_the_retry():
    with patch("app.routers.payments.webhook_inbox") as inbox, \
         patch("app.routers.payments._handle_event", side_effect=RuntimeError("db down")):
        inbox.claim.return_value = True
        res = _webhook()
    assert res.status_code == 500                      # Razorpay will redeliver
    inbox.record_failure.assert_called_once()
    inbox.mark_processed.assert_not_called()


def test_a_successful_delivery_is_marked_processed():
    with patch("app.routers.payments.webhook_inbox") as inbox:
        inbox.claim.return_value = True
        assert _webhook("evt_9").json() == {"ok": True}
    inbox.mark_processed.assert_called_once_with("razorpay", "evt_9")


# ── state machine error mapping ──────────────────────────────────────────────

@pytest.mark.parametrize("outcome,status,code,text", [
    ("not_found", None, 404, "Booking not found"),
    ("forbidden", "requested", 403, "Forbidden"),
    ("conflict", "paid", 409, "just updated"),
    ("invalid", "completed", 400, "Cannot mark as no-show a booking with status 'completed'"),
    ("key_reused", None, 422, "different action"),
])
def test_refusals_read_as_the_apps_expect(transitions, outcome, status, code, text):
    transitions.refuse = (outcome, status)
    with pytest.raises(booking_state.TransitionRefused) as exc:
        booking_state.transition("bk-1", "no_show", actor_role="doctor", actor_id="d")
    assert exc.value.status_code == code
    assert text in exc.value.message
    assert exc.value.current_status == status


# ── tick ─────────────────────────────────────────────────────────────────────

def test_tick_drains_the_outbox_and_runs_jobs():
    with patch("app.routers.maintenance.CRON_SECRET", "s"), \
         patch("app.routers.maintenance.notifications.sweep_outbox",
               return_value={"considered": 2, "sent": 2}) as sweep, \
         patch("app.routers.maintenance.jobs.run_due",
               return_value={"done": 1, "retrying": 0, "dead": 0}) as run:
        res = TestClient(app).post("/maintenance/tick", headers={"X-Cron-Secret": "s"})
    assert res.json() == {"notifications": {"considered": 2, "sent": 2},
                          "jobs": {"done": 1, "retrying": 0, "dead": 0}}
    sweep.assert_called_once()
    run.assert_called_once()


def test_tick_requires_the_cron_secret():
    with patch("app.routers.maintenance.CRON_SECRET", "s"):
        assert TestClient(app).post("/maintenance/tick").status_code == 401
