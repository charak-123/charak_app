-- ═══════════════════════════════════════════════════════════════════════════
-- Admin accounts + TOTP, session revocation, and a generic rate-limit store.
--
-- Replaces the single shared ADMIN_PASSWORD with per-admin accounts (so the
-- audit log can say who did what) and mandatory TOTP. Adds the ability to
-- force-expire a user's or doctor's existing sessions (a lost-phone response
-- that a 14/30-day token alone cannot give you), and a table backing a
-- sliding-window rate limiter usable on any endpoint, not just /auth.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── Admin accounts ───────────────────────────────────────────────────────────
-- password_hash is bcrypt. totp_secret is only ever read/written by the
-- backend (service-role key) — never exposed in an API response once set.
create table if not exists admin_users (
  id            uuid primary key default uuid_generate_v4(),
  email         text not null unique,
  password_hash text not null,
  totp_secret   text,
  totp_enabled  boolean not null default false,
  created_at    timestamptz not null default now(),
  last_login_at timestamptz
);

alter table admin_users enable row level security;
-- No policies at all: a client that could read this table could read every
-- admin's password hash and TOTP secret. Every legitimate read goes through
-- the backend's own /admin/login, which holds the service-role key.
revoke all on admin_users from anon, authenticated;

-- ── Session revocation ───────────────────────────────────────────────────────
-- A JWT issued before this timestamp is rejected even though it has not
-- expired yet. Lets ops respond to "my phone was stolen" immediately instead
-- of waiting out the token's natural lifetime.
alter table users   add column if not exists sessions_revoked_at timestamptz;
alter table doctors add column if not exists sessions_revoked_at timestamptz;

-- ── Generic rate limiting ────────────────────────────────────────────────────
-- One row per attempt. `scope` namespaces the limiter (e.g. 'admin-login',
-- 'booking-create') so the same identifier (an email, an IP, a user id) can be
-- limited independently per endpoint. Old rows are cheap to prune (see
-- maintenance.py) since nothing but a recent window is ever queried.
create table if not exists rate_limit_hits (
  id          bigint generated always as identity primary key,
  scope       text not null,
  identifier  text not null,
  created_at  timestamptz not null default now()
);

create index if not exists idx_rate_limit_hits_lookup
  on rate_limit_hits (scope, identifier, created_at desc);

alter table rate_limit_hits enable row level security;
revoke all on rate_limit_hits from anon, authenticated;
