-- 0035: online and home-visit hours are kept apart.
--
-- doctor_schedules had no channel. The doctor app saves online hours with
-- PUT /schedules/me and home-visit hours with PUT /schedules/me/home-visit,
-- and both replaced every row: saving home-visit hours wiped the online ones,
-- and every slot was offered for both channels whichever list it came from.
--
-- channel says which list a row belongs to. Rows written before this have
-- none and keep applying to both channels, as they always have; the first
-- time a doctor saves one channel's hours, the backend hands those rows to
-- the other channel (routers/schedules.py), so nothing they had disappears.
--
-- Apply before deploying the backend that writes the column.
-- Idempotent: safe to re-run in the SQL Editor.

alter table doctor_schedules
  add column if not exists channel text;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'doctor_schedules_channel_check'
  ) then
    alter table doctor_schedules
      add constraint doctor_schedules_channel_check
      check (channel is null or channel in ('online_consult', 'home_visit'));
  end if;
end $$;

create index if not exists idx_schedules_doctor_channel
  on doctor_schedules (doctor_id, channel);

comment on column doctor_schedules.channel is
  'online_consult or home_visit; null = a row from before 0035, serving both';
