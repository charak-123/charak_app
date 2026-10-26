"""
services/refunds.py: the lifecycle of a refund, from queued to confirmed.

What these tests protect:
* a refund is never reported done before Razorpay confirms it;
* retries never send a second refund (claim, adopt by notes, stale reclaim);
* a refusal from Razorpay lands in the ops queue instead of vanishing;
* webhooks only move a refund forward, and stale ones are ignored.

Uses tests/fakedb.py, so assertions are about resulting rows, not calls. The
database-side guards (over-refund trigger, cancel transaction) are covered
against real Postgres in tests/integration/test_refunds.py.
"""
from datetime import datetime, timedelta, timezone
from unittest.mock import MagicMock, patch

import pytest

from app.errors import AppError
from app.services import refunds
from tests.fakedb import FakeSupabase

NOW = datetime(2026, 11, 1, 10, 0, tzinfo=timezone.utc)
RF = "11111111-1111-4111-8111-111111111111"
REFUND_DEFAULTS = {"status": "pending", "attempts": 0, "razorpay_refund_id": None,
                   "superseded_razorpay_refund_ids": [],
                   "last_attempt_at": None, "failure_reason": None, "processed_at": None,
                   "currency": "INR"}


def _db(*, refund=None, payment_status="completed", amount=500.0, razorpay_payment_id="pay_rzp_1"):
    tables = {
        "payments": [{"id": "pay-1", "booking_id": "bk-1", "amount": amount, "type": "consult_fee",
                      "status": payment_status, "razorpay_payment_id": razorpay_payment_id}],
        "bookings": [{"id": "bk-1", "patient_id": "pat-1", "doctor_id": "doc-1"}],
        "refunds": [],
    }
    if refund is not None:
        tables["refunds"].append({**REFUND_DEFAULTS, "id": RF, "payment_id": "pay-1",
                                  "booking_id": "bk-1", "amount_paise": 50000,
                                  "reason": "booking_cancelled",
                                  "idempotency_key": "pay-1:booking_cancelled",
                                  "requested_by_role": "patient", **refund})
    return FakeSupabase(tables, defaults={"refunds": REFUND_DEFAULTS})


@pytest.fixture
def notify():
    with patch("app.services.refunds.notifications") as n:
        yield n


def _live(rzp_client):
    return [patch("app.services.refunds.live_mode", return_value=True),
            patch("app.services.refunds.razorpay_client", return_value=rzp_client)]


class _Live:
    """Context manager: live Razorpay mode with the given client mock."""
    def __init__(self, rzp):
        self.patches = _live(rzp)

    def __enter__(self):
        for p in self.patches:
            p.start()

    def __exit__(self, *a):
        for p in self.patches:
            p.stop()


class BadRequestError(Exception):
    """Same class name as razorpay.errors.BadRequestError: a permanent refusal."""


# ── to_paise ─────────────────────────────────────────────────────────────────

@pytest.mark.parametrize("rupees,paise", [(500, 50000), ("333.33", 33333), (0.1, 10), (None, 0)])
def test_to_paise_is_exact(rupees, paise):
    assert refunds.to_paise(rupees) == paise


# ── queue ────────────────────────────────────────────────────────────────────

def test_queue_records_the_unrefunded_remainder():
    db = _db()
    with patch("app.services.refunds.supabase", db):
        row = refunds.queue(db.one("payments", id="pay-1"), "late_capture", "system")
    assert row["amount_paise"] == 50000
    assert row["status"] == "pending"
    assert row["idempotency_key"] == "pay-1:late_capture"


def test_queue_twice_returns_the_same_refund():
    db = _db()
    with patch("app.services.refunds.supabase", db):
        payment = db.one("payments", id="pay-1")
        first = refunds.queue(payment, "late_capture", "system")
        second = refunds.queue(payment, "late_capture", "system")
    assert first["id"] == second["id"]
    assert len(db.rows("refunds")) == 1


def test_queue_returns_none_when_everything_is_already_refunded():
    db = _db(refund={"status": "processed"})
    with patch("app.services.refunds.supabase", db):
        assert refunds.queue(db.one("payments", id="pay-1"), "late_capture", "system") is None


def test_queue_treats_a_guard_rejection_as_nothing_left():
    """refunds_guard (23514): a racing path queued the rest a moment earlier."""
    from postgrest.exceptions import APIError

    db = MagicMock()
    db.table.return_value.select.return_value.eq.return_value.maybe_single.return_value \
        .execute.return_value = None
    db.table.return_value.select.return_value.eq.return_value.execute.return_value = \
        MagicMock(data=[])
    db.table.return_value.insert.return_value.execute.side_effect = APIError(
        {"code": "23514", "message": "would exceed"})
    with patch("app.services.refunds.supabase", db):
        assert refunds.queue({"id": "pay-1", "booking_id": "bk-1", "amount": 500},
                             "late_capture", "system") is None


# ── execute ──────────────────────────────────────────────────────────────────

def test_execute_without_live_keys_settles_at_once(notify):
    """Local development: there is no Razorpay to ask."""
    db = _db(refund={})
    with patch("app.services.refunds.supabase", db), \
         patch("app.services.refunds.live_mode", return_value=False):
        out = refunds.execute(db.one("refunds", id=RF))
    assert out["status"] == "processed"
    assert db.one("payments", id="pay-1")["status"] == "refunded"
    notify.refund_completed.assert_called_once()


def test_execute_sends_our_id_and_amount_and_waits_for_confirmation(notify):
    db = _db(refund={})
    rzp = MagicMock()
    rzp.payment.refund.return_value = {"id": "rfnd_1", "status": "pending"}
    with patch("app.services.refunds.supabase", db), _Live(rzp):
        out = refunds.execute(db.one("refunds", id=RF))

    payment_id, body = rzp.payment.refund.call_args.args
    assert payment_id == "pay_rzp_1"
    assert body["amount"] == 50000
    assert body["notes"]["charak_refund_id"] == RF
    assert rzp.payment.refund.call_args.kwargs["timeout"] > 0
    # Accepted, not done: the payment is untouched and nobody is told "refunded".
    assert out["status"] == "processing"
    assert out["razorpay_refund_id"] == "rfnd_1"
    assert db.one("payments", id="pay-1")["status"] == "completed"
    notify.refund_completed.assert_not_called()


def test_execute_marks_processed_when_razorpay_settles_instantly(notify):
    db = _db(refund={})
    rzp = MagicMock()
    rzp.payment.refund.return_value = {"id": "rfnd_1", "status": "processed"}
    with patch("app.services.refunds.supabase", db), _Live(rzp):
        out = refunds.execute(db.one("refunds", id=RF))
    assert out["status"] == "processed"
    assert db.one("payments", id="pay-1")["status"] == "refunded"
    notify.refund_completed.assert_called_once()


def test_a_partial_refund_marks_the_payment_partially_refunded(notify):
    db = _db(refund={"amount_paise": 25000})
    rzp = MagicMock()
    rzp.payment.refund.return_value = {"id": "rfnd_1", "status": "processed"}
    with patch("app.services.refunds.supabase", db), _Live(rzp):
        refunds.execute(db.one("refunds", id=RF))
    assert db.one("payments", id="pay-1")["status"] == "partially_refunded"


def test_a_refusal_from_razorpay_goes_to_ops_and_tells_the_patient(notify):
    db = _db(refund={})
    rzp = MagicMock()
    rzp.payment.refund.side_effect = BadRequestError("The refund amount is greater than captured")
    with patch("app.services.refunds.supabase", db), _Live(rzp):
        out = refunds.execute(db.one("refunds", id=RF))
    assert out["status"] == "failed"
    assert "greater than captured" in out["failure_reason"]
    notify.refund_delayed.assert_called_once()
    notify.refund_needs_attention.assert_called_once()
    assert db.one("payments", id="pay-1")["status"] == "completed"


def test_a_network_error_is_left_for_the_sweep_to_retry(notify):
    db = _db(refund={})
    rzp = MagicMock()
    rzp.payment.refund.side_effect = TimeoutError("read timed out")
    with patch("app.services.refunds.supabase", db), _Live(rzp):
        out = refunds.execute(db.one("refunds", id=RF))
    assert out["status"] == "pending"
    assert out["attempts"] == 1
    notify.refund_needs_attention.assert_not_called()


def test_retries_give_up_after_the_limit(notify):
    db = _db(refund={"attempts": refunds.MAX_AUTO_ATTEMPTS - 1})
    rzp = MagicMock()
    rzp.payment.refund.side_effect = TimeoutError("still down")
    rzp.payment.fetch_multiple_refund.return_value = {"items": []}
    with patch("app.services.refunds.supabase", db), _Live(rzp):
        out = refunds.execute(db.one("refunds", id=RF))
    assert out["status"] == "failed"
    notify.refund_needs_attention.assert_called_once()


def test_a_retry_adopts_a_refund_razorpay_already_made(notify):
    """The earlier attempt timed out on our side after Razorpay acted."""
    db = _db(refund={"attempts": 1})
    rzp = MagicMock()
    rzp.payment.fetch_multiple_refund.return_value = {"items": [
        {"id": "rfnd_other", "status": "processed", "notes": {"charak_refund_id": "someone-else"}},
        {"id": "rfnd_old", "status": "failed", "notes": {"charak_refund_id": RF}},
        {"id": "rfnd_ours", "status": "pending", "notes": {"charak_refund_id": RF}},
    ]}
    with patch("app.services.refunds.supabase", db), _Live(rzp):
        out = refunds.execute(db.one("refunds", id=RF))
    rzp.payment.refund.assert_not_called()
    assert out["razorpay_refund_id"] == "rfnd_ours"
    assert out["status"] == "processing"


def test_execute_without_a_razorpay_payment_id_fails_to_ops(notify):
    db = _db(refund={}, razorpay_payment_id=None)
    with patch("app.services.refunds.supabase", db), _Live(MagicMock()):
        out = refunds.execute(db.one("refunds", id=RF))
    assert out["status"] == "failed"
    notify.refund_needs_attention.assert_called_once()


@pytest.mark.parametrize("status", ["processing", "processed"])
def test_execute_leaves_a_refund_that_is_not_waiting_to_be_sent(status, notify):
    db = _db(refund={"status": status})
    rzp = MagicMock()
    with patch("app.services.refunds.supabase", db), _Live(rzp):
        refunds.execute(db.one("refunds", id=RF))
    rzp.payment.refund.assert_not_called()


def test_two_callers_with_the_same_snapshot_send_once(notify):
    """A request and the sweep both holding the 'pending' row: one claims it."""
    db = _db(refund={})
    snapshot = db.one("refunds", id=RF).copy()
    rzp = MagicMock()
    rzp.payment.refund.return_value = {"id": "rfnd_1", "status": "pending"}
    with patch("app.services.refunds.supabase", db), _Live(rzp):
        refunds.execute(dict(snapshot))
        refunds.execute(dict(snapshot))
    assert rzp.payment.refund.call_count == 1


# ── webhooks ─────────────────────────────────────────────────────────────────

def test_refund_processed_webhook_completes_it(notify):
    db = _db(refund={"status": "processing", "razorpay_refund_id": "rfnd_1"})
    with patch("app.services.refunds.supabase", db):
        out = refunds.apply_webhook("refund.processed", {"id": "rfnd_1", "status": "processed"})
    assert out["refund_status"] == "processed"
    assert db.one("payments", id="pay-1")["status"] == "refunded"
    notify.refund_completed.assert_called_once()


def test_a_replayed_processed_webhook_changes_nothing(notify):
    db = _db(refund={"status": "processed", "razorpay_refund_id": "rfnd_1"})
    with patch("app.services.refunds.supabase", db):
        out = refunds.apply_webhook("refund.processed", {"id": "rfnd_1"})
    assert out == {"ok": True, "idempotent": True}
    notify.refund_completed.assert_not_called()


def test_the_webhook_can_arrive_before_our_api_response_was_stored(notify):
    """Matched by the refund id we put in notes."""
    db = _db(refund={"status": "processing"})
    with patch("app.services.refunds.supabase", db):
        refunds.apply_webhook("refund.processed",
                              {"id": "rfnd_1", "notes": {"charak_refund_id": RF}})
    row = db.one("refunds", id=RF)
    assert row["status"] == "processed"
    assert row["razorpay_refund_id"] == "rfnd_1"


def test_a_failed_webhook_moves_it_to_the_ops_queue(notify):
    db = _db(refund={"status": "processing", "razorpay_refund_id": "rfnd_1"})
    with patch("app.services.refunds.supabase", db):
        refunds.apply_webhook("refund.failed", {"id": "rfnd_1", "status": "failed"})
    assert db.one("refunds", id=RF)["status"] == "failed"
    notify.refund_needs_attention.assert_called_once()


def test_a_webhook_about_a_superseded_attempt_is_ignored(notify):
    """Ops retried; the old attempt's late 'failed' must not fail the new one."""
    db = _db(refund={"status": "processing", "razorpay_refund_id": "rfnd_new"})
    with patch("app.services.refunds.supabase", db):
        out = refunds.apply_webhook("refund.failed",
                                    {"id": "rfnd_old", "notes": {"charak_refund_id": RF}})
    assert out["ignored"] == "superseded attempt"
    assert db.one("refunds", id=RF)["status"] == "processing"


def test_a_refund_made_in_the_razorpay_dashboard_is_recorded(notify):
    db = _db()
    with patch("app.services.refunds.supabase", db):
        refunds.apply_webhook("refund.processed", {
            "id": "rfnd_dash", "payment_id": "pay_rzp_1", "amount": 50000, "status": "processed",
        })
    row = db.one("refunds", razorpay_refund_id="rfnd_dash")
    assert row["reason"] == "ops"
    assert row["status"] == "processed"
    assert db.one("payments", id="pay-1")["status"] == "refunded"


def test_a_webhook_for_an_unknown_payment_is_ignored(notify):
    db = _db()
    with patch("app.services.refunds.supabase", db):
        out = refunds.apply_webhook("refund.processed", {"id": "rfnd_x", "payment_id": "pay_unknown"})
    assert out["ignored"] == "unknown refund"
    assert db.rows("refunds") == []


def test_a_malformed_note_id_does_not_reach_the_database(notify):
    db = _db()
    with patch("app.services.refunds.supabase", db):
        out = refunds.apply_webhook("refund.processed",
                                    {"id": "rfnd_x", "notes": {"charak_refund_id": "'; drop"}})
    assert out["ignored"] == "unknown refund"


# ── sweep ────────────────────────────────────────────────────────────────────

def _iso(dt):
    return dt.isoformat()


def test_sweep_reclaims_a_claim_whose_worker_died(notify):
    db = _db(refund={"status": "processing", "attempts": 1,
                     "last_attempt_at": _iso(NOW - timedelta(minutes=20))})
    with patch("app.services.refunds.supabase", db), \
         patch("app.services.refunds.live_mode", return_value=False):
        out = refunds.sweep(now=NOW)
    assert out["reclaimed"] == 1
    # Reclaimed rows wait their backoff (2^1 minutes has passed: sent).
    assert db.one("refunds", id=RF)["status"] == "processed"


def test_sweep_respects_backoff(notify):
    db = _db(refund={"status": "pending", "attempts": 3,
                     "last_attempt_at": _iso(NOW - timedelta(minutes=5))})   # needs 8
    with patch("app.services.refunds.supabase", db), \
         patch("app.services.refunds.live_mode", return_value=False):
        out = refunds.sweep(now=NOW)
    assert out["sent"] == 0
    assert db.one("refunds", id=RF)["status"] == "pending"


def test_sweep_polls_a_refund_razorpay_never_confirmed(notify):
    db = _db(refund={"status": "processing", "attempts": 1, "razorpay_refund_id": "rfnd_1",
                     "last_attempt_at": _iso(NOW - timedelta(hours=2))})
    rzp = MagicMock()
    rzp.refund.fetch.return_value = {"id": "rfnd_1", "status": "processed"}
    with patch("app.services.refunds.supabase", db), _Live(rzp):
        out = refunds.sweep(now=NOW)
    assert out["polled"] == 1
    assert db.one("refunds", id=RF)["status"] == "processed"


def test_sweep_does_not_poll_a_recent_refund(notify):
    db = _db(refund={"status": "processing", "attempts": 1, "razorpay_refund_id": "rfnd_1",
                     "last_attempt_at": _iso(NOW - timedelta(minutes=15))})
    rzp = MagicMock()
    with patch("app.services.refunds.supabase", db), _Live(rzp):
        out = refunds.sweep(now=NOW)
    assert out == {"reclaimed": 0, "sent": 0, "polled": 0}
    rzp.refund.fetch.assert_not_called()


# ── ops retry ────────────────────────────────────────────────────────────────

def test_ops_can_retry_only_a_failed_refund(notify):
    db = _db(refund={"status": "processing"})
    with patch("app.services.refunds.supabase", db):
        with pytest.raises(AppError) as exc:
            refunds.retry(RF)
    assert exc.value.status_code == 409


def test_ops_retry_sends_a_new_refund_and_keeps_the_old_id_on_record(notify):
    db = _db(refund={"status": "failed", "attempts": 2, "razorpay_refund_id": "rfnd_old",
                     "failure_reason": "bank rejected"})
    rzp = MagicMock()
    rzp.payment.fetch_multiple_refund.return_value = {"items": [
        {"id": "rfnd_old", "status": "failed", "notes": {"charak_refund_id": RF}},
    ]}
    rzp.payment.refund.return_value = {"id": "rfnd_new", "status": "pending"}
    with patch("app.services.refunds.supabase", db), _Live(rzp):
        out = refunds.retry(RF)
    assert out["razorpay_refund_id"] == "rfnd_new"
    assert out["status"] == "processing"
    assert db.one("refunds", id=RF)["superseded_razorpay_refund_ids"] == ["rfnd_old"]


def test_a_late_webhook_about_a_retried_attempt_cannot_fail_the_new_one(notify):
    """Between the ops reset and the new attempt being stored, the row has no id."""
    db = _db(refund={"status": "processing", "razorpay_refund_id": None,
                     "superseded_razorpay_refund_ids": ["rfnd_old"]})
    with patch("app.services.refunds.supabase", db):
        out = refunds.apply_webhook("refund.failed",
                                    {"id": "rfnd_old", "notes": {"charak_refund_id": RF}})
    assert out["ignored"] == "superseded attempt"
    assert db.one("refunds", id=RF)["status"] == "processing"


def test_ops_retry_of_an_unknown_refund_is_404(notify):
    with patch("app.services.refunds.supabase", _db()):
        with pytest.raises(AppError) as exc:
            refunds.retry("00000000-0000-0000-0000-000000000000")
    assert exc.value.status_code == 404
