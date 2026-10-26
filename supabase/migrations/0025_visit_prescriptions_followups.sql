-- ═══════════════════════════════════════════════════════════════════════════
-- 0025: the visit itself. Start Journey, the consultation, prescriptions,
-- completion when the patient opens the prescription, follow-ups, call joins.
--
--   paid ──start_consultation──▶ in_progress ──end_consultation──▶ consulted
--     │                                                              │
--     │ (home visits) start_journey: an event, not a status          │ patient opens the
--     │                                                              │ prescription, or 72 h
--     └──complete (legacy app builds)──▶ completed ◀──complete───────┘ after it was sent
--
-- Prescriptions are structured (medicines, dose, frequency, duration …) and
-- immutable once sent: a correction is a new version, and the old one is kept
-- as superseded. The PDF is rendered by the backend from the structured
-- record, stored privately, and its hash kept. A handwritten prescription can
-- be uploaded instead.
--
-- Idempotent: safe to re-run in the SQL Editor. Apply before deploying the
-- backend that uses it; the backend deployed before it keeps working.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. Two new booking statuses ──────────────────────────────────────────────
alter table bookings drop constraint if exists bookings_status_check;
alter table bookings add constraint bookings_status_check
  check (status in ('requested', 'accepted', 'declined', 'paid', 'in_progress', 'consulted',
                    'completed', 'cancelled', 'no_show'));

alter table bookings
  add column if not exists started_at        timestamptz,   -- consultation started
  add column if not exists consulted_at      timestamptz,   -- consultation ended
  add column if not exists completed_at      timestamptz,
  -- patient_viewed | fallback | doctor (app builds before this migration)
  add column if not exists completion_source text,
  -- When the first prescription was sent and first opened. The doctor's fee
  -- becomes withdrawable 48 h after the send if the patient opened it by then,
  -- else 72 h after it (LD-006; services/payouts.py).
  add column if not exists prescription_sent_at   timestamptz,
  add column if not exists prescription_viewed_at timestamptz;

insert into booking_transitions (from_status, event, to_status, allowed_roles) values
  ('paid',        'start_consultation', 'in_progress', '{doctor}'),
  ('in_progress', 'end_consultation',   'consulted',   '{doctor,system}'),
  ('consulted',   'complete',           'completed',   '{patient,system}'),
  -- Kept for doctor app builds that still mark a visit complete directly.
  ('paid',        'complete',           'completed',   '{doctor}')
on conflict (from_status, event) do update
  set to_status = excluded.to_status, allowed_roles = excluded.allowed_roles;

-- transition_booking() stamps the new timestamps. Same body as 0024 plus three
-- lines; recreated because plpgsql has no ALTER.
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
                   'no_show_marked_by', 'no_show_at', 'payment_failed_at', 'completion_source');
  if v_unknown is not null then
    raise exception 'transition_booking: column(s) not patchable: %', v_unknown
      using errcode = 'invalid_parameter_value';
  end if;

  perform set_config('charak.state_machine', 'on', true);

  update bookings set
    status              = v_rule.to_status,
    decision_at         = case when p_event in ('accept', 'decline') then now() else decision_at end,
    cancelled_at        = case when v_rule.to_status = 'cancelled' then now() else cancelled_at end,
    started_at          = case when v_rule.to_status = 'in_progress' then now() else started_at end,
    consulted_at        = case when v_rule.to_status = 'consulted' then now() else consulted_at end,
    completed_at        = case when v_rule.to_status = 'completed' then now() else completed_at end,
    completion_source   = case when v_patch ? 'completion_source'
                               then v_patch->>'completion_source' else completion_source end,
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

-- ── 2. Start Journey (home visits) ───────────────────────────────────────────
-- An event, not a status. It can be tapped from 2 hours before the slot (LD-005:
-- an earlier tap would make a booking non-refundable for no reason), only by
-- the booking's doctor, only on a paid home visit, and only once. A repeat tap
-- returns the first journey. The time is the server's, so it can't be
-- backdated. Locked like every transition, so a cancel racing it is ordered
-- (the cancel's quote reads journey_started_at under the same lock).
--
-- Returns {"outcome": ok | already_started | not_found | forbidden | invalid
--          | too_early, "booking": {...}, "opens_at": <when, if too early>}.
create or replace function start_journey(
  p_booking_id     uuid,
  p_doctor_id      uuid,
  p_window_minutes int         default 120,
  p_now            timestamptz default now()
) returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_booking bookings%rowtype;
begin
  select * into v_booking from bookings where id = p_booking_id for update;
  if not found then
    return jsonb_build_object('outcome', 'not_found');
  end if;
  if v_booking.doctor_id is distinct from p_doctor_id then
    return jsonb_build_object('outcome', 'forbidden');
  end if;
  if v_booking.journey_started_at is not null then
    return jsonb_build_object('outcome', 'already_started', 'booking', to_jsonb(v_booking));
  end if;
  if v_booking.channel <> 'home_visit' or v_booking.status <> 'paid' then
    return jsonb_build_object('outcome', 'invalid', 'status', v_booking.status,
                              'channel', v_booking.channel);
  end if;
  if p_now < v_booking.scheduled_start - make_interval(mins => p_window_minutes) then
    return jsonb_build_object('outcome', 'too_early',
      'opens_at', v_booking.scheduled_start - make_interval(mins => p_window_minutes));
  end if;

  update bookings set journey_started_at = p_now
   where id = p_booking_id
  returning * into v_booking;

  insert into booking_events (booking_id, event, from_status, to_status, actor_role, actor_id)
  values (p_booking_id, 'start_journey', v_booking.status, v_booking.status, 'doctor', p_doctor_id);

  return jsonb_build_object('outcome', 'ok', 'booking', to_jsonb(v_booking));
end;
$$;

-- ── 3. Prescriptions ─────────────────────────────────────────────────────────
create table if not exists prescriptions (
  id               uuid primary key default uuid_generate_v4(),
  -- Cascades only if the booking itself is removed, which the app never does
  -- (a retention purge or a test database). A sent prescription can't be
  -- deleted on its own (trigger below).
  booking_id       uuid not null references bookings(id) on delete cascade,
  doctor_id        uuid not null references doctors(id),
  patient_id       uuid not null references users(id),
  version          int  not null default 1 check (version >= 1),
  -- prescription: medicines and instructions. notes: consultation notes when
  -- nothing needs prescribing (decision N3).
  kind             text not null default 'prescription' check (kind in ('prescription', 'notes')),
  status           text not null default 'draft' check (status in ('draft', 'submitted', 'superseded')),
  -- What the Telemedicine Practice Guidelines' sample format carries. The
  -- patient's age and sex are confirmed by the doctor (TPG), not inferred.
  patient_age      int check (patient_age between 0 and 130),
  patient_sex      text check (patient_sex in ('female', 'male', 'other')),
  complaints       text,
  diagnosis        text,                    -- provisional, in the doctor's words
  investigations   text,
  advice           text,
  -- Online consultations: the doctor confirms they prescribed within the TPG
  -- rules for this mode of consultation.
  tpg_attested     boolean not null default false,
  -- A handwritten prescription uploaded instead of, or as well as, the form.
  upload_path      text,
  upload_mime      text,
  pdf_path         text,
  pdf_sha256       text,
  submitted_at     timestamptz,
  first_viewed_at  timestamptz,
  supersedes_id    uuid references prescriptions(id),
  superseded_at    timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique (booking_id, version)
);

-- Per booking: at most one prescription the patient has, and at most one
-- draft (the first one, or a correction being written while the sent one
-- stands).
create unique index if not exists uq_prescriptions_submitted
  on prescriptions (booking_id) where status = 'submitted';
create unique index if not exists uq_prescriptions_draft
  on prescriptions (booking_id) where status = 'draft';
create index if not exists idx_prescriptions_doctor on prescriptions (doctor_id, created_at desc);
create index if not exists idx_prescriptions_patient on prescriptions (patient_id, created_at desc);
create index if not exists idx_prescriptions_unviewed
  on prescriptions (submitted_at) where status = 'submitted' and first_viewed_at is null;

create table if not exists prescription_items (
  id              uuid primary key default uuid_generate_v4(),
  prescription_id uuid not null references prescriptions(id) on delete cascade,
  position        int  not null,
  medicine        text not null check (length(trim(medicine)) > 0),
  strength        text,          -- 500 mg, 5 mg/ml
  form            text,          -- tablet, syrup, ointment
  dose            text,          -- 1 tablet, 5 ml
  route           text,          -- oral, topical
  frequency       text,          -- 1-0-1, every 8 hours, SOS
  duration        text,          -- 5 days
  instructions    text,          -- after food
  created_at      timestamptz not null default now(),
  unique (prescription_id, position)
);

drop trigger if exists trg_prescriptions_updated_at on prescriptions;
create trigger trg_prescriptions_updated_at before update on prescriptions
  for each row execute function set_updated_at();

-- Once sent, a prescription is a clinical record. Its content never changes.
-- Allowed afterwards: the first view is stamped once, the PDF details are set
-- by the backend that renders it, and it can be superseded by a correction.
create or replace function guard_submitted_prescription()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    if old.status <> 'draft' and pg_trigger_depth() <= 1
       and coalesce(current_setting('charak.retention_purge', true), '') <> 'on' then
      raise exception 'a sent prescription cannot be deleted' using errcode = 'insufficient_privilege';
    end if;
    return old;
  end if;
  if old.status = 'draft' then
    return new;
  end if;
  if (new.kind, new.patient_age, new.patient_sex, new.complaints, new.diagnosis,
      new.investigations, new.advice, new.tpg_attested, new.upload_path, new.booking_id,
      new.doctor_id, new.patient_id, new.version, new.submitted_at)
     is distinct from
     (old.kind, old.patient_age, old.patient_sex, old.complaints, old.diagnosis,
      old.investigations, old.advice, old.tpg_attested, old.upload_path, old.booking_id,
      old.doctor_id, old.patient_id, old.version, old.submitted_at) then
    raise exception 'a sent prescription cannot be edited; issue a correction instead'
      using errcode = 'insufficient_privilege';
  end if;
  if old.first_viewed_at is not null and new.first_viewed_at is distinct from old.first_viewed_at then
    raise exception 'the first view of a prescription is recorded once' using errcode = 'insufficient_privilege';
  end if;
  if old.status = 'superseded' and new.status <> 'superseded' then
    raise exception 'a superseded prescription stays superseded' using errcode = 'insufficient_privilege';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_prescriptions_guard on prescriptions;
create trigger trg_prescriptions_guard before update or delete on prescriptions
  for each row execute function guard_submitted_prescription();

create or replace function guard_prescription_items()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_status text;
begin
  select status into v_status from prescriptions
   where id = coalesce(new.prescription_id, old.prescription_id);
  -- pg_trigger_depth() > 1: the cascade from deleting a draft.
  if v_status is not null and v_status <> 'draft' and pg_trigger_depth() <= 1 then
    raise exception 'the medicines on a sent prescription cannot change'
      using errcode = 'insufficient_privilege';
  end if;
  return coalesce(new, old);
end;
$$;

drop trigger if exists trg_prescription_items_guard on prescription_items;
create trigger trg_prescription_items_guard before insert or update or delete on prescription_items
  for each row execute function guard_prescription_items();

alter table prescriptions enable row level security;
alter table prescription_items enable row level security;
revoke all on prescriptions, prescription_items from anon, authenticated;
grant all on prescriptions, prescription_items to service_role;

-- Saving a draft, in one transaction: the fields and the whole medicine list
-- together, so a send never sees half a save. Creates the draft if there's
-- none (and refuses if the prescription has already been sent: that takes a
-- correction). Every function here locks the booking before the prescription,
-- so none of them can deadlock another.
--
-- Returns {"outcome": ok | not_found | forbidden | wrong_status | sent,
--          "prescription": {...}}.
create or replace function save_prescription_draft(
  p_booking_id uuid,
  p_doctor_id  uuid,
  p_fields     jsonb,
  p_items      jsonb
) returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_booking bookings%rowtype;
  v_rx      prescriptions%rowtype;
  v_fields  jsonb := coalesce(p_fields, '{}'::jsonb);
begin
  select * into v_booking from bookings where id = p_booking_id for update;
  if not found then
    return jsonb_build_object('outcome', 'not_found');
  end if;
  if v_booking.doctor_id is distinct from p_doctor_id then
    return jsonb_build_object('outcome', 'forbidden');
  end if;
  if v_booking.status not in ('paid', 'in_progress', 'consulted', 'completed') then
    return jsonb_build_object('outcome', 'wrong_status', 'status', v_booking.status);
  end if;

  select * into v_rx from prescriptions
   where booking_id = p_booking_id and status = 'draft' for update;
  if not found then
    if exists (select 1 from prescriptions where booking_id = p_booking_id and status = 'submitted') then
      return jsonb_build_object('outcome', 'sent');
    end if;
    insert into prescriptions (booking_id, doctor_id, patient_id)
    values (p_booking_id, p_doctor_id, v_booking.patient_id)
    returning * into v_rx;
  end if;

  -- The whole draft is replaced (PUT): a field left out is cleared.
  update prescriptions set
    kind           = coalesce(v_fields->>'kind', 'prescription'),
    patient_age    = (v_fields->>'patient_age')::int,
    patient_sex    = v_fields->>'patient_sex',
    complaints     = nullif(trim(v_fields->>'complaints'), ''),
    diagnosis      = nullif(trim(v_fields->>'diagnosis'), ''),
    investigations = nullif(trim(v_fields->>'investigations'), ''),
    advice         = nullif(trim(v_fields->>'advice'), ''),
    tpg_attested   = coalesce((v_fields->>'tpg_attested')::boolean, false)
  where id = v_rx.id
  returning * into v_rx;

  delete from prescription_items where prescription_id = v_rx.id;
  insert into prescription_items (prescription_id, position, medicine, strength, form, dose,
                                  route, frequency, duration, instructions)
  select v_rx.id, row_number() over (order by t.ord),
         trim(t.e->>'medicine'),
         nullif(trim(t.e->>'strength'), ''), nullif(trim(t.e->>'form'), ''),
         nullif(trim(t.e->>'dose'), ''), nullif(trim(t.e->>'route'), ''),
         nullif(trim(t.e->>'frequency'), ''), nullif(trim(t.e->>'duration'), ''),
         nullif(trim(t.e->>'instructions'), '')
    from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) with ordinality as t(e, ord)
   where coalesce(trim(t.e->>'medicine'), '') <> '';

  return jsonb_build_object('outcome', 'ok', 'prescription', to_jsonb(v_rx));
end;
$$;

-- Starting a correction, in one transaction: a new draft (version + 1) that
-- copies the sent prescription and its medicines. The sent one stays with the
-- patient until the correction is sent.
--
-- Returns {"outcome": ok | not_found | forbidden | not_current | draft_exists,
--          "prescription": {...}}.
create or replace function start_prescription_correction(
  p_prescription_id uuid,
  p_doctor_id       uuid
) returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_booking_id uuid;
  v_rx         prescriptions%rowtype;
  v_new        prescriptions%rowtype;
begin
  select booking_id into v_booking_id from prescriptions where id = p_prescription_id;
  if not found then
    return jsonb_build_object('outcome', 'not_found');
  end if;
  perform 1 from bookings where id = v_booking_id for update;
  select * into v_rx from prescriptions where id = p_prescription_id for update;
  if v_rx.doctor_id is distinct from p_doctor_id then
    return jsonb_build_object('outcome', 'forbidden');
  end if;
  if v_rx.status <> 'submitted' then
    return jsonb_build_object('outcome', 'not_current', 'status', v_rx.status);
  end if;
  if exists (select 1 from prescriptions where booking_id = v_booking_id and status = 'draft') then
    return jsonb_build_object('outcome', 'draft_exists');
  end if;

  insert into prescriptions (booking_id, doctor_id, patient_id, version, kind, patient_age,
                             patient_sex, complaints, diagnosis, investigations, advice,
                             tpg_attested, upload_path, upload_mime, supersedes_id)
  values (v_rx.booking_id, v_rx.doctor_id, v_rx.patient_id,
          (select max(version) + 1 from prescriptions where booking_id = v_booking_id),
          v_rx.kind, v_rx.patient_age, v_rx.patient_sex, v_rx.complaints, v_rx.diagnosis,
          v_rx.investigations, v_rx.advice, v_rx.tpg_attested, v_rx.upload_path,
          v_rx.upload_mime, v_rx.id)
  returning * into v_new;

  insert into prescription_items (prescription_id, position, medicine, strength, form, dose,
                                  route, frequency, duration, instructions)
  select v_new.id, position, medicine, strength, form, dose, route, frequency, duration, instructions
    from prescription_items where prescription_id = v_rx.id;

  return jsonb_build_object('outcome', 'ok', 'prescription', to_jsonb(v_new));
end;
$$;

-- Sending a prescription, in one transaction: the draft becomes the
-- patient's prescription (a correction supersedes the one it replaces), the
-- booking moves to 'consulted' (through in_progress if the consultation was
-- never started), and the follow-up recommendation is recorded. The PDF has
-- already been rendered and stored by the backend from the draft as it stood
-- at ``p_draft_updated_at``; if the draft was saved again since, nothing is
-- sent ('changed') and the backend renders it again.
--
-- Returns {"outcome": ok | not_found | forbidden | not_draft | changed
--          | wrong_status, "prescription": {...}, "superseded_id": <uuid or null>}.
drop function if exists submit_prescription(uuid, uuid, timestamptz, text, text, jsonb);
create or replace function submit_prescription(
  p_prescription_id  uuid,
  p_doctor_id        uuid,
  p_submitted_at     timestamptz,
  p_pdf_path         text,
  p_pdf_sha256       text,
  p_follow_up        jsonb default null,
  p_draft_updated_at timestamptz default null
) returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_rx         prescriptions%rowtype;
  v_booking_id uuid;
  v_status     text;
  v_old        uuid;
  v_result     jsonb;
begin
  select booking_id into v_booking_id from prescriptions where id = p_prescription_id;
  if not found then
    return jsonb_build_object('outcome', 'not_found');
  end if;
  select status into v_status from bookings where id = v_booking_id for update;
  select * into v_rx from prescriptions where id = p_prescription_id for update;
  if v_rx.doctor_id is distinct from p_doctor_id then
    return jsonb_build_object('outcome', 'forbidden');
  end if;
  if v_rx.status <> 'draft' then
    return jsonb_build_object('outcome', 'not_draft', 'status', v_rx.status);
  end if;
  if p_draft_updated_at is not null and v_rx.updated_at <> p_draft_updated_at then
    return jsonb_build_object('outcome', 'changed');
  end if;

  if v_status not in ('paid', 'in_progress', 'consulted', 'completed') then
    return jsonb_build_object('outcome', 'wrong_status', 'status', v_status);
  end if;
  if v_status = 'paid' then
    v_result := transition_booking(v_rx.booking_id, 'start_consultation', 'doctor', p_doctor_id, 'paid');
    if v_result->>'outcome' <> 'ok' then return v_result; end if;
    v_status := 'in_progress';
  end if;
  if v_status = 'in_progress' then
    v_result := transition_booking(v_rx.booking_id, 'end_consultation', 'doctor', p_doctor_id, 'in_progress');
    if v_result->>'outcome' <> 'ok' then return v_result; end if;
  end if;

  update prescriptions set status = 'superseded', superseded_at = p_submitted_at
   where booking_id = v_rx.booking_id and status = 'submitted'
  returning id into v_old;

  update prescriptions
     set status = 'submitted', submitted_at = p_submitted_at,
         pdf_path = p_pdf_path, pdf_sha256 = p_pdf_sha256
   where id = v_rx.id
  returning * into v_rx;

  update bookings set prescription_sent_at = p_submitted_at
   where id = v_rx.booking_id and prescription_sent_at is null;

  -- The sent prescription carries the doctor's current recommendation. A
  -- correction replaces the earlier one, including by having none.
  update follow_up_recommendations set status = 'dismissed'
   where booking_id = v_rx.booking_id and status = 'open';
  if p_follow_up is not null then
    insert into follow_up_recommendations (booking_id, prescription_id, doctor_id, patient_id,
                                           recommended_date, channel, note)
    values (v_rx.booking_id, v_rx.id, v_rx.doctor_id, v_rx.patient_id,
            (p_follow_up->>'date')::date, p_follow_up->>'channel', p_follow_up->>'note');
  end if;

  insert into booking_events (booking_id, event, from_status, to_status, actor_role, actor_id, metadata)
  select v_rx.booking_id, 'prescription_sent', b.status, b.status, 'doctor', p_doctor_id,
         jsonb_build_object('version', v_rx.version, 'kind', v_rx.kind,
                            'corrects', case when v_old is not null then true else false end)
    from bookings b where b.id = v_rx.booking_id;

  return jsonb_build_object('outcome', 'ok', 'prescription', to_jsonb(v_rx), 'superseded_id', v_old);
end;
$$;

-- Opening the prescription. Only the booking's own patient, only a sent
-- prescription. The first open is stamped once (later opens change nothing),
-- and if the booking is waiting on it, the booking completes (the product
-- rule: a consultation is complete when the patient views the prescription).
-- The backend calls this only for the patient's own session reading the
-- prescription itself; a doctor or ops reading it never does.
--
-- Returns {"outcome": ok | not_found | forbidden | not_sent, "first_viewed_at",
--          "completed": <true if this view completed the booking>}.
create or replace function record_prescription_view(
  p_prescription_id uuid,
  p_patient_id      uuid
) returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_rx         prescriptions%rowtype;
  v_booking_id uuid;
  v_result     jsonb;
  v_done       boolean := false;
begin
  select booking_id into v_booking_id from prescriptions where id = p_prescription_id;
  if not found then
    return jsonb_build_object('outcome', 'not_found');
  end if;
  perform 1 from bookings where id = v_booking_id for update;
  select * into v_rx from prescriptions where id = p_prescription_id for update;
  if v_rx.patient_id is distinct from p_patient_id then
    return jsonb_build_object('outcome', 'forbidden');
  end if;
  if v_rx.status = 'draft' then
    return jsonb_build_object('outcome', 'not_sent');
  end if;

  if v_rx.first_viewed_at is null then
    update prescriptions set first_viewed_at = now() where id = v_rx.id
    returning * into v_rx;
  end if;

  -- Only the current version counts for the booking. An old link to a
  -- superseded version is recorded on that version and changes nothing else.
  if v_rx.status <> 'submitted' then
    return jsonb_build_object('outcome', 'ok', 'first_viewed_at', v_rx.first_viewed_at,
                              'completed', false);
  end if;

  update bookings set prescription_viewed_at = v_rx.first_viewed_at
   where id = v_rx.booking_id and prescription_viewed_at is null;

  if exists (select 1 from bookings where id = v_rx.booking_id and status = 'consulted') then
    v_result := transition_booking(v_rx.booking_id, 'complete', 'patient', p_patient_id, 'consulted',
                                   jsonb_build_object('completion_source', 'patient_viewed'));
    v_done := v_result->>'outcome' = 'ok';
  end if;

  return jsonb_build_object('outcome', 'ok', 'first_viewed_at', v_rx.first_viewed_at,
                            'completed', v_done);
end;
$$;

-- The fallback (decision D13, LD-006): a prescription nobody opened completes
-- its booking 72 hours after it was sent. Run by the job queue.
create or replace function complete_unviewed_booking(p_booking_id uuid)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
begin
  return transition_booking(p_booking_id, 'complete', 'system', null, 'consulted',
                            jsonb_build_object('completion_source', 'fallback'));
end;
$$;

-- ── 4. Follow-up recommendations ─────────────────────────────────────────────
-- Part of the prescription the doctor sends. Nothing is ever booked or
-- charged from it: it is a recommendation with a reminder and a "Book" button.
create table if not exists follow_up_recommendations (
  id               uuid primary key default uuid_generate_v4(),
  booking_id       uuid not null references bookings(id) on delete cascade,
  prescription_id  uuid not null unique references prescriptions(id) on delete cascade,
  doctor_id        uuid not null references doctors(id),
  patient_id       uuid not null references users(id),
  recommended_date date not null,
  channel          text not null check (channel in ('online_consult', 'home_visit', 'either')),
  note             text,
  status           text not null default 'open'
                   check (status in ('open', 'booked', 'dismissed', 'expired')),
  -- The booking made from it, once there is one (Phase 4 follow-up pricing).
  booked_booking_id uuid references bookings(id) on delete set null,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index if not exists idx_follow_ups_patient on follow_up_recommendations (patient_id, status);

drop trigger if exists trg_follow_ups_updated_at on follow_up_recommendations;
create trigger trg_follow_ups_updated_at before update on follow_up_recommendations
  for each row execute function set_updated_at();

alter table follow_up_recommendations enable row level security;
revoke all on follow_up_recommendations from anon, authenticated;
grant all on follow_up_recommendations to service_role;

-- ── 5. Who joined a call, and when ───────────────────────────────────────────
-- Recorded each time the backend mints a call token. Evidence for "the doctor
-- never joined" (Phase 6) that doesn't rest on anyone's word.
create table if not exists call_joins (
  id          bigint generated always as identity primary key,
  booking_id  uuid not null references bookings(id) on delete cascade,
  actor_role  text not null check (actor_role in ('patient', 'doctor')),
  actor_id    uuid not null,
  kind        text not null check (kind in ('consultation', 'clarification')),
  joined_at   timestamptz not null default now()
);
create index if not exists idx_call_joins_booking on call_joins (booking_id, joined_at);

drop trigger if exists trg_call_joins_append_only on call_joins;
create trigger trg_call_joins_append_only before update or delete on call_joins
  for each row execute function forbid_history_rewrite();

alter table call_joins enable row level security;
revoke all on call_joins from anon, authenticated;
grant select, insert on call_joins to service_role;

-- ── 6. The doctor's signature, for the prescription PDF ─────────────────────
alter table doctors add column if not exists signature_path text;

-- ── 7. Settings ──────────────────────────────────────────────────────────────
insert into app_config (key, value) values
  -- D13: a prescription nobody opens completes its booking after this long.
  ('completion_fallback_hours', '72'),
  -- D17 (recommended): remind on the day at this hour (IST), and this many
  -- days before when the follow-up is at least `advance_if_days_away` away.
  ('follow_up_reminders', '{"hour_ist": 9, "advance_days": 2, "advance_if_days_away": 7}'),
  -- Appointment reminders, minutes before the start.
  ('appointment_reminders', '{"online_consult": [1440, 15], "home_visit": [1440, 120]}'),
  -- How early the doctor can start the consultation, minutes before the slot.
  -- Starting it ends the patient's right to cancel, so not before the window
  -- the cancellation policy already treats as "the visit is happening".
  ('consultation_start_window_minutes', '{"online_consult": 15, "home_visit": 120}')
on conflict (key) do nothing;

-- ── 8. Who may call the functions ────────────────────────────────────────────
revoke execute on function transition_booking(uuid, text, text, uuid, text, jsonb, text, jsonb) from public, anon, authenticated;
revoke execute on function start_journey(uuid, uuid, int, timestamptz)          from public, anon, authenticated;
revoke execute on function record_prescription_view(uuid, uuid)                 from public, anon, authenticated;
revoke execute on function complete_unviewed_booking(uuid)                      from public, anon, authenticated;
revoke execute on function submit_prescription(uuid, uuid, timestamptz, text, text, jsonb, timestamptz) from public, anon, authenticated;
revoke execute on function save_prescription_draft(uuid, uuid, jsonb, jsonb)    from public, anon, authenticated;
revoke execute on function start_prescription_correction(uuid, uuid)            from public, anon, authenticated;
revoke execute on function guard_submitted_prescription()                       from public, anon, authenticated;
revoke execute on function guard_prescription_items()                           from public, anon, authenticated;

grant execute on function transition_booking(uuid, text, text, uuid, text, jsonb, text, jsonb) to service_role;
grant execute on function start_journey(uuid, uuid, int, timestamptz)          to service_role;
grant execute on function record_prescription_view(uuid, uuid)                 to service_role;
grant execute on function complete_unviewed_booking(uuid)                      to service_role;
grant execute on function submit_prescription(uuid, uuid, timestamptz, text, text, jsonb, timestamptz) to service_role;
grant execute on function save_prescription_draft(uuid, uuid, jsonb, jsonb)    to service_role;
grant execute on function start_prescription_correction(uuid, uuid)            to service_role;
