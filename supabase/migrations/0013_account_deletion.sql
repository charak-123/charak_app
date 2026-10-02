-- Account deletion (DPDP erasure) support.
--
-- Patients self-delete: the account is soft-deleted (deleted_at set, login
-- blocked) and a cron purges the personal data after a grace period. Financial
-- and de-identified clinical records are retained — only PII is erased.
--
-- Doctors cannot self-purge (outstanding payouts, active bookings, bank
-- details): they file a request that ops fulfils, so this stores the request
-- state on the doctor row.

alter table users
  add column if not exists deleted_at             timestamptz,
  add column if not exists deletion_requested_at  timestamptz;

alter table doctors
  add column if not exists deletion_requested_at  timestamptz,
  add column if not exists deletion_status        text
    check (deletion_status in ('requested', 'in_progress', 'fulfilled', 'rejected'));

-- A clinician may mark a specific intake item as needed for re-examination.
-- On erasure the raw media file is kept only for held items; everything else
-- loses its file and keeps just the transcript/summary as the clinical record.
alter table intake_media
  add column if not exists clinical_hold boolean not null default false;

-- Partial index for the purge sweep, which only ever scans soft-deleted rows.
create index if not exists idx_users_deleted_at
  on users (deleted_at) where deleted_at is not null;
