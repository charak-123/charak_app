"""
Shared pytest fixtures for backend tests.

Each router imports supabase as `from ..db import supabase`, binding a local name.
Patching `app.db.supabase` won't reach them — we must patch each router module's
own supabase reference. This conftest provides a helper to do that cleanly.
"""
import pytest
from unittest.mock import MagicMock, patch
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
    c.maybe_single.return_value = c
    c.is_.return_value = c
    c.not_.return_value = c
    c.gt.return_value = c
    c.limit.return_value = c
    c.range.return_value = c
    c.ilike.return_value = c
    if list_data is not None:
        c.execute.return_value = MagicMock(data=list_data)
    elif data is not None:
        c.execute.return_value = MagicMock(data=data)
    else:
        c.execute.return_value = MagicMock(data=[])
    return c


def make_chain_seq(*execute_data_list):
    """Chain whose execute() returns successive data values on each call."""
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
    c.maybe_single.return_value = c
    c.is_.return_value = c
    c.not_.return_value = c
    c.gt.return_value = c
    c.limit.return_value = c
    c.range.return_value = c
    c.ilike.return_value = c
    c.execute.side_effect = [MagicMock(data=d) for d in execute_data_list]
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
    "app.routers.ratings.supabase",
    "app.routers.complaints.supabase",
    "app.routers.payments.supabase",
    "app.routers.admin.supabase",
    "app.routers.payouts.supabase",
    "app.routers.notifications.supabase",
    "app.routers.maintenance.supabase",
    "app.services.notifications.supabase",
    "app.services.payouts.supabase",
    "app.services.otp_store.supabase",
    "app.services.availability.supabase",
]


def patch_all_supabase(mock_db):
    """
    Context manager patching every module-level `supabase` binding at once.

    Routers do `from ..db import supabase`, which copies the reference — patching
    `app.db.supabase` alone reaches none of them. Tests that exercise a route
    touching more than one module (a booking that also writes a notification, a
    payment that also credits the ledger) need all of them patched together.
    """
    from contextlib import ExitStack

    stack = ExitStack()
    for path in _ROUTER_SUPABASE_PATHS:
        try:
            stack.enter_context(patch(path, mock_db))
        except (AttributeError, ModuleNotFoundError):  # pragma: no cover
            pass
    return stack


@pytest.fixture
def silent_push(monkeypatch):
    """
    Stop the notification service from attempting delivery.

    Persisting the row is still exercised; only the outbound HTTP call is
    stubbed, so tests assert on what was recorded without needing a network.
    """
    import app.services.notifications as notif
    sent = []

    def _fake_deliver(recipient_id, recipient_role, title, body, data, notification_id):
        sent.append({
            "recipient_id": recipient_id,
            "role": recipient_role,
            "title": title,
            "body": body,
            "data": data,
        })

    monkeypatch.setattr(notif, "_deliver", _fake_deliver)
    return sent
