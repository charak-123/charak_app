-- ═══════════════════════════════════════════════════════════════════════════
-- 0026: the pricing matrix (spec §8, plan §3.10). A doctor prices each channel
-- by duration, separately for a first visit and a follow-up; bookings carry an
-- immutable snapshot of what was charged; and the database itself refuses two
-- live bookings whose times overlap, whatever their lengths.
--
--   doctor_price_rules   one row per (channel, first/follow-up, duration) and
--                        price, never edited: a price change closes the row
--                        (effective_until) and adds a new one, so the history
--                        is the table
--   doctors.follow_up_validity_days   how long after a consultation a
--                        follow-up can be booked at the follow-up price
--   bookings             duration_min, scheduled_end, price_paise,
--                        price_rule_id, visit_category, follow_up_of
--
-- doctor_pricing stays, kept in step by set_doctor_prices(): app builds from
-- before this migration read it, and the directory's "from ₹X" sorts on it.
--
-- Idempotent: safe to re-run in the SQL Editor. Apply before deploying the
-- backend that uses it; the backend deployed before it keeps working (a
-- trigger fills the new booking columns for its inserts).
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. btree_gist, for the overlap constraint ────────────────────────────────
-- Supabase keeps extensions in their own schema; a plain Postgres has none.
do $$
begin
  if exists (select 1 from pg_namespace where nspname = 'extensions') then
    execute 'create extension if not exists btree_gist with schema extensions';
  else
    execute 'create extension if not exists btree_gist';
  end if;
end $$;

-- ── 2. Price rules ───────────────────────────────────────────────────────────
create table if not exists doctor_price_rules (
  id              uuid primary key default uuid_generate_v4(),
  doctor_id       uuid not null references doctors(id) on delete cascade,
  channel         text not null check (channel in ('online_consult', 'home_visit')),
  -- initial: a new medical issue. follow_up: a later visit for the same issue
  -- (spec §8.3), priced only when the booking qualifies.
  visit_category  text not null check (visit_category in ('initial', 'follow_up')),
  duration_min    int  not null check (duration_min in (10, 15, 20, 30, 45, 60)),
  -- Integer paise. A first visit is never free; a follow-up may be (a free
  -- follow-up is common practice) and then needs no payment.
  price_paise     bigint not null check (price_paise between 0 and 5000000),
  currency        text not null default 'INR' check (currency = 'INR'),
  effective_from  timestamptz not null default now(),
  effective_until timestamptz,
  created_by      uuid,
  created_at      timestamptz not null default now(),
  constraint price_rules_initial_not_free check (visit_category = 'follow_up' or price_paise > 0),
  constraint price_rules_period check (effective_until is null or effective_until >= effective_from)
);

-- One current price per (doctor, channel, category, duration).
create unique index if not exists uq_price_rules_current
  on doctor_price_rules (doctor_id, channel, visit_category, duration_min)
  where effective_until is null;
create index if not exists idx_price_rules_doctor
  on doctor_price_rules (doctor_id, effective_from desc);

-- A rule is history once written: only its end can be set, once.
create or replace function guard_price_rule()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    if pg_trigger_depth() <= 1
       and coalesce(current_setting('charak.retention_purge', true), '') <> 'on' then
      raise exception 'price rules are history: close one with effective_until instead'
        using errcode = 'insufficient_privilege';
    end if;
    return old;
  end if;
  if (new.doctor_id, new.channel, new.visit_category, new.duration_min, new.price_paise,
      new.currency, new.effective_from, new.created_at)
     is distinct from
     (old.doctor_id, old.channel, old.visit_category, old.duration_min, old.price_paise,
      old.currency, old.effective_from, old.created_at)
     or (old.effective_until is not null and new.effective_until is distinct from old.effective_until) then
    raise exception 'a price rule cannot be changed; close it and add a new one'
      using errcode = 'insufficient_privilege';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_price_rules_guard on doctor_price_rules;
create trigger trg_price_rules_guard before update or delete on doctor_price_rules
  for each row execute function guard_price_rule();

alter table doctor_price_rules enable row level security;
revoke all on doctor_price_rules from anon, authenticated;
grant all on doctor_price_rules to service_role;

alter table doctors add column if not exists follow_up_validity_days int;
alter table doctors drop constraint if exists doctors_follow_up_validity_days;
alter table doctors add constraint doctors_follow_up_validity_days
  check (follow_up_validity_days is null or follow_up_validity_days between 1 and 60);

-- The legacy price as a rule. A length outside the matrix's set goes to the
-- nearest one (ties to the longer).
create or replace function nearest_price_duration(p_minutes int)
returns int
language sql
immutable
as $$
  select d from unnest(array[10, 15, 20, 30, 45, 60]) d
   order by abs(d - coalesce(p_minutes, 15)), d desc limit 1
$$;

insert into doctor_price_rules (doctor_id, channel, visit_category, duration_min, price_paise, effective_from)
select dp.doctor_id, dp.channel, 'initial', nearest_price_duration(dp.base_duration_min),
       round(dp.price * 100)::bigint, coalesce(dp.updated_at, dp.created_at, now())
  from doctor_pricing dp
 where dp.price > 0
   and not exists (select 1 from doctor_price_rules r
                    where r.doctor_id = dp.doctor_id and r.channel = dp.channel)
on conflict do nothing;

-- ── 3. The booking's snapshot ────────────────────────────────────────────────
alter table bookings
  add column if not exists duration_min   int,
  add column if not exists scheduled_end  timestamptz,
  add column if not exists price_paise    bigint,
  add column if not exists price_rule_id  uuid references doctor_price_rules(id),
  add column if not exists visit_category text not null default 'initial',
  -- The consultation this follow-up continues (spec §8.3): the patient's own,
  -- with the same doctor, checked by the backend before the price is applied.
  add column if not exists follow_up_of   uuid references bookings(id);

alter table bookings drop constraint if exists bookings_visit_category;
alter table bookings add constraint bookings_visit_category
  check (visit_category in ('initial', 'follow_up') and (visit_category = 'initial') = (follow_up_of is null));
alter table bookings drop constraint if exists bookings_duration_min;
alter table bookings add constraint bookings_duration_min
  check (duration_min is null or duration_min between 5 and 240);

-- Existing bookings: the length their doctor charged for at the time (the
-- grid used it), else 15; the price they were confirmed at.
update bookings b
   set duration_min = coalesce(
         (select dp.base_duration_min from doctor_pricing dp
           where dp.doctor_id = b.doctor_id and dp.channel = b.channel), 15)
 where b.duration_min is null;
update bookings set scheduled_end = scheduled_start + make_interval(mins => duration_min)
 where scheduled_end is null;
update bookings set price_paise = round(price_confirmed * 100)::bigint
 where price_paise is null and price_confirmed is not null;

-- Rows written without the new columns (the backend deployed before this
-- migration) get them here, so the overlap check below always has an end.
create or replace function fill_booking_schedule()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.duration_min is null then
    select dp.base_duration_min into new.duration_min
      from doctor_pricing dp where dp.doctor_id = new.doctor_id and dp.channel = new.channel;
    new.duration_min := coalesce(new.duration_min, 15);
  end if;
  if new.scheduled_end is null
     or (tg_op = 'UPDATE' and new.scheduled_start is distinct from old.scheduled_start
         and new.scheduled_end is not distinct from old.scheduled_end) then
    new.scheduled_end := new.scheduled_start + make_interval(mins => new.duration_min);
  end if;
  if new.price_paise is null and new.price_confirmed is not null then
    new.price_paise := round(new.price_confirmed * 100)::bigint;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_bookings_fill_schedule on bookings;
create trigger trg_bookings_fill_schedule before insert or update on bookings
  for each row execute function fill_booking_schedule();

-- What the patient was charged never changes once it's set (spec §8.4).
create or replace function guard_booking_price()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if (old.price_paise is not null and new.price_paise is distinct from old.price_paise)
     or (old.price_confirmed is not null and new.price_confirmed is distinct from old.price_confirmed)
     or (old.price_rule_id is not null and new.price_rule_id is distinct from old.price_rule_id)
     or new.visit_category is distinct from old.visit_category
     or new.follow_up_of is distinct from old.follow_up_of
     or (old.duration_min is not null and new.duration_min is distinct from old.duration_min) then
    raise exception 'a booking''s price and length are fixed when it is made'
      using errcode = 'insufficient_privilege';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_bookings_guard_price on bookings;
create trigger trg_bookings_guard_price before update on bookings
  for each row execute function guard_booking_price();

-- ── 4. No two live bookings overlap ──────────────────────────────────────────
-- Equal start times were already refused (0010). Different lengths need
-- ranges: 10:00–10:30 and 10:15–10:30 overlap without sharing a start. Past
-- statuses (consulted, completed) can't collide with a new booking, which is
-- always in the future, so they stay out of the check.
--
-- Legacy rows: if two live bookings overlap once given their lengths (a
-- doctor changed their consult length between them), the earlier one is
-- trimmed to end where the later starts. They were both accepted that way.
with live as (
  select id, doctor_id, scheduled_start, scheduled_end,
         lead(scheduled_start) over (partition by doctor_id order by scheduled_start) as next_start
    from bookings
   where status in ('requested', 'accepted', 'paid', 'in_progress')
)
update bookings b
   set scheduled_end = live.next_start
  from live
 where b.id = live.id
   and live.next_start > live.scheduled_start
   and live.next_start < live.scheduled_end;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'ex_bookings_doctor_overlap') then
    begin
      alter table bookings add constraint ex_bookings_doctor_overlap
        exclude using gist (doctor_id with =, tstzrange(scheduled_start, scheduled_end, '[)') with &&)
        where (status in ('requested', 'accepted', 'paid', 'in_progress'));
    exception when exclusion_violation then
      raise exception 'Two live bookings for one doctor start at the same time. Find them with: '
        'select doctor_id, scheduled_start, array_agg(id) from bookings where status in '
        '(''requested'',''accepted'',''paid'',''in_progress'') group by 1, 2 having count(*) > 1; '
        'resolve each by hand, then re-run.';
    end;
  end if;
end $$;

alter table bookings drop constraint if exists bookings_scheduled_end;
alter table bookings add constraint bookings_scheduled_end
  check (scheduled_end is null or scheduled_end > scheduled_start);

-- One follow-up per consultation, at the follow-up price.
create unique index if not exists uq_bookings_one_follow_up
  on bookings (follow_up_of)
  where follow_up_of is not null
    and status in ('requested', 'accepted', 'paid', 'in_progress', 'consulted', 'completed');

-- ── 5. Saving the matrix ─────────────────────────────────────────────────────
-- The doctor's whole price list, in one transaction. A rule whose price is
-- unchanged stays as it is; a changed price closes the old rule and adds a
-- new one; a rule left out is closed. Bookings already made keep their
-- snapshot. doctor_pricing is set to the shortest first-visit price per
-- channel, for older app builds and the directory.
--
-- p_rules: [{"channel", "visit_category", "duration_min", "price_paise"}, …]
-- Returns {"outcome": "ok" | "not_found", "rules": [current rules]}.
create or replace function set_doctor_prices(
  p_doctor_id               uuid,
  p_rules                   jsonb,
  p_follow_up_validity_days int,
  p_actor_id                uuid default null
) returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_rule    jsonb;
  v_current doctor_price_rules%rowtype;
  v_keys    text[] := '{}';
  v_key     text;
  v_now     timestamptz := now();
  v_channel text;
  v_first   doctor_price_rules%rowtype;
begin
  perform 1 from doctors where id = p_doctor_id for update;
  if not found then
    return jsonb_build_object('outcome', 'not_found');
  end if;

  for v_rule in select * from jsonb_array_elements(coalesce(p_rules, '[]'::jsonb)) loop
    v_key := concat_ws('|', v_rule->>'channel', v_rule->>'visit_category', v_rule->>'duration_min');
    if v_key = any (v_keys) then
      raise exception 'set_doctor_prices: % appears twice', v_key using errcode = 'invalid_parameter_value';
    end if;
    v_keys := v_keys || v_key;

    select * into v_current from doctor_price_rules
     where doctor_id = p_doctor_id and channel = v_rule->>'channel'
       and visit_category = v_rule->>'visit_category'
       and duration_min = (v_rule->>'duration_min')::int and effective_until is null;
    if found and v_current.price_paise = (v_rule->>'price_paise')::bigint then
      continue;
    end if;
    if found then
      update doctor_price_rules set effective_until = v_now where id = v_current.id;
    end if;
    insert into doctor_price_rules (doctor_id, channel, visit_category, duration_min, price_paise,
                                    effective_from, created_by)
    values (p_doctor_id, v_rule->>'channel', v_rule->>'visit_category',
            (v_rule->>'duration_min')::int, (v_rule->>'price_paise')::bigint, v_now, p_actor_id);
  end loop;

  update doctor_price_rules set effective_until = v_now
   where doctor_id = p_doctor_id and effective_until is null
     and not (concat_ws('|', channel, visit_category, duration_min::text) = any (v_keys));

  update doctors set follow_up_validity_days = p_follow_up_validity_days where id = p_doctor_id;

  for v_channel in select unnest(array['online_consult', 'home_visit']) loop
    select * into v_first from doctor_price_rules
     where doctor_id = p_doctor_id and channel = v_channel and visit_category = 'initial'
       and effective_until is null
     order by duration_min limit 1;
    if found then
      insert into doctor_pricing (doctor_id, channel, price, base_duration_min, extra_rate_per_15min)
      values (p_doctor_id, v_channel, v_first.price_paise / 100.0, v_first.duration_min, 0)
      on conflict (doctor_id, channel) do update
        set price = excluded.price, base_duration_min = excluded.base_duration_min,
            extra_rate_per_15min = 0;
    else
      delete from doctor_pricing where doctor_id = p_doctor_id and channel = v_channel;
    end if;
  end loop;

  return jsonb_build_object('outcome', 'ok', 'rules', coalesce((
    select jsonb_agg(to_jsonb(r) order by r.channel, r.visit_category, r.duration_min)
      from doctor_price_rules r where r.doctor_id = p_doctor_id and r.effective_until is null
  ), '[]'::jsonb));
end;
$$;

-- ── 6. Who may call the functions ────────────────────────────────────────────
revoke execute on function set_doctor_prices(uuid, jsonb, int, uuid) from public, anon, authenticated;
revoke execute on function guard_price_rule()                        from public, anon, authenticated;
revoke execute on function fill_booking_schedule()                   from public, anon, authenticated;
revoke execute on function guard_booking_price()                     from public, anon, authenticated;
grant execute on function set_doctor_prices(uuid, jsonb, int, uuid)  to service_role;

-- PostgREST caches the schema; the new columns and function must be visible
-- to the API at once (Supabase also reloads on DDL by itself).
notify pgrst, 'reload schema';
