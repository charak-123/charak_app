"""
The visit's pure rules, without a database: what push text may say, when
follow-up reminders go out, and when a visit's fee can be withdrawn. The SQL
and the endpoints run against real Postgres in tests/integration/test_visit.py.
"""
from datetime import date, datetime, timedelta, timezone
from unittest.mock import patch

import pytest

from app.services import notifications, payouts, prescriptions

IST = timezone(timedelta(hours=5, minutes=30))
SENT = datetime(2026, 11, 2, 10, 0, tzinfo=timezone.utc)

# Medical words that must never reach a lock screen (spec §9.3, §16.2).
MEDICAL = ("Paracetamol", "650 mg", "Viral fever", "Fever for 3 days", "CBC", "Rest and fluids",
           "Bring reports")


@pytest.fixture
def sent():
    """Every notify() call, as recorded."""
    calls = []
    with patch.object(notifications, "notify",
                      side_effect=lambda *a, **k: calls.append((a, k)) or {}):
        yield calls


def _booking(**extra):
    # Medical text is everywhere a careless template could reach for it.
    return {"id": "bk-1", "patient_id": "pt-1", "doctor_id": "dr-1", "channel": "home_visit",
            "scheduled_start": "2026-11-03T04:30:00+00:00", "diagnosis": "Viral fever",
            "complaints": "Fever for 3 days", "advice": "Rest and fluids",
            "items": [{"medicine": "Paracetamol", "strength": "650 mg"}],
            "investigations": "CBC", **extra}


def test_no_visit_notification_carries_medical_text(sent):
    b = _booking()
    notifications.journey_started(b)
    notifications.prescription_ready(b, "rx-1")
    notifications.prescription_updated(b, "rx-2")
    notifications.prescription_reminder(b, "rx-1")
    notifications.visit_complete_to_doctor(b, "patient_viewed", SENT + timedelta(hours=48))
    notifications.visit_complete_to_doctor(b, "fallback", SENT)
    for minutes in (1440, 120, 15):
        for role in ("patient", "doctor"):
            notifications.appointment_reminder({**b, "channel": "online_consult"}, role, minutes)
            notifications.appointment_reminder(b, role, minutes)
    rec = {"id": "fu-1", "patient_id": "pt-1", "booking_id": "bk-1",
           "recommended_date": "2026-11-20", "note": "Bring reports"}
    notifications.follow_up_reminder(rec, "on_day")
    notifications.follow_up_reminder(rec, "advance")

    assert len(sent) == 20
    for args, kwargs in sent:
        title, body, data = args[3], args[4], args[5] or {}
        text = " ".join([title, body, *map(str, data.values())])
        for word in MEDICAL:
            assert word not in text, (args[2], word)


def test_visit_notifications_are_deduplicated_per_event(sent):
    b = _booking()
    notifications.journey_started(b)
    notifications.prescription_ready(b, "rx-1")
    notifications.appointment_reminder(b, "patient", 120)
    keys = [k["dedupe_key"] for _, k in sent]
    assert all(keys) and len(set(keys)) == 3


def test_the_doctor_is_told_when_the_fee_can_be_withdrawn(sent):
    future = datetime.now(timezone.utc) + timedelta(hours=40)
    notifications.visit_complete_to_doctor(_booking(), "patient_viewed", future)
    assert "can be withdrawn from" in sent[0][0][4]
    past = datetime.now(timezone.utc) - timedelta(minutes=1)
    notifications.visit_complete_to_doctor(_booking(id="bk-2"), "fallback", past)
    assert sent[1][0][4].endswith("can be withdrawn now.")


# ── Follow-up reminder times (D17) ───────────────────────────────────────────

def test_a_near_follow_up_is_reminded_on_the_day_at_9_ist():
    now = datetime(2026, 11, 2, 12, 0, tzinfo=IST)
    times = prescriptions.follow_up_reminder_times(date(2026, 11, 5), now=now)
    assert times == [(datetime(2026, 11, 5, 9, 0, tzinfo=IST), "on_day")]


def test_a_far_follow_up_also_gets_a_reminder_two_days_before():
    now = datetime(2026, 11, 2, 12, 0, tzinfo=IST)
    times = prescriptions.follow_up_reminder_times(date(2026, 11, 9), now=now)
    assert times == [(datetime(2026, 11, 9, 9, 0, tzinfo=IST), "on_day"),
                     (datetime(2026, 11, 7, 9, 0, tzinfo=IST), "advance")]


def test_reminder_times_already_past_are_skipped():
    now = datetime(2026, 11, 2, 10, 0, tzinfo=IST)
    assert prescriptions.follow_up_reminder_times(date(2026, 11, 2), now=now) == []


# ── When the fee can be withdrawn (LD-006) ───────────────────────────────────

def _entry(**booking):
    return {"source": "consult_fee", "bookings": {"status": "completed", **booking}}


@pytest.mark.parametrize("viewed_after,hours", [
    (timedelta(hours=1), 48),
    (timedelta(hours=48), 48),                       # exactly at the window: still 48
    (timedelta(hours=48, seconds=1), 72),
    (None, 72),
])
def test_release_is_48h_after_the_send_if_opened_in_48h_else_72h(viewed_after, hours):
    entry = _entry(prescription_sent_at=SENT.isoformat(),
                   prescription_viewed_at=(SENT + viewed_after).isoformat() if viewed_after else None)
    assert payouts.available_at(entry) == SENT + timedelta(hours=hours)
    assert not payouts.is_payout_eligible(entry, now=SENT + timedelta(hours=hours) - timedelta(seconds=1))
    assert payouts.is_payout_eligible(entry, now=SENT + timedelta(hours=hours))


def test_a_visit_not_yet_complete_is_never_withdrawable():
    for status in ("paid", "in_progress", "consulted"):
        entry = {"source": "consult_fee",
                 "bookings": {"status": status, "prescription_sent_at": SENT.isoformat()}}
        assert payouts.available_at(entry) is None
        assert not payouts.is_payout_eligible(entry, now=SENT + timedelta(days=30))


def test_completed_without_a_prescription_waits_48h_and_legacy_rows_are_free():
    entry = _entry(completed_at=SENT.isoformat())
    assert payouts.available_at(entry) == SENT + timedelta(hours=48)
    assert payouts.is_payout_eligible(_entry(), now=SENT)            # completed before 0025


def test_adjustments_and_reversals_have_nothing_to_wait_for():
    assert payouts.is_payout_eligible({"source": "adjustment"}, now=SENT)
    assert payouts.is_payout_eligible({"source": "reversal"}, now=SENT)
