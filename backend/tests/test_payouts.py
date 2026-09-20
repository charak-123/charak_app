"""
Tests for the commission and payout engine.

This is the money path, so the properties under test are the ones that cost real
rupees if wrong: the split arithmetic, idempotent crediting, and a failed payout
returning the doctor's earnings to payable rather than swallowing them.
"""
from decimal import Decimal
from unittest.mock import MagicMock, patch

import pytest
from fastapi.testclient import TestClient

from app.errors import AppError
from app.main import app
from app.services import payouts as engine
from tests.conftest import make_chain, make_supabase

DOCTOR_PAYLOAD = {"sub": "doc-1", "role": "doctor"}
OPS_PAYLOAD    = {"sub": "admin", "role": "ops"}
AUTH           = {"Authorization": "Bearer t"}

ENGINE_DB = "app.services.payouts.supabase"
ROUTER_DB = "app.routers.payouts.supabase"
JWT       = "app.deps.jwt"


# ── split arithmetic ──────────────────────────────────────────────────────────

def test_split_uses_money_rounding_not_float_rounding():
    gross, commission, net = engine.split(1000, 15)
    assert (gross, commission, net) == (Decimal("1000.00"), Decimal("150.00"), Decimal("850.00"))


def test_split_rounds_half_up_to_paise():
    # 15% of 333.33 is 49.9995 — must land on 50.00, and net must still sum back.
    gross, commission, net = engine.split("333.33", 15)
    assert commission == Decimal("50.00")
    assert net == Decimal("283.33")
    assert commission + net == gross


def test_split_at_zero_commission_gives_doctor_everything():
    gross, commission, net = engine.split(500, 0)
    assert commission == Decimal("0.00")
    assert net == gross


def test_split_never_loses_a_paisa():
    """commission + net == gross for every amount, which is the invariant that
    keeps the ledger reconcilable against the bank."""
    for amount in ("1", "9.99", "100.05", "1234.56", "7777.77"):
        gross, commission, net = engine.split(amount, 15)
        assert commission + net == gross, amount


# ── commission_pct_for ────────────────────────────────────────────────────────

def test_commission_pct_falls_back_to_platform_default():
    db = make_supabase({"doctors": make_chain(list_data=[{"commission_pct": None}])})
    with patch(ENGINE_DB, db), patch("app.services.payouts.PLATFORM_COMMISSION_PCT", 15.0):
        assert engine.commission_pct_for("doc-1") == Decimal("15.00")


def test_commission_pct_uses_per_doctor_override():
    db = make_supabase({"doctors": make_chain(list_data=[{"commission_pct": 8.5}])})
    with patch(ENGINE_DB, db):
        assert engine.commission_pct_for("doc-1") == Decimal("8.50")


def test_commission_pct_override_of_zero_is_honoured():
    """A 0% doctor must not be silently bumped back to the platform default —
    `if not override` would have done exactly that."""
    db = make_supabase({"doctors": make_chain(list_data=[{"commission_pct": 0}])})
    with patch(ENGINE_DB, db):
        assert engine.commission_pct_for("doc-1") == Decimal("0.00")


# ── credit ────────────────────────────────────────────────────────────────────

def _credit_db(existing_entries, doctor_pct=15):
    """Ledger chain: first execute = the duplicate lookup, second = the insert."""
    calls = {"n": 0}
    ledger = make_chain()

    def _exec():
        calls["n"] += 1
        if calls["n"] == 1:
            return MagicMock(data=existing_entries)
        return MagicMock(data=[{"id": "led-1", "net_amount": 850.0}])

    ledger.execute.side_effect = _exec
    return make_supabase({
        "doctors": make_chain(list_data=[{"commission_pct": doctor_pct}]),
        "doctor_ledger_entries": ledger,
    }), ledger


def test_credit_records_the_split():
    db, ledger = _credit_db(existing_entries=[])
    with patch(ENGINE_DB, db):
        entry = engine.credit("doc-1", 1000, "consult_fee", booking_id="bk-1")

    assert entry["id"] == "led-1"
    written = ledger.insert.call_args[0][0]
    assert written["gross_amount"] == 1000.0
    assert written["commission_amount"] == 150.0
    assert written["net_amount"] == 850.0
    assert written["status"] == "payable"


def test_credit_is_idempotent_per_booking_and_source():
    """A replayed Razorpay webhook must not pay the doctor twice."""
    existing = {"id": "led-existing", "net_amount": 850.0, "status": "payable"}
    db, ledger = _credit_db(existing_entries=[existing])
    with patch(ENGINE_DB, db):
        entry = engine.credit("doc-1", 1000, "consult_fee", booking_id="bk-1")

    assert entry["id"] == "led-existing"
    ledger.insert.assert_not_called()


def test_credit_ignores_zero_and_negative_amounts():
    db, ledger = _credit_db(existing_entries=[])
    with patch(ENGINE_DB, db):
        assert engine.credit("doc-1", 0, "consult_fee", booking_id="bk-1") is None
        assert engine.credit("doc-1", -50, "consult_fee", booking_id="bk-1") is None
    ledger.insert.assert_not_called()


def test_credit_rejects_an_unknown_source():
    with patch(ENGINE_DB, make_supabase({})):
        with pytest.raises(AppError) as exc:
            engine.credit("doc-1", 100, "tips", booking_id="bk-1")
    assert exc.value.status_code == 400


# ── reverse ───────────────────────────────────────────────────────────────────

def test_reverse_marks_a_payable_entry_reversed():
    ledger = make_chain()
    ledger.execute.side_effect = [
        MagicMock(data=[{"id": "led-1", "status": "payable"}]),
        MagicMock(data=[{"id": "led-1", "status": "reversed"}]),
    ]
    with patch(ENGINE_DB, make_supabase({"doctor_ledger_entries": ledger})):
        assert engine.reverse("bk-1", "consult_fee")["status"] == "reversed"


def test_reverse_refuses_an_already_paid_entry():
    """The money has already left the account; the correction belongs in an
    adjustment, not a silent rewrite of history."""
    ledger = make_chain(list_data=[{"id": "led-1", "status": "paid"}])
    with patch(ENGINE_DB, make_supabase({"doctor_ledger_entries": ledger})):
        with pytest.raises(AppError) as exc:
            engine.reverse("bk-1", "consult_fee")
    assert exc.value.status_code == 409


# ── balance ───────────────────────────────────────────────────────────────────

def test_balance_excludes_reversed_entries_from_totals():
    entries = [
        {"gross_amount": 1000, "commission_amount": 150, "net_amount": 850, "status": "payable",  "source": "consult_fee"},
        {"gross_amount": 2000, "commission_amount": 300, "net_amount": 1700, "status": "paid",     "source": "consult_fee"},
        {"gross_amount": 500,  "commission_amount": 75,  "net_amount": 425,  "status": "reversed", "source": "consult_fee"},
    ]
    with patch(ENGINE_DB, make_supabase({"doctor_ledger_entries": make_chain(list_data=entries)})):
        b = engine.balance("doc-1")

    assert b["payable_net"] == 850.0
    assert b["paid_net"] == 1700.0
    assert b["lifetime_gross"] == 3000.0          # reversed 500 excluded
    assert b["lifetime_commission"] == 450.0
    assert b["entry_count"] == 2


# ── create_payout ─────────────────────────────────────────────────────────────

def _payout_db(entries, bank=(("bank-1",)), payout_row=None):
    ledger = make_chain()
    ledger.execute.side_effect = [
        MagicMock(data=entries),     # the sweep query
        MagicMock(data=entries),     # the attach update
    ]
    return make_supabase({
        "doctor_ledger_entries": ledger,
        "doctor_bank_accounts": make_chain(list_data=[{"id": "bank-1"}] if bank else []),
        "payouts": make_chain(list_data=[payout_row or {
            "id": "po-1", "doctor_id": "doc-1", "net_amount": 1700.0, "status": "pending",
        }]),
    }), ledger


def test_create_payout_sums_the_swept_entries():
    entries = [
        {"id": "l1", "gross_amount": 1000, "commission_amount": 150, "net_amount": 850},
        {"id": "l2", "gross_amount": 1000, "commission_amount": 150, "net_amount": 850},
    ]
    db, ledger = _payout_db(entries)
    with patch(ENGINE_DB, db):
        payout = engine.create_payout("doc-1", "2026-09-01T00:00:00+00:00", "2026-09-30T00:00:00+00:00")

    written = db.table("payouts").insert.call_args[0][0]
    assert written["gross_amount"] == 2000.0
    assert written["commission_amount"] == 300.0
    assert written["net_amount"] == 1700.0
    assert payout["entry_count"] == 2
    # Entries are flipped to paid and stamped with the payout id.
    assert ledger.update.call_args[0][0] == {"status": "paid", "payout_id": "po-1"}


def test_create_payout_refuses_when_nothing_is_payable():
    db, _ = _payout_db([])
    with patch(ENGINE_DB, db):
        with pytest.raises(AppError) as exc:
            engine.create_payout("doc-1", "2026-09-01T00:00:00+00:00", "2026-09-30T00:00:00+00:00")
    assert exc.value.status_code == 400


def test_create_payout_refuses_without_a_bank_account():
    """Paying out to nowhere is worse than refusing to pay out."""
    entries = [{"id": "l1", "gross_amount": 100, "commission_amount": 15, "net_amount": 85}]
    db, _ = _payout_db(entries, bank=())
    with patch(ENGINE_DB, db):
        with pytest.raises(AppError) as exc:
            engine.create_payout("doc-1", "2026-09-01T00:00:00+00:00", "2026-09-30T00:00:00+00:00")
    assert "bank account" in exc.value.message


# ── mark_payout ───────────────────────────────────────────────────────────────

def test_marking_paid_stamps_paid_at():
    payouts_chain = make_chain()
    payouts_chain.execute.side_effect = [
        MagicMock(data=[{"id": "po-1", "status": "pending", "doctor_id": "doc-1"}]),
        MagicMock(data=[{"id": "po-1", "status": "paid"}]),
    ]
    with patch(ENGINE_DB, make_supabase({"payouts": payouts_chain})):
        engine.mark_payout("po-1", "paid", reference="UTR123")

    written = payouts_chain.update.call_args[0][0]
    assert written["status"] == "paid"
    assert written["reference"] == "UTR123"
    assert "paid_at" in written


def test_failed_payout_returns_entries_to_payable():
    """The doctor is still owed the money — the next run must pick it up again."""
    payouts_chain = make_chain()
    payouts_chain.execute.side_effect = [
        MagicMock(data=[{"id": "po-1", "status": "processing", "doctor_id": "doc-1"}]),
        MagicMock(data=[{"id": "po-1", "status": "failed"}]),
    ]
    ledger = make_chain(list_data=[])
    with patch(ENGINE_DB, make_supabase({"payouts": payouts_chain, "doctor_ledger_entries": ledger})):
        engine.mark_payout("po-1", "failed", failure_reason="IFSC rejected")

    assert ledger.update.call_args[0][0] == {"status": "payable", "payout_id": None}


def test_mark_payout_rejects_an_invalid_status():
    with patch(ENGINE_DB, make_supabase({})):
        with pytest.raises(AppError) as exc:
            engine.mark_payout("po-1", "cancelled")
    assert exc.value.status_code == 400


# ── routes ────────────────────────────────────────────────────────────────────

def _client(payload, db):
    with patch(ROUTER_DB, db), patch(ENGINE_DB, db), patch(JWT) as jw:
        jw.decode.return_value = payload
        yield TestClient(app)


def test_balance_route_reports_the_commission_rate():
    entries = [{"gross_amount": 1000, "commission_amount": 150, "net_amount": 850,
                "status": "payable", "source": "consult_fee"}]
    db = make_supabase({
        "doctor_ledger_entries": make_chain(list_data=entries),
        "doctors": make_chain(list_data=[{"commission_pct": 15}]),
    })
    for c in _client(DOCTOR_PAYLOAD, db):
        res = c.get("/payouts/me/balance", headers=AUTH)
        assert res.status_code == 200
        assert res.json()["payable_net"] == 850.0
        assert res.json()["commission_pct"] == 15.0


def test_bank_account_masks_the_number_in_responses():
    saved = {
        "id": "bank-1", "doctor_id": "doc-1", "account_holder": "Dr A Sharma",
        "account_number": "123456789012", "ifsc": "HDFC0001234", "verified": False,
    }
    db = make_supabase({"doctor_bank_accounts": make_chain(list_data=[saved])})
    for c in _client(DOCTOR_PAYLOAD, db):
        res = c.put("/payouts/me/bank-account", headers=AUTH, json={
            "account_holder": "Dr A Sharma",
            "account_number": "123456789012",
            "ifsc": "hdfc0001234",
            "bank_name": "HDFC",
        })
        assert res.status_code == 200
        assert res.json()["account_number"] == "••••9012"


def test_bank_account_rejects_a_malformed_ifsc():
    db = make_supabase({})
    for c in _client(DOCTOR_PAYLOAD, db):
        res = c.put("/payouts/me/bank-account", headers=AUTH, json={
            "account_holder": "Dr A Sharma",
            "account_number": "123456789012",
            "ifsc": "NOTANIFSC",
        })
        assert res.status_code == 422


def test_saving_a_bank_account_clears_the_verified_flag():
    db = make_supabase({"doctor_bank_accounts": make_chain(list_data=[{
        "id": "b1", "doctor_id": "doc-1", "account_number": "999988887777",
        "ifsc": "HDFC0001234", "account_holder": "Dr A", "verified": False,
    }])})
    for c in _client(DOCTOR_PAYLOAD, db):
        c.put("/payouts/me/bank-account", headers=AUTH, json={
            "account_holder": "Dr A",
            "account_number": "999988887777",
            "ifsc": "HDFC0001234",
        })
    assert db.table("doctor_bank_accounts").upsert.call_args[0][0]["verified"] is False


def test_marking_a_payout_paid_requires_a_bank_reference():
    """Every rupee that leaves the account must be traceable to a transaction."""
    db = make_supabase({})
    for c in _client(OPS_PAYLOAD, db):
        res = c.patch("/payouts/po-1", headers=AUTH, json={"status": "paid"})
        assert res.status_code == 400
        assert "reference" in res.json()["error"]


def test_pending_summary_groups_by_doctor():
    entries = [
        {"doctor_id": "doc-1", "net_amount": 850, "gross_amount": 1000,
         "commission_amount": 150, "doctors": {"name": "Dr A", "phone": "+91"}},
        {"doctor_id": "doc-1", "net_amount": 850, "gross_amount": 1000,
         "commission_amount": 150, "doctors": {"name": "Dr A", "phone": "+91"}},
        {"doctor_id": "doc-2", "net_amount": 425, "gross_amount": 500,
         "commission_amount": 75, "doctors": {"name": "Dr B", "phone": "+92"}},
    ]
    db = make_supabase({"doctor_ledger_entries": make_chain(list_data=entries)})
    for c in _client(OPS_PAYLOAD, db):
        body = c.get("/payouts/pending-summary", headers=AUTH).json()

    assert body["total_net"] == 2125.0
    assert body["total_commission"] == 375.0
    assert body["doctors"][0]["doctor_id"] == "doc-1"    # sorted by net, descending
    assert body["doctors"][0]["entry_count"] == 2


def test_adjustment_applies_no_commission():
    """A goodwill payment reaches the doctor in full."""
    db = make_supabase({"doctor_ledger_entries": make_chain(list_data=[{"id": "adj-1"}])})
    for c in _client(OPS_PAYLOAD, db):
        res = c.post("/payouts/adjustments", headers=AUTH, json={
            "doctor_id": "doc-1", "amount": 500, "note": "travel reimbursement",
        })
        assert res.status_code == 201

    written = db.table("doctor_ledger_entries").insert.call_args[0][0]
    assert written["commission_amount"] == 0
    assert written["net_amount"] == 500.0
    assert written["source"] == "adjustment"


def test_doctor_cannot_reach_ops_payout_endpoints():
    db = make_supabase({})
    for c in _client(DOCTOR_PAYLOAD, db):
        assert c.get("/payouts/pending-summary", headers=AUTH).status_code == 403
        assert c.post("/payouts/run", headers=AUTH, json={"doctor_id": "doc-1"}).status_code == 403
