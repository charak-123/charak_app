"""
Migration 0024 against real Postgres: cancellation policies, the quote the
cancel itself uses, partial refunds, and consent against published versions.

Home-visit rules (LD-005, decided 2026-10-26): full refund 2 h or more before
the slot; 50% inside 2 h if the doctor hasn't started travelling; nothing once
travelling; a full refund whenever the doctor cancels. Online consultations
keep a full refund until decision D3 is made.
"""
import itertools
import uuid
from datetime import datetime, timedelta, timezone

import pytest

from .conftest import AUTH

_slot = itertools.count()


def _id() -> str:
    return str(uuid.uuid4())


def _paid(db, s, *, channel="home_visit", hours_ahead=3.0, amount=800.00, journey=False):
    start = datetime.now(timezone.utc) + timedelta(hours=hours_ahead, seconds=next(_slot))
    booking = db.table("bookings").insert({
        "id": _id(), "patient_id": s["patient"]["id"], "doctor_id": s["doctor"]["id"],
        "channel": channel, "scheduled_start": start.isoformat(), "status": "paid",
        "price_confirmed": amount,
        "journey_started_at": datetime.now(timezone.utc).isoformat() if journey else None,
    }).execute().data[0]
    payment = db.table("payments").insert({
        "id": _id(), "booking_id": booking["id"], "amount": amount, "status": "completed",
        "type": "consult_fee", "razorpay_order_id": f"order_{_id()[:12]}",
        "razorpay_payment_id": f"pay_{_id()[:12]}",
    }).execute().data[0]
    db.table("doctor_ledger_entries").insert({
        "doctor_id": s["doctor"]["id"], "booking_id": booking["id"], "source": "consult_fee",
        "gross_amount": amount, "commission_pct": 0, "commission_amount": 0,
        "net_amount": amount, "status": "payable",
    }).execute()
    return booking, payment


def _quote(client, booking_id):
    res = client.get(f"/bookings/{booking_id}/cancellation-quote", headers=AUTH)
    assert res.status_code == 200, res.text
    return res.json()


# ── the policy each booking keeps ────────────────────────────────────────────

def test_a_new_booking_is_stamped_with_the_current_policy(seed, db):
    s = seed(offers_home_visit=True)
    booking, _ = _paid(db, s)
    policy = db.table("policies").select("channel, version") \
        .eq("id", booking["cancellation_policy_id"]).execute().data[0]
    assert policy == {"channel": "home_visit", "version": "2026-10-26"}


def test_a_published_policy_cannot_be_edited(db):
    row = db.table("policies").select("id").eq("version", "2026-10-26").limit(1).execute().data[0]
    with pytest.raises(Exception):
        db.table("policies").update({"summary": "changed"}).eq("id", row["id"]).execute()


# ── the quote: LD-005 for home visits ────────────────────────────────────────

@pytest.mark.parametrize("hours_ahead,journey,pct,reason", [
    (3.0, False, 100, "free_cancellation"),
    (1.0, False, 50, "late_cancellation"),
    (1.0, True, 0, "journey_started"),
    (3.0, True, 0, "journey_started"),
    (-0.5, False, 50, "late_cancellation"),     # after the start, doctor not travelling
])
def test_home_visit_quotes_follow_ld_005(seed, client_for, db, hours_ahead, journey, pct, reason):
    s = seed(offers_home_visit=True)
    booking, _ = _paid(db, s, hours_ahead=hours_ahead, journey=journey)
    q = _quote(client_for(s["patient"]["id"]), booking["id"])
    assert (q["refund_pct"], q["reason"]) == (pct, reason)
    assert q["refund_paise"] == 80000 * pct // 100
    assert q["refund_paise"] + q["kept_paise"] == 80000
    # Free cancellation ends 2 hours before the start.
    free_until = datetime.fromisoformat(q["free_until"])
    start = datetime.fromisoformat(booking["scheduled_start"])
    assert start - free_until == timedelta(hours=2)


def test_a_doctor_cancelling_always_refunds_in_full(seed, client_for, db):
    s = seed(offers_home_visit=True)
    booking, _ = _paid(db, s, hours_ahead=0.5, journey=True)
    q = _quote(client_for(s["doctor"]["id"], "doctor"), booking["id"])
    assert (q["refund_pct"], q["reason"]) == (100, "cancelled_by_doctor")


def test_online_consults_stay_fully_refundable_until_d3_is_decided(seed, client_for, db):
    s = seed()
    booking, _ = _paid(db, s, channel="online_consult", hours_ahead=0.1)
    q = _quote(client_for(s["patient"]["id"]), booking["id"])
    assert q["refund_pct"] == 100
    assert q["free_until"] is None


def test_a_half_refund_of_an_odd_amount_never_overpays(seed, client_for, db):
    s = seed(offers_home_visit=True)
    booking, _ = _paid(db, s, hours_ahead=1.0, amount=555.55)
    q = _quote(client_for(s["patient"]["id"]), booking["id"])
    assert q["refund_paise"] == 27777          # floor of 27777.5
    assert q["kept_paise"] == 27778


# ── the cancel follows the quote ─────────────────────────────────────────────

def test_a_late_cancel_refunds_half_and_the_doctor_keeps_half(seed, client_for, db):
    s = seed(offers_home_visit=True)
    booking, payment = _paid(db, s, hours_ahead=1.0)
    patient = client_for(s["patient"]["id"])
    q = _quote(patient, booking["id"])

    res = patient.patch(f"/bookings/{booking['id']}/cancel", headers=AUTH,
                        json={"expected_refund_paise": q["refund_paise"],
                              "reason_code": "schedule_conflict"})
    assert res.status_code == 200, res.text
    assert res.json()["quote"]["refund_pct"] == 50

    [refund] = db.table("refunds").select("*").eq("payment_id", payment["id"]).execute().data
    assert refund["amount_paise"] == 40000
    assert db.table("payments").select("status").eq("id", payment["id"]) \
        .execute().data[0]["status"] == "partially_refunded"

    ledger = db.table("doctor_ledger_entries").select("source, net_amount, status") \
        .eq("booking_id", booking["id"]).execute().data
    assert sum(float(e["net_amount"]) for e in ledger if e["status"] == "payable") == 400.0

    event = db.table("booking_events").select("metadata").eq("booking_id", booking["id"]) \
        .eq("event", "cancel").execute().data[0]
    assert event["metadata"]["refund_pct"] == 50
    assert event["metadata"]["reason_code"] == "schedule_conflict"

    notes = db.table("notifications").select("recipient_id, body") \
        .eq("booking_id", booking["id"]).eq("event", "booking.cancelled").execute().data
    assert any("₹400" in n["body"] and n["recipient_id"] == s["doctor"]["id"] for n in notes)


def test_a_cancel_after_the_journey_starts_refunds_nothing(seed, client_for, db):
    s = seed(offers_home_visit=True)
    booking, payment = _paid(db, s, hours_ahead=1.0, journey=True)
    res = client_for(s["patient"]["id"]).patch(f"/bookings/{booking['id']}/cancel",
                                               headers=AUTH, json={"expected_refund_paise": 0})
    assert res.status_code == 200, res.text
    assert db.table("refunds").select("id").eq("payment_id", payment["id"]).execute().data == []
    entry = db.table("doctor_ledger_entries").select("status, net_amount") \
        .eq("booking_id", booking["id"]).execute().data
    assert entry == [{"status": "payable", "net_amount": 800.0}]


def test_if_the_outcome_moved_since_the_quote_nothing_is_cancelled(seed, client_for, db):
    """The doctor started travelling between the patient's quote and their tap."""
    s = seed(offers_home_visit=True)
    booking, payment = _paid(db, s, hours_ahead=1.0)
    patient = client_for(s["patient"]["id"])
    shown = _quote(patient, booking["id"])["refund_paise"]
    db.table("bookings").update({"journey_started_at": datetime.now(timezone.utc).isoformat()}) \
        .eq("id", booking["id"]).execute()

    res = patient.patch(f"/bookings/{booking['id']}/cancel", headers=AUTH,
                        json={"expected_refund_paise": shown})
    assert res.status_code == 409
    assert res.json()["quote"]["refund_paise"] == 0
    assert db.table("bookings").select("status").eq("id", booking["id"]) \
        .execute().data[0]["status"] == "paid"
    assert db.table("refunds").select("id").eq("payment_id", payment["id"]).execute().data == []


def test_an_unknown_reason_code_is_refused(seed, client_for, db):
    s = seed(offers_home_visit=True)
    booking, _ = _paid(db, s)
    res = client_for(s["patient"]["id"]).patch(f"/bookings/{booking['id']}/cancel",
                                               headers=AUTH, json={"reason_code": "bored"})
    assert res.status_code == 400


def test_the_kept_part_becomes_payable_48_hours_after_the_cancel(seed, client_for, db):
    from app.services import payouts

    s = seed(offers_home_visit=True)
    booking, _ = _paid(db, s, hours_ahead=1.0)
    client_for(s["patient"]["id"]).patch(f"/bookings/{booking['id']}/cancel", headers=AUTH, json={})
    db.table("doctor_bank_accounts").insert({
        "doctor_id": s["doctor"]["id"], "account_holder": "Dr", "upi_id": "dr@okhdfc",
        # Saved a while ago: a destination changed in the last 48h is held.
        "updated_at": (datetime.now(timezone.utc) - timedelta(days=3)).isoformat()}).execute()
    window = ((datetime.now(timezone.utc) - timedelta(days=5)).isoformat(),
              (datetime.now(timezone.utc) + timedelta(days=1)).isoformat())

    with pytest.raises(Exception):                 # too soon: nothing eligible yet
        payouts.create_payout(s["doctor"]["id"], *window)

    # Two days later (backdating the cancel stands in for waiting).
    db.table("bookings").update({"cancelled_at": (datetime.now(timezone.utc)
                                                  - timedelta(hours=49)).isoformat()}) \
        .eq("id", booking["id"]).execute()
    payout = payouts.create_payout(s["doctor"]["id"], *window)
    assert float(payout["net_amount"]) == 400.0


# ── consent ──────────────────────────────────────────────────────────────────

def _flags(db, **values):
    from app.services import app_config
    for key, value in values.items():
        db.table("app_config").update({"value": value}).eq("key", key).execute()
    app_config.clear_cache()


@pytest.fixture
def consent_required(db):
    _flags(db, require_legal_acceptance=True, require_booking_policy_acceptance=True)
    yield
    _flags(db, require_legal_acceptance=False, require_booking_policy_acceptance=False)


def _slot_time():
    return (datetime.now(timezone.utc) + timedelta(days=4, hours=next(_slot) % 20)).replace(
        minute=0, second=0, microsecond=0).isoformat()


def test_booking_needs_current_consent_when_switched_on(seed, client_for, db, consent_required):
    s = seed()
    patient = client_for(s["patient"]["id"])
    body = {"doctor_id": s["doctor"]["id"], "channel": "online_consult",
            "scheduled_start": _slot_time(), "accepted_policy_version": "2026-10-26"}

    refused = patient.post("/bookings/", json=body, headers=AUTH)
    assert refused.status_code == 428
    assert {d["type"] for d in refused.json()["consent_required"]} == {"tos", "privacy", "telemedicine"}

    current = patient.get("/legal/current", headers=AUTH).json()
    docs = [{"type": d["type"], "version": d["version"]} for d in current["documents"]]
    accepted = patient.post("/legal/accept", headers=AUTH,
                            json={"documents": docs, "method": "signup_checkbox"})
    assert accepted.status_code == 201
    assert accepted.json()["missing"] == []

    booked = patient.post("/bookings/", json=body, headers=AUTH)
    assert booked.status_code == 201, booked.text
    assert booked.json()["cancellation_policy"]["version"] == "2026-10-26"
    evidence = db.table("consents").select("type, version, booking_id, method") \
        .eq("user_id", s["patient"]["id"]).eq("type", "booking_policy").execute().data
    assert evidence == [{"type": "booking_policy", "version": "online_consult:2026-10-26",
                         "booking_id": booked.json()["id"], "method": "booking_confirmation"}]


def test_a_booking_needs_the_policy_ticked_when_switched_on(seed, client_for, db, consent_required):
    s = seed()
    patient = client_for(s["patient"]["id"])
    _flags(db, require_legal_acceptance=False)
    body = {"doctor_id": s["doctor"]["id"], "channel": "online_consult", "scheduled_start": _slot_time()}
    res = patient.post("/bookings/", json=body, headers=AUTH)
    assert res.status_code == 428
    assert res.json()["policy"]["version"] == "2026-10-26"

    stale = patient.post("/bookings/", json={**body, "accepted_policy_version": "2025-01-01"},
                         headers=AUTH)
    assert stale.status_code == 409


def test_accepting_twice_records_once_and_a_stale_version_is_refused(seed, client_for, db):
    s = seed()
    patient = client_for(s["patient"]["id"])
    item = {"documents": [{"type": "tos", "version": "2026-10-01"}]}
    assert len(patient.post("/legal/accept", headers=AUTH, json=item).json()["recorded"]) == 1
    assert patient.post("/legal/accept", headers=AUTH, json=item).json()["recorded"] == []
    stale = patient.post("/legal/accept", headers=AUTH,
                         json={"documents": [{"type": "tos", "version": "2019-01-01"}]})
    assert stale.status_code == 409
    rows = db.table("consents").select("id").eq("user_id", s["patient"]["id"]).execute().data
    assert len(rows) == 1


def test_consent_evidence_cannot_be_edited_or_deleted(seed, client_for, db):
    s = seed()
    client_for(s["patient"]["id"]).post("/legal/accept", headers=AUTH,
                                        json={"documents": [{"type": "privacy", "version": "2026-10-01"}]})
    row = db.table("consents").select("id").eq("user_id", s["patient"]["id"]).execute().data[0]
    with pytest.raises(Exception):
        db.table("consents").update({"version": "forged"}).eq("id", row["id"]).execute()
    with pytest.raises(Exception):
        db.table("consents").delete().eq("id", row["id"]).execute()


# ── what the patient sees ────────────────────────────────────────────────────

def test_the_booking_shows_its_policy_and_the_payment_history_its_refund(seed, client_for, db):
    s = seed(offers_home_visit=True)
    booking, _ = _paid(db, s, hours_ahead=1.0)
    patient = client_for(s["patient"]["id"])

    detail = patient.get(f"/bookings/{booking['id']}", headers=AUTH).json()
    assert detail["cancellation_policy"]["free_cancellation_minutes"] == 120
    assert "50%" in detail["cancellation_policy"]["summary"]

    patient.patch(f"/bookings/{booking['id']}/cancel", headers=AUTH, json={})
    history = patient.get("/me/payments", headers=AUTH)
    assert history.status_code == 200, history.text
    [payment] = [p for p in history.json() if p["booking_id"] == booking["id"]]
    assert payment["status"] == "partially_refunded"
    assert [r["amount_paise"] for r in payment["refunds"]] == [40000]
    assert payment["bookings"]["doctors"]["name"] == "Dr Test"
