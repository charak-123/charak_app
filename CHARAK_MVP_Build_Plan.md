# CHARAK — MVP Build Plan

**53 working days · solo developer · two Flutter apps + shared backend · doctor app first**

## The whole build at a glance

```
FOUNDATION ──► DOCTOR APP ──► PATIENT APP ──► SHIP
   (shared)      (first)        (second)      (launch)
```

The **backend + `charak_core` shared package** are the spine running through everything — built once up front, then both apps plug into it. Doctor app is built and finished first; the Patient app reuses the exact same backend, so the two apps "talk" through it (no direct app-to-app link, ever).

## Timeline

| # | Phase | Days | What happens |
|---|---|---|---|
| 1 | **Foundation** | 1–15 | Monorepo, backend, Supabase schema, shared package, OTP auth. Then **Doctor app: onboarding + practice setup** (channels, schedule, radius, pricing, procedures). |
| 2 | **Doctor app** | 16–30 | **Doctor app: requests & fulfillment** — live requests, accept/decline, clarification call, procedure checklist, senior review, earnings. Doctor app is done here. |
| 3 | **Patient app** | 31–45 | **Patient app: everything** — browse → book → intake → pay → visit → procedure bill → rate → history → complaints. |
| 4 | **Ship** | 46–53 | Cross-app realtime wiring, admin/ops dashboard, real OTP + payments, store listings, beta pilot. |

## The "connected stuff" (shared spine — one build, two apps)

- **Backend** (NestJS/FastAPI + PostgreSQL/Supabase) — single source of truth
- **`charak_core`** shared Flutter package — API client, models, auth, design tokens
- **Supabase Realtime** — the live link (request → accept/decline → pay → complete → senior review)
- **Razorpay** (payments), **Agora/100ms** (video), **Whisper + LLM** (voice transcript), **FCM** (push)

## The four checkpoints (what "done" means at each gate)

1. **Day 15** — a doctor can onboard, verify, and configure a live practice.
2. **Day 30** — doctor can accept/decline, fulfill a visit, bill procedures + senior review.
3. **Day 45** — a patient can browse → book → pay → get treated → rate, end-to-end.
4. **Day 53** — both apps in Android beta, real OTP + payments, admin can verify doctors, live loop verified.

---

# Full Plan

**Assumptions:** solo developer · 53 working days · MVP scope (V1 features only) · tech stack fixed from the Requirements Doc (Flutter + `charak_core` monorepo, NestJS/FastAPI + Supabase, Razorpay, Agora/100ms, Whisper, FCM, React admin) · mockups already done (week 0, not counted).

**Sequencing rationale:** backend + `charak_core` are the shared foundation both apps sit on, so they come first. Doctor app is built to a fully working state against that backend (patient side simulated via scripted API calls), then the Patient app is built reusing the same backend — so the cross-app realtime loop is wired once, not twice.

## Chunk 1 — Foundation + Doctor App: Onboarding & Practice Setup (Days 1–15)

**Exact goal:** a doctor can sign up, submit verification, and fully configure a live practice (channels → schedule/radius → pricing → procedure catalog → senior-review threshold). Backend + Supabase schema + `charak_core` are solid, and both app shells exist.

| Day | Task |
|---|---|
| 1 | Monorepo scaffold (`apps/patient_app`, `apps/doctor_app`, `packages/charak_core`, `backend/`); design tokens → `charak_core/design`; CI + lint |
| 2 | Supabase project; Postgres migration for all §6 entities (users, doctors, categories, doctor_pricing, doctor_procedures, doctor_schedules, doctor_slot_blocks, bookings, procedure_bills, intake_media, clarification_calls, payments, ratings, complaints) |
| 3 | Backend skeleton (auth module, DB client, error handling); `charak_core` api_client + models + auth |
| 4 | OTP auth (patient + doctor) — Supabase phone auth + SMS provider stub; JWT session handling |
| 5 | Doctor app: Splash / Phone / OTP screens wired to auth |
| 6 | Doctor app: Profile Setup (name, specialty, photo, bio) + storage for photo |
| 7 | Doctor app: Verification Submission (license + cert upload) + Verification Pending screen |
| 8 | Backend: CRUD for categories, pricing, procedures, schedules, slot blocks; seed category list |
| 9 | Doctor app: Channel Setup (online / home / both) |
| 10 | Doctor app: Online Consult Setup (weekly schedule editor) + Home Visit Setup (schedule + radius 2/3/5 + base location) |
| 11 | Doctor app: Pricing Setup (base 15-min fee + extra-15-min rate + procedure catalog + senior-review threshold + live preview) |
| 12 | Doctor app: Profile tab + re-edit entries for channels/schedule/radius/pricing; slot blocking |
| 13 | Backend: slot-availability calc (recurring − blocked − booked) + unit tests |
| 14 | Doctor app: Schedule tab (week view: booked/open/blocked) + full block-time flow |
| 15 | Buffer + integration check: onboard → verify → configure → "go live" |

**Exit:** doctor reaches "live in directory"; schedule tab reflects template + blocks; backend + shared package stable.

## Chunk 2 — Doctor App: Requests & Fulfillment (Days 16–30)

**Exact goal:** full doctor-side MVP — live incoming requests, intake review, accept/decline, clarification call, visit fulfillment with procedure checklist, senior review, earnings.

| Day | Task |
|---|---|
| 16 | Backend: bookings endpoints (list-for-doctor, accept/decline, status) + Supabase Realtime channel |
| 17 | Doctor app: Requests Tab (live slide-in, new/unread badges, newest-first) |
| 18 | Doctor app: Request Detail (typed/voice-transcript/photo/video inline, visit details) + Accept/Decline |
| 19 | Backend: intake_media + transcript retrieval wired to storage |
| 20 | Backend: clarification_calls + Agora/100ms token generation (shared: clarify + consult) |
| 21 | Doctor app: Clarification Call screen (video + freeform notes → `clarification_calls.notes`) |
| 22 | Doctor app: Active Visit (patient info, payment banner, navigate, contact-through-app) |
| 23 | Doctor app: Active Visit — procedure checklist + running total + senior-review banner + Mark Complete |
| 24 | Backend: `procedure_bills` on complete + senior-review state machine (pending → under_review → approved → paid) |
| 25 | Doctor app: Earnings Tab (completed list + procedure lines + "awaiting senior review" + total) |
| 26 | Backend: earnings aggregation + ratings-received passthrough |
| 27 | Doctor app: senior approve/flag simulation → earnings updates |
| 28 | Backend: FCM push (new request, payment, senior review) |
| 29 | Doctor app: Profile polish (verification card, re-edit dials, logout) |
| 30 | Buffer + doctor-app E2E test via scripted fake patient |

**Exit:** doctor can accept/decline, clarify, fulfill a home visit with procedures + senior review, and see earnings; realtime new-request + push working.

## Chunk 3 — Patient App (Days 31–45)

**Exact goal:** full patient-side MVP — browse → book → multi-modal intake → live accept/decline → pay → fulfill (call / visit + procedure bill) → rate → history → complaint.

| Day | Task |
|---|---|
| 31 | Patient app: Splash / Phone / OTP / Name Entry (reuse `charak_core` auth) |
| 32 | Patient app: Home (greeting, search, specialty grid) + Directory (filter chips, sort) |
| 33 | Backend: directory search/filter (category, channel, radius, price, availability) |
| 34 | Patient app: Doctor Profile (verification, rating, fees base+extra, procedure prices + senior-review note) |
| 35 | Patient app: Slot Selection (date strip + time grid) + Channel Confirmation (address-in-radius) |
| 36 | Patient app: Intake Form — text + photo/video attach (storage) |
| 37 | Backend: voice upload + Whisper transcription + Claude/GPT summary; intake voice recording + editable transcript |
| 38 | Patient app: Review & Confirm (procedure-billing note) + Send Request → Request Sent |
| 39 | Backend: request write + realtime push to doctor; patient subscribes to own booking row |
| 40 | Patient app: Booking Accepted / Declined live (decline → find another doctor) |
| 41 | Backend: Razorpay order/webhook/payments; Patient app: Payment sheet + Booking Confirmed |
| 42 | Patient app: Bookings Tab + Active Booking Detail (join call / ETA / contact / running-late / cancel) |
| 43 | Patient app: Video Call (Agora/100ms, reuse doctor call UI) |
| 44 | Patient app: Visit Complete + Procedure Bill (fixed rates, senior-review wait, pay) + Rating |
| 45 | Patient app: History + History Detail + Profile + Submit Complaint + buffer |

**Exit:** full patient MVP; browse→pay works; procedure bill + senior review; rating + complaints work.

## Chunk 4 — Integration, Admin/Ops, Launch (Days 46–53)

**Exact goal:** ship-ready MVP — cross-app live loop verified, admin/ops dashboard, launch/ops checklist done, beta pilot ready.

| Day | Task |
|---|---|
| 46 | Cross-app realtime E2E test (both apps running; accept/decline/pay/complete/senior-review) |
| 47 | Admin dashboard: doctor verification queue (approve/reject → realtime unlock) |
| 48 | Admin dashboard: bookings monitor + complaint inbox + directory oversight |
| 49 | Live config: SMS OTP provider (Twilio/MSG91) + Razorpay business entity/bank account |
| 50 | Push polish (accept/decline, payment, senior review, reminders) + edge cases (decline, cancel, no-show) |
| 51 | QA/bug-fix: realtime reconnect, upload size, slot race conditions, performance |
| 52 | Play Store + App Store listings (both apps) + privacy policy; Android release build |
| 53 | Beta pilot prep: seed doctors, rollout plan, handoff; final release build |

**Exit:** both apps in beta (Android-first), doctors verifiable via admin, real OTP + payments live, realtime loop verified.

---

## Risks / notes

- **Realtime is the cross-app spine** — it's built in Chunk 2 (doctor) and consumed in Chunk 3 (patient); the one place a solo sequential build can bite is if the backend contract drifts between the two, so pin the API contract in `charak_core` early (Day 3) and don't change it.
- **iOS deferred** — Android-first pilot (per §8.2) saves the Apple $99/Mac/Xcode work for after validation; only Android release is in the 53 days.
- **Days 15/30/45/53 are buffers** — pull from them if any screen overruns.
- **Launch/ops checklist** (from Requirements Doc §8): SMS OTP provider, Razorpay business entity + bank account, Play Store / App Store listings + privacy policy, doctor verification workflow — all scheduled in Chunk 4 (Days 49–53).
