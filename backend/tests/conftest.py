"""
Shared pytest fixtures for backend tests.

Each router imports supabase as `from ..db import supabase`, binding a local name.
Patching `app.db.supabase` won't reach them — we must patch each router module's
own supabase reference. This conftest provides a helper to do that cleanly.
"""
import pytest
from unittest.mock import MagicMock
from fastapi.testclient import TestClient


def make_chain(data=None, list_data=None):
    """Build a mock Supabase query chain."""
    c = MagicMock()
    c.select.return_value = c
    c.insert.return_value = c
    c.update.return_value = c
    c.upsert.return_value = c
    c.delete.return_value = c
    c.eq.return_value = c
    c.in_.return_value = c
    c.gte.return_value = c
    c.lte.return_value = c
    c.lt.return_value = c
    c.order.return_value = c
    c.single.return_value = c
    if list_data is not None:
        c.execute.return_value = MagicMock(data=list_data)
    elif data is not None:
        c.execute.return_value = MagicMock(data=data)
    else:
        c.execute.return_value = MagicMock(data=[])
    return c


def make_supabase(table_map: dict) -> MagicMock:
    """
    Build a mock supabase client.
    table_map: {"table_name": chain_mock_or_callable, ...}
    Unrecognised tables return an empty chain.
    """
    mock = MagicMock()

    def _table(name):
        val = table_map.get(name, make_chain(list_data=[]))
        return val() if callable(val) and not isinstance(val, MagicMock) else val

    mock.table.side_effect = _table
    return mock


# All router module paths that import `supabase`
_ROUTER_SUPABASE_PATHS = [
    "app.routers.bookings.supabase",
    "app.routers.intake.supabase",
    "app.routers.calls.supabase",
    "app.routers.procedure_bills.supabase",
    "app.routers.earnings.supabase",
    "app.routers.push.supabase",
    "app.routers.doctors.supabase",
    "app.routers.auth.supabase",
    "app.routers.categories.supabase",
    "app.routers.schedules.supabase",
    "app.routers.slot_blocks.supabase",
]
