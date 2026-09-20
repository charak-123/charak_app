-- ═══════════════════════════════════════════════════════════════════════════
-- RLS for the tables added in 0007.
--
-- The backend holds the service-role key and bypasses RLS entirely, so these
-- policies exist to close the *other* door: the anon key ships inside both
-- mobile apps, and every table reachable with it is effectively public unless a
-- policy says otherwise.
--
-- The stance here is deliberately strict — no policy at all means no anon access.
-- These five tables hold OTP hashes, device-addressed notifications, bank
-- account numbers and earnings, none of which any client should read directly.
-- Every legitimate read goes through an authenticated API endpoint.
-- ═══════════════════════════════════════════════════════════════════════════

alter table otp_codes             enable row level security;
alter table notifications         enable row level security;
alter table doctor_bank_accounts  enable row level security;
alter table payouts               enable row level security;
alter table doctor_ledger_entries enable row level security;

-- ── otp_codes ────────────────────────────────────────────────────────────────
-- No policies whatsoever. A client that could read this table could read the
-- hash for any phone number and attempt offline recovery of a 6-digit code;
-- a client that could write it could mint its own login.
revoke all on otp_codes from anon, authenticated;

-- ── notifications ────────────────────────────────────────────────────────────
-- Served by GET /notifications, which scopes rows to the caller's token. Direct
-- anon access would expose one patient's medical notifications to another.
revoke all on notifications from anon, authenticated;

-- ── doctor_bank_accounts ─────────────────────────────────────────────────────
-- Account numbers. The API masks these to the last four digits even for their
-- owner; the raw column must never leave the backend.
revoke all on doctor_bank_accounts from anon, authenticated;

-- ── payouts and the ledger ───────────────────────────────────────────────────
-- Commission rates and per-doctor earnings are commercially sensitive, and a
-- writable ledger is a writable bank instruction. Read via /payouts/me/*.
revoke all on payouts from anon, authenticated;
revoke all on doctor_ledger_entries from anon, authenticated;

-- ── Service role keeps full access ───────────────────────────────────────────
-- Explicit rather than implied, so a future `revoke all on all tables` cannot
-- silently lock the backend out of its own schema.
grant all on otp_codes             to service_role;
grant all on notifications         to service_role;
grant all on doctor_bank_accounts  to service_role;
grant all on payouts               to service_role;
grant all on doctor_ledger_entries to service_role;
