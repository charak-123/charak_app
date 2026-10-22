-- Take every table away from Supabase's client roles (anon, authenticated).
--
-- Nothing legitimate talks to PostgREST with those roles any more: the apps and
-- the admin dashboard authenticate with the backend's own JWT and reach data
-- only through the API, which uses the service-role key. What was left behind
-- was a door, not a feature:
--
--   * Supabase Auth email sign-up was on, so anyone holding the anon key could
--     mint an `authenticated` session with a fresh auth.uid().
--   * 0004's `for all using (id = auth.uid())` policies on users and doctors
--     then let that session INSERT a row whose id is its own uid — with
--     verification_status = 'verified' and its own google_sub / firebase_uid /
--     phone. Signing in through the API afterwards matched that row and handed
--     out a token for a verified doctor that ops never approved. The same trick
--     on users pre-claimed a victim's phone number, and the select policies on
--     bookings / intake_media then exposed whatever the victim did next.
--
-- Sign-ups are also switched off in the dashboard (Authentication → Sign In /
-- Providers). This migration is the half that does not depend on that toggle.
--
-- After this, the only thing the anon key can read is `categories` (the
-- supabase-keepalive workflow's target). Idempotent; safe to re-run.

-- ── 1. Drop the auth.uid() policies from 0004 ────────────────────────────────
-- auth.uid() is always NULL for the backend's own JWTs, so these never served a
-- real request — they only ever matched a Supabase Auth session.
drop policy if exists "users_own_row"          on users;
drop policy if exists "doctors_own_read"       on doctors;
drop policy if exists "doctors_own_write"      on doctors;
drop policy if exists "bookings_patient_own"   on bookings;
drop policy if exists "bookings_doctor_own"    on bookings;
drop policy if exists "intake_patient_own"     on intake_media;
drop policy if exists "intake_doctor_own"      on intake_media;
drop policy if exists "payments_patient_own"   on payments;
drop policy if exists "payments_doctor_own"    on payments;
drop policy if exists "bills_patient_own"      on procedure_bills;
drop policy if exists "bills_doctor_own"       on procedure_bills;
drop policy if exists "ratings_patient_own"    on ratings;
drop policy if exists "ratings_doctor_read_own" on ratings;
drop policy if exists "complaints_patient_own" on complaints;
drop policy if exists "calls_patient_own"      on clarification_calls;
drop policy if exists "calls_doctor_own"       on clarification_calls;
drop policy if exists "consents_user_own"      on consents;
drop policy if exists "dsr_user_own"           on dsr_requests;

-- The doctor-side public reads: schedules, slot blocks, pricing and procedures
-- of every doctor (verified or not) were readable with the anon key. The API
-- serves all of these, filtered to verified doctors.
drop policy if exists "public_read_pricing"     on doctor_pricing;
drop policy if exists "public_read_procedures"  on doctor_procedures;
drop policy if exists "public_read_schedules"   on doctor_schedules;
drop policy if exists "public_read_slot_blocks" on doctor_slot_blocks;

-- ── 2. Revoke table privileges from the client roles ─────────────────────────
-- RLS stays enabled on every table as a second layer; with no grants and no
-- policies, a client role cannot read or write anything.
revoke all on all tables    in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;

-- Tables created from now on must not be born readable either. Supabase's
-- default privileges grant every new table to anon and authenticated; this
-- removes that for objects created by `postgres` (the SQL Editor's role).
alter default privileges for role postgres in schema public
  revoke all on tables    from anon, authenticated;
alter default privileges for role postgres in schema public
  revoke all on sequences from anon, authenticated;

-- ── 3. The one deliberate exception ──────────────────────────────────────────
-- A list of specialty names, read by .github/workflows/supabase-keepalive.yml.
grant select on categories to anon;

-- The backend keeps full access (service_role bypasses RLS).
grant all on all tables    in schema public to service_role;
grant all on all sequences in schema public to service_role;

-- ── Verify ───────────────────────────────────────────────────────────────────
-- Expect only `categories | anon | SELECT`:
--   select table_name, grantee, privilege_type
--   from information_schema.role_table_grants
--   where table_schema = 'public' and grantee in ('anon', 'authenticated')
--   order by 1, 2, 3;
--
-- Expect only `public_read_categories` and `audit_log_deny_all`:
--   select tablename, policyname from pg_policies where schemaname = 'public';
--
-- Any doctor marked verified without an ops approval on record. Approvals made
-- before audit logging existed show up here too; check each one by hand:
--   select d.id, d.name, d.created_at
--   from doctors d
--   where d.verification_status = 'verified'
--     and not exists (
--       select 1 from audit_log a
--       where a.entity = 'doctors' and a.entity_id = d.id
--         and a.action = 'verification_approve');
