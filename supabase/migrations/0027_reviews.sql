-- ═══════════════════════════════════════════════════════════════════════════
-- 0027: reviews (spec §12, decisions D15 and D16, recommended defaults).
--
--   reviews          one per completed booking, by its patient, within 14 days
--                    of completion: an overall 1–5 rating, three optional
--                    sub-ratings (courtesy, explanation, punctuality) and an
--                    optional comment. Editable for 48 hours. Never deleted;
--                    ops can hide one for a stated reason, and restore it.
--   review_reports   a doctor (or ops) flags a review as abusive, irrelevant
--                    or revealing private details. Reporting doesn't hide it:
--                    a negative review is not removed for being negative.
--   doctors          rating_avg: the mean overall rating of the last 200
--                    published reviews; rating_count: all published reviews;
--                    one average per sub-rating. Apps show "New" below 5.
--
-- The old one-star `ratings` table is frozen: its rows are copied here, and
-- the endpoint older apps call now writes reviews.
--
-- Idempotent: safe to re-run in the SQL Editor.
-- ═══════════════════════════════════════════════════════════════════════════

create table if not exists reviews (
  id               uuid primary key default uuid_generate_v4(),
  booking_id       uuid not null unique references bookings(id) on delete cascade,
  doctor_id        uuid not null references doctors(id),
  patient_id       uuid not null references users(id),
  overall          int  not null check (overall between 1 and 5),
  -- Optional. Never about clinical correctness (spec §12.2).
  professionalism  int  check (professionalism between 1 and 5),   -- courtesy and respect
  communication    int  check (communication between 1 and 5),     -- listened and explained
  punctuality      int  check (punctuality between 1 and 5),       -- on time
  comment          text check (length(comment) <= 1000),
  status           text not null default 'published' check (status in ('published', 'hidden')),
  hidden_reason    text,
  hidden_at        timestamptz,
  hidden_by        uuid,
  editable_until   timestamptz not null,
  edited_at        timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index if not exists idx_reviews_doctor on reviews (doctor_id, created_at desc) where status = 'published';
create index if not exists idx_reviews_patient on reviews (patient_id);

drop trigger if exists trg_reviews_updated_at on reviews;
create trigger trg_reviews_updated_at before update on reviews
  for each row execute function set_updated_at();

-- Who wrote it and about which visit never changes. What they wrote changes
-- only inside the edit window. Nobody deletes one: ops hides it, with a reason.
create or replace function guard_review()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    if pg_trigger_depth() <= 1
       and coalesce(current_setting('charak.retention_purge', true), '') <> 'on' then
      raise exception 'reviews are not deleted; hide one with a reason instead'
        using errcode = 'insufficient_privilege';
    end if;
    return old;
  end if;
  if (new.booking_id, new.doctor_id, new.patient_id, new.created_at, new.editable_until)
     is distinct from (old.booking_id, old.doctor_id, old.patient_id, old.created_at, old.editable_until) then
    raise exception 'a review''s author and visit are fixed' using errcode = 'insufficient_privilege';
  end if;
  if (new.overall, new.professionalism, new.communication, new.punctuality, new.comment)
     is distinct from (old.overall, old.professionalism, old.communication, old.punctuality, old.comment)
     and now() > old.editable_until then
    raise exception 'this review can no longer be edited' using errcode = 'insufficient_privilege';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_reviews_guard on reviews;
create trigger trg_reviews_guard before update or delete on reviews
  for each row execute function guard_review();

create table if not exists review_reports (
  id           uuid primary key default uuid_generate_v4(),
  review_id    uuid not null references reviews(id) on delete cascade,
  reporter_role text not null check (reporter_role in ('doctor', 'patient', 'ops')),
  reporter_id  uuid not null,
  reason       text not null check (reason in ('abusive', 'irrelevant', 'privacy', 'other')),
  note         text check (length(note) <= 500),
  status       text not null default 'open' check (status in ('open', 'upheld', 'dismissed')),
  resolved_at  timestamptz,
  resolved_by  uuid,
  created_at   timestamptz not null default now(),
  unique (review_id, reporter_id)
);
create index if not exists idx_review_reports_open on review_reports (created_at) where status = 'open';

alter table reviews enable row level security;
alter table review_reports enable row level security;
revoke all on reviews, review_reports from anon, authenticated;
grant all on reviews, review_reports to service_role;

-- ── The doctor's aggregate ───────────────────────────────────────────────────
alter table doctors
  add column if not exists rating_count           int not null default 0,
  add column if not exists rating_professionalism numeric(3,2),
  add column if not exists rating_communication   numeric(3,2),
  add column if not exists rating_punctuality     numeric(3,2);

-- D15 (recommended): the mean of the last 200 published reviews, so old
-- reviews age out; every published review counts towards the total shown.
-- Sub-rating averages skip reviews that left them blank.
create or replace function refresh_doctor_rating(p_doctor_id uuid)
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  with recent as (
    select overall, professionalism, communication, punctuality
      from reviews
     where doctor_id = p_doctor_id and status = 'published'
     order by created_at desc
     limit 200
  )
  update doctors d set
    rating_avg             = coalesce((select round(avg(overall)::numeric, 2) from recent), 0),
    rating_professionalism = (select round(avg(professionalism)::numeric, 2) from recent),
    rating_communication   = (select round(avg(communication)::numeric, 2) from recent),
    rating_punctuality     = (select round(avg(punctuality)::numeric, 2) from recent),
    rating_count           = (select count(*) from reviews r
                               where r.doctor_id = p_doctor_id and r.status = 'published')
  where d.id = p_doctor_id;
end;
$$;

create or replace function reviews_refresh_rating()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  perform refresh_doctor_rating(coalesce(new.doctor_id, old.doctor_id));
  return null;
end;
$$;

drop trigger if exists trg_reviews_refresh_rating on reviews;
create trigger trg_reviews_refresh_rating after insert or update or delete on reviews
  for each row execute function reviews_refresh_rating();

-- ── The old ratings ──────────────────────────────────────────────────────────
-- Copied as reviews (already past their edit window). The old trigger, which
-- averaged every rating ever and ran only on insert, goes.
drop trigger if exists trg_rating_avg on ratings;

insert into reviews (booking_id, doctor_id, patient_id, overall, comment, editable_until, created_at)
select r.booking_id, b.doctor_id, b.patient_id, r.stars, nullif(left(trim(r.comment), 1000), ''),
       coalesce(r.created_at, now()), coalesce(r.created_at, now())
  from ratings r
  join bookings b on b.id = r.booking_id
on conflict (booking_id) do nothing;

do $$
declare v uuid;
begin
  for v in select id from doctors loop
    perform refresh_doctor_rating(v);
  end loop;
end $$;

revoke execute on function refresh_doctor_rating(uuid) from public, anon, authenticated;
revoke execute on function guard_review()              from public, anon, authenticated;
revoke execute on function reviews_refresh_rating()    from public, anon, authenticated;
grant execute on function refresh_doctor_rating(uuid)  to service_role;

notify pgrst, 'reload schema';
