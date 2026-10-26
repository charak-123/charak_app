"""
Migration 0028 against real Postgres: reporting a problem, the evidence, the
patient's remedy (refund, or another doctor paid from the same payment),
reschedules, appeals, and the reliability measure (spec §12.6–12.8, §13, §14).
"""
import itertools
import uuid
from datetime import datetime, timedelta, timezone

import pytest

from .conftest import AUTH

IST = timezone(timedelta(hours=5, minutes=30))
_slot = itertools.count()


def _id() -> str:
    return str(uuid.uuid4())


def _paid(db, s, *, channel="online_consult", minutes_from_now=-15.0, amount=600.00, doctor=None):
    start = datetime.now(timezone.utc) + timedelta(minutes=minutes_from_now, seconds=next(_slot))
    doc = doctor or s["doctor"]
    booking = db.table("bookings").insert({
        "id": _id(), "patient_id": s["patient"]["id"], "doctor_id": doc["id"],
        "channel": channel, "scheduled_start": start.isoformat(), "status": "paid",
        "price_confirmed": amount, "duration_min": 15,
    }).execute().data[0]
    payment = db.table("payments").insert({
        "id": _id(), "booking_id": booking["id"], "amount": amount, "status": "completed",
        "type": "consult_fee", "razorpay_order_id": f"order_{_id()[:12]}",
        "razorpay_payment_id": f"pay_{_id()[:12]}", "method": "upi",
    }).execute().data[0]
    db.table("doctor_ledger_entries").insert({
        "doctor_id": doc["id"], "booking_id": booking["id"], "source": "consult_fee",
        "gross_amount": amount, "commission_pct": 0, "commission_amount": 0,
        "net_amount": amount, "status": "payable",
    }).execute()
    return booking, payment


def _join(db, booking, role, actor_id):
    db.table("call_joins").insert({"booking_id": booking["id"], "actor_role": role,
                                   "actor_id": actor_id, "kind": "consultation"}).execute()


def _report(client, booking_id, reported_as, note=None):
    return client.post(f"/bookings/{booking_id}/issues", headers=AUTH,
                       json={"reported_as": reported_as, "note": note})


def _ledger(db, booking_id):
    return db.table("doctor_ledger_entries").select("status, net_amount, source") \
        .eq("booking_id", booking_id).execute().data


def _refunds(db, booking_id):
    return db.table("refunds").select("amount_paise, reason, payment_id") \
        .eq("booking_id", booking_id).execute().data


# ── Reporting ────────────────────────────────────────────────────────────────

def test_doctor_not_joined_opens_after_the_grace_period(seed, client_for, db):
    s = seed()
    early, _ = _paid(db, s, minutes_from_now=-5)
    patient = client_for(s["patient"]["id"])
    res = _report(patient, early["id"], "doctor_not_joined")
    assert res.status_code == 409 and "grace" in res.json()["error"]
    assert "doctor_not_joined" not in patient.get(f"/bookings/{early['id']}/help", headers=AUTH).json()["can_report"]


def test_a_clear_online_no_show_offers_a_remedy_now_and_confirms_in_48h(seed, client_for, db):
    s = seed()
    b, _ = _paid(db, s)
    _join(db, b, "patient", s["patient"]["id"])
    patient = client_for(s["patient"]["id"])
    help_ = patient.get(f"/bookings/{b['id']}/help", headers=AUTH).json()
    assert "doctor_not_joined" in help_["can_report"]

    res = _report(patient, b["id"], "doctor_not_joined", "Waited 20 minutes")
    assert res.status_code == 201, res.text
    inc = res.json()
    assert inc["case_ref"].startswith("CHK-") and len(inc["case_ref"]) == 9
    assert (inc["status"], inc["remedy_eligible"], inc["remedies"]["available"]) == ("reported", True, True)
    assert inc["remedies"]["refund_paise"] == 60000 and inc["auto_confirm_at"]
    # Pressing again shows the same case.
    assert _report(patient, b["id"], "doctor_not_joined").json()["id"] == inc["id"]
    assert db.table("notifications").select("event").eq("recipient_id", s["doctor"]["id"]) \
        .eq("event", "incident.reported").execute().data
    # Reliability isn't touched by a report.
    doctor = client_for(s["doctor"]["id"], "doctor")
    rel = doctor.get("/doctors/me/reliability", headers=AUTH).json()
    assert rel["counted"] == 0 and rel["cases"][0]["counts"] is False

    from app.services import remedies
    db.table("incidents").update({"auto_confirm_at": (datetime.now(timezone.utc) - timedelta(minutes=1)).isoformat()}) \
        .eq("id", inc["id"]).execute()
    remedies.sweep()
    row = db.table("incidents").select("status, cause").eq("id", inc["id"]).execute().data[0]
    assert row == {"status": "confirmed", "cause": "doctor"}
    assert doctor.get("/doctors/me/reliability", headers=AUTH).json()["counted"] == 1


def test_conflicting_evidence_waits_for_ops(seed, client_for, db):
    s = seed(offers_home_visit=True)
    b, _ = _paid(db, s, channel="home_visit", minutes_from_now=-40, amount=800.00)
    db.table("bookings").update({"journey_started_at": (datetime.now(timezone.utc) - timedelta(hours=1)).isoformat()}) \
        .eq("id", b["id"]).execute()
    patient = client_for(s["patient"]["id"])
    inc = _report(patient, b["id"], "doctor_not_arrived").json()
    assert (inc["status"], inc["remedy_eligible"]) == ("under_review", False)
    assert patient.post(f"/incidents/{inc['id']}/remedy/refund", headers=AUTH).status_code == 409

    ops = client_for(_id(), "ops")
    queue = ops.get("/admin/incidents", headers=AUTH).json()
    assert queue[0]["id"] == inc["id"] and queue[0]["evidence"]["journey_started_at"]
    assert ops.post(f"/admin/incidents/{inc['id']}/decide", headers=AUTH, json={
        "status": "confirmed", "cause": "undetermined", "reason": "Doctor never arrived"}).status_code == 400
    res = ops.post(f"/admin/incidents/{inc['id']}/decide", headers=AUTH, json={
        "status": "confirmed", "cause": "doctor", "reason": "Journey started but doctor never arrived (called).",
        "offer_remedy": True})
    assert res.status_code == 200 and res.json()["remedy_eligible"] is True
    events = [e["event"] for e in db.table("incident_events").select("event").eq("incident_id", inc["id"]).execute().data]
    assert events == ["reported", "decided_confirmed"]


# ── Remedies ─────────────────────────────────────────────────────────────────

def test_the_refund_remedy_refunds_in_full_and_reverses_the_doctors_credit(seed, client_for, db):
    s = seed()
    b, pay = _paid(db, s)
    patient = client_for(s["patient"]["id"])
    inc = _report(patient, b["id"], "doctor_not_joined").json()
    res = patient.post(f"/incidents/{inc['id']}/remedy/refund", headers=AUTH)
    assert res.status_code == 200, res.text
    assert _refunds(db, b["id"]) == [{"amount_paise": 60000, "reason": "doctor_no_show", "payment_id": pay["id"]}]
    assert db.table("bookings").select("status, cancelled_by").eq("id", b["id"]).execute().data[0] == \
        {"status": "cancelled", "cancelled_by": "ops"}
    assert _ledger(db, b["id"])[0]["status"] == "reversed"
    assert patient.post(f"/incidents/{inc['id']}/remedy/refund", headers=AUTH).status_code == 409
    other = client_for(s["other_patient"]["id"])
    assert other.post(f"/incidents/{inc['id']}/remedy/refund", headers=AUTH).status_code in (403, 404)


def _replacement_doctor(db, seed, price=500.00):
    other = seed()
    db.table("doctor_pricing").update({"price": price}).eq("doctor_id", other["doctor"]["id"]).execute()
    return other


def _book_replacement(client, inc_id, doctor_id, start):
    return client.post("/bookings/", headers=AUTH, json={
        "doctor_id": doctor_id, "channel": "online_consult", "scheduled_start": start.isoformat(),
        "replaces_incident_id": inc_id})


def _tomorrow(h, m=0):
    d = datetime.now(IST).date() + timedelta(days=1)
    return datetime(d.year, d.month, d.day, h, m, tzinfo=IST)


def test_another_doctor_is_paid_from_the_same_payment(seed, client_for, db):
    s = seed()
    b, pay = _paid(db, s, amount=600.00)
    patient = client_for(s["patient"]["id"])
    inc = _report(patient, b["id"], "doctor_not_joined").json()
    other = _replacement_doctor(db, seed, price=500.00)

    res = _book_replacement(patient, inc["id"], other["doctor"]["id"], _tomorrow(10))
    assert res.status_code == 201, res.text
    new = res.json()
    assert (new["status"], new["price_paise"], new["replaces_booking_id"]) == ("requested", 50000, b["id"])
    # The original is cancelled with no refund yet; its doctor's credit reversed.
    assert db.table("bookings").select("status").eq("id", b["id"]).execute().data[0]["status"] == "cancelled"
    assert _refunds(db, b["id"]) == []
    assert _ledger(db, b["id"])[0]["status"] == "reversed"

    accept = client_for(other["doctor"]["id"], "doctor").patch(f"/bookings/{new['id']}/accept", headers=AUTH)
    assert accept.status_code == 200, accept.text
    assert db.table("bookings").select("status").eq("id", new["id"]).execute().data[0]["status"] == "paid"
    moved = db.table("payments").select("amount, razorpay_payment_id, transferred_from_payment_id") \
        .eq("booking_id", new["id"]).execute().data[0]
    assert (float(moved["amount"]), moved["razorpay_payment_id"], moved["transferred_from_payment_id"]) == \
        (500.0, pay["razorpay_payment_id"], pay["id"])
    assert db.table("payments").select("transferred_out_paise").eq("id", pay["id"]).execute().data[0] \
        ["transferred_out_paise"] == 50000
    # The ₹100 left over goes back; the new doctor is credited ₹500.
    assert _refunds(db, b["id"]) == [{"amount_paise": 10000, "reason": "replacement_difference", "payment_id": pay["id"]}]
    assert float(_ledger(db, new["id"])[0]["net_amount"]) == 500.0

    # Nothing more can come out of the original payment, and a later cancel of
    # the new booking refunds only what it was paid.
    with pytest.raises(Exception):
        db.table("refunds").insert({"payment_id": pay["id"], "booking_id": b["id"], "amount_paise": 1,
                                    "reason": "ops", "idempotency_key": _id()}).execute()
    q = patient.get(f"/bookings/{new['id']}/cancellation-quote", headers=AUTH).json()
    assert q["paid_paise"] == 50000


def test_a_replacement_costing_more_than_was_paid_changes_nothing(seed, client_for, db):
    s = seed()
    b, _ = _paid(db, s, amount=400.00)
    patient = client_for(s["patient"]["id"])
    inc = _report(patient, b["id"], "doctor_not_joined").json()
    other = _replacement_doctor(db, seed, price=900.00)
    res = _book_replacement(patient, inc["id"], other["doctor"]["id"], _tomorrow(11))
    assert res.status_code == 409 and res.json()["budget_paise"] == 40000
    assert db.table("bookings").select("status").eq("id", b["id"]).execute().data[0]["status"] == "paid"
    assert _ledger(db, b["id"])[0]["status"] == "payable"
    # Not the same doctor either.
    assert _book_replacement(patient, inc["id"], s["doctor"]["id"], _tomorrow(11)).status_code == 400


def test_a_declined_replacement_goes_back_to_the_patient_then_defaults_to_a_refund(seed, client_for, db):
    from app.services import remedies

    s = seed()
    b, pay = _paid(db, s, amount=600.00)
    patient = client_for(s["patient"]["id"])
    inc = _report(patient, b["id"], "doctor_not_joined").json()
    other = _replacement_doctor(db, seed, price=500.00)
    new = _book_replacement(patient, inc["id"], other["doctor"]["id"], _tomorrow(12)).json()
    client_for(other["doctor"]["id"], "doctor").patch(f"/bookings/{new['id']}/decline", headers=AUTH)

    assert remedies.sweep()["replacements_reopened"] == 1
    row = db.table("incidents").select("remedy, remedy_booking_id").eq("id", inc["id"]).execute().data[0]
    assert row == {"remedy": "pending", "remedy_booking_id": None}
    # No choice within 24 hours: the patient gets their money back.
    out = remedies.sweep(now=datetime.now(timezone.utc) + timedelta(hours=25))
    assert out["default_refunds"] == 1
    assert _refunds(db, b["id"]) == [{"amount_paise": 60000, "reason": "doctor_no_show", "payment_id": pay["id"]}]


def test_no_default_refund_for_a_visit_that_went_ahead(seed, client_for, db):
    from app.services import remedies

    s = seed()
    b, _ = _paid(db, s)
    inc = _report(client_for(s["patient"]["id"]), b["id"], "doctor_not_joined").json()
    db.table("bookings").update({"status": "in_progress"}).eq("id", b["id"]).execute()
    assert remedies.sweep(now=datetime.now(timezone.utc) + timedelta(hours=25))["default_refunds"] == 0
    assert _refunds(db, b["id"]) == []
    assert db.table("incidents").select("remedy_eligible").eq("id", inc["id"]).execute().data[0]["remedy_eligible"] is False


# ── The doctor's side ────────────────────────────────────────────────────────

def test_responding_stops_automatic_confirmation_and_appeals_reverse(seed, client_for, db):
    s = seed()
    b, _ = _paid(db, s)
    _join(db, b, "patient", s["patient"]["id"])
    inc = _report(client_for(s["patient"]["id"]), b["id"], "doctor_not_joined").json()
    doctor = client_for(s["doctor"]["id"], "doctor")
    res = doctor.post(f"/incidents/{inc['id']}/respond", headers=AUTH,
                      json={"note": "My app crashed on joining; I called the patient."})
    assert res.status_code == 200 and res.json()["status"] == "under_review" and res.json()["auto_confirm_at"] is None
    assert doctor.post(f"/incidents/{inc['id']}/respond", headers=AUTH, json={"note": "Again"}).status_code == 409
    assert doctor.post(f"/incidents/{inc['id']}/appeal", headers=AUTH,
                       json={"note": "Not decided yet so cannot appeal"}).status_code == 409

    ops = client_for(_id(), "ops")
    ops.post(f"/admin/incidents/{inc['id']}/decide", headers=AUTH,
             json={"status": "confirmed", "cause": "doctor", "reason": "No call attempt in logs"})
    assert doctor.get("/doctors/me/reliability", headers=AUTH).json()["counted"] == 1

    case = doctor.get("/doctors/me/reliability", headers=AUTH).json()["cases"][0]
    assert case["can_appeal"] is True and "patient_note" not in case
    assert doctor.post(f"/incidents/{inc['id']}/appeal", headers=AUTH,
                       json={"note": "Here is the crash report from my phone."}).status_code == 200
    assert doctor.post(f"/incidents/{inc['id']}/appeal", headers=AUTH,
                       json={"note": "Second appeal attempt here."}).status_code == 409
    assert ops.get("/admin/incidents?view=appealed", headers=AUTH).json()[0]["id"] == inc["id"]
    ops.post(f"/admin/incidents/{inc['id']}/appeal-decision", headers=AUTH,
             json={"outcome": "reversed", "reason": "Crash confirmed by Agora logs"})
    assert doctor.get("/doctors/me/reliability", headers=AUTH).json()["counted"] == 0


def test_appeals_close_after_seven_days(seed, client_for, db):
    s = seed()
    b, _ = _paid(db, s)
    inc = db.table("incidents").insert({
        "booking_id": b["id"], "doctor_id": s["doctor"]["id"], "patient_id": s["patient"]["id"],
        "type": "doctor_no_show", "reported_by_role": "patient", "status": "confirmed", "cause": "doctor",
        "decided_at": (datetime.now(timezone.utc) - timedelta(days=8)).isoformat()}).execute().data[0]
    res = client_for(s["doctor"]["id"], "doctor").post(f"/incidents/{inc['id']}/appeal", headers=AUTH,
                                                       json={"note": "I was there, honestly."})
    assert res.status_code == 409 and "7 days" in res.json()["error"]


def test_a_late_doctor_cancel_counts_and_an_early_one_doesnt(seed, client_for, db):
    s = seed()
    soon, _ = _paid(db, s, minutes_from_now=60)
    later, _ = _paid(db, s, minutes_from_now=60 * 24)
    doctor = client_for(s["doctor"]["id"], "doctor")
    assert doctor.patch(f"/bookings/{soon['id']}/cancel", headers=AUTH, json={}).status_code == 200
    assert doctor.patch(f"/bookings/{later['id']}/cancel", headers=AUTH, json={}).status_code == 200
    kinds = db.table("incidents").select("booking_id, type, status, cause").eq("doctor_id", s["doctor"]["id"]).execute().data
    assert kinds == [{"booking_id": soon["id"], "type": "doctor_late_cancel", "status": "confirmed", "cause": "doctor"}]


# ── Reschedules ──────────────────────────────────────────────────────────────

def test_a_reschedule_moves_the_same_booking_at_the_same_price(seed, client_for, db):
    from app.services import jobs

    s = seed()
    b, _ = _paid(db, s, minutes_from_now=-5)
    db.table("bookings").update({"status": "in_progress"}).eq("id", b["id"]).execute()
    doctor = client_for(s["doctor"]["id"], "doctor")
    times = [_tomorrow(9).isoformat(), _tomorrow(9, 30).isoformat()]
    too_soon = (datetime.now(IST) + timedelta(minutes=10)).isoformat()
    assert doctor.post(f"/bookings/{b['id']}/reschedule-requests", headers=AUTH, json={
        "cause": "doctor_device", "options": [too_soon]}).status_code == 400
    res = doctor.post(f"/bookings/{b['id']}/reschedule-requests", headers=AUTH,
                      json={"cause": "doctor_device", "options": times, "note": "Network dropped"})
    assert res.status_code == 201, res.text
    req = res.json()
    assert doctor.post(f"/bookings/{b['id']}/reschedule-requests", headers=AUTH,
                       json={"cause": "doctor_device", "options": times}).status_code == 409

    patient = client_for(s["patient"]["id"])
    help_ = patient.get(f"/bookings/{b['id']}/help", headers=AUTH).json()
    assert help_["reschedule_request"]["id"] == req["id"]
    assert patient.post(f"/reschedule-requests/{req['id']}/accept", headers=AUTH,
                        json={"start": _tomorrow(10).isoformat()}).status_code == 400
    res = patient.post(f"/reschedule-requests/{req['id']}/accept", headers=AUTH, json={"start": times[1]})
    assert res.status_code == 200, res.text
    row = db.table("bookings").select("status, scheduled_start, scheduled_end, price_paise, started_at") \
        .eq("id", b["id"]).execute().data[0]
    start = datetime.fromisoformat(row["scheduled_start"])
    assert row["status"] == "paid" and start == datetime.fromisoformat(times[1])
    assert datetime.fromisoformat(row["scheduled_end"]) - start == timedelta(minutes=15)
    assert row["price_paise"] == 60000 and row["started_at"] is None
    assert db.table("booking_events").select("event").eq("booking_id", b["id"]).eq("event", "rescheduled").execute().data
    # The doctor's own device: counts, and they said so.
    inc = db.table("incidents").select("type, cause, status, remedy").eq("booking_id", b["id"]).execute().data[0]
    assert inc == {"type": "doctor_reschedule", "cause": "doctor", "status": "confirmed", "remedy": "rescheduled"}
    # Reminders for the new time (the old ones skip themselves).
    starts = [datetime.fromisoformat(j["payload"]["start"]) for j in
              db.table("jobs").select("payload").eq("kind", "booking.reminder").execute().data]
    assert datetime.fromisoformat(times[1]) in starts


def test_declining_or_ignoring_a_reschedule_refunds_in_full(seed, client_for, db):
    from app.services import reschedules

    s = seed()
    b1, _ = _paid(db, s, minutes_from_now=-5)
    b2, _ = _paid(db, s, minutes_from_now=-40)
    doctor = client_for(s["doctor"]["id"], "doctor")
    r1 = doctor.post(f"/bookings/{b1['id']}/reschedule-requests", headers=AUTH,
                     json={"cause": "platform", "options": [_tomorrow(14).isoformat()]}).json()
    r2 = doctor.post(f"/bookings/{b2['id']}/reschedule-requests", headers=AUTH,
                     json={"cause": "mutual", "options": [_tomorrow(15).isoformat()]}).json()
    patient = client_for(s["patient"]["id"])
    assert patient.post(f"/reschedule-requests/{r1['id']}/decline", headers=AUTH).status_code == 200
    assert _refunds(db, b1["id"])[0]["amount_paise"] == 60000

    db.table("reschedule_requests").update({"expires_at": (datetime.now(timezone.utc) - timedelta(minutes=1)).isoformat()}) \
        .eq("id", r2["id"]).execute()
    assert reschedules.expire_due() == 1
    assert _refunds(db, b2["id"])[0]["amount_paise"] == 60000
    # Neither cause counts against the doctor.
    assert doctor.get("/doctors/me/reliability", headers=AUTH).json()["counted"] == 0


def test_complaints_get_a_case_reference(seed, client_for, db):
    s = seed()
    b, _ = _paid(db, s)
    res = client_for(s["patient"]["id"]).post(f"/bookings/{b['id']}/complaint", headers=AUTH,
                                              json={"description": "The doctor was rude."})
    assert res.status_code == 201 and res.json()["case_ref"].startswith("CHK-")
