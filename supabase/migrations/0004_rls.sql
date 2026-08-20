-- ── Enable RLS on all tables ──────────────────────────────────────────────────

alter table users              enable row level security;
alter table doctors            enable row level security;
alter table bookings           enable row level security;
alter table intake_media       enable row level security;
alter table payments           enable row level security;
alter table procedure_bills    enable row level security;
alter table ratings            enable row level security;
alter table complaints         enable row level security;
alter table clarification_calls enable row level security;
alter table consents           enable row level security;
alter table dsr_requests       enable row level security;
alter table audit_log          enable row level security;
alter table categories         enable row level security;
alter table doctor_pricing     enable row level security;
alter table doctor_procedures  enable row level security;
alter table doctor_schedules   enable row level security;
alter table doctor_slot_blocks enable row level security;
alter table doctor_procedures  enable row level security;

-- ── Public read tables ────────────────────────────────────────────────────────

create policy "public_read_categories"       on categories       for select using (true);
create policy "public_read_pricing"          on doctor_pricing    for select using (true);
create policy "public_read_procedures"       on doctor_procedures for select using (true);
create policy "public_read_schedules"        on doctor_schedules  for select using (true);
create policy "public_read_slot_blocks"      on doctor_slot_blocks for select using (true);

-- ── Users: own row only ───────────────────────────────────────────────────────

create policy "users_own_row"
  on users
  using (id = auth.uid());

-- ── Doctors: public read of verified; own write ───────────────────────────────

create policy "doctors_public_read_verified"
  on doctors for select
  using (verification_status = 'verified');

create policy "doctors_own_read"
  on doctors for select
  using (id = auth.uid());

create policy "doctors_own_write"
  on doctors for all
  using (id = auth.uid());

-- ── Bookings: patient reads own; doctor reads theirs ─────────────────────────

create policy "bookings_patient_own"
  on bookings for select
  using (patient_id = auth.uid());

create policy "bookings_doctor_own"
  on bookings for select
  using (doctor_id = auth.uid());

-- ── Intake media: via booking ownership ──────────────────────────────────────

create policy "intake_patient_own"
  on intake_media for select
  using (
    booking_id in (select id from bookings where patient_id = auth.uid())
  );

create policy "intake_doctor_own"
  on intake_media for select
  using (
    booking_id in (select id from bookings where doctor_id = auth.uid())
  );

-- ── Payments ──────────────────────────────────────────────────────────────────

create policy "payments_patient_own"
  on payments for select
  using (
    booking_id in (select id from bookings where patient_id = auth.uid())
  );

create policy "payments_doctor_own"
  on payments for select
  using (
    booking_id in (select id from bookings where doctor_id = auth.uid())
  );

-- ── Procedure bills ───────────────────────────────────────────────────────────

create policy "bills_patient_own"
  on procedure_bills for select
  using (
    booking_id in (select id from bookings where patient_id = auth.uid())
  );

create policy "bills_doctor_own"
  on procedure_bills for select
  using (
    booking_id in (select id from bookings where doctor_id = auth.uid())
  );

-- ── Ratings: patient all; doctor read own ─────────────────────────────────────

create policy "ratings_patient_own"
  on ratings for all
  using (
    booking_id in (select id from bookings where patient_id = auth.uid())
  );

create policy "ratings_doctor_read_own"
  on ratings for select
  using (
    booking_id in (select id from bookings where doctor_id = auth.uid())
  );

-- ── Complaints: patient own ───────────────────────────────────────────────────

create policy "complaints_patient_own"
  on complaints for all
  using (
    booking_id in (select id from bookings where patient_id = auth.uid())
  );

-- ── Clarification calls ───────────────────────────────────────────────────────

create policy "calls_patient_own"
  on clarification_calls for select
  using (
    booking_id in (select id from bookings where patient_id = auth.uid())
  );

create policy "calls_doctor_own"
  on clarification_calls for all
  using (
    booking_id in (select id from bookings where doctor_id = auth.uid())
  );

-- ── Consents: user reads own (backend inserts via service role) ───────────────

create policy "consents_user_own"
  on consents for select
  using (user_id = auth.uid());

-- ── DSR requests: user reads own ─────────────────────────────────────────────

create policy "dsr_user_own"
  on dsr_requests for select
  using (user_id = auth.uid());

-- ── Audit log: no direct user access (service role only) ─────────────────────

create policy "audit_log_deny_all"
  on audit_log
  using (false);
