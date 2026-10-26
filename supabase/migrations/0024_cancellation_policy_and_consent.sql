-- ═══════════════════════════════════════════════════════════════════════════
-- 0024: versioned cancellation policies, a refund quote that the cancel itself
-- uses, partial refunds, and consent recorded against published document
-- versions.
--
-- Why
--   * Every paid cancellation was a full refund, whatever the timing. LD-005
--     (decided 2026-10-26) sets the home-visit rules: full refund 2 h or more
--     before the slot, 50% inside 2 h before the doctor starts travelling, none
--     once travelling. The rules live here as data, versioned, and each booking
--     keeps the version it was made under, so changing the policy never
--     changes an existing booking's terms.
--   * The patient is shown a quote ("you'll get ₹400 back") and the cancel
--     must do exactly that. cancellation_quote() is the one calculation; the
--     cancel refuses with 'quote_changed' if the outcome moved since the
--     patient saw it (the doctor started travelling a second earlier, say).
--   * Consent was a passive "by continuing you agree" footer with versions
--     hard-coded in two places. legal_documents now holds the published
--     versions, and consents records which one was accepted, how, and for
--     which booking. The table is append-only.
--
-- Online consultations: the late-cancellation rule (D3) is not decided yet.
-- Their policy keeps today's behaviour (full refund up to the start) until a
-- new version is added. See the runbook.
--
-- Idempotent: safe to re-run in the SQL Editor. Apply before deploying the
-- backend that uses it; the backend deployed before it keeps working.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. Policies ──────────────────────────────────────────────────────────────
create table if not exists policies (
  id             uuid primary key default uuid_generate_v4(),
  kind           text not null check (kind in ('cancellation')),
  channel        text not null check (channel in ('online_consult', 'home_visit')),
  version        text not null,
  -- Ordered rules; the first whose conditions all hold applies.
  --   {"when": {"journey_started": true}, "refund_pct": 0}
  --   {"when": {"minutes_before_start_lt": 120}, "refund_pct": 50}
  --   {"when": {}, "refund_pct": 100}
  rules          jsonb not null,
  -- The patient-facing words for this version, shown before they book.
  summary        text not null,
  -- Where the decision is recorded (docs/legal/DECISIONS.md).
  decision_ref   text,
  effective_from timestamptz not null default now(),
  created_at     timestamptz not null default now(),
  unique (kind, channel, version)
);

-- A published version is never edited: a change is a new version. Bookings
-- point at the version they were made under.
drop trigger if exists trg_policies_append_only on policies;
create trigger trg_policies_append_only
  before update or delete on policies
  for each row execute function forbid_history_rewrite();

alter table policies enable row level security;
revoke all on policies from anon, authenticated;
grant select, insert on policies to service_role;

insert into policies (kind, channel, version, rules, summary, decision_ref, effective_from) values
  -- What every booking made before this migration was sold on: a full refund
  -- whenever it is cancelled. Those bookings keep it.
  ('cancellation', 'home_visit', 'legacy', '[{"when": {}, "refund_pct": 100}]',
   'Cancel any time before your visit for a full refund.', 'before LD-005', '2000-01-01'),
  ('cancellation', 'online_consult', 'legacy', '[{"when": {}, "refund_pct": 100}]',
   'Cancel any time before your consultation for a full refund.', 'before LD-005', '2000-01-01')
on conflict (kind, channel, version) do nothing;

insert into policies (kind, channel, version, rules, summary, decision_ref) values
  ('cancellation', 'home_visit', '2026-10-26',
   '[{"when": {"journey_started": true}, "refund_pct": 0},
     {"when": {"minutes_before_start_lt": 120}, "refund_pct": 50},
     {"when": {}, "refund_pct": 100}]',
   'Free cancellation up to 2 hours before your visit. Cancel later and you get 50% back, '
   'as long as the doctor hasn''t started travelling. Once the doctor is on the way, the fee '
   'isn''t refunded. If the doctor cancels or doesn''t come, you get a full refund.',
   'LD-005'),
  ('cancellation', 'online_consult', '2026-10-26',
   '[{"when": {}, "refund_pct": 100}]',
   'Cancel any time before your consultation starts for a full refund. If the doctor cancels '
   'or doesn''t join, you get a full refund.',
   'LD-005 (online rule D3 pending: full refund until decided)')
on conflict (kind, channel, version) do nothing;

-- ── 2. Bookings remember their policy, and when things happened ─────────────
alter table bookings
  add column if not exists cancellation_policy_id uuid references policies(id),
  -- Set by the doctor's Start Journey (Phase 3). The home-visit policy reads it.
  add column if not exists journey_started_at timestamptz,
  add column if not exists cancelled_at timestamptz;

-- The policy in force when the booking is made, stamped on insert so every
-- path that creates a booking (and the backend deployed before this) gets it.
create or replace function current_cancellation_policy(p_channel text, p_at timestamptz default now())
returns uuid
language sql
stable
security invoker
set search_path = public
as $$
  select id from policies
   where kind = 'cancellation' and channel = p_channel and effective_from <= p_at
   order by effective_from desc, created_at desc
   limit 1;
$$;

create or replace function stamp_cancellation_policy()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.cancellation_policy_id is null then
    new.cancellation_policy_id := current_cancellation_policy(new.channel, coalesce(new.created_at, now()));
  end if;
  return new;
end;
$$;

drop trigger if exists trg_bookings_cancellation_policy on bookings;
create trigger trg_bookings_cancellation_policy
  before insert on bookings
  for each row execute function stamp_cancellation_policy();

-- Bookings made before policies existed were sold on "full refund"; they keep
-- that, under the legacy version for their channel.
update bookings b
   set cancellation_policy_id = (select id from policies p
                                  where p.kind = 'cancellation' and p.channel = b.channel
                                    and p.version = 'legacy')
 where b.cancellation_policy_id is null;

-- transition_booking() now stamps cancelled_at too. Same body as 0023 plus
-- that one line; recreated rather than altered because plpgsql has no ALTER.
create or replace function transition_booking(
  p_booking_id      uuid,
  p_event           text,
  p_actor_role      text,
  p_actor_id        uuid    default null,
  p_expected_status text    default null,
  p_patch           jsonb   default '{}'::jsonb,
  p_idempotency_key text    default null,
  p_metadata        jsonb   default '{}'::jsonb
) returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_booking bookings%rowtype;
  v_rule    booking_transitions%rowtype;
  v_event   booking_events%rowtype;
  v_unknown text;
  v_patch   jsonb := coalesce(p_patch, '{}'::jsonb);
begin
  select * into v_booking from bookings where id = p_booking_id for update;
  if not found then
    return jsonb_build_object('outcome', 'not_found');
  end if;

  if p_idempotency_key is not null then
    select * into v_event from booking_events where idempotency_key = p_idempotency_key;
    if found then
      if v_event.booking_id <> p_booking_id or v_event.event <> p_event then
        return jsonb_build_object('outcome', 'key_reused');
      end if;
      return jsonb_build_object('outcome', 'replayed', 'status', v_booking.status,
                                'booking', to_jsonb(v_booking), 'event', to_jsonb(v_event));
    end if;
  end if;

  if (p_actor_role = 'patient' and v_booking.patient_id is distinct from p_actor_id)
     or (p_actor_role = 'doctor' and v_booking.doctor_id is distinct from p_actor_id)
     or p_actor_role not in ('patient', 'doctor', 'ops', 'system') then
    return jsonb_build_object('outcome', 'forbidden', 'status', v_booking.status);
  end if;

  if p_expected_status is not null and v_booking.status <> p_expected_status then
    return jsonb_build_object('outcome', 'conflict', 'status', v_booking.status);
  end if;

  select * into v_rule from booking_transitions
   where from_status = v_booking.status and event = p_event;
  if not found then
    return jsonb_build_object('outcome', 'invalid', 'status', v_booking.status);
  end if;
  if not (p_actor_role = any (v_rule.allowed_roles)) then
    return jsonb_build_object('outcome', 'forbidden', 'status', v_booking.status);
  end if;

  select string_agg(k, ', ') into v_unknown
    from jsonb_object_keys(v_patch) k
   where k not in ('hold_expires_at', 'address_released_at', 'cancelled_by',
                   'no_show_marked_by', 'no_show_at', 'payment_failed_at');
  if v_unknown is not null then
    raise exception 'transition_booking: column(s) not patchable: %', v_unknown
      using errcode = 'invalid_parameter_value';
  end if;

  perform set_config('charak.state_machine', 'on', true);

  update bookings set
    status              = v_rule.to_status,
    decision_at         = case when p_event in ('accept', 'decline') then now() else decision_at end,
    cancelled_at        = case when v_rule.to_status = 'cancelled' then now() else cancelled_at end,
    hold_expires_at     = case when v_patch ? 'hold_expires_at'
                               then (v_patch->>'hold_expires_at')::timestamptz else hold_expires_at end,
    address_released_at = case when v_patch ? 'address_released_at'
                               then (v_patch->>'address_released_at')::timestamptz else address_released_at end,
    cancelled_by        = case when v_patch ? 'cancelled_by'
                               then v_patch->>'cancelled_by' else cancelled_by end,
    no_show_marked_by   = case when v_patch ? 'no_show_marked_by'
                               then (v_patch->>'no_show_marked_by')::uuid else no_show_marked_by end,
    no_show_at          = case when v_patch ? 'no_show_at'
                               then (v_patch->>'no_show_at')::timestamptz else no_show_at end,
    payment_failed_at   = case when v_patch ? 'payment_failed_at'
                               then (v_patch->>'payment_failed_at')::timestamptz else payment_failed_at end
  where id = p_booking_id
  returning * into v_booking;

  insert into booking_events (booking_id, event, from_status, to_status, actor_role,
                              actor_id, idempotency_key, metadata)
  values (p_booking_id, p_event, v_rule.from_status, v_rule.to_status, p_actor_role,
          p_actor_id, p_idempotency_key, coalesce(p_metadata, '{}'::jsonb))
  returning * into v_event;

  return jsonb_build_object('outcome', 'ok', 'status', v_booking.status,
                            'booking', to_jsonb(v_booking), 'event', to_jsonb(v_event));
end;
$$;

-- ── 3. The quote ─────────────────────────────────────────────────────────────
-- What a cancellation by p_actor_role at p_now would refund. The cancel itself
-- uses this, so the number shown and the number refunded can't disagree.
--
-- Doctor and ops cancellations always refund in full (LD-005: practitioner
-- fault). A patient cancellation follows the booking's policy version.
-- Refunds round down to the paisa; the odd paisa of a 50% split stays with
-- the doctor, so the total refunded can never exceed what was paid.
--
-- Returns {paid_paise, refund_paise, kept_paise, refund_pct, free_until,
--          policy_id, policy_version, channel, reason}.
create or replace function cancellation_quote(
  p_booking_id uuid,
  p_actor_role text,
  p_now        timestamptz default now()
) returns jsonb
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_booking   bookings%rowtype;
  v_policy    policies%rowtype;
  v_rule      jsonb;
  v_when      jsonb;
  v_pct       int := 100;
  v_reason    text := 'policy';
  v_paid      bigint;
  v_minutes   numeric;
  v_matches   boolean;
  v_free_mins int;
begin
  select * into v_booking from bookings where id = p_booking_id;
  if not found then
    return null;
  end if;

  select * into v_policy from policies
   where id = coalesce(v_booking.cancellation_policy_id,
                       current_cancellation_policy(v_booking.channel, v_booking.created_at));

  select coalesce(sum(round(p.amount * 100)::bigint
                      - coalesce((select sum(r.amount_paise) from refunds r where r.payment_id = p.id), 0)), 0)
    into v_paid
    from payments p
   where p.booking_id = p_booking_id and p.status = 'completed';

  v_minutes := extract(epoch from (v_booking.scheduled_start - p_now)) / 60.0;

  if p_actor_role in ('doctor', 'ops') then
    v_pct := 100;
    v_reason := 'cancelled_by_' || p_actor_role;
  elsif v_policy.id is not null then
    for v_rule in select * from jsonb_array_elements(v_policy.rules)
    loop
      v_when := coalesce(v_rule->'when', '{}'::jsonb);
      v_matches := true;
      if v_when ? 'journey_started' then
        v_matches := v_matches
          and ((v_booking.journey_started_at is not null) = (v_when->>'journey_started')::boolean);
      end if;
      if v_when ? 'minutes_before_start_lt' then
        v_matches := v_matches and v_minutes < (v_when->>'minutes_before_start_lt')::numeric;
      end if;
      if v_matches then
        v_pct := (v_rule->>'refund_pct')::int;
        v_reason := case
          when v_when ? 'journey_started' then 'journey_started'
          when v_when ? 'minutes_before_start_lt' then 'late_cancellation'
          else 'free_cancellation' end;
        exit;
      end if;
    end loop;
  end if;

  -- The earliest moment a cancellation stops being a full refund: the widest
  -- time window among the rules that refund less than 100%. Null when no
  -- time-based rule ever reduces the refund.
  select max((r->'when'->>'minutes_before_start_lt')::int) into v_free_mins
    from jsonb_array_elements(coalesce(v_policy.rules, '[]'::jsonb)) r
   where (r->>'refund_pct')::int < 100 and r->'when' ? 'minutes_before_start_lt';

  return jsonb_build_object(
    'paid_paise', v_paid,
    'refund_paise', floor(v_paid * v_pct / 100.0)::bigint,
    'kept_paise', v_paid - floor(v_paid * v_pct / 100.0)::bigint,
    'refund_pct', v_pct,
    'free_until', case when v_free_mins is null then null
                       else v_booking.scheduled_start - make_interval(mins => v_free_mins) end,
    'policy_id', v_policy.id,
    'policy_version', v_policy.version,
    'channel', v_booking.channel,
    'journey_started_at', v_booking.journey_started_at,
    'reason', v_reason
  );
end;
$$;

-- ── 4. Partial ledger reversal ───────────────────────────────────────────────
-- p_refund_paise null: reverse the whole credit, as 0022 did. A smaller amount
-- reverses only that portion with a negative entry; the rest stays the
-- doctor's (a late-cancellation fee, LD-005). The old three-argument form is
-- replaced; callers that pass three named arguments still match.
drop function if exists reverse_ledger_credit(uuid, text, text);

create or replace function reverse_ledger_credit(
  p_booking_id   uuid,
  p_source       text,
  p_note         text,
  p_refund_paise bigint default null
) returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_entry  doctor_ledger_entries%rowtype;
  v_rev    doctor_ledger_entries%rowtype;
  v_gross  numeric(10,2);
  v_comm   numeric(10,2);
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
  if p_refund_paise is not null and p_refund_paise <= 0 then
    return to_jsonb(v_entry);                     -- nothing refunded, nothing reversed
  end if;

  v_gross := case when p_refund_paise is null
                  then v_entry.gross_amount
                  else least(v_entry.gross_amount, round(p_refund_paise / 100.0, 2)) end;

  -- The whole of a credit not yet paid out: mark it reversed; the money never left.
  if v_entry.status = 'payable' and v_gross >= v_entry.gross_amount then
    update doctor_ledger_entries
       set status = 'reversed', note = p_note
     where id = v_entry.id
    returning * into v_entry;
    return to_jsonb(v_entry);
  end if;

  -- Otherwise a negative entry for the refunded part: of a paid-out credit (the
  -- next payout recovers it) or a portion of one still payable (the doctor
  -- keeps the rest). Commission is reversed in proportion.
  v_comm := case when v_entry.gross_amount = 0 then 0
                 else round(v_entry.commission_amount * v_gross / v_entry.gross_amount, 2) end;
  insert into doctor_ledger_entries (
    doctor_id, booking_id, source, gross_amount, commission_pct,
    commission_amount, net_amount, status, note, reverses_entry_id
  ) values (
    v_entry.doctor_id, v_entry.booking_id, 'reversal', -v_gross,
    v_entry.commission_pct, -v_comm, -(v_gross - v_comm),
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

-- ── 5. cancel_booking() follows the quote ────────────────────────────────────
-- Locks the booking, computes the quote, and refuses with 'quote_changed' if
-- the caller passed the refund it showed the patient and the outcome has moved
-- since. Otherwise it cancels and refunds exactly the quoted amount.
drop function if exists cancel_booking(uuid, text, text, uuid, text);

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
  v_queued   bigint;
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
    select coalesce(sum(amount_paise), 0) into v_queued
      from refunds where payment_id = v_payment.id;
    v_due := round(v_payment.amount * 100)::bigint - v_queued;
    v_amount := floor(v_due * v_pct / 100.0)::bigint;

    if v_amount > 0 then
      insert into refunds (
        payment_id, booking_id, amount_paise, reason, idempotency_key,
        requested_by_role, requested_by
      ) values (
        v_payment.id, p_booking_id, v_amount, 'booking_cancelled',
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

-- ── 6. Published legal documents ─────────────────────────────────────────────
create table if not exists legal_documents (
  id           uuid primary key default uuid_generate_v4(),
  type         text not null check (type in ('tos', 'privacy', 'telemedicine', 'practitioner_terms')),
  version      text not null,
  title        text not null,
  url          text not null,
  -- Hash of the exact published text, when the publishing step records it.
  sha256       text,
  -- Who must accept it: patients, doctors or both.
  audience     text[] not null,
  -- Material change: users must accept again before continuing.
  material     boolean not null default true,
  published_at timestamptz not null default now(),
  unique (type, version)
);

drop trigger if exists trg_legal_documents_append_only on legal_documents;
create trigger trg_legal_documents_append_only
  before update or delete on legal_documents
  for each row execute function forbid_history_rewrite();

alter table legal_documents enable row level security;
revoke all on legal_documents from anon, authenticated;
grant select, insert on legal_documents to service_role;

-- The versions the apps and backend already use (LEGAL_*_VERSION). Practitioner
-- Terms aren't drafted yet (docs/legal/DECISIONS.md); added when they are.
insert into legal_documents (type, version, title, url, audience, published_at) values
  ('tos',          '2026-10-01', 'Terms of Use',          'https://www.charak.care/terms',
   '{patient,doctor}', '2026-10-01'),
  ('privacy',      '2026-10-01', 'Privacy Policy',        'https://www.charak.care/privacy',
   '{patient,doctor}', '2026-10-01'),
  ('telemedicine', '2026-10-01', 'Telemedicine Consent',  'https://www.charak.care/telemedicine',
   '{patient}', '2026-10-01')
on conflict (type, version) do nothing;

-- ── 7. Consent records: what was accepted, how, for which booking ───────────
alter table consents drop constraint if exists consents_type_check;
alter table consents add constraint consents_type_check
  check (type in ('tos', 'privacy', 'telemedicine', 'marketing', 'practitioner_terms',
                  'booking_policy'));

alter table consents
  add column if not exists role        text check (role in ('patient', 'doctor')),
  -- signup_checkbox | reconsent | booking_confirmation | legacy_footer
  add column if not exists method      text,
  -- Not a foreign key: evidence of consent outlives the booking it was given
  -- for, and an FK action would have to edit an append-only row.
  add column if not exists booking_id  uuid,
  add column if not exists app_version text;

create index if not exists idx_consents_user_type on consents (user_id, type, version);

-- Evidence of consent is never edited or removed (it survives account erasure).
drop trigger if exists trg_consents_append_only on consents;
create trigger trg_consents_append_only
  before update or delete on consents
  for each row execute function forbid_history_rewrite();

-- ── 8. Rollout switches (off until app builds with the new screens are out) ──
insert into app_config (key, value) values
  -- Booking creation requires current Terms + Privacy (and Telemedicine for an
  -- online consult); the apps show the consent sheet on 428.
  ('require_legal_acceptance', 'false'),
  -- Booking creation requires the patient to have ticked the cancellation
  -- policy shown on the confirm screen.
  ('require_booking_policy_acceptance', 'false')
on conflict (key) do nothing;

-- ── 9. Who may call the functions ────────────────────────────────────────────
revoke execute on function current_cancellation_policy(text, timestamptz)        from public, anon, authenticated;
revoke execute on function stamp_cancellation_policy()                           from public, anon, authenticated;
revoke execute on function cancellation_quote(uuid, text, timestamptz)           from public, anon, authenticated;
revoke execute on function reverse_ledger_credit(uuid, text, text, bigint)       from public, anon, authenticated;
revoke execute on function cancel_booking(uuid, text, text, uuid, text, bigint, text) from public, anon, authenticated;
revoke execute on function transition_booking(uuid, text, text, uuid, text, jsonb, text, jsonb) from public, anon, authenticated;

grant execute on function current_cancellation_policy(text, timestamptz)        to service_role;
grant execute on function cancellation_quote(uuid, text, timestamptz)           to service_role;
grant execute on function reverse_ledger_credit(uuid, text, text, bigint)       to service_role;
grant execute on function cancel_booking(uuid, text, text, uuid, text, bigint, text) to service_role;
grant execute on function transition_booking(uuid, text, text, uuid, text, jsonb, text, jsonb) to service_role;

-- ── Verify ───────────────────────────────────────────────────────────────────
-- Every booking has a policy:
--   select count(*) from bookings where cancellation_policy_id is null;   -- expect 0
-- The current policy per channel:
--   select channel, version, summary from policies p
--    where id = current_cancellation_policy(p.channel);
