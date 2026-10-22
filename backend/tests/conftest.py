"""
Shared pytest fixtures for backend tests.

Each router imports supabase as `from ..db import supabase`, binding a local name.
Patching `app.db.supabase` won't reach them — we must patch each router module's
own supabase reference. This conftest provides a helper to do that cleanly.
"""
import os

# The unit suite must never reach a real database. app.config loads
# backend/.env, which on a developer machine holds the live project's
# service-role key — so any module whose `supabase` a test forgot to patch
# would read and write production. Point the client at a dead local port
# before the app is imported (load_dotenv never overrides a set variable);
# a missed patch then fails loudly instead. The integration suite sets
# CHARAK_INTEGRATION and its own SUPABASE_URL, and is left alone.
if not os.getenv("CHARAK_INTEGRATION"):
    os.environ["SUPABASE_URL"] = "http://127.0.0.1:9"
    os.environ["SUPABASE_ANON_KEY"] = "unit-tests-have-no-database"
    os.environ["SUPABASE_SERVICE_ROLE_KEY"] = "unit-tests-have-no-database"

import pytest
from unittest.mock import MagicMock, patch
from fastapi.testclient import TestClient


@pytest.fixture(autouse=True)
def _no_revoked_sessions():
    """
    app.deps.get_current_user looks up sessions_revoked_at on every
    authenticated request (see test_deps.py for that behaviour itself). Every
    other test in the suite authenticates via `patch("app.deps.jwt")` and has
    no reason to care about revocation, so this default stands in for "never
    revoked" everywhere, the same way a real account with no revocation ever
    recorded behaves. A test that wants the other behaviour patches
    `app.deps.supabase` itself, which simply shadows this for its own `with`
    block.
    """
    def table(name):
        t = MagicMock()
        # An ops token stays valid while its admin_users row exists.
        rows = [{"id": "admin"}] if name == "admin_users" else []
        t.select.return_value.eq.return_value.execute.return_value = MagicMock(data=rows)
        return t

    db = MagicMock()
    db.table.side_effect = table
    with patch("app.deps.supabase", db):
        yield


@pytest.fixture(autouse=True)
def _rate_limit_never_triggers():
    """
    Several routes now carry a `rate_limiter(...)` dependency (admin login,
    booking creation, uploads — see services/rate_limit.py), which queries
    `rate_limit_hits` on every call. Tests for those routes patch their own
    router module's `supabase`, not rate_limit.py's, so without this they'd
    fall through to the real (unconfigured, in-test) client. Default to "no
    hits recorded yet" everywhere; test_rate_limit.py and the admin-login
    tests that care about 429s patch `app.services.rate_limit.supabase`
    themselves, which simply shadows this for their own `with` block.
    """
    db = MagicMock()
    db.table.return_value.select.return_value.eq.return_value.eq.return_value \
        .gte.return_value.execute.return_value = MagicMock(data=[])
    with patch("app.services.rate_limit.supabase", db):
        yield


@pytest.fixture(autouse=True)
def _audit_log_is_a_sink():
    """
    services/audit.py binds its own `supabase`. Ops routes across several
    routers now write to audit_log through it; without this they would reach
    the real (unconfigured, in-test) client. Tests that assert on the audit
    trail patch `app.services.audit.supabase` themselves.
    """
    with patch("app.services.audit.supabase", MagicMock()):
        yield


@pytest.fixture(autouse=True)
def _notifications_go_nowhere():
    """
    Most routes that change a booking also call services/notifications.py,
    which binds its own `supabase` — and many tests patch only their router's.
    Unpatched, every such test tried to insert a notification row (and look up
    a push token) in whatever project backend/.env points at. Default to a
    sink that records nothing and finds no device token, so nothing is sent.
    Tests about notifications patch `app.services.notifications.supabase`
    themselves, which shadows this.
    """
    db = MagicMock()
    db.table.return_value = make_chain()
    with patch("app.services.notifications.supabase", db):
        yield


@pytest.fixture(autouse=True)
def _phone_release_finds_nothing():
    """
    services/identity.py binds its own `supabase`. verify-otp and Firebase
    phone sign-in call it before their upsert; without this the call would go
    to whatever SUPABASE_URL the environment holds — a developer's backend/.env
    points at the real project. Tests that exercise the release itself patch
    `app.services.identity.supabase` themselves.
    """
    db = MagicMock()
    db.table.return_value.select.return_value.eq.return_value.eq.return_value \
        .execute.return_value = MagicMock(data=[])
    with patch("app.services.identity.supabase", db):
        yield


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
    "app.routers.consents.supabase",
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
    "app.services.erasure.supabase",
    "app.services.otp_store.supabase",
    "app.services.availability.supabase",
    "app.routers.addresses.supabase",
    "app.routers.uploads.supabase",
    "app.services.storage.supabase",
    "app.services.transcription.supabase",
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


def pricing_chain(price=500.0):
    """
    A doctor_pricing row for _resolve_price in the bookings router.

    Every create_booking call needs one now that the consult fee is resolved
    server-side from doctor_pricing rather than accepted from the request body.
    """
    return make_chain(data={"price": price})
