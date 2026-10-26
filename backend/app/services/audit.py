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


def record(user: dict, entity: str, entity_id: Optional[str], action: str,
           reason: Optional[str] = None, metadata: Optional[dict] = None) -> None:
    """
    Record one action by the caller in ``user`` (a decoded session token).

    ``reason`` is the person's own words for an override ("patient called, card
    charged twice"). ``metadata`` holds safe facts such as before and after
    values. Never put clinical detail or secrets in either. The table is
    append-only (migration 0023): a row can't be edited or removed once
    written.

    Best-effort: an audit write must never be the reason the action itself
    fails, but a failed write is logged loudly so it is noticed.
    """
    try:
        _write(user, entity, entity_id, action, reason, metadata)
    except Exception as exc:  # pragma: no cover
        logger.error("failed to record %s on %s/%s: %s", action, entity, entity_id, exc)


def record_or_refuse(user: dict, entity: str, entity_id: Optional[str], action: str,
                     reason: Optional[str] = None, metadata: Optional[dict] = None) -> None:
    """Like record(), but for access that must not happen unrecorded (ops
    reading a prescription): if the audit row can't be written, this raises
    and the caller refuses the access."""
    _write(user, entity, entity_id, action, reason, metadata)


def _write(user: dict, entity: str, entity_id: Optional[str], action: str,
           reason: Optional[str], metadata: Optional[dict]) -> None:
    supabase.table("audit_log").insert({
        "actor_id": _uuid_or_none(user.get("sub")),
        "actor_role": user.get("role", "ops"),
        "entity": entity,
        "entity_id": _uuid_or_none(entity_id),
        "action": action,
        "reason": reason,
        "metadata": metadata or {},
    }).execute()
