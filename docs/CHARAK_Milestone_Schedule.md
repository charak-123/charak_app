# CHARAK — MVP Milestone Schedule

Detailed build plan · Website · Patient app first · Doctor app · Shared backend · For founder weekly updates

| | |
|---|---|
| **Project start** | Mon 18 Aug 2026 |
| **Beta target** | Fri 31 Oct 2026 |
| **Working days** | 55 |
| **Team** | Solo developer |
| **Scope** | Website + 2 apps + backend |
| **Build order** | Website → Foundation → Patient App → Doctor App → Integration & Launch |

---

## THE FIVE CHECKPOINTS

*What "done" looks like at each milestone — these are the dates that matter for founder updates.*

| Checkpoint | Date | Status |
|---|---|---|
| Website live (charak.in) | Fri 22 Aug 2026 | ✅ COMPLETE |
| Foundation complete | Fri 5 Sep 2026 | ✅ COMPLETE |
| Patient app complete | Fri 26 Sep 2026 | ✅ COMPLETE |
| Doctor app complete | Fri 17 Oct 2026 | Upcoming |
| Android beta live | Fri 31 Oct 2026 | Upcoming |

**Current status (19 Sep 2026): on schedule, with buffer banked.**

Website, Phase 1 (Foundation) and Phase 2 (Patient App) are complete as planned.
In addition, **the entire Phase 4 backend workload has been completed early** —
the server-side work originally scheduled for Days 46–55 (20–31 Oct) landed on
19 Sep. See *Backend — completed ahead of schedule* below.

All five checkpoint dates are unchanged and remain the dates to report. The time
recovered is held as buffer, not pulled forward — it absorbs device-testing
surprises, Play Store review, and anything the integration credentials turn up.

---

## Website — charak.in

**18 Aug – 22 Aug 2026 (Week 1) · ✅ COMPLETE**

*Goal: charak.in is publicly live — doctors can register online, documents go directly into the same Supabase database the apps use. No re-entry needed when the app launches. The URL can go into outreach, ads, and QR codes immediately.*

### Week 1 — 18–22 Aug · ✅ Done

| Date | Task |
|---|---|
| Mon 18 Aug | Next.js project setup; public landing page (charak.in /): headline, "How it works" (Register → Get Verified → Go Live), doctor benefits, verification trust section, FAQ, footer with legal links, one CTA: "Register as a Doctor" |
| Tue 19 Aug | Doctor registration form (/register): full name, phone (with OTP verification built into the form), email, specialty dropdown, licence/registration number, qualification, years of experience, consultation channels checkboxes, city/state, document upload (licence or degree, PDF/JPG/PNG up to 10 MB); Submit locked until phone is verified |
| Wed 20 Aug | Backend wiring: form submission creates a doctor record in the same Supabase tables the apps use — same schema, zero re-entry. Confirmation page (/register/success) with unique reference ID (CHR-XXXXXX). Duplicate guard: same phone → "Already registered — Pending Verification". Rate limiting: max 5 submissions/IP/hour |
| Thu 21 Aug | Legal pages: Privacy Policy (DPDPA 2023 compliant), Terms of Service, Medical Disclaimer (booking platform, not medical provider), Contact page (Grievance Officer details per IT Rules 2021); SMS + email confirmation on registration |
| Fri 22 Aug | Production deploy to Vercel; full smoke test (submit real registration end-to-end, confirm record appears in Supabase within 2 seconds); URL shared for doctor outreach |

**Website exit:** charak.in is publicly live. A doctor can register, verify their phone, upload documents, and receive a reference ID. Every submission appears in Supabase instantly. Doctor acquisition can begin immediately — before either app ships.

---

## Phase 1 — Foundation

**25 Aug – 5 Sep 2026 (Days 6–15) · ✅ COMPLETE**

*Goal: monorepo is live, Supabase schema in place, shared package built, phone OTP login works on both app shells, and all core backend APIs are ready for the apps to plug into.*

### Week 2 — 25–29 Aug · ✅ Done

| Date | Task |
|---|---|
| Mon 25 Aug | Monorepo scaffold (`apps/patient_app`, `apps/doctor_app`, `packages/charak_core`, `backend/`); design tokens (colours, fonts, spacing); CI + lint |
| Tue 26 Aug | Supabase project; Postgres schema for all entities: users, doctors, bookings, payments, ratings, procedures, schedules, slot_blocks, complaints, intake_media, clarification_calls |
| Wed 27 Aug | Backend skeleton (auth module, DB client, error handling); `charak_core` — API client, data models, auth utilities; shared across both apps |
| Thu 28 Aug | Phone OTP login (works for both doctors and patients): enter number → SMS 6-digit code → logged in; stub SMS provider (website uses same); JWT session tokens |
| Fri 29 Aug | Both app shells wired to auth; branded splash + phone entry + OTP screens in both apps |

**Week 2 delivered:** A developer can log into either app on a real phone. Database schema is in place. A doctor who registered on the website can log into the app with the same phone — profile pre-filled, no re-upload.

### Week 3 — 1–5 Sep · ✅ Done

| Date | Task |
|---|---|
| Mon 1 Sep | Backend: specialty categories API (seeded list), doctor pricing & procedure catalogue APIs, schedule template APIs |
| Tue 2 Sep | Backend: slot-availability algorithm (weekly template − blocked − booked) + unit tests to prevent double-bookings |
| Wed 3 Sep | Backend: doctor directory search & filtering (specialty, channel, service radius for home visits, price range, real-time availability) |
| Thu 4 Sep | Backend: bookings API (create, list-for-doctor, list-for-patient, accept/decline, status tracking) + Supabase Realtime channel |
| Fri 5 Sep | Buffer + integration check: end-to-end API smoke test; shared package contract locked in `charak_core`; backend stable |

**Phase 1 exit:** Backend and shared package are stable. Slot availability, directory search, and booking APIs are all ready. Both app shells exist and can authenticate users.

---

## Phase 2 — Patient App

**8 Sep – 26 Sep 2026 (Days 16–30) · ✅ COMPLETE**

*Goal: the full patient journey works end-to-end — browse, book, pay, get treated, rate. Patient app is done.*

### Week 4 — 8–12 Sep · ✅ Done

| Date | Task |
|---|---|
| Mon 8 Sep | Patient app: name entry screen (after OTP, "What's your name?"); reuses Phase 1 auth — no new auth code |
| Tue 9 Sep | Patient app: home screen (personalised greeting, search bar, specialty grid) + doctor directory (name, specialty, star rating, consultation type, base fee, filter chips) |
| Wed 10 Sep | Patient app: doctor profile page (verification badge, star rating + total reviews, bio, base fee + extra-time rate, procedure price list, senior-review note, consultation types, Book button) |
| Thu 11 Sep | Patient app: slot selection (date strip + time grid showing only open slots); service-radius check for home visits (patient enters address → app checks in real time if within doctor's area) |
| Fri 12 Sep | Buffer — fix anything from the week; confirm directory, profile, and slot selection work end-to-end |

**End of Week 4:** A patient can log in, search by specialty, view a doctor's full profile, pick a slot, and confirm a home-visit address.

### Week 5 — 15–19 Sep · ✅ Done

| Date | Task |
|---|---|
| Mon 15 Sep | Patient app: intake form — text description of symptoms + photo/video attachments (uploaded to cloud storage) |
| Tue 16 Sep | Backend: voice note upload → Whisper transcription → LLM 2–3 line plain-English summary; doctor sees AI summary first, full transcript expandable below |
| Wed 17 Sep | Patient app: review & confirm screen (doctor, slot, consultation type, address, intake submitted, base fee + procedure-charge note) + "Send Request" button + confirmation screen |
| Thu 18 Sep | Backend: booking write on "Send Request" + real-time push to doctor; patient app subscribes to own booking row — updates the moment doctor accepts/declines |
| Fri 19 Sep | Patient app: live accept/decline screen ("Waiting for doctor…" with live indicator → "Dr. [Name] accepted!" or friendly decline with option to find another doctor) |

**End of Week 5:** The core real-time loop works for the first time across both apps. Patient sends a request → doctor sees it live → doctor responds → patient's screen updates live.

### Week 6 — 22–26 Sep · ✅ Done

| Date | Task |
|---|---|
| Mon 22 Sep | Backend: Razorpay order creation + webhook handling + payment record; Patient app: Razorpay payment sheet on accept (UPI, card, net banking) → booking confirmed |
| Tue 23 Sep | Patient app: bookings tab (all upcoming + past) + active booking detail (doctor name/photo, ETA, in-app contact, "Doctor is running late" banner, cancel with policy) |
| Wed 24 Sep | Patient app: video call screen for online consultations (Agora/100ms — full-screen, end-call, mute, camera-toggle; call session logged) |
| Thu 25 Sep | Patient app: visit-complete screen + procedure bill (doctor-ticked items at pre-listed rates; senior-review wait if triggered); rating screen (1–5 stars + written review) |
| Fri 26 Sep | Patient app: booking history + history detail + patient profile + submit complaint (goes to admin inbox with full booking context); buffer |

**Phase 2 exit:** A patient can browse → book → pay → attend a visit or video call → see the procedure bill → rate the doctor → view history → submit a complaint. Patient app is done.

---

## Phase 3 — Doctor App

**29 Sep – 17 Oct 2026 (Days 31–45) · Upcoming**

*Goal: doctor app is fully working — onboard, get verified, configure a live practice, receive patient requests, treat, bill, and earn.*

### Week 7 — 29 Sep – 3 Oct · Doctor Onboarding

| Date | Task |
|---|---|
| Mon 29 Sep | Doctor app: profile setup (name, specialty dropdown ~15 types, profile photo, bio) |
| Tue 30 Sep | Doctor app: document verification submission (medical licence + degree certificate, up to 10 MB); "Verification Pending" screen while team reviews |
| Wed 1 Oct | Doctor app: consultation type selection (Online / Home Visit / Both — controls which setup screens follow) |
| Thu 2 Oct | Doctor app: weekly schedule + service-radius setup (Mon–Fri 9am–6pm, lunch break, radius 2/3/5 km, drop-a-pin base location) |
| Fri 3 Oct | Doctor app: pricing setup (base 15-min fee, extra-15-min rate, procedure price catalogue, senior-review threshold) |

**End of Week 7:** A doctor can sign up, upload verification documents, choose consultation type, set schedule, and configure pricing.

### Week 8 — 6–10 Oct · Requests & Visits

| Date | Task |
|---|---|
| Mon 6 Oct | Doctor app: requests tab (live incoming requests via Supabase Realtime — new requests slide in without refresh; red badge count; newest-first) |
| Tue 7 Oct | Doctor app: request detail (patient name, slot, consultation type, intake form, photos, voice transcript inline, AI summary) + Accept/Decline buttons (decline requires brief reason) |
| Wed 8 Oct | Doctor app: clarification video call screen (before accepting — tap "Call patient"; Agora/100ms; post-call notes saved to booking) |
| Thu 9 Oct | Doctor app: active visit screen (patient address + Navigate button, in-app contact, "Running late" button → patient notified, visit timer) |
| Fri 10 Oct | Doctor app: procedure checklist + running bill total (real-time update as items ticked; senior-review banner if threshold crossed; "Mark Visit Complete") |

**End of Week 8:** A doctor can receive a live patient request, review the intake, make a clarification call, accept, navigate to the patient, and complete a visit with a procedure bill.

### Week 9 — 13–17 Oct · Earnings, Polish & Doctor App Done

| Date | Task |
|---|---|
| Mon 13 Oct | Doctor app: earnings tab (completed visits + procedure line items + "Awaiting senior review — ₹X" + running total) |
| Tue 14 Oct | Doctor app: schedule/calendar tab (week view — Open / Booked / Blocked slots; block-time flow) + profile tab (re-edit all settings, verification status card, logout) |
| Wed 15 Oct | Backend + doctor app: FCM push notifications (new patient request, payment confirmed, senior-review decision) — fires even when app is in background |
| Thu 16 Oct | Doctor app: senior-review end-to-end flow test (high-value bill triggers review → admin approves or flags → earnings tab updates in real time) |
| Fri 17 Oct | Buffer + complete doctor-app E2E test: scripted fake patient → request arrives live → clarification call → accept → visit → procedure bill (including one above senior-review threshold) → earnings updated → all push notifications fire |

**Phase 3 exit:** A doctor can onboard, get verified, configure a live practice, receive requests, complete visits with procedure bills (including senior review), and see confirmed earnings. Doctor app is fully done.

★ **Doctor onboarding begins here (17 Oct+).** The doctor app is ready to go live independently. Real doctors who registered via the website (live since 22 Aug) can now log into the app — their profile is pre-filled. Verified doctors build up the directory before any patient books.

---

## Backend — completed ahead of schedule

**Delivered 19 Sep 2026 · originally scheduled 20–31 Oct (Days 46–55)**

The backend is feature-complete against V1 scope. Every external service sits
behind an environment variable with the code path already written and tested, so
switching one on is a config change rather than a build task.

| Area | What was built |
|---|---|
| Authentication | OTP storage moved from process memory into the `otp_codes` table — survives restarts, works across multiple workers, codes stored hashed. Shared rate limiting. |
| Notifications | Complete dispatch layer with 20 product events wired into the routers that own each transition. Previously nothing in the backend ever sent a notification. Every event is recorded in-app whether or not FCM is live. |
| Doctor payouts | New commission and settlement model: ledger entries per confirmed payment, per-doctor commission override, bank accounts, payout runs, manual adjustments. None of this existed before — earnings were displayed but no money could move. |
| Payments | Real Razorpay path, mandatory webhook signature verification, failed-payment retry window, idempotent confirmation, procedure-bill payments. |
| Booking edge cases | Payment holds with automatic slot release, no-show (charging nobody), running-late notices, cancellation attribution. |
| Directory management | Doctor suspension that removes a listing from search, deep links and new bookings while preserving the account. |
| Admin | Single-call dashboard metrics, full doctor list, suspension, ops audit trail. |
| Operations | `/readyz` deep health check reporting which integrations are live, scheduled-job endpoints behind a shared secret, non-root container, health-checked Fly config, tightened CORS. |
| Tests | 57 → 227 passing. Auth, payments, payouts and admin had no test coverage at all; all four are now covered, including the money-safety properties. |

**Two follow-ups before this is live**, both documented in
`docs/runbooks/backend_go_live.md`:

1. Apply migrations `0007_phase4_backend.sql` and `0008_phase4_rls.sql` in the
   Supabase SQL editor (no CLI access on the build machine; both are idempotent).
2. Set the integration credentials — MSG91, Razorpay, FCM, Agora — plus
   `CRON_SECRET` for the scheduled jobs.

Endpoint-level notes for the UI work are in `docs/backend_api_additions.md`.

---

## Phase 4 — Integration, Admin Panel & Launch

**20 Oct – 31 Oct 2026 (Days 46–55) · Upcoming**

*Goal: both apps stress-tested together, admin panel operational, live services switched on, product ready for Android beta.*

### Week 10 — 20–24 Oct · Cross-App Testing + Admin Panel

*Backend work for this week is already done (see above). What remains is device
testing, credential switch-on, and the admin panel front end.*

| Date | Task |
|---|---|
| Mon 20 Oct | Cross-app end-to-end test on real Android devices: patient sends request → doctor sees it live → accepts → patient pays → doctor visits and bills → senior review → doctor earns → patient rates. Also test: doctor declines, patient cancels, both apps lose internet mid-visit, two patients try to book the same slot simultaneously |
| Tue 21 Oct | Admin dashboard: doctor verification queue (pending registrations from website + doctor app in one unified view; preview documents in-browser; Approve/Reject → doctor goes live immediately + receives push notification) |
| Wed 22 Oct | Admin dashboard: bookings monitor (live table, all statuses) + complaint inbox (patient grievances with full booking context, status open/in-progress/resolved) + directory management (suspend/remove a listing) |
| Thu 23 Oct | Switch to live services: set MSG91, Razorpay, FCM, Agora and `CRON_SECRET` per `docs/runbooks/backend_go_live.md` (code paths already built and tested); test a real end-to-end payment and confirm a payout reaches the bank account |
| Fri 24 Oct | Push notification polish: test every scenario (new request, accept, payment, senior review, running late). Edge-case handling: payment fails → hold booking 10 min with retry; no-show → mark without charging |

**End of Week 10:** Admin panel is live. Real OTP sending. Real payments processing and reaching the bank account. A team member can verify doctors in one click.

### Week 11 — 27–31 Oct · Bug Fixes, Store Listings & Beta Launch

| Date | Task |
|---|---|
| Mon 27 Oct | Bug-fix sprint: fix all issues from cross-app testing. Performance: API targets under 300 ms; large file upload; slot race conditions. Test on ₹8,000–₹15,000 Android devices (primary Indian user segment) |
| Tue 28 Oct | Play Store listings: icon, name, 5–8 screenshots per app, short + long descriptions, content rating, privacy policy URL (charak.in/privacy). Generate signed Android release builds (AAB) and upload to Play Console under Closed Testing |
| Wed 29 Oct | Seed first doctor accounts (early-user doctors who agreed to be in beta). Write rollout plan (beta tester count, geographies, feedback method) |
| Thu 30 Oct | Final release builds after last-minute fixes. Handoff checklist: all credentials documented, monitoring active, support email live, backup schedule confirmed |
| Fri 31 Oct | **Beta pilot live.** Both apps on Google Play (Closed Testing). Real doctors on doctor app, real patients on patient app. Real OTP, real payments, admin verification working. Product ready for first real users |

**Phase 4 exit:** Both apps live in Android beta. Doctors verifiable through admin panel. Real OTP and real payments operational. Full cross-app loop verified on real devices with real money. Product ready for first real users.

---

## Notes

**Website advantage:** doctors who registered on charak.in before the app launched have their profile pre-filled in the doctor app — same Supabase tables, same phone number, no re-entry. This gives a base of registered doctors ready to be verified before the patient app ships.

**Why patient app first:** the patient booking and payment flow is validated end-to-end before the doctor app layers on top. The shared `charak_core` package and backend are built once in Phase 1 and consumed by both apps.

**Buffer days:** 22 Aug, 5 Sep, 12 Sep, 26 Sep, 17 Oct, and 31 Oct are built-in buffers. Pull from them if any task in the preceding stretch runs long.

**Banked buffer:** the Phase 4 backend workload finished on 19 Sep against a
20–31 Oct schedule. That time is deliberately held in reserve rather than used to
pull the beta date forward — the remaining risk sits in real-device testing, live
payment behaviour and Play Store review, none of which compress well. Checkpoint
dates stay as committed.

**iOS deferred:** only Android ships within these 55 days. iOS follows after Android beta validation.

**Senior review:** bills above the doctor's configured threshold are flagged before payment releases. The state machine (Pending → Under Review → Approved/Flagged → Paid) is built in Phase 1 backend and surfaced in both apps.
