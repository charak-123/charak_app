# Backend go-live runbook

The backend is feature-complete against the V1 scope. Every external service is
behind an environment variable and a code path that is already written and
tested — switching one on is a config change, not a code change.

This document is the checklist for that switch-on, plus what to verify after each
step.

---

## 0. Apply the migrations (required first — nothing else works without this)

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
curl -s https://charak-api.fly.dev/readyz | jq
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

- URL: `https://charak-api.fly.dev/payments/webhook`
- Events: `payment.captured`, `payment.failed`

Notes:

- `RAZORPAY_WEBHOOK_SECRET` is **not** the same string as the API key secret.
  The code falls back to the key secret if the webhook secret is unset, but set
  it properly.
- Once `RAZORPAY_KEY_ID` and `RAZORPAY_KEY_SECRET` are both present,
  `POST /payments/{id}/stub-complete` starts returning 403. The dev bypass cannot
  be reached in production.
- `razorpay==1.4.2` is already in `requirements.txt`.

**Verify:** take one real ₹1 payment end to end, then check that it credited the
ledger:

```bash
curl -s -H "Authorization: Bearer <doctor token>" \
  https://charak-api.fly.dev/payouts/me/balance | jq
# payable_net should be the amount minus commission
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

**Verify:** after logging in on a device, `POST /push/register` then trigger a
booking request. Check the row:

```sql
select event, delivery, delivery_error from notifications order by created_at desc limit 5;
```

`delivery` should read `sent`. `skipped` with `no token registered` means the app
never called `/push/register`.

---

## 3b. Storage buckets (one-time)

Three buckets are needed: `doctor-photos` (public), `verification-docs` and
`intake-media` (both private). All three now exist. To recreate them on a fresh
project:

```bash
curl -s -X POST -H "Authorization: Bearer <ops token>" \
  https://charak-api.fly.dev/uploads/buckets/ensure
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

**Scope is deliberately narrow.** This is speech-to-text only — no summarising, no
triage, no symptom extraction — because the product promises intake is "reviewed
by your doctor directly, never analyzed by AI". The request carries no prompt, and
a test asserts that. Adding anything interpretive here is a product decision about
that promise, not a code change.

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
`POST /bookings/{id}/clarification-call/{call_id}/token`.

---

## 6. Scheduled jobs (required — not optional)

```
CRON_SECRET=<64 random hex chars>
```

Two endpoints must be called on a timer. Both refuse to run at all if
`CRON_SECRET` is unset (503) — an endpoint that mutates bookings will not run
unauthenticated just because a deploy forgot a variable.

| Endpoint | Frequency | What breaks without it |
|---|---|---|
| `POST /maintenance/release-expired-holds` | every 2 min | An unpaid booking holds a doctor's slot forever |
| `POST /maintenance/purge-expired-otps` | daily | Dead OTP rows accumulate as PII |

Call with the header `X-Cron-Secret: <value>`. Any scheduler works — a Fly
machine running cron, GitHub Actions on a schedule, or an external pinger:

```bash
curl -fsS -X POST -H "X-Cron-Secret: $CRON_SECRET" \
  https://charak-api.fly.dev/maintenance/release-expired-holds
```

---

## 7. Ops and hardening

```
ADMIN_PASSWORD=<strong value>              # default is 'charak-admin-2024' — change it
ALLOWED_ORIGINS=https://admin.charak.in    # default '*' — tighten before launch
PLATFORM_COMMISSION_PCT=15                 # Charak's cut; per-doctor override in doctors.commission_pct
PAYMENT_HOLD_MINUTES=10                    # how long a slot is held for payment
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
      ↓  doctor_ledger_entries: gross 1000, commission 150 (15%), net 850, status=payable
ops runs a payout   POST /payouts/run   {doctor_id, period_start, period_end}
      ↓  payouts row: net 850, status=pending; entries → paid
ops transfers in the bank portal
      ↓  PATCH /payouts/{id}  {status: "paid", reference: "<bank UTR>"}
         a reference is mandatory — every rupee is traceable to a transaction
```

Safety properties, all covered by tests:

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
  https://charak-api.fly.dev/payouts/pending-summary | jq

# 2. Create the payout (refuses if there is no bank account on file)
curl -s -X POST -H "Authorization: Bearer <ops token>" \
  -H 'content-type: application/json' \
  -d '{"doctor_id":"<uuid>"}' \
  https://charak-api.fly.dev/payouts/run

# 3. Transfer in the bank portal, then record it
curl -s -X PATCH -H "Authorization: Bearer <ops token>" \
  -H 'content-type: application/json' \
  -d '{"status":"paid","reference":"<bank UTR>"}' \
  https://charak-api.fly.dev/payouts/<payout_id>
```

If a transfer bounces, `{"status":"failed","failure_reason":"..."}` returns the
earnings to payable rather than losing them.

RazorpayX can replace step 2's manual transfer later; the ledger model does not
change.

---

## 10. Post-deploy smoke test

```bash
curl -s https://charak-api.fly.dev/readyz | jq
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
