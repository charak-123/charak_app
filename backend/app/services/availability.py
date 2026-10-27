from datetime import date, datetime, time, timedelta, timezone
from typing import Optional

from ..db import supabase

# Fallback slot length when a doctor has not set one. Doctors price each
# channel by length (doctor_price_rules, migration 0026).
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
# away with "Slot already booked" at the last step. `in_progress`, `consulted`
# and `completed` are here so a visit under way or past does not reopen its own
# slot.
SLOT_OCCUPYING_STATUSES = ["requested", "accepted", "paid", "in_progress", "consulted", "completed"]


def get_available_slots(doctor_id: str, from_date: date, days: int = 14,
                        now: Optional[datetime] = None,
                        duration_min: Optional[int] = None) -> dict:
    """
    Returns {date_str: [{"start": "09:00", "end": "09:15"}, ...], ...}

    Algorithm:
      1. Get doctor's recurring weekly schedule
      2. Get one-off blocks in the date range
      3. Get live bookings in the date range, as [start, end) ranges
      4. For each date, offer each start whose [start, start + duration) fits
         the schedule and overlaps no block and no booking

    ``duration_min`` is the length the patient picked (migration 0026). Starts
    are every ``duration_min`` minutes for a short visit, every 15 for a
    longer one, from the start of each schedule block. Without it (app builds
    from before 0026, which pick the time before the channel) the grid uses
    the longest first-visit length the doctor offers, so a slot fits either
    channel, and steps by that length, as before.

    Everything is in IST. Slots starting within MIN_LEAD_MINUTES of `now` (or
    already past) are not offered.
    """
    if duration_min is None:
        length = slot_minutes_for(doctor_id)
        step = length
    else:
        length = duration_min
        step = duration_min if duration_min < 15 else 15
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

    # A booking that started the evening before can still run into this range.
    bookings = (
        supabase.table("bookings")
        .select("scheduled_start, scheduled_end, duration_min")
        .eq("doctor_id", doctor_id)
        .in_("status", SLOT_OCCUPYING_STATUSES)
        .gte("scheduled_start", (datetime.combine(from_date, time(0), IST) - timedelta(hours=4)).isoformat())
        .lt("scheduled_start", datetime.combine(end_date, time(0), IST).isoformat())
        .execute()
        .data
    )

    # Booked ranges in IST. Converted, not sliced: the database hands
    # timestamptz back in UTC, so reading the hour straight off the string put
    # a 09:00 IST booking at 03:30.
    booked: list[tuple[datetime, datetime]] = []
    for b in bookings:
        start = to_ist(b["scheduled_start"])
        end = (to_ist(b["scheduled_end"]) if b.get("scheduled_end")
               else start + timedelta(minutes=b.get("duration_min") or length))
        booked.append((start, end))

    result: dict = {}
    current = from_date

    while current < end_date:
        dow = current.weekday()  # 0 = Monday
        day_str = str(current)

        day_schedules = [s for s in schedules if s["day_of_week"] == dow]
        day_blocks = [
            (datetime.combine(current, _parse_time(b["start_time"]), IST),
             datetime.combine(current, _parse_time(b["end_time"]), IST))
            for b in blocks if b["date"] == day_str
        ]

        slots = []
        for sched in sorted(day_schedules, key=lambda s: s["start_time"]):
            t = datetime.combine(current, _parse_time(sched["start_time"]), IST)
            close = datetime.combine(current, _parse_time(sched["end_time"]), IST)

            while t + timedelta(minutes=length) <= close:
                slot_end = t + timedelta(minutes=length)
                blocked = any(s < slot_end and t < e for s, e in day_blocks)
                taken = any(s < slot_end and t < e for s, e in booked)
                if not blocked and not taken and t >= earliest:
                    slots.append({"start": _fmt(t.time()), "end": _fmt(slot_end.time())})
                t += timedelta(minutes=step)

        if slots:
            result[day_str] = slots

        current += timedelta(days=1)

    return result


def slot_minutes_for(doctor_id: str) -> int:
    """The legacy grid length: the longest first-visit length the doctor
    prices, so a slot fits whichever channel is picked after it."""
    rules = (
        supabase.table("doctor_price_rules")
        .select("duration_min")
        .eq("doctor_id", doctor_id).eq("visit_category", "initial")
        .is_("effective_until", "null")
        .execute()
        .data
    ) or []
    lengths = [r["duration_min"] for r in rules if r.get("duration_min")]
    if not lengths:
        rows = (
            supabase.table("doctor_pricing").select("base_duration_min")
            .eq("doctor_id", doctor_id).execute().data
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
