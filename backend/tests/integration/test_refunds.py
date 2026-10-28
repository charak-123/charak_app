"""
Refunds, cancellation and ledger recovery against real SQL (migration 0022).

The unit suite can check that the router calls cancel_booking(). Only a real
database can check what the function does: that the cancel, the refund and the
ledger reversal commit together, that the over-refund guard fires, that a
paid-out credit is recovered rather than edited, that two racing cancels
produce one refund, and that the client roles cannot call any of it.

Razorpay is never reached here. tests/conftest.py blanks the keys, so a refund
settles through the local-development path the moment it is sent.
"""
import itertools
import os
import threading
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


def _paid_booking(db, s, *, amount=500.00, ledger_status="payable", channel="online_consult"):
    """A booking the patient has paid for, credited to the doctor's ledger."""
    # A fresh hour per booking: the doctor can hold only one live booking a slot.
    start = (datetime.now(timezone.utc) + timedelta(days=2, hours=next(_slot))).replace(
        minute=0, second=0, microsecond=0)
    booking = db.table("bookings").insert({
        "id": _id(), "patient_id": s["patient"]["id"], "doctor_id": s["doctor"]["id"],
        "channel": channel, "scheduled_start": start.isoformat(),
        "status": "paid", "price_confirmed": amount,
    }).execute().data[0]
    payment = db.table("payments").insert({
        "id": _id(), "booking_id": booking["id"], "amount": amount, "status": "completed",
        "type": "consult_fee", "razorpay_order_id": f"order_{_id()[:12]}",
        "razorpay_payment_id": f"pay_{_id()[:12]}",
    }).execute().data[0]
    entry = db.table("doctor_ledger_entries").insert({
        "id": _id(), "doctor_id": s["doctor"]["id"], "booking_id": booking["id"],
        "source": "consult_fee", "gross_amount": amount, "commission_pct": 0,
        "commission_amount": 0, "net_amount": amount, "status": ledger_status,
    }).execute().data[0]
    return booking, payment, entry


def _cancel(client, booking_id):
    return client.patch(f"/bookings/{booking_id}/cancel", headers=AUTH)


# ── the cancel transaction ───────────────────────────────────────────────────

def test_cancelling_a_paid_booking_refunds_and_reverses_together(seed, client_for, db):
    s = seed()
    booking, payment, entry = _paid_booking(db, s)

    res = _cancel(client_for(s["patient"]["id"]), booking["id"])
    assert res.status_code == 200, res.text
    assert res.json()["refunded_payments"] == 1

    assert db.table("bookings").select("status, cancelled_by").eq("id", booking["id"]) \
        .execute().data[0] == {"status": "cancelled", "cancelled_by": "patient"}

    refunds = db.table("refunds").select("*").eq("payment_id", payment["id"]).execute().data
    assert len(refunds) == 1
    assert refunds[0]["amount_paise"] == 50000
    assert refunds[0]["reason"] == "booking_cancelled"
    assert refunds[0]["requested_by_role"] == "patient"
    # Stub mode settles at once; with live keys this stays 'processing' until
    # Razorpay's webhook. Either way 'refunded' follows a processed refund.
    assert refunds[0]["status"] == "processed"
    assert db.table("payments").select("status").eq("id", payment["id"]) \
        .execute().data[0]["status"] == "refunded"

    assert db.table("doctor_ledger_entries").select("status").eq("id", entry["id"]) \
        .execute().data[0]["status"] == "reversed"


def test_cancelling_after_a_payout_recovers_instead_of_failing(seed, client_for, db):
    """
    Regression: a paid-out credit made payouts.reverse() raise a 409 after the
    booking was already cancelled and the refund sent. The doctor kept the
    payout and CHARAK paid twice. Now a negative entry recovers it.
    """
    s = seed()
    booking, _, entry = _paid_booking(db, s, ledger_status="paid")

    res = _cancel(client_for(s["patient"]["id"]), booking["id"])
    assert res.status_code == 200, res.text

    rows = db.table("doctor_ledger_entries").select("*").eq("booking_id", booking["id"]) \
        .execute().data
    original = next(r for r in rows if r["id"] == entry["id"])
    recovery = next(r for r in rows if r["source"] == "reversal")
    assert original["status"] == "paid"                 # history untouched
    assert float(recovery["net_amount"]) == -500.0
    assert recovery["status"] == "payable"              # nets off the next payout
    assert recovery["reverses_entry_id"] == entry["id"]


def test_a_second_cancel_is_refused_and_refunds_nothing_more(seed, client_for, db):
    s = seed()
    booking, payment, _ = _paid_booking(db, s)
    client = client_for(s["patient"]["id"])
    assert _cancel(client, booking["id"]).status_code == 200
    assert _cancel(client, booking["id"]).status_code == 400
    assert len(db.table("refunds").select("id").eq("payment_id", payment["id"]).execute().data) == 1


def test_racing_cancels_by_patient_and_doctor_produce_one_refund(seed, client_for, db):
    s = seed()
    booking, payment, _ = _paid_booking(db, s)
    patient, doctor = client_for(s["patient"]["id"]), client_for(s["doctor"]["id"], "doctor")

    results = []
    barrier = threading.Barrier(2)

    def go(client):
        barrier.wait()
        results.append(_cancel(client, booking["id"]).status_code)

    threads = [threading.Thread(target=go, args=(c,)) for c in (patient, doctor)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()

    assert sorted(results)[0] == 200
    assert results.count(200) == 1, results
    assert len(db.table("refunds").select("id").eq("payment_id", payment["id"]).execute().data) == 1


def test_cancel_fails_an_open_payment_attempt(seed, client_for, db):
    """A UPI attempt still in flight dies with the booking; a late capture is refunded."""
    s = seed()
    start = (datetime.now(timezone.utc) + timedelta(days=2)).isoformat()
    booking = db.table("bookings").insert({
        "id": _id(), "patient_id": s["patient"]["id"], "doctor_id": s["doctor"]["id"],
        "channel": "online_consult", "scheduled_start": start, "status": "accepted",
        "price_confirmed": 500,
    }).execute().data[0]
    attempt = db.table("payments").insert({
        "id": _id(), "booking_id": booking["id"], "amount": 500, "status": "initiated",
        "type": "consult_fee", "razorpay_order_id": f"order_{_id()[:12]}",
    }).execute().data[0]

    assert _cancel(client_for(s["patient"]["id"]), booking["id"]).status_code == 200
    assert db.table("payments").select("status").eq("id", attempt["id"]) \
        .execute().data[0]["status"] == "failed"
    assert db.table("refunds").select("id").eq("booking_id", booking["id"]).execute().data == []


# ── the database guards ──────────────────────────────────────────────────────

def _refund_row(payment, paise, key):
    return {"payment_id": payment["id"], "booking_id": payment["booking_id"],
            "amount_paise": paise, "reason": "ops", "idempotency_key": key,
            "requested_by_role": "ops"}


def test_refunds_can_never_exceed_the_payment(seed, db):
    s = seed()
    _, payment, _ = _paid_booking(db, s, amount=500)
    db.table("refunds").insert(_refund_row(payment, 30000, "a")).execute()
    with pytest.raises(Exception) as exc:
        db.table("refunds").insert(_refund_row(payment, 20001, "b")).execute()
    assert "exceed" in str(exc.value)
    # Exactly the remainder is fine.
    db.table("refunds").insert(_refund_row(payment, 20000, "c")).execute()


def test_a_repeated_idempotency_key_is_a_no_op_not_an_error(seed, db):
    """The guard must not count the existing row twice and raise on a retry."""
    s = seed()
    _, payment, _ = _paid_booking(db, s, amount=500)
    db.table("refunds").insert(_refund_row(payment, 50000, "full")).execute()
    db.table("refunds").upsert(_refund_row(payment, 50000, "full"),
                               on_conflict="idempotency_key", ignore_duplicates=True).execute()
    assert len(db.table("refunds").select("id").eq("payment_id", payment["id"]).execute().data) == 1


def test_a_refund_amount_cannot_be_edited(seed, db):
    s = seed()
    _, payment, _ = _paid_booking(db, s)
    row = db.table("refunds").insert(_refund_row(payment, 10000, "x")).execute().data[0]
    with pytest.raises(Exception):
        db.table("refunds").update({"amount_paise": 50000}).eq("id", row["id"]).execute()


def test_reversing_a_paid_out_credit_twice_recovers_it_once(seed, db):
    s = seed()
    booking, _, _ = _paid_booking(db, s, ledger_status="paid")
    for _ in range(2):
        db.rpc("reverse_ledger_credit", {"p_booking_id": booking["id"], "p_source": "consult_fee",
                                         "p_note": "test"}).execute()
    recoveries = db.table("doctor_ledger_entries").select("id") \
        .eq("booking_id", booking["id"]).eq("source", "reversal").execute().data
    assert len(recoveries) == 1


def test_only_a_reversal_may_be_negative(seed, db):
    s = seed()
    with pytest.raises(Exception):
        db.table("doctor_ledger_entries").insert({
            "doctor_id": s["doctor"]["id"], "source": "adjustment", "gross_amount": -100,
            "commission_pct": 0, "commission_amount": 0, "net_amount": -100,
        }).execute()


def test_the_client_roles_cannot_call_the_money_functions(seed, db):
    """
    Postgres grants EXECUTE to PUBLIC by default, and Supabase to anon and
    authenticated. The anon key ships in both apps, so without 0022's revokes
    anyone could cancel any booking through /rest/v1/rpc.
    """
    s = seed()
    booking, _, _ = _paid_booking(db, s)
    for role in ("anon", "authenticated"):
        token = jwt.encode({"role": role}, STACK_JWT_SECRET, algorithm="HS256")
        res = httpx.post(
            f"{os.environ['SUPABASE_URL']}/rest/v1/rpc/cancel_booking",
            headers={"Authorization": f"Bearer {token}", "apikey": token},
            json={"p_booking_id": booking["id"], "p_expected_status": "paid",
                  "p_cancelled_by": "patient", "p_actor_id": s["patient"]["id"]},
        )
        assert res.status_code in (401, 403, 404), (role, res.status_code, res.text)
    assert db.table("bookings").select("status").eq("id", booking["id"]) \
        .execute().data[0]["status"] == "paid"


# ── payouts ──────────────────────────────────────────────────────────────────

def test_a_payout_run_takes_completed_visits_and_nets_recoveries(seed, db):
    from app.services import payouts

    s = seed()
    done, _, _ = _paid_booking(db, s, amount=1000)
    db.table("bookings").update({"status": "completed"}).eq("id", done["id"]).execute()
    _paid_booking(db, s, amount=700)                     # paid, visit not yet happened
    cancelled, _, _ = _paid_booking(db, s, amount=300, ledger_status="paid")
    db.rpc("reverse_ledger_credit", {"p_booking_id": cancelled["id"], "p_source": "consult_fee",
                                     "p_note": "cancelled after payout"}).execute()
    db.table("doctor_bank_accounts").insert({
        "doctor_id": s["doctor"]["id"], "account_holder": "Dr Test", "upi_id": "drtest@okhdfc",
        # Saved a while ago: a destination changed in the last 48h is held.
        "updated_at": (datetime.now(timezone.utc) - timedelta(days=3)).isoformat(),
    }).execute()

    now = datetime.now(timezone.utc)
    payout = payouts.create_payout(s["doctor"]["id"], (now - timedelta(days=1)).isoformat(),
                                   (now + timedelta(days=1)).isoformat())
    assert float(payout["net_amount"]) == 700.0          # 1000 − 300 recovered
    assert payout["entry_count"] == 2

    still_payable = db.table("doctor_ledger_entries").select("net_amount") \
        .eq("doctor_id", s["doctor"]["id"]).eq("status", "payable").execute().data
    assert [float(r["net_amount"]) for r in still_payable] == [700.0]


def test_payment_history_carries_its_refunds(seed, client_for, db):
    s = seed()
    booking, _, _ = _paid_booking(db, s)
    _cancel(client_for(s["patient"]["id"]), booking["id"])

    res = client_for(s["patient"]["id"]).get(f"/payments/{booking['id']}", headers=AUTH)
    assert res.status_code == 200, res.text
    [payment] = res.json()
    assert payment["status"] == "refunded"
    assert [r["status"] for r in payment["refunds"]] == ["processed"]
