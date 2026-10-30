"""
When a doctor can be booked, channel by channel.

Verification says who the doctor is; it says nothing about whether a patient
can book them. A doctor verified before finishing setup used to appear in the
directory with no price and no hours: a patient could open the profile, pick
"Home visit", and find nothing to book. A channel is bookable once the doctor
offers it, has priced it, has hours for it, and, for home visits, has pinned
the base location the service radius is measured from.

Everything here reads a doctor row fetched with its ``doctor_pricing(*)`` and
``doctor_schedules(*)`` embedded, so the directory decides this without a
query per doctor.
"""
from __future__ import annotations

from .availability import CHANNELS, applies_to

_OFFERS = {"online_consult": "offers_online_consult", "home_visit": "offers_home_visit"}


def missing(doctor: dict, channel: str) -> list[str]:
    """What the doctor still has to add before ``channel`` can be booked:
    any of "price", "hours", "base_location". Empty when it is bookable.
    Not meaningful for a channel the doctor doesn't offer."""
    out = []
    prices = [p for p in doctor.get("doctor_pricing") or [] if p.get("channel") == channel]
    if not any(float(p.get("price") or 0) > 0 for p in prices):
        out.append("price")
    if not any(applies_to(s, channel) for s in doctor.get("doctor_schedules") or []):
        out.append("hours")
    if channel == "home_visit" and (doctor.get("base_lat") is None or doctor.get("base_lng") is None):
        out.append("base_location")
    return out


def bookable_channels(doctor: dict) -> list[str]:
    return [c for c in CHANNELS if doctor.get(_OFFERS[c]) and not missing(doctor, c)]


def mask(doctor: dict) -> dict:
    """The row as patients should see it: a channel that isn't bookable yet
    is not offered, and its price isn't shown."""
    ready = bookable_channels(doctor)
    out = {**doctor}
    for c in CHANNELS:
        out[_OFFERS[c]] = c in ready
    if isinstance(out.get("doctor_pricing"), list):
        out["doctor_pricing"] = [p for p in out["doctor_pricing"] if p.get("channel") in ready]
    return out


def summary(doctor: dict) -> dict:
    """For the doctor's own app: whether patients can find them, and what
    each offered channel still needs."""
    channels = {
        c: {"offered": bool(doctor.get(_OFFERS[c])),
            "missing": missing(doctor, c) if doctor.get(_OFFERS[c]) else []}
        for c in CHANNELS
    }
    ready = bookable_channels(doctor)
    return {
        "visible": (doctor.get("verification_status") == "verified"
                    and not doctor.get("suspended")
                    and doctor.get("accepting_requests", True) is not False
                    and bool(ready)),
        "bookable_channels": ready,
        "channels": channels,
    }
