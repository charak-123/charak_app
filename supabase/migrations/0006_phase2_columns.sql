-- FCM push token fields on both user tables
alter table users
  add column if not exists fcm_token    text,
  add column if not exists fcm_platform text check (fcm_platform in ('android', 'ios'));

alter table doctors
  add column if not exists fcm_token    text,
  add column if not exists fcm_platform text check (fcm_platform in ('android', 'ios'));

-- Procedure bill line items stored as JSONB
alter table procedure_bills
  add column if not exists items jsonb;

-- Index for fast doctor earnings queries
create index if not exists idx_bookings_doctor_status
  on bookings (doctor_id, status);

create index if not exists idx_procedure_bills_booking
  on procedure_bills (booking_id);
