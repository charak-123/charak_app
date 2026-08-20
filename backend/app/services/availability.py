from datetime import date, time, timedelta
from ..db import supabase

SLOT_MINUTES = 15


def get_available_slots(doctor_id: str, from_date: date, days: int = 14) -> dict:
    """
    Returns {date_str: [{"start": "09:00", "end": "09:15"}, ...], ...}

    Algorithm:
      1. Get doctor's recurring weekly schedule
      2. Get one-off blocks in the date range
      3. Get confirmed bookings in the date range
      4. For each date: available = recurring − blocks − bookings
      5. Split into SLOT_MINUTES increments
    """
    end_date = from_date + timedelta(days=days)

    schedules = (
        supabase.table("doctor_schedules")
        .select("day_of_week, start_time, end_time")
        .eq("doctor_id", doctor_id)
        .execute()
        .data
    )

    blocks = (
        supabase.table("doctor_slot_blocks")
        .select("date, start_time, end_time")
        .eq("doctor_id", doctor_id)
        .gte("date", str(from_date))
        .lte("date", str(end_date))
        .execute()
        .data
    )

    bookings = (
        supabase.table("bookings")
        .select("scheduled_start")
        .eq("doctor_id", doctor_id)
        .in_("status", ["accepted", "paid", "completed"])
        .gte("scheduled_start", from_date.isoformat())
        .lt("scheduled_start", end_date.isoformat())
        .execute()
        .data
    )

    # "2026-08-21T09:00" — first 16 chars
    booked_set = {b["scheduled_start"][:16] for b in bookings}

    result: dict = {}
    current = from_date

    while current < end_date:
        dow = current.weekday()  # 0 = Monday
        day_str = str(current)

        day_schedules = [s for s in schedules if s["day_of_week"] == dow]
        day_blocks    = [b for b in blocks    if b["date"] == day_str]

        slots = []
        for sched in day_schedules:
            t   = _parse_time(sched["start_time"])
            end = _parse_time(sched["end_time"])

            while _add_minutes(t, SLOT_MINUTES) <= end:
                slot_end = _add_minutes(t, SLOT_MINUTES)
                dt_str   = f"{day_str}T{_fmt(t)}"

                blocked = any(
                    _parse_time(b["start_time"]) <= t < _parse_time(b["end_time"])
                    for b in day_blocks
                )

                if not blocked and dt_str not in booked_set:
                    slots.append({"start": _fmt(t), "end": _fmt(slot_end)})

                t = slot_end

        if slots:
            result[day_str] = slots

        current += timedelta(days=1)

    return result


# ── Helpers ──────────────────────────────────────────────────────────────────

def _parse_time(t: str) -> time:
    """Parse "HH:MM" or "HH:MM:SS" to time."""
    parts = t.split(":")
    return time(int(parts[0]), int(parts[1]))


def _add_minutes(t: time, minutes: int) -> time:
    total = t.hour * 60 + t.minute + minutes
    return time((total // 60) % 24, total % 60)


def _fmt(t: time) -> str:
    return f"{t.hour:02d}:{t.minute:02d}"
