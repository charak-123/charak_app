# New backend endpoints (Phase 4)

Reference for the UI work that resumes once the backend is signed off. 78 routes
total; these are the ones that did not exist before. Every response shape below is
what the code returns today, verified against the test suite.

Auth is unchanged: `Authorization: Bearer <token>` from `/auth/verify-otp`.

---

## Notifications — in-app inbox

Works **now**, with or without FCM. Every notifiable event is written to the
`notifications` table, so the apps can ship a notification list before push is
switched on.

| Method | Path | Notes |
|---|---|---|
| `GET` | `/notifications/?unread_only=&limit=` | Newest first, scoped to the caller. `limit` capped at 200 |
| `GET` | `/notifications/unread-count` | `{count, push_enabled}` — badge count |
| `PATCH` | `/notifications/{id}/read` | 403 on someone else's notification |
| `PATCH` | `/notifications/read-all` | `{updated: n}` |
| `DELETE` | `/push/register` | Clear the device token on logout |

Each row carries `event`, `title`, `body`, `data`, `booking_id`, `read_at`. The
`event` string is the stable key to switch on for deep-linking — the copy in
`title`/`body` may change.

Events emitted today: `booking.requested`, `booking.accepted`,
`booking.declined`, `booking.cancelled`, `booking.hold_expired`,
`booking.no_show`, `payment.received`, `payment.confirmed`, `payment.failed`,
`visit.running_late`, `visit.completed`, `call.incoming`, `bill.under_review`,
`bill.approved`, `rating.received`, `doctor.verified`, `doctor.rejected`,
`doctor.suspended`, `payout.paid`, `complaint.filed`.

---

## Doctor earnings and payouts

Replaces the display-only earnings view with the real money position. Note
`/earnings/me` still exists and is unchanged; these add what a doctor is actually
*owed* after Charak's commission.

| Method | Path | Notes |
|---|---|---|
| `GET` | `/payouts/me/balance` | `{payable_net, paid_net, lifetime_gross, lifetime_commission, commission_pct}` |
| `GET` | `/payouts/me/ledger?status=payable` | Per-visit rows: `gross_amount`, `commission_amount`, `net_amount` |
| `GET` | `/payouts/me` | Payout history with `status` and bank `reference` |
| `PUT` | `/payouts/me/bank-account` | `{account_holder, account_number, ifsc, bank_name?, upi_id?}` |
| `GET` | `/payouts/me/bank-account` | 404 if none on file |

UI notes:

- `payable_net` is the headline number for the earnings tab — gross minus
  commission, not yet transferred.
- `account_number` always comes back masked (`••••9012`). The full value is never
  returned, including to its owner.
- `ifsc` is validated server-side (11 chars, RBI format) and returns 422 on a bad
  value — worth mirroring client-side to avoid a round trip.
- Saving a bank account resets `verified` to false.

---

## Booking lifecycle

| Method | Path | Notes |
|---|---|---|
| `PATCH` | `/bookings/{id}/no-show` | Doctor only. Accepted-and-unpaid only; charges nobody |
| `POST` | `/bookings/{id}/running-late` | `{minutes}` (1–180). Notifies the patient, changes no state |
| `POST` | `/payments/{id}/failed` | Client reports a failed attempt → `{retry_until, hold_minutes}` |

Two behaviours the UI needs to account for:

- **Accepting now starts a payment hold.** The booking gains
  `hold_expires_at` (default 10 minutes). Show a countdown on the patient's
  payment screen — when it lapses a scheduled job cancels the booking with
  `cancelled_by: "system"`.
- **`no_show` is a new booking status.** Any screen that switches on status needs
  a branch for it, alongside `completed`/`declined`/`cancelled`.
- `cancelled_by` is now recorded as `patient`, `doctor`, `ops` or `system`, which
  is what lets history screens say *who* cancelled.

---

## Payments

| Method | Path | Notes |
|---|---|---|
| `POST` | `/payments/{id}/order` | Now takes `{type: "consult_fee" \| "procedure_bill"}` |
| `POST` | `/payments/{id}/failed` | See above |

The order response gained `type` and `live`. `live: false` means Razorpay is
stubbed — useful for showing a dev banner instead of opening the real checkout.
Reopening the payment screen reuses the existing open order rather than creating
a duplicate.

---

## Clarification calls

| Method | Path | Notes |
|---|---|---|
| `POST` | `/bookings/{id}/clarification-call/{call_id}/token` | **Patient-side join token** |

The patient app previously had no way to join the channel it was being called on.
Both the initiate response and this one now return `agora_app_id`, `live`, and
`expires_in` (3600s) alongside `agora_channel` and `agora_token`.

---

## Admin

| Method | Path | Notes |
|---|---|---|
| `GET` | `/admin/metrics` | Whole dashboard in one call — see below |
| `GET` | `/admin/doctors?status=&suspended=` | Full list for directory management |
| `PATCH` | `/admin/doctors/{id}/suspend` | `{suspended: bool, reason?}` — reason required to suspend |
| `GET` | `/admin/audit-log?limit=` | Ops action trail |
| `GET` | `/payouts/pending-summary` | Payout worklist grouped by doctor |
| `POST` | `/payouts/run` | `{doctor_id, period_start?, period_end?}` |
| `PATCH` | `/payouts/{id}` | `{status, reference?, failure_reason?}` |
| `POST` | `/payouts/adjustments` | `{doctor_id, amount, note}` — no commission applied |

`/admin/metrics` returns four groups, which should let the dashboard drop its
six separate fetches:

```json
{
  "doctors":  {"total":3,"pending":1,"verified":2,"rejected":0,"suspended":1},
  "bookings": {"total":4,"requested":1,"accepted":0,"paid":1,"completed":1,
               "cancelled":0,"declined":0,"no_show":1},
  "revenue":  {"consult_gross":1300.0,"procedure_gross":2000.0,
               "commission_earned":420.0,"owed_to_doctors":680.0},
  "queues":   {"bills_under_review":1,"complaints_open":1,"complaints_in_review":0}
}
```

Suspension is the "remove a listing" action from the Week 10 plan: the doctor
keeps their account, history and pending payouts, but disappears from
`/doctors/search`, 404s on a direct profile link, and new bookings against them
return 409.

---

## Meta

| Method | Path | Notes |
|---|---|---|
| `GET` | `/readyz` | Confirms the database answers; reports which integrations are live |

```json
{"status":"ok","database":{"ok":true,"error":null},
 "integrations":{"sms_otp":false,"payments":false,"push":false,"video_calls":false}}
```

One call answers "what is still stubbed?" — useful for a debug screen and for the
Fly health check.

---

## Changed responses on existing endpoints

- `GET /doctors/search` now returns `limit`, `offset` and `has_more` alongside
  `total` and `items`. `limit` is clamped to 100.
- `GET /bookings/doctor/history` now includes `no_show` bookings.
- `POST /auth/send-otp` returns `expires_in` (seconds) for the resend timer.
- `POST /push/register` returns `push_enabled`.
- Procedure bills are created with their line items in a single write, so
  `items` is never briefly empty on read.
