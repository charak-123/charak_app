-- Google Sign-In.
--
-- Until DLT approval lets MSG91 deliver OTPs, both apps sign in with Google.
-- The account is keyed by Google's stable subject id (`google_sub`), not by
-- email (an address can be renamed or recycled). Phone is collected on the
-- profile step, unverified, so it can no longer be NOT NULL. It stays UNIQUE:
-- the phone-OTP login upserts on it and will come back once SMS works.

alter table users
  alter column phone drop not null,
  add column if not exists email       text,
  add column if not exists google_sub  text unique;

alter table doctors
  alter column phone drop not null,
  add column if not exists email       text,
  add column if not exists google_sub  text unique;
