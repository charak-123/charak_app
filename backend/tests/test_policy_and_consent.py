"""
API edges of migration 0024's cancellation policy and consent. The rules
themselves run against Postgres in tests/integration/test_cancellation_policy.py.
"""
from unittest.mock import MagicMock, patch

import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.services import cancellation
from tests.conftest import make_chain, make_supabase

AUTH = {"Authorization": "Bearer t"}
PATIENT = {"sub": "pat-1", "role": "patient"}
DOCTOR = {"sub": "doc-1", "role": "doctor"}
BOOKING = {"id": "bk-1", "patient_id": "pat-1", "doctor_id": "doc-1", "status": "paid",
           "channel": "home_visit"}


def _as(payload):
    p = patch("app.deps.jwt")
    jw = p.start()
    jw.decode.return_value = payload
    return p


@pytest.mark.parametrize("rules,minutes", [
    ([{"when": {"journey_started": True}, "refund_pct": 0},
      {"when": {"minutes_before_start_lt": 120}, "refund_pct": 50},
      {"when": {}, "refund_pct": 100}], 120),
    ([{"when": {}, "refund_pct": 100}], None),
    ([{"when": {"minutes_before_start_lt": 15}, "refund_pct": 0},
      {"when": {"minutes_before_start_lt": 60}, "refund_pct": 50},
      {"when": {}, "refund_pct": 100}], 60),
])
def test_free_cancellation_ends_at_the_widest_reducing_window(rules, minutes):
    assert cancellation.free_cancellation_minutes(rules) == minutes


def test_a_quote_that_moved_comes_back_as_409_with_the_new_quote():
    db = make_supabase({"bookings": make_chain(data=BOOKING)})
    db.rpc.return_value.execute.return_value = MagicMock(data={
        "outcome": "quote_changed", "status": "paid",
        "quote": {"refund_paise": 0, "kept_paise": 80000, "refund_pct": 0, "reason": "journey_started"}})
    p = _as(PATIENT)
    try:
        with patch("app.routers.bookings.supabase", db):
            res = TestClient(app).patch("/bookings/bk-1/cancel", headers=AUTH,
                                        json={"expected_refund_paise": 40000})
    finally:
        p.stop()
    assert res.status_code == 409
    assert res.json()["quote"]["refund_pct"] == 0
    params = db.rpc.call_args.args[1]
    assert params["p_expected_refund_paise"] == 40000


@pytest.mark.parametrize("payload,reason,code", [
    (PATIENT, "schedule_conflict", 200),
    (PATIENT, "emergency", 400),          # a doctor's reason
    (DOCTOR, "emergency", 200),
    (DOCTOR, "feeling_better", 400),      # a patient's reason
])
def test_reason_codes_belong_to_the_role_cancelling(payload, reason, code):
    db = make_supabase({"bookings": make_chain(data=BOOKING)})
    db.rpc.return_value.execute.return_value = MagicMock(data={
        "outcome": "cancelled", "status": "cancelled",
        "booking": {**BOOKING, "status": "cancelled"}, "refunds": [], "quote": {"kept_paise": 0}})
    p = _as(payload)
    try:
        with patch("app.routers.bookings.supabase", db), patch("app.routers.bookings.notifications"):
            res = TestClient(app).patch("/bookings/bk-1/cancel", headers=AUTH,
                                        json={"reason_code": reason})
    finally:
        p.stop()
    assert res.status_code == code


def test_the_quote_is_for_the_booking_s_own_participants_only():
    db = make_supabase({"bookings": make_chain(data={**BOOKING, "patient_id": "someone-else",
                                                     "doctor_id": "another"})})
    p = _as(PATIENT)
    try:
        with patch("app.routers.bookings.supabase", db):
            res = TestClient(app).get("/bookings/bk-1/cancellation-quote", headers=AUTH)
    finally:
        p.stop()
    assert res.status_code == 403


def test_ops_does_not_accept_patient_documents():
    p = _as({"sub": "admin", "role": "ops", "admin_role": "admin"})
    try:
        res = TestClient(app).get("/legal/current", headers=AUTH)
    finally:
        p.stop()
    assert res.status_code == 403


@pytest.mark.parametrize("body", [
    {"documents": [{"type": "tos", "version": "2026-10-01"}], "method": "telepathy"},
    {"documents": []},
])
def test_bad_acceptance_requests_are_refused(body):
    p = _as(PATIENT)
    try:
        res = TestClient(app).post("/legal/accept", headers=AUTH, json=body)
    finally:
        p.stop()
    assert res.status_code in (400, 422)


def test_the_policy_for_a_channel_is_served_for_the_confirm_screen():
    p = _as(PATIENT)
    try:
        res = TestClient(app).get("/legal/cancellation-policy?channel=home_visit", headers=AUTH)
        bad = TestClient(app).get("/legal/cancellation-policy?channel=teleport", headers=AUTH)
    finally:
        p.stop()
    assert res.status_code == 200
    assert set(res.json()) == {"channel", "version", "summary", "free_cancellation_minutes",
                               "points", "refund_timing"}
    assert all(set(pt) == {"when", "outcome", "tone"} for pt in res.json()["points"])
    assert bad.status_code == 400


# ── Every case, for the confirm screen ───────────────────────────────────────

HOME_RULES = [{"when": {"journey_started": True}, "refund_pct": 0},
              {"when": {"minutes_before_start_lt": 120}, "refund_pct": 50},
              {"when": {}, "refund_pct": 100}]


def test_the_home_visit_rules_read_earliest_first():
    rows = cancellation._patient_points("home_visit", HOME_RULES)
    assert [(r["when"], r["outcome"]) for r in rows] == [
        ("You cancel 2 hours or more before the visit", "Full refund"),
        ("You cancel less than 2 hours before the visit and the doctor hasn't set out", "50% refund"),
        ("You cancel after the doctor has started travelling", "No refund"),
    ]
    assert [r["tone"] for r in rows] == ["full", "partial", "none"]


def test_a_full_refund_any_time_reads_as_one_line():
    rows = cancellation._patient_points("online_consult", [{"when": {}, "refund_pct": 100}])
    assert rows == [{"when": "You cancel any time before the consultation starts",
                     "outcome": "Full refund", "tone": "full"}]


def test_two_time_windows_read_as_bands():
    rules = [{"when": {"minutes_before_start_lt": 15}, "refund_pct": 0},
             {"when": {"minutes_before_start_lt": 60}, "refund_pct": 50},
             {"when": {}, "refund_pct": 100}]
    assert [r["when"] for r in cancellation._patient_points("online_consult", rules)] == [
        "You cancel 1 hour or more before the consultation",
        "You cancel between 15 minutes and 1 hour before the consultation",
        "You cancel less than 15 minutes before the consultation",
    ]


def test_a_rule_the_quote_wouldnt_understand_is_not_described():
    """Better the summary alone than a line that disagrees with the refund."""
    assert cancellation._patient_points("home_visit", [{"when": {"weekday": "sun"}, "refund_pct": 0},
                                                       {"when": {}, "refund_pct": 100}]) == []


def test_every_case_is_covered_with_the_enforced_settings():
    with patch("app.services.incidents.app_config.get", return_value=None), \
         patch("app.services.app_config.get", return_value=None):
        rows = cancellation.points({"channel": "home_visit", "rules": HOME_RULES})
        online = cancellation.points({"channel": "online_consult", "rules": [{"when": {}, "refund_pct": 100}]})
    whens = [r["when"] for r in rows]
    assert whens[0] == "You withdraw your request before the doctor accepts"
    assert "The doctor cancels" in whens
    assert "The doctor hasn't arrived 30 minutes after the start" in whens        # the grace the report uses
    assert "The doctor hasn't joined 10 minutes after the start" in [r["when"] for r in online]
    assert whens[-1] == "You miss the visit" and rows[-1]["outcome"] == "No refund"
    assert "24 hours" in next(r["outcome"] for r in rows if r["when"].startswith("The doctor hasn't"))
