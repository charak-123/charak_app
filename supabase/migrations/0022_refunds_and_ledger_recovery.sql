-- ═══════════════════════════════════════════════════════════════════════════
-- 0022: refunds are tracked rather than assumed; cancelling recovers money
-- that was already paid out instead of failing halfway; cancellation is one
-- transaction.
--
-- Before this migration:
--
--   * A cancel flipped payments.status to 'refunded' *before* calling Razorpay,
--     and a refund that Razorpay rejected was only logged. The patient could be
--     left without their money, and every record said they had it.
--   * Cancelling a booking whose ledger entry had already been swept into a
--     payout raised a 409 from payouts.reverse() *after* the booking had been
--     cancelled and the refund sent. The doctor kept the payout, the patient
--     got the refund, and CHARAK paid twice.
--   * The steps of a cancel (booking status, payment, refund, ledger) were
--     separate HTTP calls through PostgREST, so a crash between them left the
--     record half-changed.
--
-- After it:
--
--   * Every refund is a row in `refunds` with its own lifecycle
--     (pending → processing → processed | failed). The payment stays
--     'completed' until Razorpay confirms the refund, then becomes 'refunded'
--     or 'partially_refunded'.
--   * A trigger stops refunds on one payment from ever adding up to more than
--     was paid.
--   * cancel_booking() changes the booking, queues the refunds and reverses
--     the ledger credit in one transaction, under a row lock. The backend calls
--     Razorpay only after it commits.
--   * A ledger entry that has already been paid out is never edited. A
--     negative 'reversal' entry is added instead, and the doctor's next payout
--     recovers it.
--
-- Idempotent: safe to re-run in the SQL Editor.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. Payment statuses ──────────────────────────────────────────────────────
-- 'refunded' now means "Razorpay confirmed the whole amount came back", not
-- "we asked for it". 'partially_refunded' is for when only part did.
alter table payments drop constraint if exists payments_status_check;
alter table payments add constraint payments_status_check
  check (status in ('initiated', 'completed', 'failed', 'refunded', 'partially_refunded'));

-- ── 2. Refunds ───────────────────────────────────────────────────────────────
create table if not exists refunds (
  id                 uuid primary key default uuid_generate_v4(),
  payment_id         uuid not null references payments(id),
  booking_id         uuid not null references bookings(id),
  -- Paise, not rupees: refund arithmetic has to be exact, and Razorpay's API
  -- takes paise anyway.
  amount_paise       bigint not null check (amount_paise > 0),
  currency           text not null default 'INR' check (currency = 'INR'),
  -- Why the money is going back:
  --   booking_cancelled  a paid booking was cancelled
  --   late_capture       money arrived after the booking was already gone
  --   ops                ops refunded it (from the admin, or straight from the
  --                      Razorpay dashboard and picked up by the webhook)
  reason             text not null
                     check (reason in ('booking_cancelled', 'late_capture', 'ops')),
  -- One logical refund per key, however many times a cancel or a webhook is
  -- retried. Usually '<payment id>:<reason>'.
  idempotency_key    text not null unique,
  status             text not null default 'pending'
                     check (status in ('pending', 'processing', 'processed', 'failed')),
  razorpay_refund_id text unique,
  -- Earlier Razorpay refunds for this row that failed and were retried by ops.
  -- Kept for the record, and so a late webhook about one of them can be
  -- recognised as stale instead of failing the attempt now in flight.
  superseded_razorpay_refund_ids text[] not null default '{}',
  attempts           int not null default 0,
  last_attempt_at    timestamptz,
  failure_reason     text,
  requested_by_role  text not null
                     check (requested_by_role in ('patient', 'doctor', 'ops', 'system')),
  requested_by       uuid,
  processed_at       timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

create index if not exists idx_refunds_booking on refunds (booking_id);
create index if not exists idx_refunds_payment on refunds (payment_id);
-- The retry sweep and the admin queue only ever look at unfinished refunds.
create index if not exists idx_refunds_open
  on refunds (status, last_attempt_at)
  where status in ('pending', 'processing', 'failed');

drop trigger if exists trg_refunds_updated_at on refunds;
create trigger trg_refunds_updated_at
  before update on refunds
  for each row execute function set_updated_at();

-- Refunds on one payment can never add up to more than the payment. Checked in
-- the database, under a lock on the payment row, so two concurrent cancels or a
-- cancel racing a webhook can't both get past an application-level check.
create or replace function refunds_guard()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_paid_paise bigint;
  v_queued     bigint;
begin
  if tg_op = 'UPDATE' then
    if new.amount_paise is distinct from old.amount_paise
       or new.payment_id is distinct from old.payment_id then
      raise exception 'a refund''s amount and payment cannot change once recorded'
        using errcode = 'check_violation';
    end if;
    return new;
  end if;

  -- A retried insert with the same key is resolved by ON CONFLICT DO NOTHING.
  -- BEFORE triggers run before that check, so let it through here rather than
  -- counting the existing row twice and raising.
  if exists (select 1 from refunds where idempotency_key = new.idempotency_key) then
    return new;
  end if;

  select round(amount * 100)::bigint into v_paid_paise
    from payments where id = new.payment_id
    for update;
  if v_paid_paise is null then
    raise exception 'refund references unknown payment %', new.payment_id
      using errcode = 'foreign_key_violation';
  end if;

  select coalesce(sum(amount_paise), 0) into v_queued
    from refunds where payment_id = new.payment_id;

  if v_queued + new.amount_paise > v_paid_paise then
    raise exception 'refunds on payment % would exceed the amount paid (% + % > % paise)',
      new.payment_id, v_queued, new.amount_paise, v_paid_paise
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_refunds_guard on refunds;
create trigger trg_refunds_guard
  before insert or update on refunds
  for each row execute function refunds_guard();

alter table refunds enable row level security;
revoke all on refunds from anon, authenticated;
grant all on refunds to service_role;

-- ── 3. Ledger: recover instead of editing paid-out history ──────────────────
alter table doctor_ledger_entries drop constraint if exists doctor_ledger_entries_source_check;
alter table doctor_ledger_entries add constraint doctor_ledger_entries_source_check
  check (source in ('consult_fee', 'procedure_bill', 'adjustment', 'reversal'));

alter table doctor_ledger_entries
  add column if not exists reverses_entry_id uuid references doctor_ledger_entries(id);

-- An entry is reversed at most once.
create unique index if not exists uq_ledger_reverses_entry
  on doctor_ledger_entries (reverses_entry_id)
  where reverses_entry_id is not null;

-- Still one credit per (booking, source). Reversals are excluded because a
-- booking with both a consult fee and a procedure bill can need two of them,
-- each keyed by the entry it reverses.
drop index if exists uq_ledger_booking_source;
create unique index uq_ledger_booking_source
  on doctor_ledger_entries (booking_id, source)
  where booking_id is not null and source <> 'reversal';

-- Only a reversal can be negative, and only a reversal can point at another
-- entry.
alter table doctor_ledger_entries drop constraint if exists doctor_ledger_entries_reversal_shape;
alter table doctor_ledger_entries add constraint doctor_ledger_entries_reversal_shape check (
  ((source = 'reversal') = (reverses_entry_id is not null))
  and (source = 'reversal' or (gross_amount >= 0 and net_amount >= 0))
  and (source <> 'reversal' or (gross_amount <= 0 and net_amount <= 0))
);

-- Reverse the credit for one (booking, source).
--   payable  → marked reversed (the money never left)
--   paid     → a negative 'reversal' entry; the next payout recovers it
--   reversed → nothing to do
-- Returns the entry that now represents the reversal, or null if the booking
-- was never credited.
create or replace function reverse_ledger_credit(
  p_booking_id uuid,
  p_source     text,
  p_note       text
) returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_entry doctor_ledger_entries%rowtype;
  v_rev   doctor_ledger_entries%rowtype;
begin
  select * into v_entry
    from doctor_ledger_entries
   where booking_id = p_booking_id and source = p_source
   for update;
  if not found then
    return null;
  end if;

  if v_entry.status = 'reversed' then
    return to_jsonb(v_entry);
  end if;

  if v_entry.status = 'payable' then
    update doctor_ledger_entries
       set status = 'reversed', note = p_note
     where id = v_entry.id
    returning * into v_entry;
    return to_jsonb(v_entry);
  end if;

  insert into doctor_ledger_entries (
    doctor_id, booking_id, source, gross_amount, commission_pct,
    commission_amount, net_amount, status, note, reverses_entry_id
  ) values (
    v_entry.doctor_id, v_entry.booking_id, 'reversal', -v_entry.gross_amount,
    v_entry.commission_pct, -v_entry.commission_amount, -v_entry.net_amount,
    'payable', p_note, v_entry.id
  )
  on conflict (reverses_entry_id) where reverses_entry_id is not null do nothing
  returning * into v_rev;

  if not found then
    select * into v_rev from doctor_ledger_entries where reverses_entry_id = v_entry.id;
  end if;
  return to_jsonb(v_rev);
end;
$$;

-- ── 4. Cancel in one transaction ─────────────────────────────────────────────
-- Locks the booking, checks it is still in the status the caller decided on,
-- cancels it, fails any unpaid payment attempt, queues a refund for whatever
-- is still unrefunded on each completed payment, and reverses the doctor's
-- credit. Razorpay is never called from here: the backend does that after
-- this commits, and the retry sweep picks up anything it didn't finish.
--
-- Returns {"outcome": "cancelled" | "conflict" | "not_cancellable" | "not_found",
--          "status": <current status>, "booking": {...}, "refunds": [...]}.
create or replace function cancel_booking(
  p_booking_id      uuid,
  p_expected_status text,
  p_cancelled_by    text,
  p_actor_id        uuid
) returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_booking  bookings%rowtype;
  v_payment  payments%rowtype;
  v_refund   refunds%rowtype;
  v_refunds  jsonb := '[]'::jsonb;
  v_queued   bigint;
  v_due      bigint;
begin
  select * into v_booking from bookings where id = p_booking_id for update;
  if not found then
    return jsonb_build_object('outcome', 'not_found');
  end if;

  if v_booking.status in ('completed', 'cancelled', 'declined', 'no_show') then
    return jsonb_build_object('outcome', 'not_cancellable', 'status', v_booking.status);
  end if;
  if v_booking.status <> p_expected_status then
    return jsonb_build_object('outcome', 'conflict', 'status', v_booking.status);
  end if;

  update bookings
     set status = 'cancelled', cancelled_by = p_cancelled_by, hold_expires_at = null
   where id = p_booking_id
  returning * into v_booking;

  -- An attempt still open in a UPI app dies with the booking. If it captures
  -- anyway, the webhook sees a cancelled booking and refunds it.
  update payments set status = 'failed'
   where booking_id = p_booking_id and status = 'initiated';

  for v_payment in
    select * from payments
     where booking_id = p_booking_id and status = 'completed'
     order by created_at
     for update
  loop
    select coalesce(sum(amount_paise), 0) into v_queued
      from refunds where payment_id = v_payment.id;
    v_due := round(v_payment.amount * 100)::bigint - v_queued;

    if v_due > 0 then
      insert into refunds (
        payment_id, booking_id, amount_paise, reason, idempotency_key,
        requested_by_role, requested_by
      ) values (
        v_payment.id, p_booking_id, v_due, 'booking_cancelled',
        v_payment.id::text || ':booking_cancelled', p_cancelled_by, p_actor_id
      )
      on conflict (idempotency_key) do nothing
      returning * into v_refund;
      if found then
        v_refunds := v_refunds || jsonb_build_array(to_jsonb(v_refund));
      end if;
    end if;

    perform reverse_ledger_credit(
      p_booking_id,
      case when v_payment.type = 'consult_fee' then 'consult_fee' else 'procedure_bill' end,
      'booking cancelled by ' || p_cancelled_by
    );
  end loop;

  return jsonb_build_object(
    'outcome', 'cancelled',
    'status', v_booking.status,
    'booking', to_jsonb(v_booking),
    'refunds', v_refunds
  );
end;
$$;

-- ── 5. Who may call these ────────────────────────────────────────────────────
-- Postgres grants EXECUTE on new functions to PUBLIC, and Supabase's default
-- privileges also grant them to anon and authenticated. That would make every
-- function here callable through PostgREST with the anon key that ships in the
-- apps. 0021 closed tables and sequences; this closes functions. They're also
-- `security invoker`, so even a stray grant can't reach tables the caller's
-- role can't.
revoke execute on function reverse_ledger_credit(uuid, text, text) from public, anon, authenticated;
revoke execute on function cancel_booking(uuid, text, text, uuid)  from public, anon, authenticated;
revoke execute on function refunds_guard()                         from public, anon, authenticated;
revoke execute on function set_updated_at()                        from public, anon, authenticated;
revoke execute on function update_doctor_rating_avg()              from public, anon, authenticated;
revoke execute on function log_procedure_bill_create()             from public, anon, authenticated;

grant execute on function reverse_ledger_credit(uuid, text, text) to service_role;
grant execute on function cancel_booking(uuid, text, text, uuid)  to service_role;

-- Functions created from now on start closed too.
alter default privileges for role postgres in schema public
  revoke execute on functions from public, anon, authenticated;

-- ── Verify ───────────────────────────────────────────────────────────────────
-- Expect no rows (nothing callable by the client roles):
--   select p.proname, r.rolname
--     from pg_proc p
--     join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public'
--     cross join (values ('anon'), ('authenticated')) r(rolname)
--    where has_function_privilege(r.rolname, p.oid, 'execute')
--      and p.proname in ('cancel_booking', 'reverse_ledger_credit');
