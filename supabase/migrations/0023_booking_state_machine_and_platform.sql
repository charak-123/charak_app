-- ═══════════════════════════════════════════════════════════════════════════
-- 0023: the booking state machine and its event log, plus the pieces every
-- later phase builds on: idempotency keys, a job queue, a notification outbox,
-- multi-device push tokens, a webhook inbox, and app config (minimum app
-- versions, feature flags).
--
-- Why
--   * Booking status changes were spread across routers: each one checked
--     strings and did its own compare-and-set update. The allowed moves now
--     live in one table (booking_transitions) and one function
--     (transition_booking) that locks the row, checks the actor and the
--     current status, and records the change in booking_events in the same
--     transaction.
--   * There was no history of a booking, only its current row.
--     booking_events is append-only. A trigger on bookings also records any
--     status change made outside the state machine (old code during a deploy,
--     a hand edit in the SQL Editor), so the timeline has no gaps.
--   * Notifications were sent from FastAPI background tasks. On Cloud Run,
--     CPU can be throttled once the response has gone, so a push could be
--     delayed or never sent. Rows are now an outbox: claimed, retried with
--     backoff, and swept by a timer.
--
-- Deploy order: apply this, then deploy the backend that uses it. The backend
-- before this keeps working against it: cancel_booking() keeps its old
-- parameters (the new one has a default), and its direct status updates are
-- still allowed, just recorded as such.
--
-- Idempotent: safe to re-run in the SQL Editor.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 0. Append-only guard, shared ─────────────────────────────────────────────
-- UPDATE is always refused. A direct DELETE is refused too. Allowed:
--   * the cascade from deleting a parent row (pg_trigger_depth() > 1), which
--     only the database owner can start;
--   * a retention purge that sets charak.retention_purge = 'on' for its
--     transaction (LD-009 retention periods).
create or replace function forbid_history_rewrite()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_op = 'UPDATE' then
    raise exception '% is append-only: rows cannot be changed', tg_table_name
      using errcode = 'insufficient_privilege';
  end if;
  if pg_trigger_depth() <= 1
     and coalesce(current_setting('charak.retention_purge', true), '') <> 'on' then
    raise exception '% is append-only: rows cannot be deleted', tg_table_name
      using errcode = 'insufficient_privilege';
  end if;
  return old;
end;
$$;

-- ── 1. Booking events ────────────────────────────────────────────────────────
create table if not exists booking_events (
  id              bigint generated always as identity primary key,
  booking_id      uuid not null references bookings(id) on delete cascade,
  -- What happened: created, accept, decline, cancel, pay, complete, no_show,
  -- hold_expire, request_expire, or status_changed_outside_state_machine.
  event           text not null,
  from_status     text,
  to_status       text not null,
  actor_role      text not null check (actor_role in ('patient', 'doctor', 'ops', 'system')),
  actor_id        uuid,
  occurred_at     timestamptz not null default now(),
  -- Set when the caller supplied one; a retried call with the same key gets
  -- the first result back instead of a second transition.
  idempotency_key text unique,
  -- Safe facts only (e.g. who cancelled, minutes late). Never clinical
  -- detail, never secrets.
  metadata        jsonb not null default '{}'::jsonb
);

create index if not exists idx_booking_events_booking on booking_events (booking_id, occurred_at);
create index if not exists idx_booking_events_occurred on booking_events (occurred_at);

drop trigger if exists trg_booking_events_append_only on booking_events;
create trigger trg_booking_events_append_only
  before update or delete on booking_events
  for each row execute function forbid_history_rewrite();

alter table booking_events enable row level security;
revoke all on booking_events from anon, authenticated;
grant select, insert on booking_events to service_role;
-- The backend writes events; it never edits or removes them. The trigger above
-- enforces that for every role. This also keeps the grant honest.
revoke update, delete, truncate on booking_events from service_role;

-- A booking's birth is an event too. Bookings are created by a plain insert
-- (create_booking in the API), so a trigger records it.
create or replace function record_booking_created()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  insert into booking_events (booking_id, event, from_status, to_status, actor_role, actor_id)
  values (new.id, 'created', null, new.status, 'patient', new.patient_id);
  return new;
end;
$$;

drop trigger if exists trg_bookings_created_event on bookings;
create trigger trg_bookings_created_event
  after insert on bookings
  for each row execute function record_booking_created();

-- Any status change that didn't go through transition_booking() is still
-- recorded, flagged as such. transition_booking() sets charak.state_machine
-- for its own transaction, so its changes are not double-counted.
create or replace function record_unmanaged_status_change()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.status is distinct from old.status
     and coalesce(current_setting('charak.state_machine', true), '') <> 'on' then
    insert into booking_events (booking_id, event, from_status, to_status, actor_role, metadata)
    values (new.id, 'status_changed_outside_state_machine', old.status, new.status, 'system',
            jsonb_build_object('db_user', current_user));
  end if;
  return new;
end;
$$;

drop trigger if exists trg_bookings_unmanaged_status on bookings;
create trigger trg_bookings_unmanaged_status
  after update of status on bookings
  for each row execute function record_unmanaged_status_change();

-- ── 2. The allowed moves ─────────────────────────────────────────────────────
create table if not exists booking_transitions (
  from_status   text not null,
  event         text not null,
  to_status     text not null,
  allowed_roles text[] not null,
  primary key (from_status, event)
);

insert into booking_transitions (from_status, event, to_status, allowed_roles) values
  ('requested', 'accept',         'accepted',  '{doctor}'),
  ('requested', 'decline',        'declined',  '{doctor}'),
  ('accepted',  'decline',        'declined',  '{doctor}'),
  ('requested', 'cancel',         'cancelled', '{patient,doctor,ops}'),
  ('accepted',  'cancel',         'cancelled', '{patient,doctor,ops}'),
  ('paid',      'cancel',         'cancelled', '{patient,doctor,ops}'),
  ('accepted',  'pay',            'paid',      '{system}'),
  ('paid',      'complete',       'completed', '{doctor}'),
  ('accepted',  'no_show',        'no_show',   '{doctor}'),
  ('accepted',  'hold_expire',    'cancelled', '{system}'),
  ('requested', 'request_expire', 'cancelled', '{system}')
on conflict (from_status, event) do update
  set to_status = excluded.to_status, allowed_roles = excluded.allowed_roles;

alter table booking_transitions enable row level security;
revoke all on booking_transitions from anon, authenticated;
grant select on booking_transitions to service_role;

-- ── 3. transition_booking() ──────────────────────────────────────────────────
-- The one way a booking changes status. In one transaction:
--   lock the row → check the actor owns it (patients and doctors) → check the
--   caller's expected status (compare-and-set) → look up the move → check the
--   actor's role may make it → apply the status and the allowed column patch
--   → append the event.
--
-- Returns {"outcome": ok | replayed | not_found | forbidden | conflict | invalid
--          | key_reused, "status": <current>, "booking": {...}, "event": {...}}.
-- Refusals are outcomes, not exceptions, so the API can word each one.
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

  -- Checked under the lock, so two calls racing with one key resolve to one
  -- transition and one replay.
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

-- ── 4. cancel_booking(), now through the state machine ───────────────────────
-- Same contract as 0022 (outcome cancelled | conflict | not_cancellable |
-- not_found, plus forbidden), now with an event and an optional idempotency
-- key. The new parameter has a default, so the backend built against 0022
-- keeps calling it unchanged.
drop function if exists cancel_booking(uuid, text, text, uuid);

create or replace function cancel_booking(
  p_booking_id      uuid,
  p_expected_status text,
  p_cancelled_by    text,
  p_actor_id        uuid,
  p_idempotency_key text default null
) returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_result   jsonb;
  v_outcome  text;
  v_payment  payments%rowtype;
  v_refund   refunds%rowtype;
  v_refunds  jsonb := '[]'::jsonb;
  v_queued   bigint;
  v_due      bigint;
begin
  v_result := transition_booking(
    p_booking_id, 'cancel', p_cancelled_by, p_actor_id, p_expected_status,
    jsonb_build_object('cancelled_by', p_cancelled_by, 'hold_expires_at', null),
    p_idempotency_key, jsonb_build_object('cancelled_by', p_cancelled_by)
  );
  v_outcome := v_result->>'outcome';

  if v_outcome = 'invalid' then
    return jsonb_build_object('outcome', 'not_cancellable', 'status', v_result->>'status');
  end if;
  if v_outcome = 'replayed' then
    -- The first call committed. Hand back whatever of its refunds hasn't been
    -- sent yet, so a retry that lost the first response can finish the job.
    select coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb) into v_refunds
      from refunds r where r.booking_id = p_booking_id and r.status = 'pending';
    return jsonb_build_object('outcome', 'cancelled', 'status', v_result->>'status',
                              'booking', v_result->'booking', 'refunds', v_refunds);
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

  return jsonb_build_object('outcome', 'cancelled', 'status', 'cancelled',
                            'booking', v_result->'booking', 'refunds', v_refunds);
end;
$$;

-- ── 5. Timers that move bookings ─────────────────────────────────────────────
-- Accepted bookings whose payment window has closed. Each one is its own
-- transition (with its event), and SKIP LOCKED means a booking whose payment is
-- being confirmed right now is left for the next run instead of being
-- cancelled under it.
create or replace function expire_payment_holds(p_now timestamptz default now())
returns setof uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_id     uuid;
  v_result jsonb;
begin
  for v_id in
    select id from bookings
     where status = 'accepted' and hold_expires_at < p_now
     order by hold_expires_at
     for update skip locked
  loop
    v_result := transition_booking(
      v_id, 'hold_expire', 'system', null, 'accepted',
      jsonb_build_object('cancelled_by', 'system', 'hold_expires_at', null)
    );
    if v_result->>'outcome' = 'ok' then
      update payments set status = 'failed'
       where booking_id = v_id and status = 'initiated';
      return next v_id;
    end if;
  end loop;
end;
$$;

-- Requests the doctor never answered. A request whose slot has started can
-- never be fulfilled, so it always expires then. p_max_age, if given, expires
-- them sooner (decision N4 in docs/plans/next-release-plan.md; off unless the
-- app_config flag is set).
create or replace function expire_stale_requests(
  p_now     timestamptz default now(),
  p_max_age interval    default null
) returns setof uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_id     uuid;
  v_result jsonb;
begin
  for v_id in
    select id from bookings
     where status = 'requested'
       and (scheduled_start <= p_now
            or (p_max_age is not null and created_at < p_now - p_max_age))
     order by scheduled_start
     for update skip locked
  loop
    v_result := transition_booking(
      v_id, 'request_expire', 'system', null, 'requested',
      jsonb_build_object('cancelled_by', 'system')
    );
    if v_result->>'outcome' = 'ok' then
      return next v_id;
    end if;
  end loop;
end;
$$;

-- ── 6. Audit log: append-only, with a reason ─────────────────────────────────
alter table audit_log
  add column if not exists reason   text,
  add column if not exists metadata jsonb not null default '{}'::jsonb;

drop trigger if exists trg_audit_log_append_only on audit_log;
create trigger trg_audit_log_append_only
  before update or delete on audit_log
  for each row execute function forbid_history_rewrite();
revoke update, delete, truncate on audit_log from service_role;

-- ── 7. Idempotency keys (HTTP) ───────────────────────────────────────────────
-- One row per (user, Idempotency-Key header). The first request claims it; a
-- retry with the same key gets the stored response instead of running again.
-- Kept 24 hours (purged by /maintenance/purge-old-rate-limit-hits).
create table if not exists idempotency_keys (
  user_id       uuid not null,
  key           text not null check (length(key) between 8 and 128),
  method        text not null,
  path          text not null,
  request_hash  text not null,
  status_code   int,
  response_body jsonb,
  created_at    timestamptz not null default now(),
  completed_at  timestamptz,
  primary key (user_id, key)
);
create index if not exists idx_idempotency_keys_created on idempotency_keys (created_at);

alter table idempotency_keys enable row level security;
revoke all on idempotency_keys from anon, authenticated;
grant all on idempotency_keys to service_role;

-- ── 8. Job queue ─────────────────────────────────────────────────────────────
-- Postgres as the queue (the pg-boss / Solid Queue pattern). /maintenance/tick
-- claims due jobs with SKIP LOCKED, runs them, and retries failures with
-- backoff. A job that keeps failing ends 'dead' and shows in admin.
create table if not exists jobs (
  id            bigint generated always as identity primary key,
  kind          text not null,
  payload       jsonb not null default '{}'::jsonb,
  status        text not null default 'queued'
                check (status in ('queued', 'running', 'done', 'dead')),
  run_at        timestamptz not null default now(),
  attempts      int not null default 0,
  max_attempts  int not null default 8 check (max_attempts between 1 and 50),
  locked_until  timestamptz,
  last_error    text,
  -- One live job per key (e.g. "reminder:<booking>:T-1h"), so a retried
  -- enqueue never schedules the same work twice.
  dedupe_key    text unique,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  finished_at   timestamptz
);
create index if not exists idx_jobs_due on jobs (run_at) where status = 'queued';
create index if not exists idx_jobs_running on jobs (locked_until) where status = 'running';

drop trigger if exists trg_jobs_updated_at on jobs;
create trigger trg_jobs_updated_at before update on jobs
  for each row execute function set_updated_at();

alter table jobs enable row level security;
revoke all on jobs from anon, authenticated;
grant all on jobs to service_role;

create or replace function enqueue_job(
  p_kind         text,
  p_payload      jsonb       default '{}'::jsonb,
  p_run_at       timestamptz default now(),
  p_dedupe_key   text        default null,
  p_max_attempts int         default 8
) returns bigint
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_id bigint;
begin
  insert into jobs (kind, payload, run_at, dedupe_key, max_attempts)
  values (p_kind, coalesce(p_payload, '{}'::jsonb), coalesce(p_run_at, now()),
          p_dedupe_key, p_max_attempts)
  on conflict (dedupe_key) do nothing
  returning id into v_id;
  if v_id is null and p_dedupe_key is not null then
    select id into v_id from jobs where dedupe_key = p_dedupe_key;
  end if;
  return v_id;
end;
$$;

-- Claim up to p_limit due jobs, plus running ones whose lease expired (their
-- worker died). Each claim takes a lease; finish_job() or fail_job() ends it.
create or replace function claim_jobs(p_limit int default 10, p_lease_seconds int default 120)
returns setof jobs
language plpgsql
security invoker
set search_path = public
as $$
begin
  return query
  update jobs j
     set status = 'running',
         attempts = j.attempts + 1,
         locked_until = now() + make_interval(secs => p_lease_seconds)
   where j.id in (
     select id from jobs
      where (status = 'queued' and run_at <= now())
         or (status = 'running' and locked_until < now())
      order by run_at
      for update skip locked
      limit greatest(p_limit, 0)
   )
  returning j.*;
end;
$$;

create or replace function finish_job(p_id bigint)
returns void
language sql
security invoker
set search_path = public
as $$
  update jobs set status = 'done', locked_until = null, finished_at = now(), last_error = null
   where id = p_id and status = 'running';
$$;

-- Backoff: 1, 2, 4 … minutes, capped at an hour. Out of attempts → dead.
create or replace function fail_job(p_id bigint, p_error text)
returns text
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_status text;
begin
  update jobs
     set status = case when attempts >= max_attempts then 'dead' else 'queued' end,
         -- Exponent capped before the power, so a high max_attempts can't
         -- overflow the interval arithmetic.
         run_at = now() + least(make_interval(mins => power(2, least(greatest(attempts - 1, 0), 6))::int),
                                interval '1 hour'),
         locked_until = null,
         last_error = left(p_error, 2000),
         finished_at = case when attempts >= max_attempts then now() else null end
   where id = p_id and status = 'running'
  returning status into v_status;
  return v_status;
end;
$$;

-- ── 9. Notifications as an outbox ────────────────────────────────────────────
-- A row is claimed (claimed_until) before it is sent, so the inline attempt
-- and the timer never both send it. Temporary failures wait deliver_after and
-- are retried. dedupe_key makes one-shot events (booking accepted, refund
-- completed …) impossible to send twice.
alter table notifications
  add column if not exists dedupe_key      text,
  add column if not exists deliver_after   timestamptz not null default now(),
  add column if not exists claimed_until   timestamptz,
  add column if not exists attempts        int not null default 0,
  add column if not exists last_attempt_at timestamptz;

-- Rows left 'pending' by the old inline sender are history, not work: the
-- sweeper must not wake them up and push week-old news.
update notifications
   set delivery = 'skipped', delivery_error = 'not delivered before the outbox existed'
 where delivery = 'pending' and created_at < now() - interval '1 hour';

create unique index if not exists uq_notifications_dedupe
  on notifications (dedupe_key) where dedupe_key is not null;
create index if not exists idx_notifications_outbox
  on notifications (deliver_after) where delivery = 'pending';

-- ── 10. Device tokens: one row per device ────────────────────────────────────
-- users.fcm_token / doctors.fcm_token hold one device each, so a doctor signed
-- in on two phones got pushes on one. A token belongs to whoever registered it
-- last (a shared tablet that changes hands moves with the sign-in).
create table if not exists device_tokens (
  id           uuid primary key default uuid_generate_v4(),
  owner_id     uuid not null,
  owner_role   text not null check (owner_role in ('patient', 'doctor')),
  token        text not null unique,
  platform     text check (platform in ('android', 'ios')),
  created_at   timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);
create index if not exists idx_device_tokens_owner on device_tokens (owner_id);

alter table device_tokens enable row level security;
revoke all on device_tokens from anon, authenticated;
grant all on device_tokens to service_role;

insert into device_tokens (owner_id, owner_role, token, platform)
select id, 'patient', fcm_token, fcm_platform from users
 where fcm_token is not null and deleted_at is null
on conflict (token) do nothing;
insert into device_tokens (owner_id, owner_role, token, platform)
select id, 'doctor', fcm_token, fcm_platform from doctors
 where fcm_token is not null
on conflict (token) do nothing;

-- ── 11. Webhook inbox ────────────────────────────────────────────────────────
-- Every provider event is recorded once, by the provider's own event id.
-- A redelivery of an event already processed is acknowledged without running
-- again; one that failed half way (processed_at null) runs again.
create table if not exists webhook_events (
  id           bigint generated always as identity primary key,
  provider     text not null,
  event_id     text not null,
  event_type   text,
  payload      jsonb not null,
  received_at  timestamptz not null default now(),
  processed_at timestamptz,
  attempts     int not null default 0,
  last_error   text,
  unique (provider, event_id)
);
create index if not exists idx_webhook_events_unprocessed
  on webhook_events (received_at) where processed_at is null;

alter table webhook_events enable row level security;
revoke all on webhook_events from anon, authenticated;
grant all on webhook_events to service_role;

-- ── 12. App config: minimum versions and feature flags ──────────────────────
-- Read by GET /config/app (public). Raising min_version makes older builds
-- show a "please update" screen before they can reach a changed API.
create table if not exists app_config (
  key        text primary key,
  value      jsonb not null,
  updated_at timestamptz not null default now()
);

insert into app_config (key, value) values
  ('min_app_version', '{"patient": "1.0.0", "doctor": "1.0.0"}'),
  ('store_urls', '{
     "patient": {"android": "https://play.google.com/store/apps/details?id=com.charak.patient_app", "ios": null},
     "doctor":  {"android": "https://play.google.com/store/apps/details?id=com.charak.doctor_app",  "ios": null}
   }'),
  -- Unanswered requests expire after this many minutes (decision N4). Null:
  -- they expire only when their slot starts.
  ('request_expiry_minutes', 'null')
on conflict (key) do nothing;

drop trigger if exists trg_app_config_updated_at on app_config;
create trigger trg_app_config_updated_at before update on app_config
  for each row execute function set_updated_at();

alter table app_config enable row level security;
revoke all on app_config from anon, authenticated;
grant all on app_config to service_role;

-- ── 13. Who may call the functions ───────────────────────────────────────────
revoke execute on function forbid_history_rewrite()                                   from public, anon, authenticated;
revoke execute on function record_booking_created()                                   from public, anon, authenticated;
revoke execute on function record_unmanaged_status_change()                           from public, anon, authenticated;
revoke execute on function transition_booking(uuid, text, text, uuid, text, jsonb, text, jsonb) from public, anon, authenticated;
revoke execute on function cancel_booking(uuid, text, text, uuid, text)               from public, anon, authenticated;
revoke execute on function expire_payment_holds(timestamptz)                          from public, anon, authenticated;
revoke execute on function expire_stale_requests(timestamptz, interval)               from public, anon, authenticated;
revoke execute on function enqueue_job(text, jsonb, timestamptz, text, int)           from public, anon, authenticated;
revoke execute on function claim_jobs(int, int)                                       from public, anon, authenticated;
revoke execute on function finish_job(bigint)                                         from public, anon, authenticated;
revoke execute on function fail_job(bigint, text)                                     from public, anon, authenticated;

grant execute on function transition_booking(uuid, text, text, uuid, text, jsonb, text, jsonb) to service_role;
grant execute on function cancel_booking(uuid, text, text, uuid, text)               to service_role;
grant execute on function expire_payment_holds(timestamptz)                          to service_role;
grant execute on function expire_stale_requests(timestamptz, interval)               to service_role;
grant execute on function enqueue_job(text, jsonb, timestamptz, text, int)           to service_role;
grant execute on function claim_jobs(int, int)                                       to service_role;
grant execute on function finish_job(bigint)                                         to service_role;
grant execute on function fail_job(bigint, text)                                     to service_role;

-- ── Verify ───────────────────────────────────────────────────────────────────
-- Expect no rows:
--   select p.proname, r.rolname
--     from pg_proc p
--     join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public'
--     cross join (values ('anon'), ('authenticated')) r(rolname)
--    where has_function_privilege(r.rolname, p.oid, 'execute')
--      and p.proname not like 'uuid_%';
--
-- Every booking created from now on has a 'created' event:
--   select count(*) from bookings b
--    where b.created_at > now() - interval '1 day'
--      and not exists (select 1 from booking_events e
--                       where e.booking_id = b.id and e.event = 'created');
