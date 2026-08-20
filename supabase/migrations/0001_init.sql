-- Enable UUID extension
create extension if not exists "uuid-ossp";

-- ── categories ───────────────────────────────────────────────────────────────
create table categories (
  id         uuid primary key default uuid_generate_v4(),
  name       text not null unique,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- ── users (patients) ─────────────────────────────────────────────────────────
create table users (
  id           uuid primary key default uuid_generate_v4(),
  phone        text not null unique,
  otp_verified boolean not null default false,
  name         text,
  created_at   timestamptz default now(),
  updated_at   timestamptz default now()
);

-- ── doctors ──────────────────────────────────────────────────────────────────
create table doctors (
  id                              uuid primary key default uuid_generate_v4(),
  phone                           text not null unique,
  name                            text,
  category_id                     uuid references categories(id),
  verification_status             text not null default 'pending'
                                  check (verification_status in ('pending','verified','rejected')),
  license_number                  text,
  verification_document_url       text,
  verification_rejection_reason   text,
  offers_online_consult           boolean not null default false,
  offers_home_visit               boolean not null default false,
  online_consult_mode             text not null default 'scheduled'
                                  check (online_consult_mode in ('scheduled','available_now','both')),
  base_lat                        double precision,
  base_lng                        double precision,
  service_radius_km               int check (service_radius_km in (2,3,5)),
  rating_avg                      numeric(3,2) default 0,
  procedure_review_threshold      numeric(10,2),
  bio                             text,
  photo_url                       text,
  otp_verified                    boolean not null default false,
  created_at                      timestamptz default now(),
  updated_at                      timestamptz default now()
);

-- ── doctor_pricing ───────────────────────────────────────────────────────────
create table doctor_pricing (
  id                   uuid primary key default uuid_generate_v4(),
  doctor_id            uuid not null references doctors(id) on delete cascade,
  category_id          uuid references categories(id),
  channel              text not null check (channel in ('online_consult','home_visit')),
  price                numeric(10,2) not null,
  base_duration_min    int not null default 15,
  extra_rate_per_15min numeric(10,2) not null default 0,
  created_at           timestamptz default now(),
  updated_at           timestamptz default now(),
  unique (doctor_id, channel)
);

-- ── doctor_procedures ────────────────────────────────────────────────────────
create table doctor_procedures (
  id         uuid primary key default uuid_generate_v4(),
  doctor_id  uuid not null references doctors(id) on delete cascade,
  name       text not null,
  price      numeric(10,2) not null,
  active     boolean not null default true,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- ── doctor_schedules (recurring weekly template) ─────────────────────────────
create table doctor_schedules (
  id          uuid primary key default uuid_generate_v4(),
  doctor_id   uuid not null references doctors(id) on delete cascade,
  day_of_week int not null check (day_of_week between 0 and 6),
  start_time  time not null,
  end_time    time not null,
  created_at  timestamptz default now(),
  updated_at  timestamptz default now()
);

-- ── doctor_slot_blocks (one-off blocked time) ────────────────────────────────
create table doctor_slot_blocks (
  id         uuid primary key default uuid_generate_v4(),
  doctor_id  uuid not null references doctors(id) on delete cascade,
  date       date not null,
  start_time time not null,
  end_time   time not null,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- ── bookings ─────────────────────────────────────────────────────────────────
create table bookings (
  id               uuid primary key default uuid_generate_v4(),
  patient_id       uuid not null references users(id),
  doctor_id        uuid not null references doctors(id),
  category_id      uuid references categories(id),
  channel          text not null check (channel in ('online_consult','home_visit')),
  scheduled_start  timestamptz not null,
  status           text not null default 'requested'
                   check (status in ('requested','accepted','declined','paid','completed','cancelled')),
  decision_at      timestamptz,
  price_confirmed  numeric(10,2),
  created_at       timestamptz default now(),
  updated_at       timestamptz default now()
);

-- ── procedure_bills ──────────────────────────────────────────────────────────
create table procedure_bills (
  id          uuid primary key default uuid_generate_v4(),
  booking_id  uuid not null unique references bookings(id),
  status      text not null default 'pending'
              check (status in ('pending','under_review','approved','paid')),
  total       numeric(10,2) not null,
  reviewed_by uuid references doctors(id),
  reviewed_at timestamptz,
  created_at  timestamptz default now(),
  updated_at  timestamptz default now()
);

-- ── intake_media ─────────────────────────────────────────────────────────────
create table intake_media (
  id              uuid primary key default uuid_generate_v4(),
  booking_id      uuid not null references bookings(id) on delete cascade,
  media_type      text not null check (media_type in ('voice','text','video','image')),
  file_url        text,
  transcript_text text,
  created_at      timestamptz default now()
);

-- ── clarification_calls ──────────────────────────────────────────────────────
create table clarification_calls (
  id          uuid primary key default uuid_generate_v4(),
  booking_id  uuid not null references bookings(id),
  call_status text not null default 'initiated'
              check (call_status in ('initiated','completed','missed')),
  notes       text,
  started_at  timestamptz,
  ended_at    timestamptz,
  created_at  timestamptz default now(),
  updated_at  timestamptz default now()
);

-- ── payments ─────────────────────────────────────────────────────────────────
create table payments (
  id                  uuid primary key default uuid_generate_v4(),
  booking_id          uuid not null references bookings(id),
  amount              numeric(10,2) not null,
  status              text not null default 'initiated'
                      check (status in ('initiated','completed','failed','refunded')),
  method              text,
  type                text not null check (type in ('consult_fee','procedure_bill')),
  paid_at             timestamptz,
  razorpay_order_id   text unique,
  razorpay_payment_id text,
  created_at          timestamptz default now(),
  updated_at          timestamptz default now()
);

-- ── ratings ──────────────────────────────────────────────────────────────────
create table ratings (
  id         uuid primary key default uuid_generate_v4(),
  booking_id uuid not null unique references bookings(id),
  stars      int not null check (stars between 1 and 5),
  comment    text,
  created_at timestamptz default now()
);

-- ── complaints ───────────────────────────────────────────────────────────────
create table complaints (
  id          uuid primary key default uuid_generate_v4(),
  booking_id  uuid not null references bookings(id),
  description text not null,
  status      text not null default 'open'
              check (status in ('open','in_review','resolved','closed')),
  created_at  timestamptz default now(),
  updated_at  timestamptz default now()
);

-- ── audit_log (DPDP accountability) ──────────────────────────────────────────
create table audit_log (
  id         uuid primary key default uuid_generate_v4(),
  actor_id   uuid,
  actor_role text,
  entity     text not null,
  entity_id  uuid,
  action     text not null,
  at         timestamptz default now(),
  ip         text
);

-- ── consents (immutable append-only) ─────────────────────────────────────────
create table consents (
  id          uuid primary key default uuid_generate_v4(),
  user_id     uuid not null,
  type        text not null check (type in ('tos','privacy','telemedicine','marketing')),
  version     text not null,
  accepted_at timestamptz default now(),
  ip          text
);

-- ── dsr_requests (Data Subject Rights — DPDP §11-14) ─────────────────────────
create table dsr_requests (
  id           uuid primary key default uuid_generate_v4(),
  user_id      uuid not null references users(id),
  type         text not null check (type in ('access','erasure','correction')),
  status       text not null default 'pending'
               check (status in ('pending','in_progress','fulfilled','rejected')),
  requested_at timestamptz default now(),
  fulfilled_at timestamptz
);
