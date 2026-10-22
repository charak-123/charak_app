"""
The ops audit trail (``audit_log``).

One writer for every router that lets ops change something — doctor
verification, payouts, ledger adjustments, bill review, complaint status. A
single compromised or careless ops account should never be able to move money
or change a record without leaving a row here saying who did it.
"""
from __future__ import annotations

import logging
import uuid
from typing import Optional

from ..db import supabase

logger = logging.getLogger(__name__)


def _uuid_or_none(value) -> Optional[str]:
    """``audit_log.entity_id`` / ``actor_id`` are uuid columns; anything else
    would fail the insert and lose the record, so it is stored as null."""
    try:
        return str(uuid.UUID(str(value)))
    except (ValueError, TypeError, AttributeError):
        return None


def record(user: dict, entity: str, entity_id: Optional[str], action: str) -> None:
    """
    Record one action by the caller in ``user`` (a decoded session token).

    Best-effort: an audit write must never be the reason the action itself
    fails, but a failed write is logged loudly so it is noticed.
    """
    try:
        supabase.table("audit_log").insert({
            "actor_id": _uuid_or_none(user.get("sub")),
            "actor_role": user.get("role", "ops"),
            "entity": entity,
            "entity_id": _uuid_or_none(entity_id),
            "action": action,
        }).execute()
    except Exception as exc:  # pragma: no cover
        logger.error("failed to record %s on %s/%s: %s", action, entity, entity_id, exc)
