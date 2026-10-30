"""
Unit tests for the slot availability calculation.
These tests mock the Supabase client so no real DB connection is needed.
"""
from datetime import date, datetime, time
from unittest.mock import MagicMock, patch

import pytest

# Patch supabase before importing the module under test
_mock_supabase = MagicMock()

with patch("app.db.supabase", _mock_supabase):
    from app.services.availability import (
        IST,
        get_available_slots as _get_available_slots,
        _parse_time,
        _add_minutes,
        _fmt,
    )

# The fixtures below are dated August 2026. Pin "now" before them so the
# grid's no-past-slots rule does not empty every day.
_BEFORE_ALL_FIXTURES = datetime(2026, 8, 1, 9, 0, tzinfo=IST)


def get_available_slots(doctor_id, from_date, days=14, now=_BEFORE_ALL_FIXTURES):
    return _get_available_slots(doctor_id, from_date, days=days, now=now)


def _make_supabase(schedules=None, blocks=None, bookings=None):
    """Return a mock supabase client that yields the given data."""
    mock = MagicMock()

    def _chain(data):
        c = MagicMock()
        c.select.return_value = c
        c.eq.return_value     = c
        c.in_.return_value    = c
        c.gte.return_value    = c
        c.lte.return_value    = c
        c.lt.return_value     = c
        c.execute.return_value = MagicMock(data=data)
        return c

    # table() returns different chains based on the table name
    def _table(name):
        if name == "doctor_schedules":
            return _chain(schedules or [])
        if name == "doctor_slot_blocks":
            return _chain(blocks or [])
        if name == "bookings":
            return _chain(bookings or [])
        return _chain([])

    mock.table.side_effect = _table
    return mock


# ── Helper tests ──────────────────────────────────────────────────────────────

def test_parse_time():
    assert _parse_time("09:00") == time(9, 0)
    assert _parse_time("17:30") == time(17, 30)
    assert _parse_time("09:00:00") == time(9, 0)


def test_add_minutes():
    assert _add_minutes(time(9, 0), 15) == time(9, 15)
    assert _add_minutes(time(9, 45), 15) == time(10, 0)
    assert _add_minutes(time(23, 45), 15) == time(0, 0)


def test_fmt():
    assert _fmt(time(9, 0))  == "09:00"
    assert _fmt(time(17, 30)) == "17:30"


# ── Slot calculation tests ────────────────────────────────────────────────────

def test_no_schedule_returns_empty():
    mock = _make_supabase(schedules=[], blocks=[], bookings=[])
    with patch("app.services.availability.supabase", mock):
        result = get_available_slots("doc-1", date(2026, 8, 25), days=1)
    assert result == {}


def test_single_day_schedule_produces_correct_slots():
    # Monday (weekday=0) 09:00-09:45 → 3 slots: 09:00, 09:15, 09:30
    monday = date(2026, 8, 24)  # 2026-08-24 is a Monday
    assert monday.weekday() == 0

    mock = _make_supabase(
        schedules=[{"day_of_week": 0, "start_time": "09:00", "end_time": "09:45"}],
        blocks=[],
        bookings=[],
    )
    with patch("app.services.availability.supabase", mock):
        result = get_available_slots("doc-1", monday, days=1)

    assert "2026-08-24" in result
    slots = result["2026-08-24"]
    assert len(slots) == 3
    assert slots[0] == {"start": "09:00", "end": "09:15"}
    assert slots[1] == {"start": "09:15", "end": "09:30"}
    assert slots[2] == {"start": "09:30", "end": "09:45"}


def test_slot_block_removes_slots():
    monday = date(2026, 8, 24)
    mock = _make_supabase(
        schedules=[{"day_of_week": 0, "start_time": "09:00", "end_time": "09:45"}],
        blocks=[{"date": "2026-08-24", "start_time": "09:00", "end_time": "09:30"}],
        bookings=[],
    )
    with patch("app.services.availability.supabase", mock):
        result = get_available_slots("doc-1", monday, days=1)

    # 09:00 and 09:15 are blocked; only 09:30 remains
    slots = result.get("2026-08-24", [])
    assert len(slots) == 1
    assert slots[0]["start"] == "09:30"


def test_confirmed_booking_removes_slot():
    monday = date(2026, 8, 24)
    mock = _make_supabase(
        schedules=[{"day_of_week": 0, "start_time": "09:00", "end_time": "09:30"}],
        blocks=[],
        bookings=[{"scheduled_start": "2026-08-24T03:30:00+00:00"}],  # 09:00 IST, as the DB returns it
    )
    with patch("app.services.availability.supabase", mock):
        result = get_available_slots("doc-1", monday, days=1)

    # 09:00 booked; only 09:15 remains
    slots = result.get("2026-08-24", [])
    assert len(slots) == 1
    assert slots[0]["start"] == "09:15"


def test_fully_booked_day_absent_from_result():
    monday = date(2026, 8, 24)
    mock = _make_supabase(
        schedules=[{"day_of_week": 0, "start_time": "09:00", "end_time": "09:15"}],
        blocks=[],
        bookings=[{"scheduled_start": "2026-08-24T03:30:00+00:00"}],  # 09:00 IST, as the DB returns it
    )
    with patch("app.services.availability.supabase", mock):
        result = get_available_slots("doc-1", monday, days=1)

    assert "2026-08-24" not in result


def test_multiple_days():
    monday = date(2026, 8, 24)
    mock = _make_supabase(
        schedules=[
            {"day_of_week": 0, "start_time": "09:00", "end_time": "09:30"},  # Mon 2 slots
            {"day_of_week": 2, "start_time": "14:00", "end_time": "14:15"},  # Wed 1 slot
        ],
        blocks=[],
        bookings=[],
    )
    with patch("app.services.availability.supabase", mock):
        result = get_available_slots("doc-1", monday, days=7)

    assert "2026-08-24" in result  # Monday
    assert "2026-08-26" in result  # Wednesday
    assert len(result["2026-08-24"]) == 2
    assert len(result["2026-08-26"]) == 1
    # Tuesday, Thursday, Friday, Saturday, Sunday have no schedule
    assert "2026-08-25" not in result


def test_a_requested_booking_hides_its_slot_from_the_grid():
    """
    Regression: availability ignored `requested`, but create_booking refuses
    it. A second patient was shown a slot that was already spoken for, filled
    in their whole intake, and was turned away with "Slot already booked" at
    the final step.
    """
    from app.routers.bookings import SLOT_HOLDING_STATUSES
    from app.services.availability import SLOT_OCCUPYING_STATUSES

    assert "requested" in SLOT_OCCUPYING_STATUSES
    # Everything that blocks a booking must also be hidden from the grid.
    for status in SLOT_HOLDING_STATUSES:
        assert status in SLOT_OCCUPYING_STATUSES, (
            f"{status} blocks booking but is still offered as a free slot")


def test_a_booking_returned_in_utc_hides_its_ist_slot():
    """
    Regression: the grid read the hour straight off the stored string. The
    database returns timestamptz in UTC, so a 09:00 IST booking ("03:30+00")
    left 09:00 on offer.
    """
    monday = date(2026, 8, 24)
    mock = _make_supabase(
        schedules=[{"day_of_week": 0, "start_time": "09:00", "end_time": "09:30"}],
        bookings=[{"scheduled_start": "2026-08-24T03:30:00+00:00"}],
    )
    with patch("app.services.availability.supabase", mock):
        result = get_available_slots("doc-1", monday, days=1)

    assert [s["start"] for s in result["2026-08-24"]] == ["09:15"]


def test_slots_that_have_started_or_are_too_close_are_not_offered():
    monday = date(2026, 8, 24)
    mock = _make_supabase(
        schedules=[{"day_of_week": 0, "start_time": "09:00", "end_time": "10:00"}],
    )
    now = datetime(2026, 8, 24, 9, 10, tzinfo=IST)   # 09:00 started; 09:15 is < 15 min away
    with patch("app.services.availability.supabase", mock):
        result = get_available_slots("doc-1", monday, days=1, now=now)

    assert [s["start"] for s in result["2026-08-24"]] == ["09:30", "09:45"]


# ── Per-channel hours (migration 0035) ───────────────────────────────────────

_MONDAY = date(2026, 8, 24)
_SPLIT = [
    {"day_of_week": 0, "start_time": "09:00", "end_time": "10:00", "channel": "online_consult"},
    {"day_of_week": 0, "start_time": "16:00", "end_time": "17:00", "channel": "home_visit"},
]


def _starts(channel, schedules=_SPLIT):
    with patch("app.services.availability.supabase", _make_supabase(schedules=schedules)):
        grid = _get_available_slots("doc-1", _MONDAY, days=1, now=_BEFORE_ALL_FIXTURES,
                                    duration_min=30, channel=channel)
    return [s["start"] for s in grid.get(str(_MONDAY), [])]


def test_home_visit_hours_are_not_online_slots():
    # A 30-minute visit can start every 15 minutes.
    assert _starts("online_consult") == ["09:00", "09:15", "09:30"]
    assert _starts("home_visit") == ["16:00", "16:15", "16:30"]


def test_without_a_channel_every_hour_counts():
    assert _starts(None) == ["09:00", "09:15", "09:30", "16:00", "16:15", "16:30"]


def test_hours_saved_before_0035_serve_both_channels():
    legacy = [{"day_of_week": 0, "start_time": "09:00", "end_time": "10:00"}]
    assert _starts("online_consult", legacy) == _starts("home_visit", legacy) == ["09:00", "09:15", "09:30"]


def test_overlapping_online_and_home_hours_list_a_time_once():
    both = [
        {"day_of_week": 0, "start_time": "09:00", "end_time": "10:00", "channel": "online_consult"},
        {"day_of_week": 0, "start_time": "09:00", "end_time": "10:00", "channel": "home_visit"},
    ]
    assert _starts(None, both) == ["09:00", "09:15", "09:30"]
