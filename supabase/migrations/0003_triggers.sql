-- ── updated_at auto-maintenance ──────────────────────────────────────────────

create or replace function set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

do $$
declare
  tbl text;
begin
  foreach tbl in array array[
    'users', 'doctors', 'doctor_pricing', 'doctor_procedures',
    'doctor_schedules', 'doctor_slot_blocks', 'bookings', 'procedure_bills',
    'clarification_calls', 'payments', 'complaints', 'dsr_requests'
  ]
  loop
    execute format(
      'create trigger trg_%s_updated_at
       before update on %s
       for each row execute function set_updated_at()',
      tbl, tbl
    );
  end loop;
end;
$$;


-- ── Rating average maintenance ────────────────────────────────────────────────

create or replace function update_doctor_rating_avg()
returns trigger language plpgsql as $$
declare
  v_doctor_id uuid;
begin
  select doctor_id into v_doctor_id from bookings where id = NEW.booking_id;

  update doctors
  set rating_avg = (
    select coalesce(avg(r.stars::numeric), 0)
    from ratings r
    join bookings b on r.booking_id = b.id
    where b.doctor_id = v_doctor_id
  )
  where id = v_doctor_id;

  return NEW;
end;
$$;

create trigger trg_rating_avg
after insert on ratings
for each row execute function update_doctor_rating_avg();


-- ── Procedure bill auto-threshold check (called from backend; guard here) ────
-- Backend creates procedure_bills with correct status derived from threshold.
-- This trigger logs the creation to audit_log for accountability.

create or replace function log_procedure_bill_create()
returns trigger language plpgsql as $$
begin
  insert into audit_log (entity, entity_id, action, actor_role)
  values ('procedure_bills', NEW.id, 'created', 'backend');
  return NEW;
end;
$$;

create trigger trg_procedure_bill_audit
after insert on procedure_bills
for each row execute function log_procedure_bill_create();
