"""
Fixtures for the integration suite — real Postgres, real PostgREST, real SQL.

The sibling suite in tests/ mocks the Supabase client, which makes it fast and
makes it blind: it never executes a statement, so constraints, RLS policies,
triggers and column names are all unverified there, and a query naming a column
that does not exist passes exactly as green as a correct one.

Nothing here is patched except JWT decoding. The routers bind ``supabase`` from
app.db at import time, and app.db reads SUPABASE_URL from the environment, so
pointing the env at the local stack is enough to make the real code talk to a real
database — no seam, no test double.

Run ``./stack.sh up`` first; without CHARAK_INTEGRATION the whole directory skips,
so the default ``pytest`` run stays green on a machine with no Docker.
"""
import os
import uuid

import pytest

pytestmark = pytest.mark.integration

if not os.getenv("CHARAK_INTEGRATION"):
    pytest.skip(
        "integration stack not running — start it with tests/integration/stack.sh up",
        allow_module_level=True,
    )

from urllib.parse import urlparse                # noqa: E402

# clean_db below deletes every row of every table. CHARAK_INTEGRATION alone is
# not enough of a guard: with it set and backend/.env pointing at the live
# project, this suite would wipe production. Refuse anything but the local stack.
_host = urlparse(os.getenv("SUPABASE_URL", "")).hostname
if _host not in ("localhost", "127.0.0.1", "::1"):
    pytest.exit(
        f"integration suite refuses to run against {_host!r}: it deletes every "
        "row in every table. Point SUPABASE_URL at the local stack (stack.sh up).",
        returncode=2,
    )

from app.db import supabase                     # noqa: E402 — after the skip guard

# Every table the suite writes to, ordered children-before-parents so plain
# DELETEs satisfy the foreign keys without needing superuser TRUNCATE CASCADE.
_TABLES = [
    "device_tokens", "refunds", "doctor_ledger_entries", "payouts", "payments",
    "procedure_bills", "ratings",
    "complaints", "clarification_calls", "intake_media", "notifications",
    "bookings", "patient_addresses", "doctor_slot_blocks", "doctor_schedules",
    "doctor_pricing", "doctor_procedures", "doctors", "users", "categories",
]


@pytest.fixture(autouse=True)
def clean_db():
    """A blank database per test — order matters, so no test inherits state."""
    for table in _TABLES:
        try:
            supabase.table(table).delete().neq(
                "id", "00000000-0000-0000-0000-000000000000"
            ).execute()
        except Exception:
            # A table this migration set does not have yet is not a failure here.
            pass
    # Tables keyed by something other than a uuid id (0023). booking_events and
    # audit_log are append-only; booking_events goes with its bookings.
    for table, column, value in (("jobs", "id", 0), ("webhook_events", "id", 0)):
        try:
            supabase.table(table).delete().gte(column, value).execute()
        except Exception:
            pass
    try:
        supabase.table("idempotency_keys").delete().neq("key", "").execute()
    except Exception:
        pass
    # Policy and document versions a test published (stack.sh helper).
    try:
        supabase.rpc("test_forget_test_versions").execute()
    except Exception:
        pass
    yield


@pytest.fixture
def db():
    return supabase


def _id() -> str:
    return str(uuid.uuid4())


@pytest.fixture
def seed():
    """
    Insert the minimum real rows a booking needs, and hand back their ids.

    Deliberately inserts through the same client the routers use, so a column
    named wrongly here fails the same way it would in production.
    """
    def _seed(*, verified=True, offers_home_visit=False, radius_km=5):
        category = supabase.table("categories").insert(
            {"id": _id(), "name": f"Cat {_id()[:8]}"}
        ).execute().data[0]

        patient = supabase.table("users").insert(
            {"id": _id(), "phone": f"+9190{_id().replace('-', '')[:8]}",
             "name": "Test Patient", "otp_verified": True}
        ).execute().data[0]

        other_patient = supabase.table("users").insert(
            {"id": _id(), "phone": f"+9191{_id().replace('-', '')[:8]}",
             "name": "Other Patient", "otp_verified": True}
        ).execute().data[0]

        doctor = supabase.table("doctors").insert(
            {"id": _id(), "phone": f"+9192{_id().replace('-', '')[:8]}",
             "name": "Dr Test", "category_id": category["id"],
             "verification_status": "verified" if verified else "pending",
             "offers_online_consult": True,
             "offers_home_visit": offers_home_visit,
             "service_radius_km": radius_km,
             "base_lat": 19.0760, "base_lng": 72.8777,
             "otp_verified": True}
        ).execute().data[0]

        # A doctor with no published price cannot be booked at all: the consult
        # fee is resolved server-side from doctor_pricing, so every channel the
        # doctor offers needs a row or create_booking refuses with a 409.
        pricing = [{"id": _id(), "doctor_id": doctor["id"],
                    "channel": "online_consult", "price": 500.00}]
        if offers_home_visit:
            pricing.append({"id": _id(), "doctor_id": doctor["id"],
                            "channel": "home_visit", "price": 800.00})
        supabase.table("doctor_pricing").insert(pricing).execute()

        # create_booking only accepts a time on the doctor's real slot grid, so
        # the doctor works every day, all day, in the default 15-minute slots.
        supabase.table("doctor_schedules").insert([
            {"id": _id(), "doctor_id": doctor["id"], "day_of_week": d,
             "start_time": "00:00", "end_time": "23:59"}
            for d in range(7)
        ]).execute()

        return {"category": category, "patient": patient,
                "other_patient": other_patient, "doctor": doctor,
                "pricing": pricing}

    return _seed


# Sessions in this suite are real HS256 tokens signed with a test-only secret,
# so two clients in one test really are two different people. (The suite used
# to patch the JWT decoder globally, so the second client created silently
# took over the first one's identity.)
TEST_JWT_SECRET = "integration-suite-jwt-secret-0123456789abcdef"


@pytest.fixture
def client_for():
    """
    A TestClient signed in as ``user_id`` with ``role``, through the real
    authentication path: the token is verified by app.deps exactly as in
    production, with the suite's own secret. Every database call is real.
    """
    import time

    import jwt
    from unittest.mock import patch
    from fastapi.testclient import TestClient
    from app.main import app

    patches = [patch("app.deps.JWT_SECRET", TEST_JWT_SECRET),
               patch("app.services.idempotency.JWT_SECRET", TEST_JWT_SECRET)]
    for p in patches:
        p.start()

    def make(user_id, role="patient", admin_role="admin"):
        claims = {"sub": user_id, "role": role, "iat": int(time.time()) - 5}
        if role == "ops":
            claims["admin_role"] = admin_role
        token = jwt.encode(claims, TEST_JWT_SECRET, algorithm="HS256")
        return TestClient(app, headers={"Authorization": f"Bearer {token}"})

    yield make
    for p in patches:
        p.stop()


# Kept for the call sites: each client already carries its own token, and an
# explicit Authorization header would override it.
AUTH: dict = {}
