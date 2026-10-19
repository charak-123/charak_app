from datetime import date, time, timedelta
from ..db import supabase

# Fallback slot length when a doctor has not set one. Doctors choose their own
# consult length per channel (doctor_pricing.base_duration_min).
SLOT_MINUTES = 15

# Statuses that occupy a slot. A `requested` booking holds its time while the
# doctor decides, so it has to disappear from the grid too — otherwise a second
# patient is shown the slot as free, fills in their whole intake, and is turned
# away with "Slot already booked" at the last step. `completed` is here so a
# past visit does not reopen its own slot.
SLOT_OCCUPYING_STATUSES = ["requested", "accepted", "paid", "completed"]


def get_available_slots(doctor_id: str, from_date: date, days: int = 14) -> dict:
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
    """
    slot_minutes = slot_minutes_for(doctor_id)
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
        .in_("status", SLOT_OCCUPYING_STATUSES)
        .gte("scheduled_start", from_date.isoformat())
        .lt("scheduled_start", end_date.isoformat())
        .execute()
        .data
    )

    # Booked start times per day as minutes-since-midnight. A booking holds
    # [start, start + slot_minutes); comparing ranges rather than exact start
    # strings keeps an old booking blocking its time after the doctor changes
    # their consult length and the grid shifts.
    booked: dict[str, list[int]] = {}
    for b in bookings:
        start = b["scheduled_start"]
        booked.setdefault(start[:10], []).append(int(start[11:13]) * 60 + int(start[14:16]))

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

                if not blocked and not taken:
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
