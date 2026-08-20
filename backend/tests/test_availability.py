"""
Unit tests for the slot availability calculation.
These tests mock the Supabase client so no real DB connection is needed.
"""
from datetime import date, time
from unittest.mock import MagicMock, patch

import pytest

# Patch supabase before importing the module under test
_mock_supabase = MagicMock()

with patch("app.db.supabase", _mock_supabase):
    from app.services.availability import (
        get_available_slots,
        _parse_time,
        _add_minutes,
        _fmt,
    )


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
        bookings=[{"scheduled_start": "2026-08-24T09:00:00+00:00"}],
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
        bookings=[{"scheduled_start": "2026-08-24T09:00:00+00:00"}],
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
