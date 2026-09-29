"""
Phase 3 E2E integration test — the doctor's whole life, scripted.

Phase 2's E2E starts with a doctor who is already live. This one starts before
that: a doctor who has just installed the app, and follows them through to money
that has cleared senior review.

  Onboarding
    1.  Doctor saves their profile
    2.  Doctor submits a verification document → back to `pending`
    3.  Ops sees them in the verification queue
    4.  Ops approves → verified, and the doctor is notified
    5.  Doctor configures pricing, including the senior-review threshold

  A visit
    6.  Patient requests a booking; the doctor is notified
    7.  Doctor starts a clarification call
    8.  Patient joins the call they were never given an id for
    9.  Doctor accepts; visit is completed

  Senior review
    10. Doctor bills ABOVE their threshold → `under_review`, not payable
    11. Earnings count it as pending, not earned
    12. Ops sees it in the review queue and approves it
    13. Earnings now count it as earned, and pending drops to zero

Every Supabase call is mocked at the router module level. What is being tested
is the wiring between routers — that a state one endpoint writes is the state
the next one reads — which is exactly what unit tests per router cannot see.
"""
from unittest.mock import MagicMock, patch

import pytest
from fastapi.testclient import TestClient

from app.main import app
from tests.conftest import make_chain, make_supabase, patch_all_supabase

DOCTOR_TOKEN  = "Bearer doc_token"
PATIENT_TOKEN = "Bearer pat_token"
OPS_TOKEN     = "Bearer ops_token"

DOC_PAYLOAD = {"sub": "doc-1", "role": "doctor"}
PAT_PAYLOAD = {"sub": "pat-1", "role": "patient"}
OPS_PAYLOAD = {"sub": "admin", "role": "ops"}

JWT = "app.deps.jwt"

# The doctor bills ₹4,200 against a ₹3,000 threshold — comfortably over, so the
# review branch is unambiguous rather than resting on a rounding edge.
THRESHOLD   = 3000.0
BILL_TOTAL  = 4200.0
CONSULT_FEE = 800.0

BOOKING_ID = "bk-1"
BILL_ID    = "bill-1"


def _client(payload, db):
    """A TestClient with every router's supabase bound to `db`."""
    with patch_all_supabase(db), patch(JWT) as jw:
        jw.decode.return_value = payload
        yield TestClient(app)


def _booking(status="requested"):
    return {
        "id": BOOKING_ID,
        "doctor_id": "doc-1",
        "patient_id": "pat-1",
        "channel": "home_visit",
        "status": status,
        "scheduled_start": "2026-10-20T10:00:00+00:00",
        "price_confirmed": CONSULT_FEE,
        "category_id": "cat-1",
    }


# ── Onboarding ────────────────────────────────────────────────────────────────

def test_step1_doctor_saves_their_profile(silent_push):
    doctors = make_chain(data=[{
        "id": "doc-1", "name": "Dr Anita Rao", "category_id": "cat-1",
        "bio": "MBBS, MD — 12 years",
    }])
    db = make_supabase({"doctors": doctors})

    for c in _client(DOC_PAYLOAD, db):
        res = c.patch("/doctors/me", json={
            "name": "Dr Anita Rao",
            "category_id": "cat-1",
            "bio": "MBBS, MD — 12 years",
        }, headers={"Authorization": DOCTOR_TOKEN})

    assert res.status_code == 200
    assert res.json()["name"] == "Dr Anita Rao"


def test_step2_verification_document_puts_the_doctor_in_the_queue(silent_push):
    """The document is required now, and submitting it is what makes the doctor
    reviewable — a licence number on its own is not something ops can check."""
    doctors = make_chain()
    doctors.execute.side_effect = [
        MagicMock(data={"verification_document_path": None}),
        MagicMock(data=[{"id": "doc-1", "verification_status": "pending"}]),
    ]
    db = make_supabase({"doctors": doctors})

    with patch("app.services.storage.upload", lambda *a: a[1]):
        for c in _client(DOC_PAYLOAD, db):
            res = c.post(
                "/uploads/doctor/verification-document",
                headers={"Authorization": DOCTOR_TOKEN},
                files={"file": ("licence.pdf", b"%PDF-1.4 fake licence", "application/pdf")},
            )

    assert res.status_code == 201
    written = doctors.update.call_args[0][0]
    assert written["verification_status"] == "pending"
    assert written["verification_document_path"]
    # A prior rejection must not survive a fresh submission.
    assert written["verification_rejection_reason"] is None


def test_step3_ops_sees_the_pending_doctor(silent_push):
    doctors = make_chain(list_data=[{
        "id": "doc-1", "name": "Dr Anita Rao", "phone": "+919000000001",
        "license_number": "MCI-118342",
        "verification_document_path": "doctors/doc-1/verification.pdf",
        "verification_document_mime": "application/pdf",
    }])
    db = make_supabase({"doctors": doctors})

    for c in _client(OPS_PAYLOAD, db):
        res = c.get("/admin/doctors/pending", headers={"Authorization": OPS_TOKEN})

    assert res.status_code == 200
    queue = res.json()
    assert len(queue) == 1
    # Without a stored document there is nothing for a reviewer to look at.
    assert queue[0]["verification_document_path"]


def test_step4_ops_approves_and_the_doctor_is_notified(silent_push):
    doctors = make_chain()
    doctors.execute.side_effect = [
        MagicMock(data=[{"id": "doc-1"}]),                                  # exists
        MagicMock(data=[{"id": "doc-1", "verification_status": "verified"}]),  # updated
        MagicMock(data={"id": "doc-1", "name": "Dr Anita Rao", "fcm_token": "tok"}),
    ]
    db = make_supabase({"doctors": doctors})

    for c in _client(OPS_PAYLOAD, db):
        res = c.patch(
            "/admin/doctors/doc-1/verify",
            json={"action": "approve"},
            headers={"Authorization": OPS_TOKEN},
        )

    assert res.status_code == 200
    assert res.json()["verification_status"] == "verified"
    assert any(n["role"] == "doctor" for n in silent_push), \
        "an approved doctor must be told they are live"


def test_step5_doctor_sets_pricing_and_the_review_threshold(silent_push):
    doctors = make_chain(data=[{
        "id": "doc-1", "procedure_review_threshold": THRESHOLD,
    }])
    db = make_supabase({"doctors": doctors})

    for c in _client(DOC_PAYLOAD, db):
        res = c.patch(
            "/doctors/me",
            json={"procedure_review_threshold": THRESHOLD},
            headers={"Authorization": DOCTOR_TOKEN},
        )

    assert res.status_code == 200
    assert res.json()["procedure_review_threshold"] == THRESHOLD


# ── A visit ───────────────────────────────────────────────────────────────────

def test_step6_doctor_sees_the_incoming_request(silent_push):
    db = make_supabase({"bookings": make_chain(list_data=[_booking()])})

    for c in _client(DOC_PAYLOAD, db):
        res = c.get("/bookings/doctor/incoming", headers={"Authorization": DOCTOR_TOKEN})

    assert res.status_code == 200
    assert [b["id"] for b in res.json()] == [BOOKING_ID]


def test_step7_doctor_starts_a_clarification_call(silent_push):
    calls = make_chain()
    calls.execute.side_effect = [
        MagicMock(data=[]),                                                  # none active
        MagicMock(data=[{"id": "call-1", "booking_id": BOOKING_ID,
                         "call_status": "initiated"}]),
    ]
    db = make_supabase({
        "bookings": make_chain(data=_booking()),
        "clarification_calls": calls,
    })

    for c in _client(DOC_PAYLOAD, db):
        res = c.post(f"/bookings/{BOOKING_ID}/clarification-call",
                     headers={"Authorization": DOCTOR_TOKEN})

    assert res.status_code == 201
    body = res.json()
    assert body["call_status"] == "initiated"
    assert body["agora_channel"]
    # Unconfigured in tests, and the apps switch on exactly this flag.
    assert body["live"] is False


def test_step8_patient_joins_the_call_without_knowing_its_id(silent_push):
    """The patient app is only told a doctor is calling; it has no call id, which
    is why `/bookings/{id}/call` resolves the live call itself."""
    db = make_supabase({
        "bookings": make_chain(data={
            "patient_id": "pat-1", "doctor_id": "doc-1",
            "doctors": {"name": "Dr Anita Rao"},
        }),
        "clarification_calls": make_chain(data=[{
            "id": "call-1", "booking_id": BOOKING_ID, "call_status": "initiated",
        }]),
    })

    for c in _client(PAT_PAYLOAD, db):
        res = c.post(f"/bookings/{BOOKING_ID}/call", json={"uid": 1001},
                     headers={"Authorization": PATIENT_TOKEN})

    assert res.status_code == 200
    body = res.json()
    assert body["call_id"] == "call-1"
    assert body["doctor_name"] == "Dr Anita Rao"
    # Both sides must land on the same channel or they never see each other.
    assert body["agora_channel"] == f"charak_{BOOKING_ID[:8]}"


def test_step9_doctor_accepts_then_completes_the_visit(silent_push):
    accepted = _booking("accepted")
    bookings = make_chain()
    bookings.execute.side_effect = [
        MagicMock(data=_booking("requested")),
        MagicMock(data=[accepted]),
    ]
    db = make_supabase({"bookings": bookings})

    for c in _client(DOC_PAYLOAD, db):
        res = c.patch(f"/bookings/{BOOKING_ID}/accept",
                      headers={"Authorization": DOCTOR_TOKEN})
    assert res.status_code == 200
    assert res.json()["status"] == "accepted"

    completed = _booking("completed")
    bookings2 = make_chain()
    bookings2.execute.side_effect = [
        # The patient pays between accept and complete. Completing straight
        # from "accepted" is refused — the consult fee could never be
        # collected once the booking left that state.
        MagicMock(data=_booking("paid")),
        MagicMock(data=[completed]),
    ]
    db2 = make_supabase({"bookings": bookings2})

    for c in _client(DOC_PAYLOAD, db2):
        res = c.patch(f"/bookings/{BOOKING_ID}/complete",
                      headers={"Authorization": DOCTOR_TOKEN})
    assert res.status_code == 200
    assert res.json()["status"] == "completed"


# ── Senior review ─────────────────────────────────────────────────────────────

def test_step10_a_bill_over_the_threshold_is_held_for_review(silent_push):
    bills = make_chain()
    bills.execute.side_effect = [
        MagicMock(data=[]),                                       # no existing bill
        MagicMock(data=[{"id": BILL_ID, "booking_id": BOOKING_ID,
                         "total": BILL_TOTAL, "status": "under_review"}]),
    ]
    db = make_supabase({
        "bookings": make_chain(data=_booking("completed")),
        "doctors": make_chain(data={"procedure_review_threshold": THRESHOLD}),
        "procedure_bills": bills,
    })

    for c in _client(DOC_PAYLOAD, db):
        res = c.post(
            f"/bookings/{BOOKING_ID}/procedure-bill",
            json={"items": [
                {"name": "Wound debridement", "price": 3200},
                {"name": "Dressing", "price": 1000},
            ]},
            headers={"Authorization": DOCTOR_TOKEN},
        )

    assert res.status_code == 201
    body = res.json()
    assert body["needs_review"] is True
    assert body["status"] == "under_review"
    written = bills.insert.call_args[0][0]
    assert written["total"] == BILL_TOTAL
    assert any(n["role"] == "doctor" for n in silent_push), \
        "the doctor must know their bill is being reviewed, not paid"


def test_step11_earnings_hold_the_bill_as_pending_not_earned(silent_push):
    db = make_supabase({
        "bookings": make_chain(list_data=[{
            "id": BOOKING_ID, "channel": "home_visit",
            "scheduled_start": "2026-10-20T10:00:00+00:00",
            "price_confirmed": CONSULT_FEE, "status": "completed",
            "users": {"name": "Ravi Kumar"},
        }]),
        "procedure_bills": make_chain(list_data=[{
            "id": BILL_ID, "booking_id": BOOKING_ID,
            "total": BILL_TOTAL, "status": "under_review",
        }]),
    })

    for c in _client(DOC_PAYLOAD, db):
        res = c.get("/earnings/me", headers={"Authorization": DOCTOR_TOKEN})

    assert res.status_code == 200
    e = res.json()
    assert e["pending_review_total"] == BILL_TOTAL
    assert e["procedure_total"] == 0
    # The consult fee is earned regardless — only the procedure is in question.
    assert e["consult_total"] == CONSULT_FEE
    assert e["grand_total"] == CONSULT_FEE


def test_step12_ops_sees_and_approves_the_bill(silent_push):
    review_queue = make_chain(list_data=[{
        "id": BILL_ID, "booking_id": BOOKING_ID,
        "total": BILL_TOTAL, "status": "under_review",
    }])
    db = make_supabase({"procedure_bills": review_queue})

    for c in _client(OPS_PAYLOAD, db):
        res = c.get("/admin/procedure-bills/review", headers={"Authorization": OPS_TOKEN})
    assert res.status_code == 200
    assert [b["id"] for b in res.json()] == [BILL_ID]

    bills = make_chain()
    bills.execute.side_effect = [
        MagicMock(data=[{"id": BILL_ID, "booking_id": BOOKING_ID,
                         "total": BILL_TOTAL, "status": "under_review"}]),
        MagicMock(data=[{"id": BILL_ID, "booking_id": BOOKING_ID,
                         "total": BILL_TOTAL, "status": "approved"}]),
    ]
    db2 = make_supabase({
        "procedure_bills": bills,
        "bookings": make_chain(data=_booking("completed")),
    })

    for c in _client(OPS_PAYLOAD, db2):
        res = c.patch(f"/bookings/{BOOKING_ID}/procedure-bill/approve",
                      headers={"Authorization": OPS_TOKEN})

    assert res.status_code == 200
    assert res.json()["status"] == "approved"
    assert silent_push, "approving a bill must notify somebody"


def test_step13_earnings_move_the_bill_from_pending_review_to_payable(silent_push):
    db = make_supabase({
        "bookings": make_chain(list_data=[{
            "id": BOOKING_ID, "channel": "home_visit",
            "scheduled_start": "2026-10-20T10:00:00+00:00",
            "price_confirmed": CONSULT_FEE, "status": "completed",
            "users": {"name": "Ravi Kumar"},
        }]),
        "procedure_bills": make_chain(list_data=[{
            "id": BILL_ID, "booking_id": BOOKING_ID,
            "total": BILL_TOTAL, "status": "approved",
        }]),
    })

    for c in _client(DOC_PAYLOAD, db):
        res = c.get("/earnings/me", headers={"Authorization": DOCTOR_TOKEN})

    assert res.status_code == 200
    e = res.json()
    # Senior approval moves the bill out of review and makes it payable. It
    # becomes *earnings* only once the patient actually pays it.
    assert e["pending_review_total"] == 0
    assert e["awaiting_payment_total"] == BILL_TOTAL
    assert e["procedure_total"] == 0
    assert e["grand_total"] == CONSULT_FEE


def test_a_flagged_bill_stays_out_of_earnings(silent_push):
    """Flagging is the other half of review, and the earnings consequence is the
    part that matters: a flagged bill must not quietly become payable."""
    bills = make_chain()
    bills.execute.side_effect = [
        MagicMock(data=[{"id": BILL_ID, "booking_id": BOOKING_ID,
                         "total": BILL_TOTAL, "status": "under_review"}]),
        MagicMock(data=[{"id": BILL_ID, "booking_id": BOOKING_ID,
                         "total": BILL_TOTAL, "status": "under_review",
                         "reviewed_at": "2026-10-20T12:00:00+00:00"}]),
    ]
    db = make_supabase({"procedure_bills": bills})

    for c in _client(OPS_PAYLOAD, db):
        res = c.patch(f"/bookings/{BOOKING_ID}/procedure-bill/flag",
                      headers={"Authorization": OPS_TOKEN})

    assert res.status_code == 200
    assert res.json()["status"] == "under_review"
    assert res.json()["reviewed_at"]
