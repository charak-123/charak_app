-- Firebase ID token sign-in (POST /auth/firebase).
--
-- A second, separate identity key from google_sub above: that one is the raw
-- Google OAuth subject id from the apps' own google_sign_in package.
-- firebase_uid is a Firebase Auth user id — the website's Google sign-in
-- already goes through Firebase (a different token, a different `sub`), and
-- phone sign-in (website today, both apps later) will too. Keeping them as
-- separate columns means neither sign-in path can collide with or spoof the
-- other's accounts.
--
-- application_details holds the website registration's richer fields that
-- have no dedicated column (qualification, college, passing year, council,
-- registration year, NUID, HPR ID, practitioner type, certifying body) —
-- additive rather than widening the doctors table by nine narrow columns
-- most of which apply to only one practitioner type. The fields that do have
-- a real column already (name, phone, email, license_number,
-- offers_online_consult, offers_home_visit) are written there directly, not
-- duplicated into this blob.

alter table users
  add column if not exists firebase_uid text unique;

alter table doctors
  add column if not exists firebase_uid        text unique,
  add column if not exists application_details jsonb;
