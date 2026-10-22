"""
Who owns a phone number.

A number reaches a ``users``/``doctors`` row two ways: typed into the profile
step after Google sign-in (a claim — ``otp_verified`` false), or proven by an
OTP or a Firebase phone token (``otp_verified`` true). Phone sign-in looks the
account up by number, so a claim must never outrank proof: otherwise anyone
could type a stranger's number into their own profile and, the day that
stranger first signed in by OTP, receive them into the claimant's account —
bookings, addresses and intake included.

When someone proves a number, every row that merely claimed it lets go.
"""
from __future__ import annotations

import logging
from typing import Optional

from ..db import supabase

logger = logging.getLogger(__name__)


def release_unproven_phone(table: str, phone: str,
                           keep_firebase_uid: Optional[str] = None) -> int:
    """
    Clear ``phone`` from every row in ``table`` that holds it without having
    proven it. Returns how many rows were released.

    ``keep_firebase_uid`` spares the row the caller is signing into, so a
    returning Firebase phone user is not released from their own number.
    """
    rows = (
        supabase.table(table)
        .select("id, firebase_uid")
        .eq("phone", phone)
        .eq("otp_verified", False)
        .execute()
        .data
        or []
    )
    released = 0
    for row in rows:
        if keep_firebase_uid and row.get("firebase_uid") == keep_firebase_uid:
            continue
        supabase.table(table).update({"phone": None}).eq("id", row["id"]).execute()
        logger.info("released unproven phone from %s/%s", table, row["id"])
        released += 1
    return released
