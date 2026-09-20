-- ═══════════════════════════════════════════════════════════════════════════
-- Phase 4 backend completion
--
-- Adds everything the code needs that credentials alone cannot provide:
--   1. Durable OTP storage (replaces the in-process dict in auth.py)
--   2. Notifications ledger (every push is recorded, deliverable in-app too)
--   3. Doctor payouts: commission model, ledger, bank accounts, payout runs
--   4. Booking edge cases: payment holds, retries, no-show
--   5. Directory management: doctor suspension
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. OTP codes ─────────────────────────────────────────────────────────────
-- Survives restarts and works across multiple workers/machines, which the
-- previous in-memory store could not. Codes are stored as a salted SHA-256
-- hash so a database leak does not expose live OTPs.
create table if not exists otp_codes (
  id           uuid primary key default uuid_generate_v4(),
  phone        text not null,
  role         text not null check (role in ('patient','doctor')),
  code_hash    text not null,
  expires_at   timestamptz not null,
  attempts     int not null default 0,
  consumed_at  timestamptz,
  created_at   timestamptz default now()
);

create index if not exists idx_otp_codes_phone_created
  on otp_codes (phone, created_at desc);
create index if not exists idx_otp_codes_expires
  on otp_codes (expires_at);

-- ── 2. Notifications ─────────────────────────────────────────────────────────
-- Written on every notifiable event whether or not FCM is configured, so the
-- apps can render a notification list and delivery is auditable.
create table if not exists notifications (
  id            uuid primary key default uuid_generate_v4(),
  recipient_id  uuid not null,
  recipient_role text not null check (recipient_role in ('patient','doctor','ops')),
  event         text not null,
  title         text not null,
  body          text not null,
  data          jsonb not null default '{}'::jsonb,
  booking_id    uuid references bookings(id) on delete set null,
  delivery      text not null default 'pending'
                check (delivery in ('pending','sent','skipped','failed')),
  delivery_error text,
  read_at       timestamptz,
  created_at    timestamptz default now()
);

create index if not exists idx_notifications_recipient
  on notifications (recipient_id, created_at desc);
create index if not exists idx_notifications_unread
  on notifications (recipient_id) where read_at is null;

-- ── 3. Payouts ───────────────────────────────────────────────────────────────

-- Per-doctor commission override; null means use the platform default.
alter table doctors
  add column if not exists commission_pct numeric(5,2)
    check (commission_pct >= 0 and commission_pct <= 100);

create table if not exists doctor_bank_accounts (
  id             uuid primary key default uuid_generate_v4(),
  doctor_id      uuid not null unique references doctors(id) on delete cascade,
  account_holder text not null,
  account_number text not null,
  ifsc           text not null,
  bank_name      text,
  upi_id         text,
  verified       boolean not null default false,
  created_at     timestamptz default now(),
  updated_at     timestamptz default now()
);

create table if not exists payouts (
  id           uuid primary key default uuid_generate_v4(),
  doctor_id    uuid not null references doctors(id),
  period_start timestamptz not null,
  period_end   timestamptz not null,
  gross_amount      numeric(10,2) not null default 0,
  commission_amount numeric(10,2) not null default 0,
  net_amount        numeric(10,2) not null default 0,
  status       text not null default 'pending'
               check (status in ('pending','processing','paid','failed')),
  reference    text,              -- bank UTR / Razorpay payout id
  failure_reason text,
  initiated_at timestamptz,
  paid_at      timestamptz,
  created_at   timestamptz default now(),
  updated_at   timestamptz default now()
);

create index if not exists idx_payouts_doctor_status
  on payouts (doctor_id, status);

-- One ledger entry per confirmed money event. `payable` entries are what a
-- payout run sweeps up; once swept they become `paid` and carry a payout_id.
create table if not exists doctor_ledger_entries (
  id            uuid primary key default uuid_generate_v4(),
  doctor_id     uuid not null references doctors(id),
  booking_id    uuid references bookings(id) on delete set null,
  source        text not null check (source in ('consult_fee','procedure_bill','adjustment')),
  gross_amount      numeric(10,2) not null,
  commission_pct    numeric(5,2) not null,
  commission_amount numeric(10,2) not null,
  net_amount        numeric(10,2) not null,
  status        text not null default 'payable'
                check (status in ('payable','paid','reversed')),
  payout_id     uuid references payouts(id) on delete set null,
  note          text,
  created_at    timestamptz default now(),
  updated_at    timestamptz default now()
);

-- A booking yields at most one entry per source — makes crediting idempotent
-- even if a webhook is delivered twice.
create unique index if not exists uq_ledger_booking_source
  on doctor_ledger_entries (booking_id, source)
  where booking_id is not null;

create index if not exists idx_ledger_doctor_status
  on doctor_ledger_entries (doctor_id, status);
create index if not exists idx_ledger_payout
  on doctor_ledger_entries (payout_id);

-- ── 4. Booking edge cases ────────────────────────────────────────────────────

-- 'no_show' is a new terminal status, so the CHECK constraint is rebuilt.
alter table bookings drop constraint if exists bookings_status_check;
alter table bookings add constraint bookings_status_check
  check (status in ('requested','accepted','declined','paid','completed','cancelled','no_show'));

alter table bookings
  add column if not exists hold_expires_at   timestamptz,
  add column if not exists payment_failed_at timestamptz,
  add column if not exists payment_attempts  int not null default 0,
  add column if not exists no_show_marked_by uuid,
  add column if not exists no_show_at        timestamptz,
  add column if not exists cancelled_by      text
    check (cancelled_by in ('patient','doctor','ops','system'));

create index if not exists idx_bookings_hold_expiry
  on bookings (hold_expires_at) where hold_expires_at is not null;

-- ── 5. Directory management ──────────────────────────────────────────────────
alter table doctors
  add column if not exists suspended        boolean not null default false,
  add column if not exists suspended_reason text,
  add column if not exists suspended_at     timestamptz;

create index if not exists idx_doctors_listable
  on doctors (verification_status, suspended);
