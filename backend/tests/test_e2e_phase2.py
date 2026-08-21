"""
Phase 2 E2E integration test — scripted fake doctor + fake patient flow.

Simulates the full doctor-side MVP:
  1. Patient creates booking (requested)
  2. Doctor lists incoming requests → sees it
  3. Doctor adds a clarification call → completes it with notes
  4. Doctor accepts booking
  5. Doctor marks booking complete (home visit)
  6. Doctor submits procedure bill (below threshold → auto approved)
  7. Doctor views earnings → sees the booking + bill
  8. Doctor views earnings → pending-review amount is 0 (bill was auto-approved)

All Supabase calls are mocked at the router module level.
"""
from unittest.mock import MagicMock, patch, call as mock_call
import pytest
from fastapi.testclient import TestClient
from app.main import app
from tests.conftest import make_chain, make_supabase

DOCTOR_TOKEN  = "Bearer doc_token"
PATIENT_TOKEN = "Bearer pat_token"
DOC_PAYLOAD  = {"sub": "doc-1", "role": "doctor"}
PAT_PAYLOAD  = {"sub": "pat-1", "role": "patient"}
JWT_TARGET   = "app.deps.jwt"

BOOKING_ID = "bk-e2e-1"
CALL_ID    = "call-e2e-1"
BILL_ID    = "bill-e2e-1"

# ── Shared booking states ─────────────────────────────────────────────────────

def _booking(status="requested"):
    return {
        "id": BOOKING_ID,
        "patient_id": "pat-1",
        "doctor_id": "doc-1",
        "channel": "home_visit",
        "scheduled_start": "2026-08-26T10:00:00+00:00",
        "status": status,
        "price_confirmed": 800.0,
        "users": {"name": "Ramesh Kumar", "phone": "+919876543210"},
        "decision_at": None,
    }

# ── Step 1: Patient creates booking ──────────────────────────────────────────

def test_step1_patient_creates_booking():
    verified_doc  = make_chain(data={"id": "doc-1", "verification_status": "verified"})
    no_conflict   = make_chain(list_data=[])
    created       = make_chain(list_data=[_booking("requested")])

    bookings_calls = {"n": 0}
    bookings_chain = make_chain()
    def bk_execute():
        bookings_calls["n"] += 1
        if bookings_calls["n"] == 1:
            return MagicMock(data=[])              # slot check
        return MagicMock(data=[_booking("requested")])  # insert
    bookings_chain.execute.side_effect = bk_execute

    mock_db = make_supabase({"doctors": verified_doc, "bookings": bookings_chain})

    with patch("app.routers.bookings.supabase", mock_db), patch(JWT_TARGET) as jw:
        jw.decode.return_value = PAT_PAYLOAD
        client = TestClient(app)
        resp = client.post("/bookings/", json={
            "doctor_id": "doc-1",
            "channel": "home_visit",
            "scheduled_start": "2026-08-26T10:00:00+00:00",
            "price_confirmed": 800.0,
        }, headers={"Authorization": PATIENT_TOKEN})

    assert resp.status_code == 201
    assert resp.json()["status"] == "requested"


# ── Step 2: Doctor lists incoming ────────────────────────────────────────────

def test_step2_doctor_sees_incoming_request():
    incoming = [_booking("requested")]
    mock_db = make_supabase({"bookings": make_chain(list_data=incoming)})

    with patch("app.routers.bookings.supabase", mock_db), patch(JWT_TARGET) as jw:
        jw.decode.return_value = DOC_PAYLOAD
        client = TestClient(app)
        resp = client.get("/bookings/doctor/incoming", headers={"Authorization": DOCTOR_TOKEN})

    assert resp.status_code == 200
    data = resp.json()
    assert len(data) == 1
    assert data[0]["id"] == BOOKING_ID


# ── Step 3: Doctor initiates clarification call ───────────────────────────────

def test_step3_clarification_call_initiated():
    call_row = {
        "id": CALL_ID, "booking_id": BOOKING_ID,
        "call_status": "initiated", "notes": None,
    }
    calls_chain = make_chain()
    n = {"v": 0}
    def exec_():
        n["v"] += 1
        if n["v"] == 1: return MagicMock(data=[])         # no active calls
        return MagicMock(data=[call_row])                  # inserted
    calls_chain.execute.side_effect = exec_

    mock_db = make_supabase({
        "bookings": make_chain(data=_booking("requested")),
        "clarification_calls": calls_chain,
    })

    with patch("app.routers.calls.supabase", mock_db), patch(JWT_TARGET) as jw:
        jw.decode.return_value = DOC_PAYLOAD
        client = TestClient(app)
        resp = client.post(f"/bookings/{BOOKING_ID}/clarification-call",
                           headers={"Authorization": DOCTOR_TOKEN})

    assert resp.status_code == 201
    assert resp.json()["call_status"] == "initiated"
    assert resp.json()["agora_channel"].startswith("charak_")


# ── Step 4: Doctor completes the call with notes ──────────────────────────────

def test_step4_clarification_call_completed():
    initiated = {
        "id": CALL_ID, "booking_id": BOOKING_ID, "call_status": "initiated",
        "bookings": {"doctor_id": "doc-1"},
    }
    completed = {**initiated, "call_status": "completed", "notes": "Patient has a sprained ankle"}

    chain = make_chain()
    n = {"v": 0}
    def exec_():
        n["v"] += 1
        return MagicMock(data=initiated) if n["v"] == 1 else MagicMock(data=[completed])
    chain.execute.side_effect = exec_

    mock_db = make_supabase({"clarification_calls": chain})
    with patch("app.routers.calls.supabase", mock_db), patch(JWT_TARGET) as jw:
        jw.decode.return_value = DOC_PAYLOAD
        client = TestClient(app)
        resp = client.patch(
            f"/bookings/{BOOKING_ID}/clarification-call/{CALL_ID}/complete",
            json={"notes": "Patient has a sprained ankle"},
            headers={"Authorization": DOCTOR_TOKEN},
        )

    assert resp.status_code == 200
    assert resp.json()["call_status"] == "completed"


# ── Step 5: Doctor accepts the booking ───────────────────────────────────────

def test_step5_doctor_accepts():
    row = _booking("requested")
    accepted = {**row, "status": "accepted"}
    chain = make_chain()
    n = {"v": 0}
    def exec_():
        n["v"] += 1
        return MagicMock(data=row) if n["v"] == 1 else MagicMock(data=[accepted])
    chain.execute.side_effect = exec_

    mock_db = make_supabase({"bookings": chain})
    with patch("app.routers.bookings.supabase", mock_db), patch(JWT_TARGET) as jw:
        jw.decode.return_value = DOC_PAYLOAD
        client = TestClient(app)
        resp = client.patch(f"/bookings/{BOOKING_ID}/accept", headers={"Authorization": DOCTOR_TOKEN})

    assert resp.status_code == 200
    assert resp.json()["status"] == "accepted"


# ── Step 6: Doctor marks booking complete ────────────────────────────────────

def test_step6_booking_completed():
    row = _booking("accepted")
    completed = {**row, "status": "completed"}
    chain = make_chain()
    n = {"v": 0}
    def exec_():
        n["v"] += 1
        return MagicMock(data=row) if n["v"] == 1 else MagicMock(data=[completed])
    chain.execute.side_effect = exec_

    mock_db = make_supabase({"bookings": chain})
    with patch("app.routers.bookings.supabase", mock_db), patch(JWT_TARGET) as jw:
        jw.decode.return_value = DOC_PAYLOAD
        client = TestClient(app)
        resp = client.patch(f"/bookings/{BOOKING_ID}/complete", headers={"Authorization": DOCTOR_TOKEN})

    assert resp.status_code == 200
    assert resp.json()["status"] == "completed"


# ── Step 7: Doctor submits procedure bill (below threshold → auto approved) ───

def test_step7_procedure_bill_approved():
    bill_row = {"id": BILL_ID, "booking_id": BOOKING_ID, "total": 500.0, "status": "approved"}
    bills_chain = make_chain()
    n = {"v": 0}
    def exec_():
        n["v"] += 1
        if n["v"] == 1: return MagicMock(data=[])          # no duplicate
        if n["v"] == 2: return MagicMock(data=[bill_row])  # insert
        return MagicMock(data=[bill_row])                   # update items

    bills_chain.execute.side_effect = exec_

    mock_db = make_supabase({
        "bookings": make_chain(data=_booking("completed")),
        "procedure_bills": bills_chain,
        "doctors": make_chain(data={"id": "doc-1", "procedure_review_threshold": 1000.0}),
    })
    with patch("app.routers.procedure_bills.supabase", mock_db), patch(JWT_TARGET) as jw:
        jw.decode.return_value = DOC_PAYLOAD
        client = TestClient(app)
        resp = client.post(
            f"/bookings/{BOOKING_ID}/procedure-bill",
            json={"items": [{"name": "Dressing", "price": 300}, {"name": "Injection", "price": 200}]},
            headers={"Authorization": DOCTOR_TOKEN},
        )

    assert resp.status_code == 201
    assert resp.json()["status"] == "approved"
    assert resp.json()["needs_review"] is False


# ── Step 8: Earnings shows completed booking + approved bill ──────────────────

def test_step8_earnings_reflect_completed_visit():
    booking_row = {
        "id": BOOKING_ID, "channel": "home_visit",
        "scheduled_start": "2026-08-26T10:00:00+00:00",
        "price_confirmed": 800.0, "status": "completed",
        "users": {"name": "Ramesh Kumar"},
    }
    bill_row = {
        "id": BILL_ID, "booking_id": BOOKING_ID,
        "total": 500.0, "status": "approved", "items": [],
    }

    mock_db = make_supabase({
        "bookings": make_chain(list_data=[booking_row]),
        "procedure_bills": make_chain(list_data=[bill_row]),
    })
    with patch("app.routers.earnings.supabase", mock_db), patch(JWT_TARGET) as jw:
        jw.decode.return_value = DOC_PAYLOAD
        client = TestClient(app)
        resp = client.get("/earnings/me", headers={"Authorization": DOCTOR_TOKEN})

    assert resp.status_code == 200
    data = resp.json()
    assert data["consult_total"] == 800.0
    assert data["procedure_total"] == 500.0
    assert data["grand_total"] == 1300.0
    assert data["pending_review_total"] == 0.0
    assert len(data["items"]) == 1
    assert data["items"][0]["patient_name"] == "Ramesh Kumar"
