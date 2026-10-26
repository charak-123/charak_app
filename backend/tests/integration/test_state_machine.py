"""
Migration 0023 against real Postgres: the booking state machine, its event log,
the expiry timers, the job queue, HTTP idempotency, the webhook inbox, the
notification outbox and push tokens.

The unit suite stands a recorder in for transition_booking(). Only a real
database can show that the rules hold: ownership, compare-and-set, allowed
roles, append-only history, row locks under concurrency, SKIP LOCKED claims.
"""
import itertools
import os
import threading
import time
import uuid
from datetime import datetime, timedelta, timezone

import httpx
import jwt
import pytest

from .conftest import AUTH

STACK_JWT_SECRET = "charak-test-jwt-secret-at-least-32-chars-long"   # stack.sh
_slot = itertools.count()


def _id() -> str:
    return str(uuid.uuid4())


def _booking(db, s, status="requested", *, hours_ahead=None, **extra):
    hours = next(_slot) if hours_ahead is None else hours_ahead
    start = (datetime.now(timezone.utc) + timedelta(days=3, hours=hours)).replace(
        minute=0, second=0, microsecond=0)
    if hours_ahead is not None:
        start = datetime.now(timezone.utc) + timedelta(hours=hours_ahead)
    return db.table("bookings").insert({
        "id": _id(), "patient_id": s["patient"]["id"], "doctor_id": s["doctor"]["id"],
        "channel": "online_consult", "scheduled_start": start.isoformat(),
        "status": status, "price_confirmed": 500, **extra,
    }).execute().data[0]


def _transition(db, booking_id, event, role, actor, **kw):
    params = {"p_booking_id": booking_id, "p_event": event, "p_actor_role": role,
              "p_actor_id": actor, **{f"p_{k}": v for k, v in kw.items()}}
    return db.rpc("transition_booking", params).execute().data


def _events(db, booking_id):
    return db.table("booking_events").select("*").eq("booking_id", booking_id) \
        .order("id").execute().data


# ── transitions ──────────────────────────────────────────────────────────────

def test_a_doctor_accepts_through_the_state_machine_and_it_is_recorded(seed, client_for, db):
    s = seed()
    b = _booking(db, s)
    res = client_for(s["doctor"]["id"], "doctor").patch(f"/bookings/{b['id']}/accept", headers=AUTH)
    assert res.status_code == 200, res.text
    assert res.json()["status"] == "accepted"
    assert res.json()["hold_expires_at"]

    events = _events(db, b["id"])
    assert [e["event"] for e in events] == ["created", "accept"]
    accept = events[1]
    assert (accept["from_status"], accept["to_status"]) == ("requested", "accepted")
    assert (accept["actor_role"], accept["actor_id"]) == ("doctor", s["doctor"]["id"])
    assert db.table("bookings").select("decision_at").eq("id", b["id"]) \
        .execute().data[0]["decision_at"]


@pytest.mark.parametrize("role,actor_key,outcome", [
    ("patient", "patient", "forbidden"),          # a patient may not accept
    ("doctor", "other", "forbidden"),             # a doctor may not act on another's booking
])
def test_the_wrong_actor_is_refused(seed, db, role, actor_key, outcome):
    s = seed()
    b = _booking(db, s)
    actor = s["patient"]["id"] if actor_key == "patient" else _id()
    out = _transition(db, b["id"], "accept", role, actor)
    assert out["outcome"] == outcome
    assert db.table("bookings").select("status").eq("id", b["id"]).execute().data[0]["status"] \
        == "requested"


def test_a_move_the_table_does_not_allow_is_invalid(seed, db):
    s = seed()
    b = _booking(db, s, status="completed")
    out = _transition(db, b["id"], "accept", "doctor", s["doctor"]["id"])
    assert out == {"outcome": "invalid", "status": "completed"}


def test_a_stale_read_loses_with_a_conflict(seed, db):
    s = seed()
    b = _booking(db, s)
    out = _transition(db, b["id"], "decline", "doctor", s["doctor"]["id"], expected_status="accepted")
    assert out == {"outcome": "conflict", "status": "requested"}


def test_an_idempotency_key_replays_instead_of_moving_twice(seed, db):
    s = seed()
    b = _booking(db, s)
    key = f"test:{_id()}"
    first = _transition(db, b["id"], "accept", "doctor", s["doctor"]["id"], idempotency_key=key)
    again = _transition(db, b["id"], "accept", "doctor", s["doctor"]["id"], idempotency_key=key)
    assert first["outcome"] == "ok"
    assert again["outcome"] == "replayed"
    assert again["event"]["id"] == first["event"]["id"]
    other = _transition(db, b["id"], "decline", "doctor", s["doctor"]["id"], idempotency_key=key)
    assert other["outcome"] == "key_reused"


def test_only_known_columns_can_be_patched(seed, db):
    s = seed()
    b = _booking(db, s)
    with pytest.raises(Exception) as exc:
        _transition(db, b["id"], "accept", "doctor", s["doctor"]["id"],
                    patch={"price_confirmed": 1})
    assert "not patchable" in str(exc.value)


def test_racing_accept_and_cancel_produce_one_outcome(seed, client_for, db):
    s = seed()
    b = _booking(db, s)
    doctor = client_for(s["doctor"]["id"], "doctor")
    patient = client_for(s["patient"]["id"])
    barrier = threading.Barrier(2)
    codes = {}

    def accept():
        barrier.wait()
        codes["accept"] = doctor.patch(f"/bookings/{b['id']}/accept", headers=AUTH).status_code

    def cancel():
        barrier.wait()
        codes["cancel"] = patient.patch(f"/bookings/{b['id']}/cancel", headers=AUTH).status_code

    threads = [threading.Thread(target=accept), threading.Thread(target=cancel)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()

    final = db.table("bookings").select("status").eq("id", b["id"]).execute().data[0]["status"]
    moves = [e["event"] for e in _events(db, b["id"]) if e["event"] != "created"]
    # Both may legitimately succeed in sequence (accept, then cancel), but the
    # history must match the final state and contain no impossible move.
    assert final in ("accepted", "cancelled")
    assert moves in (["accept"], ["cancel"], ["accept", "cancel"])
    assert (final == "cancelled") == (moves[-1] == "cancel")
    assert all(code in (200, 400, 409) for code in codes.values()), codes


# ── history ──────────────────────────────────────────────────────────────────

def test_events_cannot_be_edited_or_deleted(seed, db):
    s = seed()
    b = _booking(db, s)
    [created] = _events(db, b["id"])
    with pytest.raises(Exception):
        db.table("booking_events").update({"event": "forged"}).eq("id", created["id"]).execute()
    with pytest.raises(Exception):
        db.table("booking_events").delete().eq("id", created["id"]).execute()
    assert _events(db, b["id"])[0]["event"] == "created"


def test_a_status_change_outside_the_state_machine_is_still_recorded(seed, db):
    """Old code mid-deploy, or a hand edit in the SQL Editor: no gaps in the timeline."""
    s = seed()
    b = _booking(db, s)
    db.table("bookings").update({"status": "declined"}).eq("id", b["id"]).execute()
    last = _events(db, b["id"])[-1]
    assert last["event"] == "status_changed_outside_state_machine"
    assert (last["from_status"], last["to_status"]) == ("requested", "declined")


def test_the_timeline_endpoint_shows_participants_their_history_only(seed, client_for, db):
    s = seed()
    b = _booking(db, s)
    client_for(s["doctor"]["id"], "doctor").patch(f"/bookings/{b['id']}/accept", headers=AUTH)

    res = client_for(s["patient"]["id"]).get(f"/bookings/{b['id']}/timeline", headers=AUTH)
    assert res.status_code == 200, res.text
    assert [e["event"] for e in res.json()] == ["created", "accept"]
    assert "actor_id" not in res.json()[0]

    outsider = client_for(s["other_patient"]["id"]).get(f"/bookings/{b['id']}/timeline",
                                                        headers=AUTH)
    assert outsider.status_code == 403


# ── timers ───────────────────────────────────────────────────────────────────

def test_expired_payment_holds_are_released_with_their_attempts(seed, db):
    s = seed()
    past = (datetime.now(timezone.utc) - timedelta(minutes=1)).isoformat()
    future = (datetime.now(timezone.utc) + timedelta(minutes=9)).isoformat()
    expired = _booking(db, s, status="accepted", hold_expires_at=past)
    live = _booking(db, s, status="accepted", hold_expires_at=future)
    attempt = db.table("payments").insert({
        "booking_id": expired["id"], "amount": 500, "status": "initiated",
        "type": "consult_fee", "razorpay_order_id": f"order_{_id()[:10]}",
    }).execute().data[0]

    released = db.rpc("expire_payment_holds", {}).execute().data
    assert released == [expired["id"]]
    rows = {r["id"]: r for r in db.table("bookings").select("id, status, cancelled_by")
            .in_("id", [expired["id"], live["id"]]).execute().data}
    assert rows[expired["id"]]["status"] == "cancelled"
    assert rows[expired["id"]]["cancelled_by"] == "system"
    assert rows[live["id"]]["status"] == "accepted"
    assert db.table("payments").select("status").eq("id", attempt["id"]) \
        .execute().data[0]["status"] == "failed"
    assert _events(db, expired["id"])[-1]["event"] == "hold_expire"


def test_a_request_whose_slot_has_started_expires(seed, db):
    s = seed()
    started = _booking(db, s, hours_ahead=-1)
    upcoming = _booking(db, s)
    expired = db.rpc("expire_stale_requests", {}).execute().data
    assert expired == [started["id"]]
    assert db.table("bookings").select("status").eq("id", upcoming["id"]) \
        .execute().data[0]["status"] == "requested"


def test_requests_expire_sooner_only_when_configured(seed, db):
    s = seed()
    b = _booking(db, s)
    assert db.rpc("expire_stale_requests", {}).execute().data == []
    out = db.rpc("expire_stale_requests", {"p_max_age": "0 minutes"}).execute().data
    assert out == [b["id"]]


# ── job queue ────────────────────────────────────────────────────────────────

def test_a_dedupe_key_queues_a_job_once(db):
    first = db.rpc("enqueue_job", {"p_kind": "test.job", "p_dedupe_key": f"k:{_id()}"}).execute().data
    key = db.table("jobs").select("dedupe_key").eq("id", first).execute().data[0]["dedupe_key"]
    again = db.rpc("enqueue_job", {"p_kind": "test.job", "p_dedupe_key": key}).execute().data
    assert first == again


def test_concurrent_claims_never_hand_out_the_same_job(db):
    ids = {db.rpc("enqueue_job", {"p_kind": "test.claim"}).execute().data for _ in range(12)}
    claimed: list[int] = []
    lock = threading.Lock()
    barrier = threading.Barrier(3)

    def worker():
        barrier.wait()
        got = db.rpc("claim_jobs", {"p_limit": 5, "p_lease_seconds": 60}).execute().data
        with lock:
            claimed.extend(j["id"] for j in got if j["kind"] == "test.claim")

    threads = [threading.Thread(target=worker) for _ in range(3)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    assert len(claimed) == len(set(claimed))           # no job twice
    assert set(claimed) <= ids


def test_a_failing_job_backs_off_then_dies(db):
    job = db.rpc("enqueue_job", {"p_kind": "test.fail", "p_max_attempts": 2}).execute().data
    db.table("jobs").update({"run_at": "2000-01-01T00:00:00+00:00"}).eq("id", job).execute()
    db.rpc("claim_jobs", {"p_limit": 50}).execute()
    assert db.rpc("fail_job", {"p_id": job, "p_error": "boom"}).execute().data == "queued"
    row = db.table("jobs").select("*").eq("id", job).execute().data[0]
    assert row["run_at"] > datetime.now(timezone.utc).isoformat()

    db.table("jobs").update({"run_at": "2000-01-01T00:00:00+00:00"}).eq("id", job).execute()
    db.rpc("claim_jobs", {"p_limit": 50}).execute()
    assert db.rpc("fail_job", {"p_id": job, "p_error": "boom"}).execute().data == "dead"


def test_the_job_runner_runs_registered_handlers(db):
    from app.services import jobs

    seen = []
    jobs.HANDLERS["test.runner"] = lambda payload: seen.append(payload["n"])
    try:
        jobs.enqueue("test.runner", {"n": 7})
        out = jobs.run_due(budget_seconds=5)
    finally:
        jobs.HANDLERS.pop("test.runner", None)
    assert 7 in seen
    assert out["done"] >= 1


# ── HTTP idempotency ─────────────────────────────────────────────────────────

def test_a_retried_request_with_the_same_key_runs_once(seed, db, monkeypatch):
    from fastapi.testclient import TestClient
    from unittest.mock import patch
    from app.main import app
    import app.services.idempotency as idem

    s = seed()
    secret = "idem-test-secret-0123456789abcdef"
    monkeypatch.setattr(idem, "JWT_SECRET", secret)
    token = jwt.encode({"sub": s["patient"]["id"], "role": "patient", "iat": int(time.time())},
                       secret, algorithm="HS256")
    body = {"label": "Home", "line1": "Flat 4B", "city": "Pune", "pincode": "411038",
            "lat": 18.5, "lng": 73.8}
    headers = {"Authorization": f"Bearer {token}", "Idempotency-Key": f"key-{_id()}"}
    with patch("app.deps.jwt") as jw:
        jw.decode.return_value = {"sub": s["patient"]["id"], "role": "patient"}
        client = TestClient(app)
        first = client.post("/addresses", json=body, headers=headers)
        second = client.post("/addresses", json=body, headers=headers)
        different = client.post("/addresses", json={**body, "line1": "Other"}, headers=headers)

    assert first.status_code in (200, 201), first.text
    assert second.status_code == first.status_code
    assert second.json() == first.json()
    assert second.headers.get("idempotent-replayed") == "true"
    assert different.status_code == 422
    rows = db.table("patient_addresses").select("id").eq("patient_id", s["patient"]["id"]) \
        .execute().data
    assert len(rows) == 1


# ── webhook inbox ────────────────────────────────────────────────────────────

def test_a_redelivered_webhook_is_acknowledged_without_running_again(seed, db, monkeypatch):
    from fastapi.testclient import TestClient
    from app.main import app
    import app.routers.payments as payments

    monkeypatch.setattr(payments, "_WEBHOOK_SECRET", "")
    monkeypatch.setattr(payments, "ALLOW_INSECURE_PAYMENTS", True)
    event = {"event": "order.paid", "payload": {"payment": {"entity": {"order_id": "o"}}}}
    headers = {"x-razorpay-event-id": f"evt_{_id()}"}
    client = TestClient(app)
    first = client.post("/payments/webhook", json=event, headers=headers)
    second = client.post("/payments/webhook", json=event, headers=headers)
    assert first.json() == {"ok": True}
    assert second.json() == {"ok": True, "duplicate": True}
    row = db.table("webhook_events").select("*").eq("event_id", headers["x-razorpay-event-id"]) \
        .execute().data[0]
    assert row["processed_at"] and row["attempts"] == 1


# ── notifications and devices ────────────────────────────────────────────────

def test_a_one_shot_notification_is_recorded_once(seed, db):
    from app.services import notifications

    s = seed()
    b = _booking(db, s, status="accepted")
    notifications.booking_accepted(b, "Dr Test")
    notifications.booking_accepted(b, "Dr Test")
    rows = db.table("notifications").select("id").eq("booking_id", b["id"]) \
        .eq("event", "booking.accepted").execute().data
    assert len(rows) == 1


def test_push_tokens_are_kept_per_device_and_move_with_the_sign_in(seed, client_for, db):
    s = seed()
    patient = client_for(s["patient"]["id"])
    other = client_for(s["other_patient"]["id"])
    for token in ("phone-1", "tablet-1"):
        assert patient.post("/push/register", json={"fcm_token": token, "platform": "android"},
                            headers=AUTH).status_code == 200
    assert {r["token"] for r in db.table("device_tokens").select("token")
            .eq("owner_id", s["patient"]["id"]).execute().data} == {"phone-1", "tablet-1"}

    # The tablet changes hands.
    other.post("/push/register", json={"fcm_token": "tablet-1", "platform": "android"}, headers=AUTH)
    assert db.table("device_tokens").select("owner_id").eq("token", "tablet-1") \
        .execute().data[0]["owner_id"] == s["other_patient"]["id"]

    patient.request("DELETE", "/push/register?token=phone-1", headers=AUTH)
    assert db.table("device_tokens").select("id").eq("owner_id", s["patient"]["id"]) \
        .execute().data == []


# ── app config ───────────────────────────────────────────────────────────────

def test_an_old_build_is_told_to_update(client_for, db):
    from app.services import app_config

    db.table("app_config").update({"value": {"patient": "1.2.0", "doctor": "1.0.0"}}) \
        .eq("key", "min_app_version").execute()
    app_config.clear_cache()
    try:
        client = client_for(_id())
        # %2B: a literal '+' in a query string decodes as a space.
        old = client.get("/config/app?app=patient&platform=android&version=1.1.9%2B20").json()
        new = client.get("/config/app?app=patient&platform=android&version=1.2.0").json()
    finally:
        db.table("app_config").update({"value": {"patient": "1.0.0", "doctor": "1.0.0"}}) \
            .eq("key", "min_app_version").execute()
        app_config.clear_cache()
    assert old["update_required"] is True
    assert old["store_url"].endswith("com.charak.patient_app")
    assert new["update_required"] is False


# ── privileges ───────────────────────────────────────────────────────────────

@pytest.mark.parametrize("fn,args", [
    ("transition_booking", {"p_booking_id": "00000000-0000-0000-0000-000000000000",
                            "p_event": "accept", "p_actor_role": "system"}),
    ("expire_payment_holds", {}),
    ("claim_jobs", {}),
])
def test_the_client_roles_cannot_call_the_new_functions(fn, args):
    for role in ("anon", "authenticated"):
        token = jwt.encode({"role": role}, STACK_JWT_SECRET, algorithm="HS256")
        res = httpx.post(f"{os.environ['SUPABASE_URL']}/rest/v1/rpc/{fn}",
                         headers={"Authorization": f"Bearer {token}", "apikey": token}, json=args)
        assert res.status_code in (401, 403, 404), (fn, role, res.status_code, res.text)
