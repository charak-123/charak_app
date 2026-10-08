-- Close the anonymous read of the doctors table.
--
-- 0004 granted `doctors_public_read_verified`: anyone holding the project's
-- anon key could SELECT every column of every verified doctor. The anon key is
-- public by design (it shipped in early app builds and sits in CI secrets), so
-- that exposed, to anyone, each doctor's phone number, email, Google subject
-- id, home base coordinates, FCM push token, licence number and the storage
-- path of their verification document.
--
-- Nothing legitimate uses it. The backend reads the directory with the
-- service-role key (which bypasses RLS), and neither app nor the admin console
-- holds a Supabase client any more. 0004's other policies were written for
-- `auth.uid()`, which is always NULL here because sessions are the backend's
-- own JWTs, so they match nothing and are harmless; this one is the exception
-- because its test is a plain column comparison.
--
-- Deliberately left readable by anon: `categories` (a list of specialties,
-- and the target of the supabase-keepalive workflow).
--
-- Before applying: confirm the marketing website does not read `doctors`
-- with the anon key. If it needs a public directory, expose a view of safe
-- columns (name, category, photo_url, rating) instead of reopening this table.

drop policy if exists "doctors_public_read_verified" on doctors;
revoke select on doctors from anon;

-- Verify (as anon, expect HTTP 401/403 or an empty array):
--   curl "$SUPABASE_URL/rest/v1/doctors?select=phone&limit=1" \
--     -H "apikey: $SUPABASE_ANON_KEY" -H "Authorization: Bearer $SUPABASE_ANON_KEY"
