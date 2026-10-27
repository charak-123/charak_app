-- ═══════════════════════════════════════════════════════════════════════════
-- 0029: operations hardening (plan Phase 7, spec §17, §21, §27).
--
--   admin_users.role     support | ops_lead | finance | admin; the backend maps
--                        each role to what it may do (services/admin_roles.py)
--   approvals            a cancellation policy or legal document applies only
--                        once someone has recorded approving it (the legal
--                        review gate, D20); approvals are append-only
--   ops overrides        ops can correct a stuck booking through the state
--                        machine only, with a reason (spec §17.3: no unlogged
--                        "edit anything")
--   ops_metrics()        the §21 numbers that drive action, in one call
--
-- Idempotent: safe to re-run in the SQL Editor.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. Admin roles ───────────────────────────────────────────────────────────
-- Existing accounts keep everything they could do: they become 'admin'.
alter table admin_users add column if not exists role text not null default 'admin';
alter table admin_users drop constraint if exists admin_users_role;
alter table admin_users add constraint admin_users_role
  check (role in ('support', 'ops_lead', 'finance', 'admin'));
-- New accounts start with the least: an admin raises it.
alter table admin_users alter column role set default 'support';

-- ── 2. The legal review gate ─────────────────────────────────────────────────
create table if not exists policy_approvals (
  id            uuid primary key default uuid_generate_v4(),
  policy_id     uuid not null unique references policies(id),
  -- Who approved it, in words (e.g. "Founder; counsel review 2026-11-02").
  approved_by   text not null check (length(approved_by) between 3 and 200),
  admin_id      uuid,
  note          text,
  approved_at   timestamptz not null default now()
);

create table if not exists legal_document_approvals (
  id            uuid primary key default uuid_generate_v4(),
  document_id   uuid not null unique references legal_documents(id),
  approved_by   text not null check (length(approved_by) between 3 and 200),
  admin_id      uuid,
  note          text,
  approved_at   timestamptz not null default now()
);

drop trigger if exists trg_policy_approvals_append_only on policy_approvals;
create trigger trg_policy_approvals_append_only before update or delete on policy_approvals
  for each row execute function forbid_history_rewrite();
drop trigger if exists trg_legal_document_approvals_append_only on legal_document_approvals;
create trigger trg_legal_document_approvals_append_only before update or delete on legal_document_approvals
  for each row execute function forbid_history_rewrite();

alter table policy_approvals enable row level security;
alter table legal_document_approvals enable row level security;
revoke all on policy_approvals, legal_document_approvals from anon, authenticated;
grant select, insert on policy_approvals, legal_document_approvals to service_role;

-- Versions already in force were decided before this gate existed; they're
-- recorded as such so nothing in use stops applying.
insert into policy_approvals (policy_id, approved_by, note, approved_at)
select p.id, 'In force before the review gate (migration 0029)',
       coalesce('Decision ' || p.decision_ref, null), p.created_at
  from policies p
on conflict (policy_id) do nothing;

insert into legal_document_approvals (document_id, approved_by, note, approved_at)
select d.id, 'In force before the review gate (migration 0029)', null, d.published_at
  from legal_documents d
on conflict (document_id) do nothing;

-- Only an approved version is ever current.
create or replace function current_cancellation_policy(p_channel text, p_at timestamptz default now())
returns uuid
language sql
stable
security invoker
set search_path = public
as $$
  select p.id from policies p
    join policy_approvals a on a.policy_id = p.id
   where p.kind = 'cancellation' and p.channel = p_channel and p.effective_from <= p_at
   order by p.effective_from desc, p.created_at desc
   limit 1;
$$;

-- ── 3. Ops overrides, through the state machine ──────────────────────────────
-- A visit happened but nobody closed it (completion_source 'ops'), or a
-- consultation was started by mistake. Every other change goes through the
-- normal flows (cancel, remedies, reschedules).
insert into booking_transitions (from_status, event, to_status, allowed_roles) values
  ('paid',        'ops_complete', 'completed', '{ops}'),
  ('in_progress', 'ops_complete', 'completed', '{ops}'),
  ('consulted',   'ops_complete', 'completed', '{ops}'),
  ('in_progress', 'ops_revert',   'paid',      '{ops}')
on conflict (from_status, event) do update
  set to_status = excluded.to_status, allowed_roles = excluded.allowed_roles;

-- ── 4. The numbers that drive action (spec §21) ──────────────────────────────
-- One call for the admin Health page. Counts only; nothing about any one
-- patient. Bookings by when they were made; visits by when they were due.
create or replace function ops_metrics(p_days int default 30)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_since timestamptz := now() - make_interval(days => greatest(1, least(p_days, 365)));
  v_out   jsonb;
begin
  with
  made as (select * from bookings where created_at >= v_since),
  due  as (select * from bookings where scheduled_start >= v_since and scheduled_start < now()),
  held as (select * from due where status in ('in_progress', 'consulted', 'completed')),
  cancels as (
    select b.id, b.cancelled_by, (e.metadata->>'refund_pct')::int as pct
      from made b
      left join lateral (select metadata from booking_events
                          where booking_id = b.id and event = 'cancel' order by occurred_at desc limit 1) e on true
     where b.status = 'cancelled'
  ),
  inc as (select * from incidents where created_at >= v_since),
  ref as (select * from refunds where created_at >= v_since),
  rx  as (select * from bookings where prescription_sent_at >= v_since),
  rv  as (select * from reviews where created_at >= v_since and status = 'published')
  select jsonb_build_object(
    'window_days', extract(day from now() - v_since)::int,
    'bookings', jsonb_build_object(
      'requested', (select count(*) from made),
      'confirmed', (select count(*) from made b
                     where exists (select 1 from booking_events e where e.booking_id = b.id and e.event = 'pay')),
      'patient_cancelled_free', (select count(*) from cancels where cancelled_by = 'patient' and coalesce(pct, 100) >= 100),
      'patient_cancelled_late', (select count(*) from cancels where cancelled_by = 'patient' and pct < 100),
      'doctor_cancelled', (select count(*) from cancels where cancelled_by = 'doctor'),
      'requests_expired', (select count(*) from cancels where cancelled_by = 'system'),
      'patient_no_shows', (select count(*) from due where status = 'no_show')
    ),
    'attendance', jsonb_build_object(
      'visits_held', (select count(*) from held),
      'home_visits_held', (select count(*) from held where channel = 'home_visit'),
      'home_visits_with_journey', (select count(*) from held where channel = 'home_visit' and journey_started_at is not null),
      'doctor_no_shows_confirmed', (select count(*) from inc where type = 'doctor_no_show' and status = 'confirmed'
                                      and cause = 'doctor' and appeal_status <> 'reversed'),
      'call_problems_reported', (select count(*) from inc where type = 'technical'),
      'reschedules', (select coalesce(jsonb_object_agg(cause, n), '{}'::jsonb)
                        from (select cause, count(*) n from reschedule_requests
                               where created_at >= v_since group by cause) r)
    ),
    'incidents', jsonb_build_object(
      'reported', (select count(*) from inc),
      'unresolved', (select count(*) from incidents where status in ('reported', 'under_review')),
      'appeals_open', (select count(*) from incidents where appeal_status = 'appealed'),
      'appeals_reversed', (select count(*) from inc where appeal_status = 'reversed'),
      'remedies', (select coalesce(jsonb_object_agg(remedy, n), '{}'::jsonb)
                     from (select remedy, count(*) n from inc where remedy_eligible group by remedy) r),
      'replacements_paid', (select count(*) from inc i join bookings b on b.id = i.remedy_booking_id
                             where i.remedy = 'replacement' and b.status in ('paid', 'in_progress', 'consulted', 'completed'))
    ),
    'refunds', jsonb_build_object(
      'count', (select count(*) from ref),
      'processed', (select count(*) from ref where status = 'processed'),
      'failed', (select count(*) from ref where status = 'failed'),
      'open', (select count(*) from refunds where status in ('pending', 'processing')),
      'median_minutes_to_processed', (select round(percentile_cont(0.5) within group
                                        (order by extract(epoch from processed_at - created_at) / 60)::numeric, 1)
                                        from ref where status = 'processed' and processed_at is not null),
      'by_reason', (select coalesce(jsonb_object_agg(reason, n), '{}'::jsonb)
                      from (select reason, count(*) n from ref group by reason) r)
    ),
    'prescriptions', jsonb_build_object(
      'sent', (select count(*) from rx),
      'median_minutes_after_start', (select round(percentile_cont(0.5) within group
                                       (order by extract(epoch from prescription_sent_at - scheduled_start) / 60)::numeric, 1)
                                       from rx),
      'opened_within_48h', (select count(*) from rx where prescription_viewed_at <= prescription_sent_at + interval '48 hours'),
      'awaiting_view', (select count(*) from bookings where status = 'consulted'),
      'completed_by_fallback', (select count(*) from rx where completion_source = 'fallback'),
      'follow_ups_recommended', (select count(*) from follow_up_recommendations where created_at >= v_since),
      'follow_ups_booked', (select count(*) from made where follow_up_of is not null)
    ),
    'reviews', jsonb_build_object(
      'count', (select count(*) from rv),
      'completed_visits', (select count(*) from due where status = 'completed'),
      'distribution', (select coalesce(jsonb_object_agg(overall, n), '{}'::jsonb)
                         from (select overall, count(*) n from rv group by overall) r),
      'avg_professionalism', (select round(avg(professionalism)::numeric, 2) from rv),
      'avg_communication', (select round(avg(communication)::numeric, 2) from rv),
      'avg_punctuality', (select round(avg(punctuality)::numeric, 2) from rv),
      'reported_open', (select count(*) from review_reports where status = 'open'),
      'hidden', (select count(*) from reviews where status = 'hidden')
    ),
    'money', jsonb_build_object(
      'payouts', (select coalesce(jsonb_object_agg(status, n), '{}'::jsonb)
                    from (select status, count(*) n from payouts where created_at >= v_since group by status) r),
      'ledger_reversals', (select count(*) from doctor_ledger_entries
                            where created_at >= v_since and (status = 'reversed' or source = 'reversal'))
    ),
    'system', jsonb_build_object(
      'dead_jobs', (select count(*) from jobs where status = 'dead'),
      -- Received but never processed, after at least one failed attempt.
      'failed_webhooks', (select count(*) from webhook_events
                            where processed_at is null and last_error is not null),
      'failed_notifications', (select count(*) from notifications
                                 where delivery = 'failed' and created_at >= v_since)
    )
  ) into v_out;
  return v_out;
end;
$$;

revoke execute on function ops_metrics(int) from public, anon, authenticated;
grant execute on function ops_metrics(int) to service_role;

notify pgrst, 'reload schema';
