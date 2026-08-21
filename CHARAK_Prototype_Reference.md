# CHARAK — Prototype Reference Doc

**Purpose:** working reference for building the Patient App and Doctor App prototypes in opencode + opendesign. Covers the design system, visual references, and every screen — its goal, where it sits in the flow, and what UI elements it needs.

**Scope:** V1 only (see the App Requirements Document for full functional/technical scope). Two independent apps, one shared design system.

---

## 1. Design Direction

**The brief:** somewhere between *minimal, reliable* and *modern, premium*. Not sterile-hospital-clinical, not startup-flashy. Think: a product you'd trust with your parent's health data, that also doesn't look like it was built in 2016.

**Reference feeling:** closer to a well-designed banking app (Revolut, Mercury) crossed with a calm health app (Headspace's restraint, Ada Health's clarity) — confident whitespace, one accent color doing all the work, no visual noise competing with the content.

### 1.1 Color System

White + a soothing blue as the two theme colors, kept genuinely minimal — no third "hero" color.

| Token | Hex | Usage |
|---|---|---|
| `--color-bg` | `#FFFFFF` | Primary background, all screens |
| `--color-bg-subtle` | `#F5F8FA` | Section backgrounds, cards-on-cards, input fields |
| `--color-primary` | `#2F6FED` | Primary buttons, active states, links, selected chips |
| `--color-primary-soft` | `#EAF1FE` | Selected backgrounds, info banners, badge fills |
| `--color-primary-deep` | `#1E4FBF` | Pressed states, primary text on primary-soft backgrounds |
| `--color-ink` | `#101828` | Primary text |
| `--color-ink-muted` | `#5B6472` | Secondary text, captions, placeholder text |
| `--color-border` | `#E4E8EE` | Dividers, input borders, card borders |
| `--color-success` | `#1FAA6D` | Booking accepted, payment success, verified badge |
| `--color-warning` | `#E0930B` | Pending states, clarification-call notice |
| `--color-danger` | `#E0473E` | Declined, cancelled, errors, destructive actions |

**Why this palette:** a single blue carries every "this is interactive / this is CHARAK" moment, so it never competes with itself. Success/warning/danger are desaturated enough to sit quietly next to the blue rather than turning the UI into a traffic light. No gradients, no glassmorphism — flat fills and soft shadows only, which is what keeps this reading "reliable" rather than "trendy."

### 1.2 Typography

| Role | Suggested typeface | Notes |
|---|---|---|
| Display / headings | **Inter** (or **General Sans**) | Geometric-humanist sans, reads premium without being cold. Semibold/600 for headings. |
| Body | **Inter** | Same family throughout — one typeface, weight does the differentiating. Regular/400 body, Medium/500 for emphasis. |
| Numerals (price, time, OTP) | **Inter, tabular figures** | Tabular lining figures so prices and countdown timers don't jitter as digits change. |

**Type scale (base 16px):**

| Style | Size | Weight | Line height |
|---|---|---|---|
| Display | 28px | 600 | 1.2 |
| H1 (screen title) | 22px | 600 | 1.3 |
| H2 (section header) | 17px | 600 | 1.4 |
| Body | 15px | 400 | 1.5 |
| Body Medium | 15px | 500 | 1.5 |
| Caption | 13px | 400 | 1.4 |
| Micro (badges, timestamps) | 11px | 500, uppercase, +0.04em tracking | 1.3 |

### 1.3 Spacing, Radius, Elevation

- **Spacing unit:** 4px base. Common gaps: 8 / 12 / 16 / 24 / 32.
- **Corner radius:** 12px for cards, 10px for buttons/inputs, 100px (pill) for chips/badges/tags. Consistent rounding is a big part of reading "modern premium" — avoid mixing sharp and round in the same screen.
- **Elevation:** soft, low-contrast shadows only (`0 2px 8px rgba(16,24,40,0.06)` for resting cards, `0 8px 24px rgba(16,24,40,0.12)` for sheets/modals). No hard drop shadows, no borders + shadows stacked on the same element — pick one per surface.
- **Touch targets:** minimum 44×44px, consistent with both iOS HIG and Material.

### 1.4 Motion & Animation

Motion should feel **confirming, not decorative** — every animation exists to tell the user something happened, never just to look nice.

| Interaction | Animation | Duration | Easing |
|---|---|---|---|
| Screen transition (push) | Slide from right, slight fade-in of incoming screen | 280ms | ease-out |
| Sheet/modal open | Slide up from bottom + backdrop fade | 240ms | ease-out |
| Button press | Scale to 0.97 + opacity 0.9 | 100ms | ease-in-out |
| Booking status change (live update) | Cross-fade old → new state, brief highlight pulse on the changed element (primary-soft flash, fades over 600ms) | 600ms | ease-out |
| Success confirmation (payment, booking accepted) | Checkmark draws in (stroke animation), scale-in 0.9→1 | 400ms | spring (light bounce, damping ~0.8) |
| Loading | Skeleton screens (shimmer), never spinners for content that has a known shape | — | continuous, subtle |
| Pull-to-refresh (directory, history lists) | Standard platform pull-to-refresh | — | platform default |
| Realtime "new request" arrival (Doctor App) | New card slides in from top of list + soft haptic tap | 320ms | ease-out |

**Principle:** nothing bounces or spins just for delight. The one place a slightly more expressive animation is earned is the booking-accepted / payment-success moment — that's the emotional peak of the flow and can feel a little more alive than the rest of the app.

### 1.5 Component Style Notes

- **Buttons:** solid primary-blue fill for the main action, ghost/outline for secondary, text-only for tertiary. No skeuomorphism, no gradients.
- **Cards:** white fill, 1px `--color-border` OR soft shadow — not both. Doctor cards, booking cards, and history cards should all share the same card shell so the app feels like one system.
- **Chips/tags:** pill-shaped, used for specialty labels, channel labels (Online/Home Visit), and status badges (Requested/Accepted/Declined/Completed).
- **Status badges:** color-coded using the tokens above (warning=pending, success=accepted/completed, danger=declined/cancelled) — always paired with text, never color-only, for accessibility.
- **Empty states:** simple line-art illustration in primary-blue-on-white, one line of reassuring copy, one clear action. Avoid stock illustration packs that don't match the rest of the UI.

---

## 2. Design References

Specific apps to pull from, and specifically *what* to borrow from each — not "make it look like X," but the particular pattern worth stealing.

| App | Borrow this specifically | Don't borrow |
|---|---|---|
| **Uber (Rider app)** | The booking-confirmation screen's calm certainty — big status text, clear next step, no clutter. The way price is shown upfront and confirmed, never ambiguous. | Uber's dense, map-first home screen — CHARAK's home is a directory/list, not a map. |
| **Uber (Driver app)** | The incoming-request card pattern — new requests slide in, key info (name, distance/time, price) visible without a tap, accept/decline as two clear thumb-reach buttons. <cite index="1-1">Recent Uber Driver updates show trip details upfront on the request card itself</cite> — CHARAK's doctor request card should do the same with patient's category, price, and slot. | Uber's real-time map/routing UI — not relevant, CHARAK has no live dispatch. |
| **Practo** | The specialty-first directory browsing pattern (filter by category before anything else), and the doctor profile card's information hierarchy (photo, name, specialty, rating, price all scannable in one glance). | Practo's very dense doctor-listing screens — CHARAK should feel airier, fewer cards visible at once, more whitespace per card. |
| **Calendly** | The slot-picker UI — calendar + time-slot list side by side (or stacked on mobile), immediately clear what's available vs. booked. | Calendly's generic, brand-neutral visual style — CHARAK needs its own color identity, not Calendly's default blue-on-white template feel. |
| **Headspace** | Restraint — large type, one idea per screen, generous whitespace, calm color use. This is the single best reference for CHARAK's *overall pacing*, even though the product category is unrelated. | Headspace's illustration-heavy, playful visual language — too whimsical for a medical booking context. |
| **Ada Health / a modern symptom-checker app** | The intake flow's step-by-step, one-question-at-a-time pacing, and how it handles multi-modal input (text + attachment) without feeling like a form. | Any diagnostic/AI-suggestion UI patterns — CHARAK's intake is descriptive only, never diagnostic, so avoid anything that visually implies the app is "figuring out" what's wrong. |
| **Revolut / Mercury (banking apps)** | The overall premium-but-restrained visual tone — confident typography, generous spacing, a single accent color used sparingly and consistently. This is the best reference for the *general vibe* the brief is asking for. | Financial-specific patterns like balance charts — not applicable here. |

---

## 3. Information Architecture

### 3.1 Patient App — Top-Level Navigation

Bottom tab bar, 4 tabs:

1. **Home** (directory/browse)
2. **Bookings** (active + upcoming)
3. **History** (past visits, ratings, receipts)
4. **Profile** (account, saved info)

### 3.2 Doctor App — Top-Level Navigation

Bottom tab bar, 4 tabs:

1. **Requests** (incoming, needs action — default landing tab)
2. **Schedule** (calendar, availability, slot management)
3. **Earnings** *(V1: simplified — just a completed-bookings list with amounts; full dashboard is V2)*
4. **Profile** (account, verification status, channel/pricing settings)

---

## 4. Patient App — Screens

### 4.1 Onboarding & Auth

**Screen: Splash**
- **Goal:** brand moment, check auth state, route accordingly.
- **Flow:** App open → Splash (auto, ~800ms) → Phone Entry (if logged out) or Home (if logged in).
- **UI elements:** Centered logo/wordmark on white, primary-blue background wash or plain white — keep it under a second, this is not a place for elaborate animation.

**Screen: Phone Entry**
- **Goal:** collect phone number to start OTP flow.
- **Flow:** Splash → here → OTP Verification.
- **UI elements:** Single phone input (country code pre-filled +91), large primary button ("Continue"), minimal copy. Keyboard should auto-focus on load.

**Screen: OTP Verification**
- **Goal:** verify phone via OTP, matching `users.otp_verified` from the data model.
- **Flow:** Phone Entry → here → Name Entry (first-time) or Home (returning user).
- **UI elements:** 6-digit OTP input (auto-advancing boxes), countdown timer for resend ("Resend in 0:28"), auto-read/autofill support on both platforms.

**Screen: Name Entry** *(first-time only)*
- **Goal:** collect `users.name`.
- **Flow:** OTP Verification (first-time) → here → Home.
- **UI elements:** Single text input, primary button. This is the entire onboarding form — resist adding more fields here.

### 4.2 Home / Directory

**Screen: Home (Category Select)**
- **Goal:** patient picks a specialty to start booking — this is the true entry point of the core loop.
- **Flow:** Home tab → here (default view) → Directory List.
- **UI elements:** Grid or horizontally-scrollable row of specialty chips/cards (General Physician, Orthopedic, Nurse, Cardiology, Dermatology, Gynecology, Pediatrics, Dentistry, Physiotherapy, +more), each with a simple icon. Search bar above the grid for direct doctor/specialty search. Greeting header ("Hi, [Name]") kept small and secondary — the specialties are the actual content.

**Screen: Directory List**
- **Goal:** browse doctors within a chosen specialty, filtered by radius/price/availability.
- **Flow:** Home (Category Select) → here → Doctor Profile.
- **UI elements:** Filter bar (channel: Online/Home Visit/Both, sort by price/rating/distance), doctor cards in a vertical list — each card: photo, name, specialty, rating (stars + count), price, next available slot, channel badges. Sticky filter bar on scroll.

**Screen: Doctor Profile**
- **Goal:** patient reviews a specific doctor before booking.
- **Flow:** Directory List → here → Slot Selection.
- **UI elements:** Photo, name, specialty, verification badge (ties to `doctors.verification_status`), rating summary, bio/credentials text, price per channel (base 15-min consult + extra-time rate), service radius (if Home Visit offered), the doctor's fixed procedure-price list with the senior-review note for home-visit bills above their threshold, "Book" primary button (sticky at bottom).

### 4.3 Booking Flow

**Screen: Slot Selection**
- **Goal:** patient picks a specific date + time slot for the chosen doctor.
- **Flow:** Doctor Profile → here → Channel Confirmation (if doctor offers both) → Intake Form.
- **UI elements:** Calendar/date strip (horizontally scrollable dates) + time-slot grid below (per Calendly reference in Section 2), unavailable slots visually greyed and non-interactive, selected slot highlighted in primary-blue.

**Screen: Channel Confirmation** *(only if doctor offers both Online + Home Visit)*
- **Goal:** confirm Online Consult vs. Home Visit for this specific booking.
- **Flow:** Slot Selection → here → Intake Form.
- **UI elements:** Two large tappable cards (Online Consult / Home Visit), each showing its price (base 15-min consult) and extra-time rate, brief description, and (for Home Visit) confirming the patient's address falls within the doctor's radius.

**Screen: Intake Form**
- **Goal:** patient describes the issue — voice, text, video, or images (Section 3.6 of the Requirements Doc).
- **Flow:** Slot/Channel Selection → here → Review & Confirm.
- **UI elements:** Segmented input-type selector (Text / Voice / Photo / Video tabs), large text area for typed description, mic button with waveform visualization while recording (voice auto-transcribes — show the transcript inline once done, editable), photo/video attach button with thumbnail preview strip. Persistent reassurance microcopy near the media upload area: "Reviewed by your doctor directly — never analyzed by AI" (reinforces the hard AI boundary from the Requirements Doc, Section 3.6/3.8).

**Screen: Review & Confirm**
- **Goal:** final check before submitting the request — doctor, slot, price, intake summary.
- **Flow:** Intake Form → here → Request Sent (Pending).
- **UI elements:** Summary card (doctor, date/time, channel, price), intake preview (collapsed, expandable), primary button "Send Request." For Home Visit, the summary carries a note that procedures are billed after the visit at the doctor's fixed rates, with a senior-doctor review for bills above the doctor's threshold.

**Screen: Request Sent (Pending)**
- **Goal:** confirm the request went out; set expectation that the doctor needs to review it — this is the screen that must clearly communicate "not confirmed yet" (Requirements Doc, Section 4.1: "Doctor review is not automatic acceptance").
- **Flow:** Review & Confirm → here → (live update via Realtime) → Booking Accepted or Booking Declined.
- **UI elements:** Warm, calm waiting-state illustration or icon, status badge ("Pending doctor review," warning-color), doctor's name/photo, estimated response expectation copy if available, subtle pulsing animation on the status badge to indicate it's live/waiting (not stuck).

**Screen: Booking Accepted**
- **Goal:** the emotional high point — confirm the booking is real, show what's next.
- **Flow:** arrives via Realtime push from Request Sent (Pending) → here → Payment.
- **UI elements:** Success animation (checkmark draw-in, per Section 1.4), booking summary, primary button "Pay Now." This transition should use the more expressive animation treatment noted in the motion section.

**Screen: Booking Declined**
- **Goal:** soften the rejection, redirect to another doctor — mirrors "Decline sends the patient back to the directory, not a dead end" (Requirements Doc, Section 4.1).
- **Flow:** arrives via Realtime push from Request Sent (Pending) → here → Directory List (same specialty, pre-filtered).
- **UI elements:** Neutral (not alarming) icon, brief explanatory copy, primary button "Find another doctor" leading straight back into the same specialty's directory.

**Screen: Payment**
- **Goal:** collect payment for the confirmed booking (Razorpay — UPI + cards).
- **Flow:** Booking Accepted → here → Booking Confirmed (final).
- **UI elements:** Standard Razorpay checkout sheet (native SDK UI — minimal custom design needed here beyond entry point styling), price breakdown above the payment sheet trigger.

**Screen: Booking Confirmed**
- **Goal:** final confirmation screen, entry point into the "active booking" state.
- **Flow:** Payment → here → (on visit day) Active Booking screen.
- **UI elements:** Confirmation summary, "Add to calendar" action, doctor contact-adjacent info (not raw phone number — handled through app), link to Bookings tab.

### 4.4 Active Booking & Fulfillment

**Screen: Bookings Tab (List)**
- **Goal:** see all active/upcoming bookings at a glance.
- **Flow:** Bottom tab → here → Active Booking Detail.
- **UI elements:** List of booking cards, each with status badge, doctor, date/time, channel icon.

**Screen: Active Booking Detail**
- **Goal:** everything needed for an imminent or in-progress visit.
- **Flow:** Bookings Tab → here → (Online Consult) Video Call screen, or (Home Visit) stays here through visit.
- **UI elements:** For Online Consult — "Join Call" primary button (enabled starting ~5 min before slot), countdown to slot time. For Home Visit — doctor's ETA-adjacent info if available, address confirmation, doctor contact-through-app button. Both — "Request Clarification Call" secondary action if the doctor initiates one (Requirements Doc: clarification call is doctor-initiated, but the patient-side screen should show it clearly if scheduled).

**Screen: Video Call** *(Online Consult)*
- **Goal:** conduct the consult.
- **Flow:** Active Booking Detail → here → Rating.
- **UI elements:** Standard video call UI (Agora/100ms SDK — camera preview, mute/camera-toggle/end-call controls), doctor name overlay, call duration timer.

**Screen: Visit Complete**
- **Goal:** transition from active visit to rating.
- **Flow:** Video Call ends, or Home Visit marked complete by doctor → here → Procedure Bill (if procedures were done) or Rating.
- **UI elements:** Simple confirmation, "Rate your visit" primary button.

**Screen: Procedure Bill** *(Home Visit only — shown when the doctor marked procedures done during the visit)*
- **Goal:** show the patient what procedures were done and their fixed-rate cost, charged after the visit — the consult fee was already paid at confirmation.
- **Flow:** Visit Complete → here → (senior review if the bill is above the doctor's threshold) → Pay procedure bill → Rating / History.
- **UI elements:** List of procedures performed with their fixed rates, consult fee shown as already paid, procedures total, and — when the bill is above the doctor's threshold — an "Under senior review" waiting state (warning-color) with the pay button locked until a senior doctor approves or flags the bill. Once approved, a "Pay ₹X" button settles it.

**Screen: Rating**
- **Goal:** collect the 5-star rating (Requirements Doc, Section 3.7).
- **Flow:** Visit Complete → here → History (booking now archived).
- **UI elements:** Large 5-star tap input, optional comment text area, submit button. Skippable but gently encouraged.

### 4.5 History & Profile

**Screen: History Tab**
- **Goal:** browse past bookings.
- **Flow:** Bottom tab → here → Past Booking Detail (receipt, rating given).
- **UI elements:** List similar to Bookings Tab but status is always Completed/Cancelled, grouped by month.

**Screen: Profile Tab**
- **Goal:** account management, entry to complaints.
- **Flow:** Bottom tab → here → Edit Profile / Submit Complaint / Settings.
- **UI elements:** Profile summary card, list-style menu (Edit Profile, Payment Methods, Submit a Complaint, Help, Logout).

**Screen: Submit Complaint**
- **Goal:** file a complaint tied to a booking (Requirements Doc, Section 3.7 — human-ops-handled).
- **Flow:** Profile Tab or Past Booking Detail → here → Confirmation.
- **UI elements:** Booking picker (if not pre-selected), description text area, submit button, clear expectation-setting copy ("A member of our team will review this").

---

## 5. Doctor App — Screens

### 5.1 Onboarding & Verification

**Screen: Splash / Phone Entry / OTP Verification**
- Same pattern as Patient App (Section 4.1) — shared visual language via `charak_core` design tokens, but this is a separate app/flow, not shared code execution.

**Screen: Profile Setup**
- **Goal:** collect doctor's professional profile — name, specialty, photo, bio, credentials.
- **Flow:** OTP Verification (first-time) → here → Verification Submission.
- **UI elements:** Multi-field form (kept to one scrollable screen, not a wizard — doctors are professionals filling this out once, don't over-paginate), category/specialty picker (single-select from the full V1 specialty list), photo upload.

**Screen: Verification Submission**
- **Goal:** submit license/ID for manual ops-side verification (Requirements Doc, Section 3.7).
- **Flow:** Profile Setup → here → Verification Pending → (ops approves) → Channel Setup.
- **UI elements:** Document upload (license number field + photo/PDF upload of certificate/ID), clear copy on what happens next and typical review time.

**Screen: Verification Pending**
- **Goal:** waiting state while ops reviews.
- **Flow:** Verification Submission → here → (async, ops-side) → Channel Setup, unlocked on approval.
- **UI elements:** Status illustration, "Under Review" badge (warning-color), the app should still be explorable (read-only) beyond this screen so the doctor isn't fully blocked — but nothing goes live in the directory until verified.

### 5.2 Practice Setup (Doctor Control Panel)

This maps directly to the "Doctor control panel" from the Explainer Doc — four dials, each its own setup screen.

**Screen: Channel Setup**
- **Goal:** choose Online Consult / Home Visit / both.
- **Flow:** Verification approved → here → Online Consult Setup and/or Home Visit Setup (based on selection) → Pricing Setup.
- **UI elements:** Two large tappable toggle-cards (per the update-banner logic in the Explainer Doc — a cardiologist can simply not select Home Visit), can select one or both.

**Screen: Online Consult Setup** *(if selected)*
- **Goal:** set scheduled availability for video consults.
- **Flow:** Channel Setup → here → Pricing Setup.
- **UI elements:** Weekly recurring-schedule editor (day rows, tap to add time blocks), no "Available Now" toggle in V1 (per the scope note in the Requirements Doc — scheduled slots only).

**Screen: Home Visit Setup** *(if selected)*
- **Goal:** set schedule, radius, base location for home visits.
- **Flow:** Channel Setup → here → Pricing Setup.
- **UI elements:** Same weekly-schedule editor as Online Consult, plus: base location picker (map pin drop or address search), radius selector (2/3/5km — three large tappable preset chips, not a slider, matching the fixed presets in the data model).

**Screen: Pricing Setup**
- **Goal:** set price per category/channel, the procedure catalog, and the senior-review threshold.
- **Flow:** Online/Home Visit Setup → here → Directory Live (Profile complete).
- **UI elements:** Consult-fee input per selected channel (base 15-min price + extra-15-min rate), the doctor's fixed procedure-price list, and the senior-review threshold — procedure bills above it are checked by a senior doctor before the patient pays. A live preview shows exactly what the patient sees on the profile.

**Screen: Slot Blocking** *(ongoing, accessed from Schedule tab)*
- **Goal:** block off one-off unavailable time (vacation, personal time) without touching the recurring weekly template.
- **Flow:** Schedule Tab → here → back to Schedule Tab.
- **UI elements:** Calendar date picker, time-range block for that date, list of currently-blocked dates with a remove action.

### 5.3 Requests & Fulfillment

**Screen: Requests Tab (Incoming List)**
- **Goal:** the doctor's default landing screen — review and act on incoming booking requests.
- **Flow:** App open (post-onboarding) → here (default tab) → Request Detail.
- **UI elements:** Per the Uber Driver reference (Section 2) — cards showing patient's category, requested slot, channel, and price without needing a tap. New requests arrive via Realtime and animate in from the top of the list (per Section 1.4). Sort: newest first, with a subtle unread indicator.

**Screen: Request Detail**
- **Goal:** review the patient's intake before deciding.
- **Flow:** Requests Tab → here → Accept or Decline.
- **UI elements:** Patient's submitted intake (transcript from voice, typed text, photo/video attachments — viewable inline, images/video open full-screen on tap), slot/channel/price summary, "Request Clarification Call" secondary button (optional, doctor-initiated per Requirements Doc Section 4.1), two primary actions at the bottom: Accept / Decline (Accept in primary-blue, Decline as a lower-emphasis outline button — this is a professional decision screen, not a swipe-to-reject pattern).

**Screen: Clarification Call** *(optional)*
- **Goal:** doctor-initiated call before deciding, to ask about equipment/condition.
- **Flow:** Request Detail → here → back to Request Detail (to then Accept/Decline).
- **UI elements:** Same video-call UI as the Patient App's consult call, plus a lightweight freeform notes field visible during/after the call (maps to `clarification_calls.notes` — deliberately freeform, not structured, per the Requirements Doc's design note).

**Screen: Active Visit** *(post-accept)*
- **Goal:** doctor's view during an upcoming/active visit.
- **Flow:** Request Detail (Accept) → here → Mark Complete.
- **UI elements:** For Home Visit — patient address, navigation-launch button (opens native maps app), patient contact-through-app, and a procedure checklist (tap the procedures actually done this visit; running total at the fixed rates) with a senior-review banner when the total is above the doctor's threshold. For Online Consult — "Start Call" button enabled near slot time. "Mark as Complete" primary action once the visit has occurred — for Home Visit this sends the procedure bill to the patient (straight to senior review if above threshold).

### 5.4 Schedule, Earnings, Profile

**Screen: Schedule Tab (Calendar View)**
- **Goal:** see the week/month at a glance — booked slots, open slots, blocked time.
- **Flow:** Bottom tab → here → Slot Blocking or Request Detail (tapping a booked slot).
- **UI elements:** Week view default (day columns, time rows), booked slots shown as filled blocks (color-coded by channel), open slots visually lighter, tap-to-block on empty slots.

**Screen: Earnings Tab** *(V1 simplified)*
- **Goal:** see completed bookings and amounts — full analytics dashboard is V2.
- **Flow:** Bottom tab → here → (no further drill-down needed in V1).
- **UI elements:** Simple list — date, patient category (not name, for a scannable list), channel, amount — with a running total at the top for a selected period (this week/month). Amounts include any procedure fees billed after the visit; rows for procedure bills awaiting senior review show an "Awaiting senior review" indicator and their amount is not counted in the confirmed total until approved.

**Screen: Profile Tab**
- **Goal:** account settings, verification status, channel/pricing edits.
- **Flow:** Bottom tab → here → Edit Profile / Channel Setup (re-edit) / Pricing Setup (re-edit).
- **UI elements:** Profile summary with verification badge, list-style menu into each control-panel dial (Channels, Pricing, Schedule, Radius) for re-editing post-setup, plus Help/Logout.

---

## 6. Cross-App / Shared Flow Moments

These are the points where the two apps are effectively "talking" through the backend (Requirements Doc, Section 2.1) — worth prototyping together to check the live-sync feel is right, even though they're separate apps.

| Moment | Patient App shows | Doctor App shows | Sync mechanism |
|---|---|---|---|
| Request submitted | "Request Sent (Pending)" screen | New card animates into Requests Tab | Realtime insert on `bookings` |
| Doctor accepts | "Booking Accepted" screen (live push, no refresh) | Request Detail updates, card moves out of pending list | Realtime update on `bookings.status` |
| Doctor declines | "Booking Declined" screen (live push) | Card removed from pending list | Realtime update on `bookings.status` |
| Clarification call requested | Incoming call notification / "Clarification call scheduled" banner on Active Booking | Clarification Call screen | Realtime insert on `clarification_calls` + push notification |
| Payment completed | Booking Confirmed screen | Active Visit screen becomes fully confirmed (price-confirmed badge) | Realtime update on `payments.status` |
| Visit marked complete (doctor-side) | Prompt to rate | Booking moves to Earnings list | Realtime update on `bookings.status` |
| Procedure bill above senior-review threshold | "Under senior review" on the Procedure Bill screen — pay button locked until approved | Earnings row shows "awaiting senior review" until the senior doctor approves | Realtime update on `procedure_bills.status` |

**Prototyping note:** since both apps read live from the same backend state, it's worth prototyping the Request Detail (Doctor) and Request Sent/Accepted (Patient) screens side by side first — that pair is where the "live, connected" feel of the product either works or doesn't.

---

## 7. What's Deliberately Not Designed in V1

Carried over from the Requirements Doc's scope boundaries — worth keeping visible here so prototyping doesn't accidentally design for something out of scope:

- No "Available Now" / instant-booking UI, for any specialty or channel
- No triage flow, no severity/urgency selector on intake
- No ambulance-related UI
- No diagnostic or AI-suggestion UI on the intake or request screens
- No insurance flow
- No hospital-referral UI

---

*Reference this alongside the CHARAK App Requirements Document (technical spec, data model, API contract) and the CHARAK Product Explainer (plain-language product overview) — this doc covers screen-level design only.*
