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

# The same file can hold live third-party credentials. No test, unit or
# integration, may reach Razorpay, FCM, SMS or a transcription API with them:
# with live Razorpay keys, a refund test would send a real refund request.
# load_dotenv never overrides a variable that is already set, even to "", so
# blanking them here (before app.config is imported) keeps every SDK in stub
# mode. A test that needs "live" behaviour patches live_mode() and the client.
for _credential in (
    "RAZORPAY_KEY_ID", "RAZORPAY_KEY_SECRET", "RAZORPAY_WEBHOOK_SECRET",
    "FCM_PROJECT_ID", "FCM_SERVER_KEY", "GOOGLE_APPLICATION_CREDENTIALS",
    "FIREBASE_ADMIN_CREDENTIALS_JSON", "MSG91_API_KEY", "OPENAI_API_KEY",
    "VERTEX_PROJECT_ID", "AGORA_APP_ID", "AGORA_APP_CERTIFICATE",
):
    os.environ[_credential] = ""

import pytest
from unittest.mock import MagicMock, patch
from fastapi.testclient import TestClient


def _integration(request) -> bool:
    """The integration suite runs against a real local database; the unit
    stand-ins below must not replace what it is there to exercise."""
    return "integration" in request.node.path.parts


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
def _audit_log_is_a_sink(request):
    """
    services/audit.py binds its own `supabase`. Ops routes across several
    routers now write to audit_log through it; without this they would reach
    the real (unconfigured, in-test) client. Tests that assert on the audit
    trail patch `app.services.audit.supabase` themselves.
    """
    if _integration(request):   # real database: nothing to stand in for
        yield
        return
    with patch("app.services.audit.supabase", MagicMock()):
        yield


@pytest.fixture(autouse=True)
def _every_requested_slot_is_open(request):
    """
    create_booking checks the requested time against the doctor's real slot
    grid (bookings._assert_bookable). Booking tests are about what happens
    after that, and use fixed dates that are now in the past, so default to
    "the slot is open". test_security_lockdown.py exercises the real check.
    """
    if _integration(request):   # real database: nothing to stand in for
        yield
        return
    with patch("app.routers.bookings._assert_bookable"):
        yield


@pytest.fixture(autouse=True)
def _notifications_go_nowhere(request):
    """
    Most routes that change a booking also call services/notifications.py,
    which binds its own `supabase` — and many tests patch only their router's.
    Unpatched, every such test tried to insert a notification row (and look up
    a push token) in whatever project backend/.env points at. Default to a
    sink that records nothing and finds no device token, so nothing is sent.
    Tests about notifications patch `app.services.notifications.supabase`
    themselves, which shadows this.
    """
    if _integration(request):   # real database: nothing to stand in for
        yield
        return
    db = MagicMock()
    db.table.return_value = make_chain()
    with patch("app.services.notifications.supabase", db):
        yield


@pytest.fixture(autouse=True)
def _refunds_db_is_a_sink(request):
    """
    services/refunds.py binds its own `supabase`. A cancel or a late capture
    calls it after the router's own writes; unpatched, those calls would reach
    whatever SUPABASE_URL the environment holds. Tests about refunds patch
    `app.services.refunds.supabase` themselves, which shadows this.
    """
    if _integration(request):   # real database: nothing to stand in for
        yield
        return
    db = MagicMock()
    db.table.return_value = make_chain()
    with patch("app.services.refunds.supabase", db):
        yield


class TransitionRecorder:
    """
    Stands in for the transition_booking() SQL function in the unit suite.

    Every call is recorded (``calls``: event, params) and answered the way the
    function answers a permitted move: outcome 'ok', the booking with its new
    status and the patch applied. The rules themselves, ownership, compare-and-
    set, allowed roles and refusals, run against real Postgres in
    tests/integration/test_state_machine.py. A test that needs a refusal sets
    ``refuse = (outcome, current_status)``.
    """

    TO_STATUS = {
        "accept": "accepted", "decline": "declined", "cancel": "cancelled",
        "pay": "paid", "complete": "completed", "no_show": "no_show",
        "hold_expire": "cancelled", "request_expire": "cancelled",
        "start_consultation": "in_progress", "end_consultation": "consulted",
    }

    def __init__(self):
        self.calls: list[dict] = []
        self.refuse = None

    def rpc(self, name, params):
        data = None
        if name == "transition_booking":
            self.calls.append(params)
            if self.refuse:
                outcome, status = self.refuse
                data = {"outcome": outcome, "status": status}
            else:
                status = self.TO_STATUS[params["p_event"]]
                data = {"outcome": "ok", "status": status,
                        "booking": {"id": params["p_booking_id"], "status": status,
                                    **(params.get("p_patch") or {})}}
        result = MagicMock()
        result.execute.return_value = MagicMock(data=data)
        return result

    def last(self, event=None):
        calls = [c for c in self.calls if event is None or c["p_event"] == event]
        return calls[-1] if calls else None


@pytest.fixture(autouse=True)
def transitions(request):
    """The state machine's stand-in (see TransitionRecorder). Tests that care
    take it as an argument to inspect or refuse transitions."""
    if _integration(request):
        yield None
        return
    recorder = TransitionRecorder()
    db = MagicMock()
    db.rpc.side_effect = recorder.rpc
    db.table.return_value = make_chain()
    with patch("app.services.booking_state.supabase", db):
        yield recorder


@pytest.fixture(autouse=True)
def _platform_services_are_sinks(request):
    """
    Modules from migration 0023 that bind their own ``supabase``: the webhook
    inbox (every delivery is new), the job queue (nothing due), idempotency
    keys (only used when a test sends the header) and app_config (empty, so
    defaults apply). Tests about each patch it themselves.
    """
    if _integration(request):
        yield
        return
    from app.services import app_config

    config_db = MagicMock()
    config_db.table.return_value = make_chain(list_data=[])
    jobs_db = MagicMock()
    jobs_db.rpc.return_value.execute.return_value = MagicMock(data=[])
    app_config.clear_cache()
    with patch("app.services.webhook_inbox.supabase", MagicMock()), \
         patch("app.services.jobs.supabase", jobs_db), \
         patch("app.services.idempotency.supabase", MagicMock()), \
         patch("app.services.app_config.supabase", config_db):
        yield
    app_config.clear_cache()


@pytest.fixture(autouse=True)
def _visit_services_are_sinks(request):
    """
    services/visits.py and services/prescriptions.py (migration 0025) bind
    their own ``supabase``: call joins, reminders and the completion backstop
    write nowhere and find nothing. tests/test_visit.py patches them itself.
    """
    if _integration(request):
        yield
        return
    db = MagicMock()
    db.table.return_value = make_chain(list_data=[])
    db.rpc.return_value.execute.return_value = MagicMock(data={})
    with patch("app.services.visits.supabase", db), \
         patch("app.services.prescriptions.supabase", db):
        yield


class _FollowBookingsDb:
    """Forwards to whatever ``app.routers.bookings.supabase`` is right now."""

    def __getattr__(self, name):
        import app.routers.bookings as bookings
        return getattr(bookings.supabase, name)


class _FollowRatingsDb:
    """Forwards to whatever ``app.routers.ratings.supabase`` is right now."""

    def __getattr__(self, name):
        import app.routers.ratings as ratings
        return getattr(ratings.supabase, name)


@pytest.fixture(autouse=True)
def _reviews_read_the_ratings_db(request):
    """services/reviews.py (migration 0027) binds its own ``supabase``; review
    tests mock the ratings router's, and the service reads the same mock.
    Its audit writes go nowhere."""
    if _integration(request):
        yield
        return
    with patch("app.services.reviews.supabase", _FollowRatingsDb()):
        yield


@pytest.fixture(autouse=True)
def _pricing_reads_the_bookings_db(request):
    """
    services/pricing.py (migration 0026) binds its own ``supabase``. Booking
    tests mock the bookings router's client with the doctor's prices in it;
    pricing reads the same mock, so those tests need no second one.
    """
    if _integration(request):
        yield
        return
    with patch("app.services.pricing.supabase", _FollowBookingsDb()):
        yield


DEFAULT_POLICY = {
    "id": "pol-1", "channel": "online_consult", "version": "2026-10-26",
    "rules": [{"when": {}, "refund_pct": 100}], "summary": "Full refund before the start.",
}


@pytest.fixture(autouse=True)
def _policy_and_consent_sinks(request):
    """
    services/cancellation.py and services/legal.py (migration 0024) bind their
    own ``supabase``. Default: one current full-refund policy for any channel,
    and no consent rows (the requirement switches in app_config are off). Tests
    about policies, quotes or consent patch these themselves.
    """
    if _integration(request):
        yield
        return
    policy_db = MagicMock()
    policy_db.table.return_value = make_chain(list_data=[DEFAULT_POLICY])
    legal_db = MagicMock()
    legal_db.table.return_value = make_chain(list_data=[])
    with patch("app.services.cancellation.supabase", policy_db), \
         patch("app.services.legal.supabase", legal_db):
        yield


@pytest.fixture(autouse=True)
def _phone_release_finds_nothing(request):
    """
    services/identity.py binds its own `supabase`. verify-otp and Firebase
    phone sign-in call it before their upsert; without this the call would go
    to whatever SUPABASE_URL the environment holds — a developer's backend/.env
    points at the real project. Tests that exercise the release itself patch
    `app.services.identity.supabase` themselves.
    """
    if _integration(request):   # real database: nothing to stand in for
        yield
        return
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


def rpc_returns(mock_db: MagicMock, data) -> MagicMock:
    """Make every ``mock_db.rpc(...).execute()`` return ``data``."""
    mock_db.rpc.return_value.execute.return_value = MagicMock(data=data)
    return mock_db


def cancelled(row: dict, refunds=()) -> dict:
    """What the cancel_booking() SQL function returns for a successful cancel."""
    return {"outcome": "cancelled", "status": "cancelled",
            "booking": {**row, "status": "cancelled"}, "refunds": list(refunds)}


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
    "app.services.refunds.supabase",
    "app.services.webhook_inbox.supabase",
    "app.services.jobs.supabase",
    "app.services.legal.supabase",
    "app.services.idempotency.supabase",
    "app.services.app_config.supabase",
    "app.services.erasure.supabase",
    "app.services.otp_store.supabase",
    "app.services.availability.supabase",
    "app.services.pricing.supabase",
    "app.routers.addresses.supabase",
    "app.routers.uploads.supabase",
    "app.services.storage.supabase",
    "app.services.transcription.supabase",
]


# Deliberately absent: app.services.booking_state.supabase. The autouse
# `transitions` fixture stands in for transition_booking() there, and a
# generic table mock would answer the RPC with nothing.


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
    Record who was notified, and send nothing.

    Hooked at notify(), where "who is told what" is decided, rather than at
    the sender: with the outbox (migration 0023) nothing reaches the sender
    when a test's fake table can't hand back a row, and these tests are about
    the recipient, not the outbox. The real notify() still runs, so recording
    is exercised; only delivery is stubbed.
    """
    import app.services.notifications as notif
    sent = []
    original = notif.notify

    def _recording_notify(recipient_id, recipient_role, event, title, body,
                          data=None, booking_id=None, background=None, **kwargs):
        sent.append({
            "recipient_id": recipient_id,
            "role": recipient_role,
            "event": event,
            "title": title,
            "body": body,
            "data": {k: str(v) for k, v in (data or {}).items()},
        })
        return original(recipient_id, recipient_role, event, title, body,
                        data, booking_id, background, **kwargs)

    monkeypatch.setattr(notif, "notify", _recording_notify)
    monkeypatch.setattr(notif, "_deliver", lambda *a, **k: None)
    return sent


def pricing_chain(price=500.0):
    """
    A doctor_pricing row for _resolve_price in the bookings router.

    Every create_booking call needs one now that the consult fee is resolved
    server-side from doctor_pricing rather than accepted from the request body.
    """
    return make_chain(data={"price": price})
