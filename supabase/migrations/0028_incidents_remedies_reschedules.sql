-- ═══════════════════════════════════════════════════════════════════════════
-- 0028: when a visit goes wrong (spec §12.6–12.7, §13, §14; decisions D5–D12
-- at their recommended defaults).
--
--   incidents            what went wrong, who said so, the evidence, and what
--                        ops decided: reported → under_review → confirmed |
--                        dismissed | undetermined; a confirmed one can be
--                        appealed once (upheld | reversed). Only confirmed,
--                        doctor-caused, not-reversed incidents count against a
--                        doctor's reliability. Every step is an incident_event.
--   case refs            CHK-XXXXX on every incident and complaint, for support
--   remedies             when the evidence supports it (or ops says so), the
--                        patient chooses a full refund or another doctor paid
--                        from the same payment: no wallet, no credit balance.
--                        The original payment is re-pointed to the replacement
--                        booking when the new doctor accepts, and anything left
--                        over is refunded against it.
--   reschedule_requests  the doctor can't make it (or the call failed) and
--                        proposes new times; the patient picks one or takes a
--                        refund. Same booking, same price.
--
-- Idempotent: safe to re-run in the SQL Editor.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. Support case references ───────────────────────────────────────────────
-- CHK- and five characters a person can read out on the phone (no 0/O, 1/I).
create or replace function new_case_ref()
returns text
language sql
volatile
as $$
  select 'CHK-' || string_agg(substr('23456789ABCDEFGHJKLMNPQRSTUVWXYZ', 1 + floor(random() * 32)::int, 1), '')
    from generate_series(1, 5)
$$;

alter table complaints add column if not exists case_ref text default new_case_ref();
update complaints set case_ref = new_case_ref() where case_ref is null;
create unique index if not exists uq_complaints_case_ref on complaints (case_ref);

-- ── 2. Incidents ─────────────────────────────────────────────────────────────
create table if not exists incidents (
  id               uuid primary key default uuid_generate_v4(),
  case_ref         text not null unique default new_case_ref(),
  booking_id       uuid not null references bookings(id) on delete cascade,
  doctor_id        uuid not null references doctors(id),
  patient_id       uuid not null references users(id),
  -- doctor_no_show: the doctor didn't arrive or didn't join.
  -- technical: the call failed. doctor_reschedule: the doctor moved it.
  -- doctor_late_cancel: the doctor cancelled a paid visit close to its time.
  type             text not null check (type in ('doctor_no_show', 'technical', 'doctor_reschedule',
                                                 'doctor_late_cancel', 'other')),
  -- What the patient pressed, as they'd say it.
  reported_as      text check (reported_as in ('doctor_not_arrived', 'doctor_not_joined', 'call_failed', 'other')),
  reported_by_role text not null check (reported_by_role in ('patient', 'doctor', 'system', 'ops')),
  reported_by      uuid,
  -- Whose fault, as far as is known (spec §13.3). Only 'doctor' can count
  -- against a doctor, and only once confirmed.
  cause            text not null default 'undetermined'
                   check (cause in ('doctor', 'patient', 'platform', 'mutual', 'undetermined')),
  status           text not null default 'reported'
                   check (status in ('reported', 'under_review', 'confirmed', 'dismissed', 'undetermined')),
  -- Facts captured when it was reported: times, journey, who joined the call.
  evidence         jsonb not null default '{}'::jsonb,
  patient_note     text check (length(patient_note) <= 1000),
  doctor_response  text check (length(doctor_response) <= 1000),
  doctor_responded_at timestamptz,
  -- Online, with clear evidence (the patient joined, the doctor didn't): it
  -- is confirmed at this time unless the doctor responds first (D7).
  auto_confirm_at  timestamptz,
  decided_by       uuid,
  decided_at       timestamptz,
  decision_reason  text,
  policy_version   text not null default '2026-10-27',
  appeal_status    text not null default 'none'
                   check (appeal_status in ('none', 'appealed', 'upheld', 'reversed')),
  appeal_note      text check (length(appeal_note) <= 1000),
  appealed_at      timestamptz,
  appeal_decided_at timestamptz,
  appeal_decided_by uuid,
  appeal_reason    text,
  -- The patient's remedy: offered when the evidence supports it, or by ops.
  remedy_eligible  boolean not null default false,
  remedy_offered_at timestamptz,
  remedy           text not null default 'none'
                   check (remedy in ('none', 'pending', 'refund', 'replacement', 'rescheduled')),
  -- No foreign key: a second bookings↔incidents link would make PostgREST's
  -- embeds ambiguous. Only start_replacement() writes it.
  remedy_booking_id uuid,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index if not exists idx_incidents_doctor on incidents (doctor_id, created_at desc);
create index if not exists idx_incidents_open on incidents (created_at)
  where status in ('reported', 'under_review') or appeal_status = 'appealed';
-- One open patient report per booking: pressing again shows the same case.
create unique index if not exists uq_incidents_open_report on incidents (booking_id)
  where reported_by_role = 'patient' and status in ('reported', 'under_review');

drop trigger if exists trg_incidents_updated_at on incidents;
create trigger trg_incidents_updated_at before update on incidents
  for each row execute function set_updated_at();

-- An incident's facts are fixed; decisions are recorded, never erased.
create or replace function guard_incident()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    if pg_trigger_depth() <= 1
       and coalesce(current_setting('charak.retention_purge', true), '') <> 'on' then
      raise exception 'incidents are not deleted' using errcode = 'insufficient_privilege';
    end if;
    return old;
  end if;
  if (new.case_ref, new.booking_id, new.doctor_id, new.patient_id, new.reported_by_role,
      new.reported_by, new.evidence, new.created_at, new.reported_as)
     is distinct from
     (old.case_ref, old.booking_id, old.doctor_id, old.patient_id, old.reported_by_role,
      old.reported_by, old.evidence, old.created_at, old.reported_as) then
    raise exception 'an incident''s facts cannot change' using errcode = 'insufficient_privilege';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_incidents_guard on incidents;
create trigger trg_incidents_guard before update or delete on incidents
  for each row execute function guard_incident();

create table if not exists incident_events (
  id          bigint generated always as identity primary key,
  incident_id uuid not null references incidents(id) on delete cascade,
  event       text not null,
  actor_role  text not null check (actor_role in ('patient', 'doctor', 'system', 'ops')),
  actor_id    uuid,
  note        text,
  metadata    jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now()
);
create index if not exists idx_incident_events on incident_events (incident_id, occurred_at);

drop trigger if exists trg_incident_events_append_only on incident_events;
create trigger trg_incident_events_append_only before update or delete on incident_events
  for each row execute function forbid_history_rewrite();

alter table incidents enable row level security;
alter table incident_events enable row level security;
revoke all on incidents, incident_events from anon, authenticated;
grant all on incidents to service_role;
grant select, insert on incident_events to service_role;

-- ── 3. Paying a replacement from the original payment ───────────────────────
alter table payments
  add column if not exists transferred_out_paise bigint not null default 0
    check (transferred_out_paise >= 0),
  add column if not exists transferred_from_payment_id uuid references payments(id);

-- prepaid_from_payment_id has no foreign key on purpose: a second
-- bookings↔payments link would make every `payments(…)`/`bookings(…)` embed
-- ambiguous. Only start_replacement() writes it, from a locked payment row.
alter table bookings
  add column if not exists replaces_booking_id uuid references bookings(id),
  add column if not exists prepaid_from_payment_id uuid;
alter table bookings drop constraint if exists bookings_prepaid_from_payment_id_fkey;
alter table incidents drop constraint if exists incidents_remedy_booking_id_fkey;

-- One live replacement per original booking.
create unique index if not exists uq_bookings_one_replacement on bookings (replaces_booking_id)
  where replaces_booking_id is not null
    and status in ('requested', 'accepted', 'paid', 'in_progress', 'consulted', 'completed');

alter table refunds drop constraint if exists refunds_reason_check;
alter table refunds add constraint refunds_reason_check
  check (reason in ('booking_cancelled', 'late_capture', 'ops', 'doctor_no_show', 'replacement_difference'));

-- A payment's refundable amount is what was paid less what was moved to a
-- replacement booking (which then carries its own payment row).
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

  if exists (select 1 from refunds where idempotency_key = new.idempotency_key) then
    return new;
  end if;

  select round(amount * 100)::bigint - transferred_out_paise into v_paid_paise
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

-- What can still be refunded on a payment.
create or replace function payment_refundable_paise(p_payment_id uuid)
returns bigint
language sql
stable
set search_path = public
as $$
  select round(p.amount * 100)::bigint - p.transferred_out_paise
         - coalesce((select sum(r.amount_paise) from refunds r where r.payment_id = p.id), 0)
    from payments p where p.id = p_payment_id
$$;

-- ── 4. Reschedule requests ───────────────────────────────────────────────────
create table if not exists reschedule_requests (
  id           uuid primary key default uuid_generate_v4(),
  booking_id   uuid not null references bookings(id) on delete cascade,
  doctor_id    uuid not null references doctors(id),
  incident_id  uuid references incidents(id),
  -- Why, as the doctor says it (spec §13.3).
  cause        text not null check (cause in ('doctor_unavailable', 'doctor_device', 'patient_device',
                                              'platform', 'mutual', 'other')),
  note         text check (length(note) <= 500),
  -- Up to three new start times, all at the booking's length.
  options      timestamptz[] not null check (array_length(options, 1) between 1 and 3),
  status       text not null default 'proposed'
               check (status in ('proposed', 'accepted', 'declined', 'expired', 'withdrawn')),
  chosen_start timestamptz,
  expires_at   timestamptz not null,
  decided_at   timestamptz,
  created_at   timestamptz not null default now()
);
create unique index if not exists uq_reschedule_open on reschedule_requests (booking_id)
  where status = 'proposed';

alter table reschedule_requests enable row level security;
revoke all on reschedule_requests from anon, authenticated;
grant all on reschedule_requests to service_role;

-- ── 5. Cancellation, now aware of re-pointed payments ────────────────────────
-- Same as 0024 except the amount still due on a payment excludes what was
-- moved to a replacement booking.
create or replace function cancel_booking(
  p_booking_id            uuid,
  p_expected_status       text,
  p_cancelled_by          text,
  p_actor_id              uuid,
  p_idempotency_key       text   default null,
  p_expected_refund_paise bigint default null,
  p_reason_code           text   default null
) returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_lock     bookings%rowtype;
  v_quote    jsonb;
  v_pct      int;
  v_result   jsonb;
  v_outcome  text;
  v_payment  payments%rowtype;
  v_refund   refunds%rowtype;
  v_refunds  jsonb := '[]'::jsonb;
  v_due      bigint;
  v_amount   bigint;
begin
  select * into v_lock from bookings where id = p_booking_id for update;
  if not found then
    return jsonb_build_object('outcome', 'not_found');
  end if;

  v_quote := cancellation_quote(p_booking_id, p_cancelled_by);
  if p_expected_refund_paise is not null
     and v_lock.status = p_expected_status
     and (v_quote->>'refund_paise')::bigint <> p_expected_refund_paise then
    return jsonb_build_object('outcome', 'quote_changed', 'status', v_lock.status, 'quote', v_quote);
  end if;
  v_pct := (v_quote->>'refund_pct')::int;

  v_result := transition_booking(
    p_booking_id, 'cancel', p_cancelled_by, p_actor_id, p_expected_status,
    jsonb_build_object('cancelled_by', p_cancelled_by, 'hold_expires_at', null),
    p_idempotency_key,
    jsonb_build_object('cancelled_by', p_cancelled_by,
                       'refund_pct', v_pct,
                       'refund_paise', (v_quote->>'refund_paise')::bigint,
                       'policy_version', v_quote->>'policy_version',
                       'reason_code', p_reason_code)
  );
  v_outcome := v_result->>'outcome';

  if v_outcome = 'invalid' then
    return jsonb_build_object('outcome', 'not_cancellable', 'status', v_result->>'status');
  end if;
  if v_outcome = 'replayed' then
    select coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb) into v_refunds
      from refunds r where r.booking_id = p_booking_id and r.status = 'pending';
    return jsonb_build_object('outcome', 'cancelled', 'status', v_result->>'status',
                              'booking', v_result->'booking', 'refunds', v_refunds,
                              'quote', v_quote);
  end if;
  if v_outcome <> 'ok' then
    return v_result;
  end if;

  update payments set status = 'failed'
   where booking_id = p_booking_id and status = 'initiated';

  for v_payment in
    select * from payments
     where booking_id = p_booking_id and status = 'completed'
     order by created_at
     for update
  loop
    v_due := payment_refundable_paise(v_payment.id);
    v_amount := floor(v_due * v_pct / 100.0)::bigint;

    if v_amount > 0 then
      insert into refunds (
        payment_id, booking_id, amount_paise, reason, idempotency_key,
        requested_by_role, requested_by
      ) values (
        v_payment.id, p_booking_id, v_amount,
        case when p_reason_code = 'doctor_no_show' then 'doctor_no_show' else 'booking_cancelled' end,
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
        || case when v_pct < 100 then ' (' || v_pct || '% refunded under ' || coalesce(v_quote->>'policy_version', 'policy') || ')' else '' end,
      case when v_pct >= 100 then null else v_amount end
    );
  end loop;

  return jsonb_build_object('outcome', 'cancelled', 'status', 'cancelled',
                            'booking', v_result->'booking', 'refunds', v_refunds,
                            'quote', v_quote);
end;
$$;

-- ── 6. Remedies ──────────────────────────────────────────────────────────────
-- The patient's refund. If the booking is still live it is cancelled with a
-- full refund and the doctor's credit reversed (cancel_booking). If it was
-- already cancelled for a replacement that didn't happen, what's left on the
-- payment is refunded.
--
-- Returns {"outcome": ok | not_found | forbidden | not_eligible | already,
--          "refunds": [...]}.
create or replace function apply_remedy_refund(
  p_incident_id uuid,
  p_actor_role  text,
  p_actor_id    uuid default null
) returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_inc     incidents%rowtype;
  v_booking bookings%rowtype;
  v_result  jsonb;
  v_payment payments%rowtype;
  v_refund  refunds%rowtype;
  v_refunds jsonb := '[]'::jsonb;
  v_due     bigint;
begin
  select booking_id into v_booking.id from incidents where id = p_incident_id;
  if v_booking.id is null then
    return jsonb_build_object('outcome', 'not_found');
  end if;
  select * into v_booking from bookings where id = v_booking.id for update;
  select * into v_inc from incidents where id = p_incident_id for update;
  if p_actor_role = 'patient' and v_inc.patient_id is distinct from p_actor_id then
    return jsonb_build_object('outcome', 'forbidden');
  end if;
  if v_inc.remedy in ('refund', 'replacement', 'rescheduled') then
    return jsonb_build_object('outcome', 'already', 'remedy', v_inc.remedy);
  end if;
  if not v_inc.remedy_eligible then
    return jsonb_build_object('outcome', 'not_eligible');
  end if;
  -- The visit went ahead after all (the doctor arrived late): no refund here;
  -- ops decides the incident.
  if v_booking.status in ('in_progress', 'consulted', 'completed') then
    return jsonb_build_object('outcome', 'not_eligible', 'status', v_booking.status);
  end if;

  if v_booking.status in ('paid', 'accepted', 'requested') then
    v_result := cancel_booking(v_booking.id, v_booking.status, 'ops', null,
                               'incident:' || p_incident_id::text, null, 'doctor_no_show');
    if v_result->>'outcome' <> 'cancelled' then
      return v_result;
    end if;
    v_refunds := coalesce(v_result->'refunds', '[]'::jsonb);
  else
    -- Already cancelled for a replacement: refund what the payment still holds.
    for v_payment in
      select * from payments where booking_id = v_booking.id and status in ('completed', 'partially_refunded')
       for update
    loop
      v_due := payment_refundable_paise(v_payment.id);
      if v_due > 0 then
        insert into refunds (payment_id, booking_id, amount_paise, reason, idempotency_key,
                             requested_by_role, requested_by)
        values (v_payment.id, v_booking.id, v_due, 'doctor_no_show',
                v_payment.id::text || ':incident:' || p_incident_id::text, p_actor_role, p_actor_id)
        on conflict (idempotency_key) do nothing
        returning * into v_refund;
        if found then v_refunds := v_refunds || jsonb_build_array(to_jsonb(v_refund)); end if;
      end if;
    end loop;
  end if;

  update incidents set remedy = 'refund' where id = p_incident_id;
  insert into incident_events (incident_id, event, actor_role, actor_id, metadata)
  values (p_incident_id, 'remedy_refund', p_actor_role, p_actor_id,
          jsonb_build_object('refunds', jsonb_array_length(v_refunds)));
  return jsonb_build_object('outcome', 'ok', 'refunds', v_refunds);
end;
$$;

-- The patient chose another doctor. In one transaction: the original booking
-- is cancelled without a refund (its money is going to the new one) and its
-- doctor's credit reversed; the replacement is requested from the new doctor
-- with the price the backend resolved; the incident records it. The money
-- moves only when the new doctor accepts (settle_replacement).
--
-- p_booking: {"doctor_id", "channel", "scheduled_start", "duration_min",
--             "price_paise", "price_rule_id", "category_id", address fields…}
-- Returns {"outcome": ok | not_found | forbidden | not_eligible | already
--          | over_budget | slot_taken, "booking": {...}}.
create or replace function start_replacement(
  p_incident_id uuid,
  p_patient_id  uuid,
  p_booking     jsonb
) returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_inc      incidents%rowtype;
  v_orig     bookings%rowtype;
  v_payment  payments%rowtype;
  v_budget   bigint;
  v_price    bigint := (p_booking->>'price_paise')::bigint;
  v_new      bookings%rowtype;
  v_result   jsonb;
begin
  select booking_id into v_orig.id from incidents where id = p_incident_id;
  if v_orig.id is null then
    return jsonb_build_object('outcome', 'not_found');
  end if;
  select * into v_orig from bookings where id = v_orig.id for update;
  select * into v_inc from incidents where id = p_incident_id for update;
  if v_inc.patient_id is distinct from p_patient_id then
    return jsonb_build_object('outcome', 'forbidden');
  end if;
  if v_inc.remedy in ('refund', 'replacement', 'rescheduled') then
    return jsonb_build_object('outcome', 'already', 'remedy', v_inc.remedy);
  end if;
  if not v_inc.remedy_eligible then
    return jsonb_build_object('outcome', 'not_eligible');
  end if;

  select * into v_payment from payments
   where booking_id = v_orig.id and type = 'consult_fee' and status in ('completed', 'partially_refunded')
   order by created_at limit 1 for update;
  if not found then
    return jsonb_build_object('outcome', 'not_eligible');
  end if;
  v_budget := payment_refundable_paise(v_payment.id);
  if v_price > v_budget then
    return jsonb_build_object('outcome', 'over_budget', 'budget_paise', v_budget);
  end if;

  if v_orig.status in ('paid', 'accepted', 'requested') then
    v_result := transition_booking(v_orig.id, 'cancel', 'ops', null, v_orig.status,
                                   jsonb_build_object('cancelled_by', 'ops', 'hold_expires_at', null),
                                   'replacement:' || p_incident_id::text,
                                   jsonb_build_object('reason_code', 'doctor_no_show', 'remedy', 'replacement'));
    if v_result->>'outcome' not in ('ok', 'replayed') then
      return v_result;
    end if;
    perform reverse_ledger_credit(v_orig.id, 'consult_fee', 'doctor no-show: paid to a replacement doctor', null);
  end if;

  begin
    insert into bookings (patient_id, doctor_id, channel, scheduled_start, scheduled_end, duration_min,
                          price_paise, price_confirmed, price_rule_id, visit_category, category_id,
                          status, replaces_booking_id, prepaid_from_payment_id,
                          address_id, patient_address, patient_address_lat, patient_address_lng,
                          distance_km, cancellation_policy_id)
    values (p_patient_id, (p_booking->>'doctor_id')::uuid, p_booking->>'channel',
            (p_booking->>'scheduled_start')::timestamptz,
            (p_booking->>'scheduled_start')::timestamptz + make_interval(mins => (p_booking->>'duration_min')::int),
            (p_booking->>'duration_min')::int, v_price, v_price / 100.0,
            nullif(p_booking->>'price_rule_id', '')::uuid, 'initial',
            nullif(p_booking->>'category_id', '')::uuid, 'requested', v_orig.id, v_payment.id,
            nullif(p_booking->>'address_id', '')::uuid, p_booking->>'patient_address',
            (p_booking->>'patient_address_lat')::double precision,
            (p_booking->>'patient_address_lng')::double precision,
            (p_booking->>'distance_km')::numeric,
            nullif(p_booking->>'cancellation_policy_id', '')::uuid)
    returning * into v_new;
  exception when unique_violation or exclusion_violation then
    raise exception using errcode = 'P0001', message = 'slot_taken';
  end;

  update incidents set remedy = 'replacement', remedy_booking_id = v_new.id where id = p_incident_id;
  insert into incident_events (incident_id, event, actor_role, actor_id, metadata)
  values (p_incident_id, 'remedy_replacement_requested', 'patient', p_patient_id,
          jsonb_build_object('booking_id', v_new.id, 'price_paise', v_price, 'budget_paise', v_budget));
  return jsonb_build_object('outcome', 'ok', 'booking', to_jsonb(v_new), 'budget_paise', v_budget);
end;
$$;

-- The replacement doctor accepted: the booking is paid from the original
-- payment. A payment row for the new booking (same Razorpay payment, so a
-- later cancel refunds against it as usual), the original row's refundable
-- amount reduced by the same, the booking moved to 'paid', and anything left
-- of the original payment refunded to the patient.
--
-- Returns {"outcome": ok | not_found | not_prepaid | invalid,
--          "booking": {...}, "payment": {...}, "refunds": [...]}.
create or replace function settle_replacement(p_booking_id uuid)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_booking  bookings%rowtype;
  v_orig_pay payments%rowtype;
  v_pay      payments%rowtype;
  v_result   jsonb;
  v_left     bigint;
  v_refund   refunds%rowtype;
  v_refunds  jsonb := '[]'::jsonb;
begin
  select * into v_booking from bookings where id = p_booking_id for update;
  if not found then
    return jsonb_build_object('outcome', 'not_found');
  end if;
  if v_booking.prepaid_from_payment_id is null then
    return jsonb_build_object('outcome', 'not_prepaid');
  end if;
  if exists (select 1 from payments where booking_id = p_booking_id and transferred_from_payment_id is not null) then
    return jsonb_build_object('outcome', 'ok', 'booking', to_jsonb(v_booking), 'refunds', '[]'::jsonb);
  end if;

  select * into v_orig_pay from payments where id = v_booking.prepaid_from_payment_id for update;
  if payment_refundable_paise(v_orig_pay.id) < v_booking.price_paise then
    return jsonb_build_object('outcome', 'invalid', 'reason', 'original payment no longer covers it');
  end if;

  insert into payments (booking_id, amount, status, method, type, paid_at, razorpay_payment_id,
                        transferred_from_payment_id)
  values (p_booking_id, v_booking.price_paise / 100.0, 'completed', v_orig_pay.method, 'consult_fee',
          now(), v_orig_pay.razorpay_payment_id, v_orig_pay.id)
  returning * into v_pay;
  update payments set transferred_out_paise = transferred_out_paise + v_booking.price_paise
   where id = v_orig_pay.id;

  v_result := transition_booking(p_booking_id, 'pay', 'system', null, 'accepted',
                                 jsonb_build_object('hold_expires_at', null),
                                 'replacement-pay:' || p_booking_id::text,
                                 jsonb_build_object('paid_from_payment_id', v_orig_pay.id));
  if v_result->>'outcome' not in ('ok', 'replayed') then
    raise exception 'settle_replacement: booking % could not be marked paid (%)', p_booking_id, v_result->>'outcome';
  end if;

  v_left := payment_refundable_paise(v_orig_pay.id);
  if v_left > 0 then
    insert into refunds (payment_id, booking_id, amount_paise, reason, idempotency_key, requested_by_role)
    values (v_orig_pay.id, v_orig_pay.booking_id, v_left, 'replacement_difference',
            v_orig_pay.id::text || ':replacement_difference', 'system')
    on conflict (idempotency_key) do nothing
    returning * into v_refund;
    if found then v_refunds := v_refunds || jsonb_build_array(to_jsonb(v_refund)); end if;
  end if;

  return jsonb_build_object('outcome', 'ok', 'booking', v_result->'booking', 'payment', to_jsonb(v_pay),
                            'refunds', v_refunds);
end;
$$;

-- ── 7. Accepting a reschedule ────────────────────────────────────────────────
-- The patient picked one of the doctor's proposed times: the same booking
-- moves there (back to 'paid' if the failed call had started it). The overlap
-- constraint refuses a time that has been taken since.
--
-- Returns {"outcome": ok | not_found | forbidden | not_open | bad_time
--          | slot_taken, "booking": {...}}.
create or replace function accept_reschedule(
  p_request_id uuid,
  p_patient_id uuid,
  p_start      timestamptz
) returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_req     reschedule_requests%rowtype;
  v_booking bookings%rowtype;
  v_from    timestamptz;
begin
  select booking_id into v_booking.id from reschedule_requests where id = p_request_id;
  if v_booking.id is null then
    return jsonb_build_object('outcome', 'not_found');
  end if;
  select * into v_booking from bookings where id = v_booking.id for update;
  select * into v_req from reschedule_requests where id = p_request_id for update;
  if v_booking.patient_id is distinct from p_patient_id then
    return jsonb_build_object('outcome', 'forbidden');
  end if;
  if v_req.status <> 'proposed' or v_req.expires_at < now()
     or v_booking.status not in ('paid', 'in_progress') then
    return jsonb_build_object('outcome', 'not_open');
  end if;
  if not (p_start = any (v_req.options)) or p_start <= now() then
    return jsonb_build_object('outcome', 'bad_time');
  end if;

  v_from := v_booking.scheduled_start;
  perform set_config('charak.state_machine', 'on', true);
  begin
    update bookings set scheduled_start = p_start, status = 'paid', started_at = null,
                        journey_started_at = null
     where id = v_booking.id
    returning * into v_booking;
  exception when unique_violation or exclusion_violation then
    return jsonb_build_object('outcome', 'slot_taken');
  end;

  update reschedule_requests set status = 'accepted', chosen_start = p_start, decided_at = now()
   where id = p_request_id;
  insert into booking_events (booking_id, event, from_status, to_status, actor_role, actor_id, metadata)
  values (v_booking.id, 'rescheduled', 'paid', 'paid', 'patient', p_patient_id,
          jsonb_build_object('from', v_from, 'to', p_start, 'request_id', p_request_id));
  if v_req.incident_id is not null then
    update incidents set remedy = 'rescheduled' where id = v_req.incident_id and remedy in ('none', 'pending');
  end if;
  return jsonb_build_object('outcome', 'ok', 'booking', to_jsonb(v_booking));
end;
$$;

-- ── 8. Settings ──────────────────────────────────────────────────────────────
insert into app_config (key, value) values
  -- D5 / D6: how long after the start before "Doctor hasn't arrived/joined?".
  ('no_show_grace_minutes', '{"home_visit": 30, "online_consult": 10}'),
  -- How long the patient has to answer a reschedule before it lapses (and the
  -- default refund applies), and how long a remedy waits for a choice.
  ('reschedule_answer_hours', '24'),
  ('remedy_default_refund_hours', '24'),
  -- D10: appeals within this many days of the decision.
  ('incident_appeal_days', '7'),
  -- A doctor cancelling a paid visit this close to its start is an incident.
  ('doctor_late_cancel_minutes', '120')
on conflict (key) do nothing;

-- ── 9. Who may call the functions ────────────────────────────────────────────
revoke execute on function new_case_ref()                                 from public, anon, authenticated;
revoke execute on function guard_incident()                               from public, anon, authenticated;
revoke execute on function payment_refundable_paise(uuid)                 from public, anon, authenticated;
revoke execute on function apply_remedy_refund(uuid, text, uuid)          from public, anon, authenticated;
revoke execute on function start_replacement(uuid, uuid, jsonb)           from public, anon, authenticated;
revoke execute on function settle_replacement(uuid)                       from public, anon, authenticated;
revoke execute on function accept_reschedule(uuid, uuid, timestamptz)     from public, anon, authenticated;
revoke execute on function cancel_booking(uuid, text, text, uuid, text, bigint, text) from public, anon, authenticated;
grant execute on function new_case_ref()                                  to service_role;
grant execute on function payment_refundable_paise(uuid)                  to service_role;
grant execute on function apply_remedy_refund(uuid, text, uuid)           to service_role;
grant execute on function start_replacement(uuid, uuid, jsonb)            to service_role;
grant execute on function settle_replacement(uuid)                        to service_role;
grant execute on function accept_reschedule(uuid, uuid, timestamptz)      to service_role;
grant execute on function cancel_booking(uuid, text, text, uuid, text, bigint, text) to service_role;

notify pgrst, 'reload schema';
