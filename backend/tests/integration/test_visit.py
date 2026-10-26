"""
Migration 0025 against real Postgres: Start Journey, the consultation, the
prescription (draft, send, open, correct), completion on view and the 72-hour
fallback, follow-ups, call joins, the payout timing that follows (LD-006), and
the ops queue and break-glass access.

Storage is the one stand-in (the stack has no Storage service): an in-memory
store, so the PDF is really rendered and really "uploaded".
"""
import itertools
import uuid
from datetime import date, datetime, timedelta, timezone
from unittest.mock import patch

import pytest

from .conftest import AUTH

_slot = itertools.count()


def _id() -> str:
    return str(uuid.uuid4())


def _ts(value) -> datetime:
    return datetime.fromisoformat(str(value).replace("Z", "+00:00"))


@pytest.fixture
def store():
    """An in-memory private bucket."""
    objects: dict[str, bytes] = {}

    def upload(bucket, path, content, content_type):
        objects[f"{bucket}/{path}"] = content
        return path

    def remove(bucket, path):
        objects.pop(f"{bucket}/{path}", None)

    with patch("app.services.storage.upload", side_effect=upload), \
         patch("app.services.storage.remove", side_effect=remove), \
         patch("app.services.storage.download", side_effect=lambda b, p: objects.get(f"{b}/{p}")), \
         patch("app.services.storage.signed_url",
               side_effect=lambda b, p, ttl=300: f"https://signed.test/{b}/{p}"):
        yield objects


def _paid(db, s, *, channel="online_consult", minutes_ahead=10, amount=500.00):
    start = datetime.now(timezone.utc) + timedelta(minutes=minutes_ahead, seconds=next(_slot))
    booking = db.table("bookings").insert({
        "id": _id(), "patient_id": s["patient"]["id"], "doctor_id": s["doctor"]["id"],
        "channel": channel, "scheduled_start": start.isoformat(), "status": "paid",
        "price_confirmed": amount,
    }).execute().data[0]
    db.table("doctor_ledger_entries").insert({
        "doctor_id": s["doctor"]["id"], "booking_id": booking["id"], "source": "consult_fee",
        "gross_amount": amount, "commission_pct": 0, "commission_amount": 0,
        "net_amount": amount, "status": "payable",
    }).execute()
    return booking


def _status(db, booking_id) -> dict:
    return db.table("bookings").select("*").eq("id", booking_id).execute().data[0]


def _events(db, booking_id, event) -> list:
    return db.table("booking_events").select("*").eq("booking_id", booking_id) \
        .eq("event", event).execute().data


def _notes(db, booking_id, event) -> list:
    return db.table("notifications").select("*").eq("booking_id", booking_id) \
        .eq("event", event).execute().data


DRAFT = {
    "patient_age": 34, "patient_sex": "female",
    "complaints": "Fever for 3 days", "diagnosis": "Viral fever",
    "advice": "Rest and fluids", "tpg_attested": True,
    "items": [
        {"medicine": "Paracetamol", "strength": "500 mg", "form": "tablet", "dose": "1 tablet",
         "frequency": "1-1-1", "duration": "3 days", "instructions": "after food"},
        {"medicine": "ORS", "dose": "1 sachet", "frequency": "twice a day", "duration": "2 days"},
    ],
}


def _send(doctor, booking_id, *, draft=DRAFT, follow_up=None):
    res = doctor.put(f"/bookings/{booking_id}/prescription", json=draft, headers=AUTH)
    assert res.status_code == 200, res.text
    res = doctor.post(f"/bookings/{booking_id}/prescription/submit",
                      json={"follow_up": follow_up}, headers=AUTH)
    assert res.status_code == 200, res.text
    return res.json()


# ── Start Journey ────────────────────────────────────────────────────────────

def test_start_journey_is_once_by_the_assigned_doctor_and_notifies_once(seed, client_for, db):
    s = seed(offers_home_visit=True)
    other = seed(offers_home_visit=True)
    booking = _paid(db, s, channel="home_visit", minutes_ahead=60, amount=800.00)

    assert client_for(other["doctor"]["id"], "doctor") \
        .post(f"/bookings/{booking['id']}/journey/start", headers=AUTH).status_code == 403
    assert client_for(s["patient"]["id"]) \
        .post(f"/bookings/{booking['id']}/journey/start", headers=AUTH).status_code == 403

    doctor = client_for(s["doctor"]["id"], "doctor")
    first = doctor.post(f"/bookings/{booking['id']}/journey/start", headers=AUTH)
    assert first.status_code == 200, first.text
    again = doctor.post(f"/bookings/{booking['id']}/journey/start", headers=AUTH)
    assert again.status_code == 200
    assert again.json()["already_started"] is True
    assert again.json()["journey_started_at"] == first.json()["journey_started_at"]

    assert len(_events(db, booking["id"], "start_journey")) == 1
    assert len(_notes(db, booking["id"], "visit.journey_started")) == 1
    # From now a patient cancellation refunds nothing (LD-005).
    q = client_for(s["patient"]["id"]).get(f"/bookings/{booking['id']}/cancellation-quote",
                                           headers=AUTH).json()
    assert q["refund_paise"] == 0 and q["reason"] == "journey_started"


def test_start_journey_opens_two_hours_before_and_only_for_home_visits(seed, client_for, db):
    s = seed(offers_home_visit=True)
    doctor = client_for(s["doctor"]["id"], "doctor")

    early = _paid(db, s, channel="home_visit", minutes_ahead=180)
    res = doctor.post(f"/bookings/{early['id']}/journey/start", headers=AUTH)
    assert res.status_code == 409 and "opens_at" in res.json()
    assert _status(db, early["id"])["journey_started_at"] is None

    online = _paid(db, s, channel="online_consult", minutes_ahead=30)
    assert doctor.post(f"/bookings/{online['id']}/journey/start", headers=AUTH).status_code == 400


# ── The consultation ─────────────────────────────────────────────────────────

def test_consultation_start_window_and_no_cancel_once_started(seed, client_for, db):
    s = seed(offers_home_visit=True)
    doctor = client_for(s["doctor"]["id"], "doctor")

    too_early = _paid(db, s, channel="online_consult", minutes_ahead=60)
    res = doctor.post(f"/bookings/{too_early['id']}/consultation/start", headers=AUTH)
    assert res.status_code == 409
    assert _status(db, too_early["id"])["status"] == "paid"

    booking = _paid(db, s, channel="online_consult", minutes_ahead=10)
    res = doctor.post(f"/bookings/{booking['id']}/consultation/start", headers=AUTH)
    assert res.status_code == 200, res.text
    row = _status(db, booking["id"])
    assert row["status"] == "in_progress" and row["started_at"]
    # A second tap changes nothing.
    assert doctor.post(f"/bookings/{booking['id']}/consultation/start", headers=AUTH).status_code == 200
    assert len(_events(db, booking["id"], "start_consultation")) == 1

    patient = client_for(s["patient"]["id"])
    assert patient.patch(f"/bookings/{booking['id']}/cancel", json={}, headers=AUTH).status_code == 400
    assert _status(db, booking["id"])["status"] == "in_progress"


def test_the_doctor_joining_a_paid_consult_starts_it_and_every_join_is_recorded(seed, client_for, db):
    s = seed()
    booking = _paid(db, s, minutes_ahead=5)

    assert client_for(s["patient"]["id"]).post(f"/bookings/{booking['id']}/call",
                                               json={}, headers=AUTH).status_code == 200
    assert _status(db, booking["id"])["status"] == "paid"      # the patient joining doesn't
    assert client_for(s["doctor"]["id"], "doctor").post(f"/bookings/{booking['id']}/call",
                                                         json={}, headers=AUTH).status_code == 200
    assert _status(db, booking["id"])["status"] == "in_progress"

    joins = db.table("call_joins").select("actor_role, kind").eq("booking_id", booking["id"]) \
        .order("joined_at").execute().data
    assert joins == [{"actor_role": "patient", "kind": "consultation"},
                     {"actor_role": "doctor", "kind": "consultation"}]
    with pytest.raises(Exception):
        db.table("call_joins").delete().eq("booking_id", booking["id"]).execute()


# ── The prescription ─────────────────────────────────────────────────────────

def test_a_draft_is_private_to_the_doctor_and_replaced_whole(seed, client_for, db, store):
    s = seed()
    booking = _paid(db, s)
    doctor = client_for(s["doctor"]["id"], "doctor")
    patient = client_for(s["patient"]["id"])

    assert doctor.put(f"/bookings/{booking['id']}/prescription", json=DRAFT, headers=AUTH).status_code == 200
    assert patient.get(f"/bookings/{booking['id']}/prescription", headers=AUTH).json() == {"prescription": None}
    draft = doctor.get(f"/bookings/{booking['id']}/prescription", headers=AUTH).json()["prescription"]
    assert [i["medicine"] for i in draft["items"]] == ["Paracetamol", "ORS"]
    # The patient can't open a draft by its id either.
    assert patient.post(f"/prescriptions/{draft['id']}/view", headers=AUTH).status_code == 404

    res = doctor.put(f"/bookings/{booking['id']}/prescription",
                     json={**DRAFT, "diagnosis": None, "items": [{"medicine": "Cetirizine"}]}, headers=AUTH)
    assert res.status_code == 200
    assert [i["medicine"] for i in res.json()["items"]] == ["Cetirizine"]
    assert res.json()["diagnosis"] is None
    assert len(db.table("prescriptions").select("id").eq("booking_id", booking["id"]).execute().data) == 1


def test_a_prescription_cant_be_written_before_payment(seed, client_for, db):
    s = seed()
    booking = _paid(db, s)
    db.table("bookings").update({"status": "accepted"}).eq("id", booking["id"]).execute()
    res = client_for(s["doctor"]["id"], "doctor").put(
        f"/bookings/{booking['id']}/prescription", json=DRAFT, headers=AUTH)
    assert res.status_code == 409


def test_online_prescriptions_need_the_tpg_confirmation(seed, client_for, db, store):
    s = seed()
    booking = _paid(db, s)
    doctor = client_for(s["doctor"]["id"], "doctor")
    doctor.put(f"/bookings/{booking['id']}/prescription", json={**DRAFT, "tpg_attested": False}, headers=AUTH)
    res = doctor.post(f"/bookings/{booking['id']}/prescription/submit", json={}, headers=AUTH)
    assert res.status_code == 400 and "Telemedicine" in res.json()["error"]
    assert _status(db, booking["id"])["status"] == "paid"


def test_sending_moves_the_booking_records_everything_and_locks_the_record(seed, client_for, db, store):
    s = seed()
    booking = _paid(db, s)
    doctor = client_for(s["doctor"]["id"], "doctor")
    follow = (date.today() + timedelta(days=10)).isoformat()
    rx = _send(doctor, booking["id"], follow_up={"date": follow, "channel": "either", "note": "Review"})

    row = _status(db, booking["id"])
    assert row["status"] == "consulted"
    assert row["started_at"] and row["consulted_at"] and row["prescription_sent_at"]
    assert rx["status"] == "submitted" and rx["follow_up"]["recommended_date"] == follow

    stored = db.table("prescriptions").select("pdf_path, pdf_sha256").eq("id", rx["id"]).execute().data[0]
    pdf = store[f"prescriptions/{stored['pdf_path']}"]
    assert pdf.startswith(b"%PDF") and len(stored["pdf_sha256"]) == 64

    kinds = {j["kind"] for j in db.table("jobs").select("kind").execute().data}
    assert {"booking.complete_fallback", "prescription.view_reminder", "follow_up.reminder"} <= kinds
    assert len(_notes(db, booking["id"], "prescription.ready")) == 1

    # A clinical record now: no edits, no deletes, no new medicines.
    with pytest.raises(Exception):
        db.table("prescriptions").update({"diagnosis": "changed"}).eq("id", rx["id"]).execute()
    with pytest.raises(Exception):
        db.table("prescriptions").delete().eq("id", rx["id"]).execute()
    with pytest.raises(Exception):
        db.table("prescription_items").insert({"prescription_id": rx["id"], "position": 9,
                                               "medicine": "Extra"}).execute()
    # And the doctor's draft endpoint refuses: a change takes a correction.
    assert doctor.put(f"/bookings/{booking['id']}/prescription", json=DRAFT,
                      headers=AUTH).status_code == 409


def test_a_send_built_from_a_stale_draft_sends_nothing(seed, client_for, db, store):
    s = seed()
    booking = _paid(db, s)
    doctor = client_for(s["doctor"]["id"], "doctor")
    draft = doctor.put(f"/bookings/{booking['id']}/prescription", json=DRAFT, headers=AUTH).json()
    stale = db.table("prescriptions").select("updated_at").eq("id", draft["id"]).execute().data[0]
    doctor.put(f"/bookings/{booking['id']}/prescription", json={**DRAFT, "advice": "New"}, headers=AUTH)

    result = db.rpc("submit_prescription", {
        "p_prescription_id": draft["id"], "p_doctor_id": s["doctor"]["id"],
        "p_submitted_at": datetime.now(timezone.utc).isoformat(), "p_pdf_path": "x.pdf",
        "p_pdf_sha256": "0" * 64, "p_draft_updated_at": stale["updated_at"],
    }).execute().data
    assert result["outcome"] == "changed"
    assert _status(db, booking["id"])["status"] == "paid"


def test_the_patients_first_open_completes_the_booking_once(seed, client_for, db, store):
    s = seed()
    booking = _paid(db, s)
    rx = _send(client_for(s["doctor"]["id"], "doctor"), booking["id"])
    patient = client_for(s["patient"]["id"])

    summary = patient.get(f"/bookings/{booking['id']}/prescription", headers=AUTH).json()["prescription"]
    assert summary["id"] == rx["id"] and summary["first_viewed_at"] is None

    opened = patient.post(f"/prescriptions/{rx['id']}/view", headers=AUTH)
    assert opened.status_code == 200, opened.text
    assert [i["medicine"] for i in opened.json()["items"]] == ["Paracetamol", "ORS"]
    first = opened.json()["first_viewed_at"]
    row = _status(db, booking["id"])
    assert row["status"] == "completed" and row["completion_source"] == "patient_viewed"
    assert row["prescription_viewed_at"]

    again = patient.post(f"/prescriptions/{rx['id']}/view", headers=AUTH).json()
    assert again["first_viewed_at"] == first
    assert len(_events(db, booking["id"], "complete")) == 1
    assert len(_notes(db, booking["id"], "visit.completed")) == 1

    files = patient.get(f"/prescriptions/{rx['id']}/files", headers=AUTH).json()
    assert files["pdf_url"].startswith("https://signed.test/prescriptions/")


def test_nobody_else_can_open_it_or_complete_the_booking(seed, client_for, db, store):
    s = seed()
    booking = _paid(db, s)
    rx = _send(client_for(s["doctor"]["id"], "doctor"), booking["id"])

    other = client_for(s["other_patient"]["id"])
    assert other.post(f"/prescriptions/{rx['id']}/view", headers=AUTH).status_code == 403
    assert other.get(f"/prescriptions/{rx['id']}/files", headers=AUTH).status_code == 403
    assert other.get(f"/bookings/{booking['id']}/prescription", headers=AUTH).status_code == 403
    # The doctor can't record the patient's view.
    assert client_for(s["doctor"]["id"], "doctor") \
        .post(f"/prescriptions/{rx['id']}/view", headers=AUTH).status_code == 403
    # The doctor reading it is not a view.
    assert client_for(s["doctor"]["id"], "doctor") \
        .get(f"/prescriptions/{rx['id']}", headers=AUTH).status_code == 200

    assert _status(db, booking["id"])["status"] == "consulted"
    assert db.table("prescriptions").select("first_viewed_at").eq("id", rx["id"]) \
        .execute().data[0]["first_viewed_at"] is None


def test_a_correction_supersedes_and_keeps_the_original(seed, client_for, db, store):
    s = seed()
    booking = _paid(db, s)
    doctor = client_for(s["doctor"]["id"], "doctor")
    follow = (date.today() + timedelta(days=5)).isoformat()
    v1 = _send(doctor, booking["id"], follow_up={"date": follow, "channel": "home_visit"})

    res = doctor.post(f"/prescriptions/{v1['id']}/correct", headers=AUTH)
    assert res.status_code == 201, res.text
    draft = res.json()
    assert draft["version"] == 2 and draft["status"] == "draft"
    assert [i["medicine"] for i in draft["items"]] == ["Paracetamol", "ORS"]
    assert draft["follow_up"]["recommended_date"] == follow          # prefilled
    assert doctor.post(f"/prescriptions/{v1['id']}/correct", headers=AUTH).status_code == 409

    v2 = _send(doctor, booking["id"], draft={**DRAFT, "items": [{"medicine": "Paracetamol",
                                                                  "strength": "650 mg"}]})
    old = db.table("prescriptions").select("status, diagnosis").eq("id", v1["id"]).execute().data[0]
    assert old == {"status": "superseded", "diagnosis": "Viral fever"}
    assert v2["status"] == "submitted" and v2["version"] == 2
    # The correction carried no follow-up, so the earlier one is withdrawn.
    assert db.table("follow_up_recommendations").select("status") \
        .eq("prescription_id", v1["id"]).execute().data[0]["status"] == "dismissed"
    assert len(_notes(db, booking["id"], "prescription.updated")) == 1

    # An old link opens the old version, points at the new one, and doesn't
    # complete the booking.
    patient = client_for(s["patient"]["id"])
    stale = patient.post(f"/prescriptions/{v1['id']}/view", headers=AUTH).json()
    assert stale["status"] == "superseded" and stale["replaced_by_id"] == v2["id"]
    assert _status(db, booking["id"])["status"] == "consulted"
    patient.post(f"/prescriptions/{v2['id']}/view", headers=AUTH)
    assert _status(db, booking["id"])["status"] == "completed"


def test_consultation_notes_can_end_a_visit_without_medicines(seed, client_for, db, store):
    s = seed()
    booking = _paid(db, s)
    rx = _send(client_for(s["doctor"]["id"], "doctor"), booking["id"],
               draft={"kind": "notes", "advice": "No medicines needed. Rest.", "items": []})
    assert rx["kind"] == "notes"
    assert _status(db, booking["id"])["status"] == "consulted"


# ── The fallback and the money ───────────────────────────────────────────────

def test_an_unopened_prescription_completes_its_booking_after_72_hours(seed, client_for, db, store):
    from app.services import visits

    s = seed()
    booking = _paid(db, s)
    _send(client_for(s["doctor"]["id"], "doctor"), booking["id"])
    sent = _ts(_status(db, booking["id"])["prescription_sent_at"])

    assert visits.complete_overdue(now=sent + timedelta(hours=71)) == 0
    assert _status(db, booking["id"])["status"] == "consulted"
    assert visits.complete_overdue(now=sent + timedelta(hours=72, minutes=1)) == 1
    row = _status(db, booking["id"])
    assert row["status"] == "completed" and row["completion_source"] == "fallback"
    assert len(_notes(db, booking["id"], "visit.completed")) == 1
    # The queued job, when it runs, finds nothing to do.
    from app.services import prescriptions
    prescriptions._complete_fallback({"booking_id": booking["id"]})
    assert len(_events(db, booking["id"], "complete")) == 1


@pytest.mark.parametrize("opened,hours", [(True, 48), (False, 72)])
def test_the_fee_is_withdrawable_48h_after_the_send_if_opened_else_72h(
        seed, client_for, db, store, opened, hours):
    from app.services import payouts, visits

    s = seed()
    booking = _paid(db, s)
    rx = _send(client_for(s["doctor"]["id"], "doctor"), booking["id"])
    if opened:
        client_for(s["patient"]["id"]).post(f"/prescriptions/{rx['id']}/view", headers=AUTH)
    else:
        sent = _ts(_status(db, booking["id"])["prescription_sent_at"])
        visits.complete_overdue(now=sent + timedelta(hours=73))

    entry = db.table("doctor_ledger_entries") \
        .select(f"source, bookings({payouts.BOOKING_RELEASE_COLUMNS})") \
        .eq("booking_id", booking["id"]).execute().data[0]
    sent = _ts(entry["bookings"]["prescription_sent_at"])
    assert payouts.available_at(entry) == sent + timedelta(hours=hours)
    assert not payouts.is_payout_eligible(entry)                      # not yet
    assert payouts.is_payout_eligible(entry, now=sent + timedelta(hours=hours, seconds=1))

    balance = client_for(s["doctor"]["id"], "doctor").get("/payouts/me/balance", headers=AUTH).json()
    assert balance["available_net"] == 0 and balance["waiting_net"] == 500.0
    assert _ts(balance["next_available_at"]) == sent + timedelta(hours=hours)


def test_completion_does_not_release_the_fee_before_the_hold(seed, client_for, db, store):
    from app.services import payouts

    s = seed()
    booking = _paid(db, s)
    rx = _send(client_for(s["doctor"]["id"], "doctor"), booking["id"])
    client_for(s["patient"]["id"]).post(f"/prescriptions/{rx['id']}/view", headers=AUTH)
    assert _status(db, booking["id"])["status"] == "completed"
    with pytest.raises(Exception, match="No payable earnings"):
        payouts.create_payout(s["doctor"]["id"], "2000-01-01", "2100-01-01")


# ── Follow-ups and reminders ─────────────────────────────────────────────────

def test_the_patient_sees_and_can_dismiss_a_follow_up(seed, client_for, db, store):
    s = seed()
    booking = _paid(db, s)
    follow = (date.today() + timedelta(days=3)).isoformat()
    _send(client_for(s["doctor"]["id"], "doctor"), booking["id"],
          follow_up={"date": follow, "channel": "online_consult", "note": "Bring reports"})

    patient = client_for(s["patient"]["id"])
    rows = patient.get("/me/follow-ups", headers=AUTH).json()
    assert len(rows) == 1 and rows[0]["recommended_date"] == follow
    assert rows[0]["doctors"]["name"] == "Dr Test"
    assert client_for(s["other_patient"]["id"]) \
        .post(f"/me/follow-ups/{rows[0]['id']}/dismiss", headers=AUTH).status_code == 404
    assert patient.post(f"/me/follow-ups/{rows[0]['id']}/dismiss", headers=AUTH).status_code == 200
    assert patient.get("/me/follow-ups", headers=AUTH).json() == []


def test_a_follow_up_in_the_past_is_refused(seed, client_for, db, store):
    s = seed()
    booking = _paid(db, s)
    doctor = client_for(s["doctor"]["id"], "doctor")
    doctor.put(f"/bookings/{booking['id']}/prescription", json=DRAFT, headers=AUTH)
    res = doctor.post(f"/bookings/{booking['id']}/prescription/submit", headers=AUTH,
                      json={"follow_up": {"date": "2020-01-01", "channel": "either"}})
    assert res.status_code == 400
    assert _status(db, booking["id"])["status"] == "paid"


def test_paying_queues_appointment_reminders_that_skip_a_cancelled_visit(seed, db):
    from app.services import jobs, visits

    s = seed()
    booking = _paid(db, s, minutes_ahead=2 * 24 * 60)
    assert visits.schedule_reminders(booking) == 2
    assert visits.schedule_reminders(booking) == 2               # deduped, still two rows
    rows = db.table("jobs").select("kind, payload").eq("kind", "booking.reminder").execute().data
    assert sorted(r["payload"]["minutes"] for r in rows) == [15, 1440]

    db.table("bookings").update({"status": "cancelled"}).eq("id", booking["id"]).execute()
    jobs.HANDLERS["booking.reminder"]({"booking_id": booking["id"], "minutes": 15})
    assert _notes(db, booking["id"], "booking.reminder") == []


# ── Ops ──────────────────────────────────────────────────────────────────────

def test_ops_queue_flags_a_home_visit_with_no_journey(seed, client_for, db):
    s = seed(offers_home_visit=True)
    late = _paid(db, s, channel="home_visit", minutes_ahead=10, amount=800.00)
    _paid(db, s, channel="home_visit", minutes_ahead=180, amount=800.00)    # not yet
    queues = client_for(_id(), "ops").get("/admin/visits/queues", headers=AUTH).json()
    assert [r["id"] for r in queues["journey_not_started"]] == [late["id"]]
    assert queues["journey_not_started"][0]["patient_name"] == "Test Patient"


def test_break_glass_needs_a_reason_and_is_audited(seed, client_for, db, store):
    s = seed()
    booking = _paid(db, s)
    rx = _send(client_for(s["doctor"]["id"], "doctor"), booking["id"])
    ops_id = _id()
    ops = client_for(ops_id, "ops")

    meta = ops.get(f"/admin/bookings/{booking['id']}/prescriptions", headers=AUTH).json()
    assert meta[0]["status"] == "submitted" and "diagnosis" not in meta[0]
    assert ops.post(f"/prescriptions/{rx['id']}/view", headers=AUTH).status_code == 403
    assert ops.post(f"/admin/prescriptions/{rx['id']}/access", json={"reason": "x"},
                    headers=AUTH).status_code == 422

    res = ops.post(f"/admin/prescriptions/{rx['id']}/access",
                   json={"reason": "Pharmacy called to verify the dose"}, headers=AUTH)
    assert res.status_code == 200 and res.json()["diagnosis"] == "Viral fever"
    audit = db.table("audit_log").select("action, reason").eq("actor_id", ops_id).execute().data
    assert audit == [{"action": "break_glass_read", "reason": "Pharmacy called to verify the dose"}]
    # Ops reading it is not the patient's view.
    assert _status(db, booking["id"])["status"] == "consulted"


def test_a_journey_started_after_the_quote_stops_the_cancel(seed, client_for, db):
    """The patient was shown 50% back; the doctor then left. The cancel must
    not refund what the policy no longer allows: nothing changes, and the new
    quote (0%) comes back."""
    s = seed(offers_home_visit=True)
    booking = _paid(db, s, channel="home_visit", minutes_ahead=60, amount=800.00)
    db.table("payments").insert({
        "id": _id(), "booking_id": booking["id"], "amount": 800.00, "status": "completed",
        "type": "consult_fee", "razorpay_order_id": f"order_{_id()[:12]}",
        "razorpay_payment_id": f"pay_{_id()[:12]}",
    }).execute()
    patient = client_for(s["patient"]["id"])
    quote = patient.get(f"/bookings/{booking['id']}/cancellation-quote", headers=AUTH).json()
    assert quote["refund_paise"] == 40000

    client_for(s["doctor"]["id"], "doctor").post(f"/bookings/{booking['id']}/journey/start", headers=AUTH)
    res = patient.patch(f"/bookings/{booking['id']}/cancel", headers=AUTH,
                        json={"expected_refund_paise": quote["refund_paise"]})
    assert res.status_code == 409 and res.json()["quote"]["refund_paise"] == 0
    assert _status(db, booking["id"])["status"] == "paid"
