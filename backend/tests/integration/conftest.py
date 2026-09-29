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

from app.db import supabase                     # noqa: E402 — after the skip guard

# Every table the suite writes to, ordered children-before-parents so plain
# DELETEs satisfy the foreign keys without needing superuser TRUNCATE CASCADE.
_TABLES = [
    "doctor_ledger_entries", "payments", "procedure_bills", "ratings",
    "complaints", "clarification_calls", "intake_media", "notifications",
    "bookings", "patient_addresses", "slot_blocks", "schedules",
    "doctor_pricing", "procedures", "doctors", "users", "categories",
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

        return {"category": category, "patient": patient,
                "other_patient": other_patient, "doctor": doctor,
                "pricing": pricing}

    return _seed


@pytest.fixture
def client_for():
    """
    TestClient authenticated as a given user id and role.

    Only the JWT decode is faked; every database call underneath is real.
    """
    from unittest.mock import patch
    from fastapi.testclient import TestClient
    from app.main import app

    class _Ctx:
        def __init__(self):
            self._stack = []

        def __call__(self, user_id, role="patient"):
            p = patch("app.deps.jwt")
            jw = p.start()
            jw.decode.return_value = {"sub": user_id, "role": role}
            self._stack.append(p)
            return TestClient(app)

        def close(self):
            for p in self._stack:
                p.stop()

    ctx = _Ctx()
    yield ctx
    ctx.close()


AUTH = {"Authorization": "Bearer test-token"}
