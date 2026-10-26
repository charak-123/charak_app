# Backend go-live runbook

The backend is feature-complete against the V1 scope. Every external service is
behind an environment variable and a code path that is already written and
tested — switching one on is a config change, not a code change.

This document is the checklist for that switch-on, plus what to verify after each
step.

Production runs on **Cloud Run** (service `charak-api`, region `asia-south1`,
deployed with `gcloud run deploy charak-api --source backend`). Commands below use

```bash
export API_URL=$(gcloud run services describe charak-api --region asia-south1 --format 'value(status.url)')
```

---

## 0. Apply the migrations (required first — nothing else works without this)

> **Latest: `0026_pricing_matrix.sql`.** Apply before deploying the backend that
> uses it. It adds `doctor_price_rules` (each price by channel, first visit or
> follow-up, and length; never edited, so it is the price history), the
> doctor's follow-up window, the price and length snapshot on bookings, and a
> constraint that refuses two live bookings for one doctor whose times overlap.
> Existing prices are copied into rules; existing bookings get their length and
> end time. Needs the `btree_gist` extension, which the migration enables. If it
> stops with "Two live bookings for one doctor start at the same time", run the
> query in the message and resolve those by hand first. Idempotent. App builds
> from before it keep working: they book at the doctor's shortest first-visit
> price, which `doctor_pricing` keeps showing (§6e).
>
> **Before it: `0025_visit_prescriptions_followups.sql`** (applied 2026-10-27). Apply before deploying the
> backend that uses it, and make sure `charak-tick` exists (§6) first: the
> 72-hour completion, prescription and follow-up reminders and appointment
> reminders all run from it. It adds the `in_progress` and `consulted`
> statuses, Start Journey, prescriptions (drafts, sent versions, corrections;
> sent ones can't be edited or deleted), completion when the patient opens the
> prescription, follow-up recommendations, `call_joins`, and the doctor's
> signature. Idempotent. Then create the `prescriptions` bucket (§3b). Old app
> builds keep working: a doctor build without the prescription screen can still
> mark a paid visit complete. Raise `min_app_version` (§6b) once the new builds
> are in the stores, so every visit goes through a prescription.
>
> **Before it: `0024_cancellation_policy_and_consent.sql`** (applied 2026-10-26). Apply before deploying
> the backend that uses it. It adds versioned cancellation policies (LD-005 for
> home visits; online keeps a full refund until D3 is decided), the refund quote
> the cancel uses, partial refunds, `legal_documents`, and consent records with
> method and booking. Existing bookings keep their full-refund terms (the
> `legacy` policy version). The two consent switches start off; see §6c.
>
> **Before it: `0023_booking_state_machine_and_platform.sql`.** Apply it in the SQL
> Editor *before* deploying the backend that uses it. That backend calls
> `transition_booking()`, `expire_payment_holds()` and the job functions, and
> writes to `device_tokens`, `idempotency_keys` and `webhook_events`. The backend
> already deployed keeps working once 0023 is in: `cancel_booking()` keeps its
> parameters, and its direct status writes are still allowed, just recorded as
> `status_changed_outside_state_machine` events. Idempotent. Its last block has
> two verification queries.
>
> **Before it: `0022_refunds_and_ledger_recovery.sql`** (applied 2026-10-26). Apply it in the SQL Editor
> *before* deploying the backend that uses it: the cancel endpoint calls the
> `cancel_booking()` function it creates, so a backend deployed first returns a
> 500 on every cancel until 0022 runs. It is idempotent. It adds the `refunds`
> table, the `partially_refunded` payment status, ledger `reversal` entries, and
> closes EXECUTE on functions to the client roles. Its last block is a query to
> verify that.

Two new migrations must be applied to the Supabase project. There is no Supabase
CLI or direct Postgres connection string on the dev machine, so these are applied
by hand:

1. Open the Supabase dashboard → **SQL Editor**
2. Paste and run `supabase/migrations/0007_phase4_backend.sql`
3. Paste and run `supabase/migrations/0008_phase4_rls.sql`
4. Paste and run `supabase/migrations/0009_addresses_uploads_media.sql`

Both are idempotent (`create table if not exists`, `add column if not exists`),
so re-running them is harmless.

**Verify:**

```bash
curl -s $API_URL/readyz | jq
# database.ok must be true
```

`0007` adds: `otp_codes`, `notifications`, `doctor_bank_accounts`, `payouts`,
`doctor_ledger_entries`; the `no_show` booking status; payment-hold columns; and
doctor `suspended` / `commission_pct`.
`0008` revokes anon access to all five new tables.
`0009` adds `patient_addresses`, the booking address snapshot and
`address_released_at`, plus Storage path columns and transcription status on
`intake_media`. **Home visits do not work at all until 0009 is applied** — the
doctor app reads `booking.patient_address`, and until this runs that column does
not exist.

---

## 0b. Close Supabase's own client door (required)

The apps and the admin never use Supabase Auth or PostgREST directly; everything
goes through the API with the service-role key. Two settings must match that:

1. Dashboard → **Authentication → Sign In / Providers**: turn **off** "Allow new
   users to sign up", and turn off the **Email** provider. Authentication →
   Users should be empty.
2. SQL Editor: run `supabase/migrations/0021_lock_down_client_roles.sql`. It
   drops the old `auth.uid()` policies and revokes every table from `anon` and
   `authenticated`, except `categories` (read by the keepalive workflow).

Why both: with sign-up on, anyone holding the (public) anon key could mint an
`authenticated` session, and 0004's `for all using (id = auth.uid())` policies
let that session insert its own `doctors` row already marked `verified`.

**Verify** (expect `401` for `doctors`/`users`, `200` for `categories`):

```bash
for t in doctors users bookings categories; do
  curl -s -o /dev/null -w "$t %{http_code}\n" "$SUPABASE_URL/rest/v1/$t?select=id&limit=1" \
    -H "apikey: $SUPABASE_ANON_KEY" -H "Authorization: Bearer $SUPABASE_ANON_KEY"
done
```

The verify queries at the bottom of 0021 also list any doctor marked verified
without an ops approval in `audit_log`.

---

## 1. SMS OTP — MSG91

```
MSG91_API_KEY=...
MSG91_SENDER_ID=CHARAK
MSG91_TEMPLATE_ID=...
```

Until these are set, `POST /auth/send-otp` prints the code to the server log
(`[OTP STUB] +9198... → 123456`) and returns success. With them set, the code is
sent by SMS and a gateway error surfaces as a 502 rather than silently leaving
the patient on a dead OTP screen.

**Verify:** request an OTP on a real handset and log in. Then request four codes
in a row — the fourth must return 429.

---

## 2. Payments — Razorpay

```
RAZORPAY_KEY_ID=rzp_live_...
RAZORPAY_KEY_SECRET=...
RAZORPAY_WEBHOOK_SECRET=...          # from the Razorpay webhook settings page
```

Then in the Razorpay dashboard, add the webhook:

- URL: `$API_URL/payments/webhook`
- Events: `payment.captured`, `payment.failed`, `refund.created`,
  `refund.processed`, `refund.failed`

The refund events matter: a refund is shown to the patient as completed, and the
payment marked `refunded`, only when `refund.processed` arrives (or the sweep in
§6 polls Razorpay and finds it processed).

Notes:

- `RAZORPAY_WEBHOOK_SECRET` is **not** the same string as the API key secret, and
  there is no fallback: with live keys and no webhook secret, the webhook refuses
  every delivery (503) and `/readyz` reports degraded.
- Once `RAZORPAY_KEY_ID` and `RAZORPAY_KEY_SECRET` are both present,
  `POST /payments/{id}/stub-complete` starts returning 403. The dev bypass cannot
  be reached in production.
- `razorpay==2.0.1` is in `requirements.txt`. The earlier 1.4.2 pin imported
  `pkg_resources`, which `python:3.13-slim` does not have, so `import razorpay`
  failed in the production image and every live order or refund was a 500.
  Redeploy after pulling this change. `tests/test_dependencies.py` now catches it.

**Verify:** take one real ₹1 payment end to end, then check that it credited the
ledger:

```bash
curl -s -H "Authorization: Bearer <doctor token>" \
  $API_URL/payouts/me/balance | jq
# payable_net should be the amount paid (no platform fee: LD-003)
```

Then cancel a test booking you paid for and confirm the refund lands:

```bash
curl -s -H "Authorization: Bearer <ops token>" "$API_URL/admin/refunds?status=processed" | jq '.[0]'
# status "processed", a razorpay_refund_id, and the payment now 'refunded'
```

---

## 3. Push notifications — FCM

Preferred (HTTP v1, the non-deprecated API):

```
FCM_PROJECT_ID=charak-xxxx
GOOGLE_APPLICATION_CREDENTIALS=/app/secrets/fcm-service-account.json
```

Legacy server key also works if it is faster to obtain:

```
FCM_SERVER_KEY=...
```

Until either is set, every notification is still **written to the
`notifications` table** with `delivery = 'skipped'`, so the in-app inbox
(`GET /notifications`) is already live and nothing is lost. Switching FCM on
changes delivery only.

`google-auth==2.41.1` is already in `requirements.txt`.

### App side

Both apps register automatically — `CharakPush.start()` is called from
`AuthNotifier` on login and on a resumed session, and `stop()` on logout, so no
screen has to remember to do it. What the apps still need at build time is a
Firebase project:

1. Add an Android app per package name (`in.charak.partner`, `in.charak.app`)
   to the same Firebase project the backend's service account belongs to.
2. Drop each `google-services.json` at `apps/<app>/android/app/`.
3. Add the Google Services plugin to `apps/<app>/android/` —
   `id("com.google.gms.google-services") version "4.4.2" apply false` in the
   root `build.gradle.kts`, applied in `app/build.gradle.kts`.

Until that file exists `Firebase.initializeApp()` throws, `CharakPush` records
`unavailableReason` and returns quietly — the apps build and run, they simply
receive nothing. Notification taps are routed per event in each app's
`router.dart`.

**Verify:** after logging in on a device, `POST /push/register` then trigger a
booking request. Check the row:

```sql
select event, delivery, delivery_error from notifications order by created_at desc limit 5;
```

`delivery` should read `sent`. `skipped` with `no token registered` means the app
never called `/push/register`.

---

## 3b. Storage buckets (one-time)

Four buckets are needed: `doctor-photos` (public), `verification-docs`,
`intake-media` and `prescriptions` (all private). `prescriptions` is new with
migration 0025: prescription PDFs, handwritten uploads and doctors' signatures.
The call below creates any that are missing (and is how to create them on a
fresh project):

```bash
curl -s -X POST -H "Authorization: Bearer <ops token>" \
  $API_URL/uploads/buckets/ensure
```

Uploads go **through the backend**, never from the app. The apps authenticate with
a JWT this API issues rather than a Supabase Auth session, so `auth.uid()` is null
inside any Storage policy and no RLS rule can authorise them — which is why
client-side uploads silently failed and doctors could not submit licence
documents. No Storage policies are needed: the backend holds the service-role key
and authorises each request itself. Private objects are read through 5-minute
signed URLs minted per request.

---

## 4. Voice transcription — OpenAI Whisper

```
OPENAI_API_KEY=sk-...
```

Until set, a voice note still uploads and is still playable by the doctor; the
`intake_media` row records `transcript_status='failed'` with the reason, so the
gap is visible rather than looking like a patient who said nothing.

### Vertex AI (preferred) — transcript and summary in one call

```
VERTEX_PROJECT_ID=charak-xxxx
VERTEX_LOCATION=asia-south1          # Mumbai. Do not use the global endpoint.
GEMINI_MODEL=gemini-2.5-flash
GOOGLE_APPLICATION_CREDENTIALS=/app/secrets/gcp-service-account.json
```

The same service-account file FCM uses, with the `cloud-platform` scope. No new
dependency — `google-auth` is already installed.

Two reasons this is preferred over Whisper:

* **Data residency.** Patient voice notes describing symptoms are health data.
  `asia-south1` keeps processing in India; the *global* endpoint silently does
  not, which is why the region is baked into the request URL and a test asserts
  it.
* **One call, two outputs.** Transcript and summary together, for roughly a
  sixth of Whisper's per-minute cost.

Pin the model. APAC regions lag US on new releases, so check the model is
actually served in `asia-south1` before changing `GEMINI_MODEL`.

**Fallback.** If Vertex is unset or a call fails, it falls back to Whisper and
stores the transcript with no summary. A transcript without a summary is a
working intake; losing the transcript would not be.

### Where the AI boundary sits

Requirements Document §3.8: *"Voice → transcription + summary for the doctor
only. Nothing diagnostic. Nothing analyzes video or images. This is a hard
product boundary."*

So, concretely:

* voice may be transcribed **and summarised**;
* photos and video are stored and displayed as-is — nothing reads them, and the
  doctor app will not render a summary on a non-voice item;
* the summary reports what the patient *said*, never what it might mean. No
  triage, no urgency, no severity, no differential, no advice.

`SUMMARY_PROMPT` in `services/transcription.py` is the only place that boundary
is expressed, and tests assert its constraining clauses are still present.
Weakening it is a product decision, not a refactor.

⚠️ **The patient-facing microcopy is now wrong.** `intake_screen.dart` says
"Reviewed by your doctor directly — never analyzed by AI." That was accurate when
nothing was summarised. It is not accurate now, and it needs rewording before
launch — see the note in the milestone schedule.

---

## 5. Video calls — Agora

```
AGORA_APP_ID=...
AGORA_APP_CERTIFICATE=...
```

`agora-token-builder==1.0.0` is already in `requirements.txt`. Tokens are minted
for one hour. If credentials are set but the package is missing, the endpoint
returns a clear 500 rather than handing the app a token that cannot join a
channel.

Both sides get a token: the doctor from
`POST /bookings/{id}/clarification-call`, the patient from
`POST /bookings/{id}/call` — which resolves whatever call is ringing on the
booking, because the patient app is never told a call id.
`POST /bookings/{id}/clarification-call/{call_id}/token` remains for a caller
that does hold one.

### App side

`CharakCallSession` in `charak_core` owns the Agora engine for both apps —
permissions, join, mute/camera, the elapsed clock and the two video views. No
extra build configuration is needed; the `agora_rtc_engine` plugin and the
camera/microphone manifest permissions are already in place.

The `live` flag in every token response is what the apps switch on. While the
credentials above are unset the backend returns a `stub_…` token, no engine is
created, and both call screens say **"Dev stub · Agora not configured"** rather
than sitting on "Connecting…" forever — so the flow stays testable without
credentials, and it is obvious which mode you are in.

---

## 6. Scheduled jobs (required — not optional)

```
CRON_SECRET=<64 random hex chars>
```

These endpoints must be called on a timer. All of them refuse to run at all if
`CRON_SECRET` is unset (503) — an endpoint that mutates bookings will not run
unauthenticated just because a deploy forgot a variable.

| Endpoint | Frequency | What breaks without it |
|---|---|---|
| `POST /maintenance/release-expired-holds` | every 2–5 min | An unpaid booking holds a doctor's slot forever |
| `POST /maintenance/purge-expired-otps` | hourly | Dead OTP rows accumulate as PII |
| `POST /maintenance/purge-deleted-accounts` | daily | A self-deleted patient's data outlives its 30-day grace window |
| `POST /maintenance/purge-old-rate-limit-hits` | daily | `rate_limit_hits` (admin login, bookings, uploads) grows forever — nothing reads a row older than an hour |
| `POST /maintenance/tick` | **every minute** | Notifications whose first send didn't happen (Cloud Run throttles CPU after a response) or failed for a moment are never retried; scheduled jobs never run: no appointment, prescription or follow-up reminders, and a prescription nobody opens never completes its visit (so the doctor's fee is never released) |
| `POST /maintenance/retry-refunds` | every 5 min | A refund whose Razorpay call failed (timeout, outage) is never sent; a refund whose webhook was lost never shows "Refunded" |

Call with the header `X-Cron-Secret: <value>`. Production uses Cloud Scheduler,
one job per endpoint. As of 2026-10-26 these exist (schedules in UTC):

| Job | Schedule |
|---|---|
| `charak-release-expired-holds` | `*/5 * * * *` |
| `charak-purge-expired-otps` | `0 * * * *` |
| `charak-purge-deleted-accounts` | `15 2 * * *` |
| `charak-purge-old-rate-limit-hits` | `30 2 * * *` |

`charak-tick` is new with migration 0023. Create it after that backend is
deployed, the same way as the refund job below:

```bash
gcloud scheduler jobs create http charak-tick --location asia-south1 \
  --schedule "* * * * *" --time-zone "Etc/UTC" --http-method POST \
  --uri "$API_URL/maintenance/tick" \
  --headers "X-Cron-Secret=$CRON_SECRET" --attempt-deadline 90s
```

`release-expired-holds` now also expires requests the doctor never answered
(once their slot has started, or after `app_config.request_expiry_minutes` if
ops sets it). No new job is needed for that.

`charak-retry-refunds` is new with migration 0022 (created 2026-10-26). Create it **after** the backend
that has the endpoint is deployed (before that it would only log 404s):

```bash
# CRON_SECRET: the same value the other jobs send (Cloud Run env / Secret Manager).
gcloud scheduler jobs create http charak-retry-refunds --location asia-south1 \
  --schedule "*/5 * * * *" --time-zone "Etc/UTC" --http-method POST \
  --uri "$API_URL/maintenance/retry-refunds" \
  --headers "X-Cron-Secret=$CRON_SECRET" --attempt-deadline 120s

# Run it once by hand and check the response is {"reclaimed":…, "sent":…, "polled":…}:
gcloud scheduler jobs run charak-retry-refunds --location asia-south1
gcloud scheduler jobs list --location asia-south1
```

Check the list after any redeploy that changes the service URL.

---

## 6b. Forcing an app update

`app_config.min_app_version` holds the oldest build each app may run. The apps
read it at launch (`GET /config/app`). A build below it shows a full-screen
"Update CHARAK" with a store link and can't go further. Raise it only after the
new build is live in the stores:

```sql
update app_config set value = '{"patient": "1.1.0", "doctor": "1.1.0"}' where key = 'min_app_version';
```

Instances pick the change up within a minute. Set the iOS store links in
`store_urls` once the apps are listed (they're null until then; the screen then
names the App Store instead of linking).

---

## 6c. Cancellation policy and consent

**Changing a cancellation policy.** A published version is never edited (the
table refuses). Add a new version, and new bookings get it. Existing bookings
keep theirs. For example, when the online late-cancellation rule (D3) is
decided as "no refund inside 15 minutes":

```sql
insert into policies (kind, channel, version, rules, summary, decision_ref) values
  ('cancellation', 'online_consult', '2026-11-01',
   '[{"when": {"minutes_before_start_lt": 15}, "refund_pct": 0},
     {"when": {}, "refund_pct": 100}]',
   'Free cancellation up to 15 minutes before your consultation. After that the fee '
   'isn''t refunded. If the doctor cancels or doesn''t join, you get a full refund.',
   'LD-005 / D3');
```

Rules are checked in order and the first match wins. Conditions:
`journey_started` (true/false) and `minutes_before_start_lt` (number).
Refunds round down to the paisa. A doctor or ops cancellation is always a full
refund.

**Publishing a new legal document version.** Publish the text on the website
first, then:

```sql
insert into legal_documents (type, version, title, url, audience, material)
values ('tos', '2026-12-01', 'Terms of Use', 'https://www.charak.care/terms', '{patient,doctor}', true);
```

Apps ask everyone again on their next visit to home. With the switch below on,
booking also refuses (428) until they have accepted.

**Consent switches** (`app_config`). Turn them on once app builds with the new
screens are in the stores, and raise `min_app_version` at the same time (§6b):

```sql
update app_config set value = 'true' where key = 'require_legal_acceptance';           -- Terms, Privacy, Telemedicine
update app_config set value = 'true' where key = 'require_booking_policy_acceptance';  -- the ticked cancellation policy
```

---

## 6d. The visit and prescriptions (migration 0025)

- **Completion.** A visit completes when the patient opens the prescription,
  or 72 hours after it was sent (`app_config.completion_fallback_hours`). The
  tick also completes any visit whose timer job was lost.
- **When the doctor's fee can be withdrawn (LD-006).** 48 hours after the
  prescription was sent if the patient opened it within those 48 hours,
  otherwise 72 hours after it. `GET /payouts/me/balance` shows `available_net`,
  `waiting_net` and `next_available_at`; `/payouts/run` only takes entries
  whose time has come.
- **Ops queues.** Admin → Visits lists home visits with no journey near their
  time, visits with nothing sent 2 hours after the start, and prescriptions not
  opened after a day. Nothing there changes a booking by itself.
- **Reading a prescription (break-glass).** Ops sees only whether a
  prescription was sent and opened. Reading the content needs a written reason
  in Admin → Visits → Prescription; the read is written to `audit_log`
  (`break_glass_read`) before anything is shown, and refused if that write
  fails. Review those rows regularly:

  ```sql
  select at, actor_id, reason, metadata from audit_log
   where action = 'break_glass_read' order by at desc limit 50;
  ```

- **Retention.** Prescriptions are kept when a patient deletes their account,
  like the intake transcript: a clinical record. The PDF carries the patient's
  name. Confirm the retention period with counsel (D20).
- **Settings** (`app_config`): `consultation_start_window_minutes` (how early
  the doctor can start: online 15, home 120), `appointment_reminders` (minutes
  before the start), `follow_up_reminders` (9:00 IST on the day, plus 2 days
  before when it's at least 7 days away).

---

## 6e. Prices (migration 0026)

- **The matrix.** Doctors set a price per channel and length (10, 15, 20, 30,
  45 or 60 min, up to 4 each) for a first visit, and optionally a follow-up
  price, with how many days after a visit it applies (1–60). A follow-up can be
  free; a first visit can't. The patient picks the length first and is shown
  times that fit it.
- **Extra-time rates are gone.** The old screens advertised "+₹X per extra N
  min", but nothing ever charged it. Lengths are priced individually instead.
  Doctors who priced one length should check their prices in the new app.
- **What a booking costs never changes.** Each booking keeps `price_paise`,
  `duration_min` and the `price_rule_id` it was charged by. A trigger refuses
  changes. If the doctor changes a price while a patient is booking, the
  booking is refused with the new price, never charged at it.
- **Follow-ups.** A follow-up price applies only to a booking that names a
  consultation of the patient's own with the same doctor, after its
  prescription was sent, starting within the doctor's window (or up to 3 days
  after the follow-up date the doctor recommended, if that is later). One per
  consultation. A free follow-up is confirmed when the doctor accepts it, with
  no payment.
- **Support.** Admin → Directory → Prices shows every price a doctor has had and
  when each applied. Or:

  ```sql
  select channel, visit_category, duration_min, price_paise, effective_from, effective_until
    from doctor_price_rules where doctor_id = '<uuid>' order by effective_from desc;
  ```

---

## 7. Ops and hardening

Admin accounts are per-person with mandatory TOTP, not a shared password.
Create the first one with `scripts/create_admin.py <email>` (needs
`SUPABASE_URL` / `SUPABASE_SERVICE_ROLE_KEY` — point it at `backend/.env` or
export the production values first). It prints instructions for the one-time
QR-code enrollment step done at `/admin/login` itself.

```
ALLOWED_ORIGINS=https://charak.care          # the admin is served at charak.care/admin; default '*'
TRUSTED_PROXY_HOPS=1                       # X-Forwarded-For entries our proxies append; 2 behind an HTTPS LB
OTP_ALLOWED_COUNTRY_CODES=+91              # SMS only to these; stops SMS-pumping to premium ranges
PROCEDURE_REVIEW_THRESHOLD_MAX=5000        # bills above this always get senior review
ENABLE_API_DOCS=                           # leave unset in production (/docs, /openapi.json stay 404)
PLATFORM_COMMISSION_PCT=15                 # Charak's cut; per-doctor override in doctors.commission_pct
PAYMENT_HOLD_MINUTES=10                    # how long a slot is held for payment
ADMIN_TOKEN_TTL_HOURS=12                   # default — admin sessions are short-lived by design
JWT_SECRET=<64 random hex chars>           # rotating this logs every user out
```

CORS only governs the admin dashboard — the mobile apps send no `Origin` header —
but `*` with credentials is worth closing regardless.

---

## 8. Money flow reference

Money is recognised in exactly one place: `_confirm_payment` in
`app/routers/payments.py`. Both the Razorpay webhook and the dev shortcut route
through it, so development and production behave identically.

```
patient pays ₹1000
      ↓  doctor_ledger_entries: gross 1000, commission 0 (LD-003), net 1000, status=payable
visit happens, booking → completed            (only now is the entry payout-eligible)
ops runs a payout   POST /payouts/run   {doctor_id, period_start, period_end}
      ↓  payouts row: net 1000, status=pending; entries → paid
ops transfers (UPI or bank)
      ↓  PATCH /payouts/{id}  {status: "paid", reference: "<UTR>"}
         a reference is mandatory — every rupee is traceable to a transaction
```

Cancelling a paid booking (one transaction, `cancel_booking()` in 0022):

```
booking → cancelled; any open payment attempt → failed
refunds row queued per completed payment (pending)  → Razorpay → processing → processed
ledger: entry still payable  → reversed
        entry already paid out → a negative 'reversal' entry, recovered from the next payout
payment stays 'completed' until refund.processed, then 'refunded'
```

Safety properties, all covered by tests:

- **A refund is never reported done before Razorpay confirms it.** Failed refunds
  land in Admin → Refunds with a Retry button. Retries look for an earlier
  Razorpay refund carrying our id before sending another, so a timeout never
  refunds twice. The database also refuses refunds that add up to more than the
  payment (`refunds_guard`).
- **A payout only takes fees for completed visits.** A fee credited at payment
  waits until the visit has happened.
- **A payout only moves forward.** `paid` and `failed` are final; marking a paid
  payout failed is refused (it used to put the entries back to payable and pay
  the doctor twice).

- **Crediting is idempotent** on `(booking_id, source)`. A Razorpay webhook
  replay cannot pay a doctor twice.
- **The credit runs before the payment is flipped to `completed`.** A crash
  between the two is recoverable: the retry re-credits harmlessly. The other
  ordering would lose the doctor's earnings permanently.
- **A failed payout returns its entries to `payable`.** The doctor is still
  owed the money and the next run picks it up.
- **A no-show creates no ledger entry.** Nobody is charged.

---

## 9. Payout cycle (ops, weekly)

```bash
# 1. Who is owed what
curl -s -H "Authorization: Bearer <ops token>" \
  $API_URL/payouts/pending-summary | jq

# 2. Create the payout (refuses if there is no bank account on file)
curl -s -X POST -H "Authorization: Bearer <ops token>" \
  -H 'content-type: application/json' \
  -d '{"doctor_id":"<uuid>"}' \
  $API_URL/payouts/run

# 3. Transfer in the bank portal, then record it
curl -s -X PATCH -H "Authorization: Bearer <ops token>" \
  -H 'content-type: application/json' \
  -d '{"status":"paid","reference":"<bank UTR>"}' \
  $API_URL/payouts/<payout_id>
```

If a transfer bounces, `{"status":"failed","failure_reason":"..."}` returns the
earnings to payable rather than losing them.

RazorpayX can replace step 2's manual transfer later; the ledger model does not
change.

---

## 10. Post-deploy smoke test

```bash
curl -s $API_URL/readyz | jq
```

```json
{
  "status": "ok",
  "database": {"ok": true, "error": null},
  "integrations": {
    "sms_otp": true,
    "payments": true,
    "push": true,
    "video_calls": true,
    "transcription": true
  }
}
```

Every flag reflects whether that integration's credentials are actually present,
so this one call answers "what is still stubbed in production?".
