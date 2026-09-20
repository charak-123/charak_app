-- ═══════════════════════════════════════════════════════════════════════════
-- Home-visit addresses, backend-mediated uploads, and intake media metadata.
--
-- Closes the three V1 gaps that were unbuilt rather than merely unconfigured:
--
--   1. Home visits had no address. The doctor app already reads
--      booking.patient_address (active_visit_screen.dart, requests_tab.dart) —
--      a column that did not exist, so it always fell back to placeholder text.
--   2. doctors.base_lat/base_lng/service_radius_km were stored but never read,
--      so a patient could book a home visit from a doctor 40km away.
--   3. Uploads had no working path at all. The apps attempt client-side
--      Supabase Storage writes, but they authenticate with a custom backend JWT
--      rather than Supabase Auth, so auth.uid() is null and no Storage RLS
--      policy can ever authorise them. Uploads must go through the backend,
--      which holds the service-role key — so these columns record what the
--      backend stored, not what a client claimed.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. Patient addresses ─────────────────────────────────────────────────────
-- A patient may keep several (home, parents', office) and pick one per booking.
create table if not exists patient_addresses (
  id           uuid primary key default uuid_generate_v4(),
  patient_id   uuid not null references users(id) on delete cascade,
  label        text not null default 'Home',
  line1        text not null,
  line2        text,
  landmark     text,
  city         text not null,
  pincode      text not null check (pincode ~ '^[1-9][0-9]{5}$'),
  lat          double precision not null check (lat between -90 and 90),
  lng          double precision not null check (lng between -180 and 180),
  is_default   boolean not null default false,
  created_at   timestamptz default now(),
  updated_at   timestamptz default now()
);

create index if not exists idx_patient_addresses_patient
  on patient_addresses (patient_id);

-- At most one default per patient, enforced by the database rather than by
-- hoping every write path remembers to clear the previous one.
create unique index if not exists uq_patient_default_address
  on patient_addresses (patient_id) where is_default;

-- ── 2. Booking address ───────────────────────────────────────────────────────
-- Both a reference and a snapshot. The reference keeps the addresses list
-- navigable; the snapshot is what the doctor actually visited, and must survive
-- the patient later editing or deleting that address — a completed visit record
-- that silently changes its own address is not a record.
alter table bookings
  add column if not exists address_id         uuid references patient_addresses(id) on delete set null,
  add column if not exists patient_address    text,
  add column if not exists patient_address_lat double precision,
  add column if not exists patient_address_lng double precision,
  add column if not exists distance_km        numeric(6,2),
  -- The patient's full address is withheld from the doctor until they accept.
  -- The apps already promise this ("Address shared on accept"); this column is
  -- what makes the promise true server-side rather than in copy alone.
  add column if not exists address_released_at timestamptz;

create index if not exists idx_bookings_address on bookings (address_id);

-- ── 3. Upload metadata ───────────────────────────────────────────────────────
-- Storage paths, not URLs. A private object has no durable URL — it is read
-- through a short-lived signed URL minted per request — so the path is the
-- durable reference and the URL is derived. doctors.verification_document_url
-- is kept for the rows already written against it.
alter table doctors
  add column if not exists photo_path                text,
  add column if not exists verification_document_path text,
  add column if not exists verification_document_mime text;

alter table intake_media
  add column if not exists storage_path text,
  add column if not exists mime_type    text,
  add column if not exists size_bytes   bigint,
  -- Voice notes are transcribed so the doctor can read them. Transcription is
  -- not interpretation: the product promises intake is "reviewed by your doctor
  -- directly — never analyzed by AI", and nothing here infers or diagnoses.
  add column if not exists transcript_status text not null default 'none'
    check (transcript_status in ('none','pending','done','failed')),
  add column if not exists transcript_error text;

create index if not exists idx_intake_media_booking on intake_media (booking_id);

-- ── 4. RLS ───────────────────────────────────────────────────────────────────
-- Addresses are home addresses of patients awaiting a stranger's visit. The
-- anon key ships in both apps, so this table gets no anon access whatsoever;
-- reads go through the authenticated API, which scopes them to the caller.
alter table patient_addresses enable row level security;
revoke all on patient_addresses from anon, authenticated;
grant all on patient_addresses to service_role;
