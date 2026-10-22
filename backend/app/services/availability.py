from datetime import date, datetime, time, timedelta, timezone
from typing import Optional

from ..db import supabase

# Fallback slot length when a doctor has not set one. Doctors choose their own
# consult length per channel (doctor_pricing.base_duration_min).
SLOT_MINUTES = 15

# Doctors' schedules are wall-clock times in India, and the patient app books
# them as "+05:30". India has no daylight saving, so a fixed offset is exact
# (and needs no tz database in the slim container image).
IST = timezone(timedelta(hours=5, minutes=30))

# How soon a slot can start and still be offered. The doctor has to accept and
# the patient has to pay inside the hold window before the visit begins.
MIN_LEAD_MINUTES = 15


def now_ist() -> datetime:
    return datetime.now(IST)


def to_ist(ts) -> datetime:
    """A stored timestamptz (any offset, 'Z' tolerated) as an IST datetime."""
    dt = ts if isinstance(ts, datetime) else datetime.fromisoformat(str(ts).replace("Z", "+00:00"))
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=IST)
    return dt.astimezone(IST)

# Statuses that occupy a slot. A `requested` booking holds its time while the
# doctor decides, so it has to disappear from the grid too — otherwise a second
# patient is shown the slot as free, fills in their whole intake, and is turned
# away with "Slot already booked" at the last step. `completed` is here so a
# past visit does not reopen its own slot.
SLOT_OCCUPYING_STATUSES = ["requested", "accepted", "paid", "completed"]


def get_available_slots(doctor_id: str, from_date: date, days: int = 14,
                        now: Optional[datetime] = None) -> dict:
    """
    Returns {date_str: [{"start": "09:00", "end": "09:15"}, ...], ...}

    Algorithm:
      1. Get doctor's recurring weekly schedule
      2. Get one-off blocks in the date range
      3. Get confirmed bookings in the date range
      4. For each date: available = recurring − blocks − bookings
      5. Split into slots of the doctor's consult length

    The patient picks a time before choosing a channel, so the grid uses the
    longest consult length the doctor offers — a slot then fits either channel.

    Everything is in IST. Slots starting within MIN_LEAD_MINUTES of `now` (or
    already past) are not offered.
    """
    slot_minutes = slot_minutes_for(doctor_id)
    end_date = from_date + timedelta(days=days)
    earliest = (now or now_ist()).astimezone(IST) + timedelta(minutes=MIN_LEAD_MINUTES)

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
        .in_("status", SLOT_OCCUPYING_STATUSES)
        .gte("scheduled_start", datetime.combine(from_date, time(0), IST).isoformat())
        .lt("scheduled_start", datetime.combine(end_date, time(0), IST).isoformat())
        .execute()
        .data
    )

    # Booked start times per IST day as minutes-since-midnight. A booking holds
    # [start, start + slot_minutes); comparing ranges rather than exact start
    # strings keeps an old booking blocking its time after the doctor changes
    # their consult length and the grid shifts.
    #
    # Converted, not sliced: the database hands timestamptz back in UTC, so
    # reading the hour straight off the string put a 09:00 IST booking at
    # 03:30 — the real slot stayed on offer and an unrelated one disappeared.
    booked: dict[str, list[int]] = {}
    for b in bookings:
        start = to_ist(b["scheduled_start"])
        booked.setdefault(str(start.date()), []).append(start.hour * 60 + start.minute)

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

            while _minutes(t) + slot_minutes <= _minutes(end):
                slot_end = _add_minutes(t, slot_minutes)
                start_m  = _minutes(t)

                blocked = any(
                    _parse_time(b["start_time"]) <= t < _parse_time(b["end_time"])
                    for b in day_blocks
                )

                taken = any(
                    abs(start_m - m) < slot_minutes for m in booked.get(day_str, [])
                )

                too_soon = datetime.combine(current, t, IST) < earliest

                if not blocked and not taken and not too_soon:
                    slots.append({"start": _fmt(t), "end": _fmt(slot_end)})

                t = slot_end

        if slots:
            result[day_str] = slots

        current += timedelta(days=1)

    return result


def slot_minutes_for(doctor_id: str) -> int:
    rows = (
        supabase.table("doctor_pricing")
        .select("base_duration_min")
        .eq("doctor_id", doctor_id)
        .execute()
        .data
    ) or []
    lengths = [r["base_duration_min"] for r in rows if r.get("base_duration_min")]
    return max(lengths) if lengths else SLOT_MINUTES


# ── Helpers ──────────────────────────────────────────────────────────────────

def _parse_time(t: str) -> time:
    """Parse "HH:MM" or "HH:MM:SS" to time."""
    parts = t.split(":")
    return time(int(parts[0]), int(parts[1]))


def _add_minutes(t: time, minutes: int) -> time:
    total = t.hour * 60 + t.minute + minutes
    return time((total // 60) % 24, total % 60)


def _minutes(t: time) -> int:
    return t.hour * 60 + t.minute


def _fmt(t: time) -> str:
    return f"{t.hour:02d}:{t.minute:02d}"
