# Charak legal decision log

This file records the legal and policy decisions behind the Terms of Use, Practitioner
Terms, Privacy Policy, Telemedicine Consent, Refund & Cancellation Policy and Cookie
Policy for the website (`charak site`) and both apps. Use it as the source of truth
when drafting or changing those documents.

**This is not legal advice.** A qualified Indian lawyer must review every decision
here before launch.

## How to use this log

- Each decision has an ID (`LD-NNN`), a status, a date, and the reasoning behind it.
- **Statuses**
  - **Decided**: confirmed by the founder. The documents must follow it.
  - **Proposed**: recommended but not yet confirmed. The documents may use it, but
    mark the clause for review.
  - **Open**: still needs input before the clause can be written.
  - **Superseded**: replaced by a later decision. Kept for history.
- Don't rewrite a decided entry. Add a new entry that supersedes it, so the history
  stays readable.
- When a decision changes a published document materially, bump that document's
  version in `packages/charak_core/lib/legal.dart` and `backend/app/config.py`
  (`LEGAL_*_VERSION`). See `README.md` in this folder.

## Summary

| ID | Topic | Decision | Status |
|---|---|---|---|
| LD-001 | Governing law and courts | Indian law. Exclusive jurisdiction of the courts at Mumbai. | Decided |
| LD-002 | Dispute resolution | Grievance → conciliation → arbitration (seat Mumbai). Consumer forums stay open to patients. | Proposed |
| LD-003 | Platform fee | Charak keeps no fee at launch. The full consultation fee goes to the practitioner. | Decided |
| LD-004 | Role in payments | Charak collects through Razorpay as the practitioner's limited collection agent. | Proposed |
| LD-005 | Refunds and cancellations | Tiered rules by consultation type and by who cancels (see table). Home visits: full refund ≥ 2 h before; 50% if < 2 h and the practitioner hasn't started travelling; none once travelling. | Decided (home visits); Proposed (rest) |
| LD-006 | Practitioner payouts | Fees build up in the practitioner's earnings balance. Each one can be withdrawn 48 h after its consultation is complete, whenever the practitioner chooses. | Decided |
| LD-007 | Consultation recording | Video and audio consultations are never recorded. | Proposed |
| LD-008 | Voice notes and AI | Voice notes are recorded only when the patient chooses to make one. AI transcription and summary are disclosed. No diagnostic AI. | Proposed |
| LD-009 | Data retention | Clinical records kept for 3 years, payment records for 8 years, security logs for 1 year. OTP codes deleted within minutes. | Proposed |
| LD-010 | Eligible practitioners | Practitioners registered with NMC/SMC, the Dental Council, or NCISM/NCH (AYUSH), each within their own system of medicine. | Proposed |
| LD-011 | Legal entity and Grievance Officer | M/s Radiant Technologies, Airoli, Navi Mumbai. Grievance Officer and DPO: Neelima Patil. | Decided |
| LD-012 | Minors and geography | Who may book for a minor; India-only service. | Open |
| LD-013 | Third-party tool for drafting | The documents are drafted in-house from the product's actual behaviour. Termly is not the primary source. | Decided |
| LD-014 | Signing in the apps | Each role reads and signs its full documents in the app, one by one, against a recorded version and fingerprint. Patients: Terms of Use, Privacy, Cancellation & Refund (+ Telemedicine at the first online consult). Doctors: Practitioner Agreement, Privacy, Cancellation & Refund. | Decided |

---

## LD-001: Governing law and courts

- **Status:** Decided (2026-10-22, founder)
- **Decision:** The Terms are governed by the laws of India. The courts at **Mumbai,
  Maharashtra** have exclusive jurisdiction, subject to LD-002.
- **Reasoning:** Charak's office is in Navi Mumbai, and Indian platforms pick the
  courts of their home city. The Navi Mumbai area falls under Thane district courts.
  The founder chose Mumbai as the main court. Before launch, a lawyer should confirm
  the exact wording ("courts at Mumbai") given where the registered office actually is.
- **Benchmark:** Apollo 24|7 (Apollo HealthCo Ltd) names the courts at Chennai, its
  home city. Practo names Bengaluru, its home city (from memory; not re-verified).
- **Applies to:** the Patient Terms, Practitioner Terms and website Terms.

## LD-002: Dispute resolution

- **Status:** Proposed
- **Decision:**
  1. The user raises the issue in the app or with the Grievance Officer. The
     Grievance Officer acknowledges a complaint within 24 hours and resolves it
     within 15 days (IT Rules 2021 / DPDP).
  2. If it isn't resolved, the parties try conciliation for 30 days.
  3. After that, arbitration under the Arbitration and Conciliation Act 1996, with a
     sole arbitrator, **seated in Mumbai**, in English.
  4. **Patients:** nothing in the Terms limits a patient's right to approach a
     Consumer Commission under the Consumer Protection Act 2019. Indian courts have
     held that consumer disputes can't be forced into arbitration, so the clause says
     this openly.
  5. **Practitioners:** arbitration is binding, because this is a business-to-business
     contract.
- **Benchmark:** Apollo 24|7 §13.5 uses conciliation, then a sole arbitrator, seated
  in Chennai, in English.

## LD-003: Platform fee

- **Status:** Decided (2026-10-16, founder)
- **Decision:** At launch Charak charges **no fee** to practitioners or patients. The
  practitioner sets the consultation fee and session length (10–60 minutes), and the
  **full fee** is passed on to the practitioner.
- **Implementation:** `PLATFORM_COMMISSION_PCT` defaults to 0, and migration 0020 lets
  a practitioner be paid to UPI only. Practitioners give UPI and/or bank details in
  doctor app → Profile → Payout details.
- **Document impact:** no document may mention a commission. The Practitioner Terms
  must keep the right to introduce fees later, with at least 30 days' notice, and
  that change will need a new decision in this log.
- **Superseded assumption:** the code originally defaulted to a 15% commission. That
  was never the business model.

## LD-004: Charak's role in payments

- **Status:** Proposed
- **Decision:** The patient pays through Razorpay checkout (UPI intent on Android; UPI
  collect, card or net banking on iOS). Charak receives the payment **as the
  practitioner's limited collection agent** and passes the full amount to the
  practitioner (LD-003).
  - The practitioner provides the medical service and is the supplier of it. Any
    receipt or invoice is issued in the practitioner's name.
  - A booking counts as paid only once Razorpay confirms the payment to Charak's
    backend through its signed webhook. The app returning from the UPI app is not
    proof of payment.
  - Charak never stores card details or UPI PINs.
- **To confirm with a lawyer or CA:** the agent wording and GST treatment (Charak earns
  nothing, but GST rules for e-commerce operators may still apply), and whether the
  collection flow raises issues under RBI's payment aggregator rules. Using Razorpay
  Route or settlement to the practitioner may avoid them.

## LD-005: Refunds and cancellations

- **Status:** The home-visit rows are Decided (2026-10-26, founder). The other rows are still
  Proposed.
- **Decision:**

| Situation | Outcome |
|---|---|
| Patient cancels an online consultation ≥ 15 minutes before the slot | Full refund |
| Patient cancels an online consultation < 15 minutes before the slot | No refund |
| Patient cancels a home visit ≥ 2 hours before the slot | Full refund **(Decided)** |
| Patient cancels a home visit < 2 hours before the slot, before the practitioner has started travelling | 50% refund **(Decided)** |
| Patient cancels a home visit after the practitioner has started travelling | No refund **(Decided)** |
| Practitioner cancels, doesn't respond, or doesn't turn up | Full refund, plus the option to rebook |
| Patient doesn't turn up | No refund |
| Call fails for technical reasons | Patient chooses a free reschedule or a full refund |
| Patient unhappy with the consultation | Handled case by case through the complaint process. No automatic refund. |
| Refund timing | Back to the original payment method within 5–7 working days |

- **Reasoning:** Apollo 24|7 allows free cancellation up to 15 minutes before an online
  consultation and 30 minutes before a physical one, with refunds in 5–7 working days.
  Charak's home visits involve the practitioner travelling, so they get a longer window.
- **Implementation note:** cancellation attribution and no-show handling already exist
  in the booking flow. The windows above must match the backend's rules before the
  policy is published.
- **Home-visit rules (Decided 2026-10-26).** The implementation rules below are Proposed:
  - "Started travelling" means the practitioner tapped **Start Journey** in the doctor app.
    The server records the time, and the patient is notified straight away. The cancel
    screen shows the time ("Your doctor started travelling at 10:12").
  - Start Journey can only be tapped in the 2 hours before the slot. Otherwise a
    practitioner could tap it early and make a booking non-refundable. Service areas are
    2–5 km, so 2 hours is plenty of travel time.
  - The amount kept (50%, or all of it) goes to the practitioner's earnings. Charak takes
    no fee (LD-003).
  - The practitioner-fault row still applies after a journey starts. If the practitioner
    then cancels or doesn't arrive, the patient gets a full refund.
  - The server decides which came first when a cancel and a journey start arrive together.
    If the outcome changed after the patient saw the refund amount, the patient is shown
    the new amount and confirms again.
- **Built (2026-10-26, migration 0024):**
  - The rules are a versioned policy in the database, and each booking keeps the version
    it was made under.
  - The patient sees the policy and the exact free-cancellation time, and ticks it before
    sending a request.
  - The cancel screen shows the exact refund.
  - Refunds round down to the paisa, so the doctor keeps the odd paisa of a 50% split.
  - Bookings made before this keep a full refund.
  - Online consultations keep a full refund until the online rule (D3 in the plan) is
    confirmed; adding it is one new policy version (runbook §6c).

## LD-006: Practitioner payouts

- **Status:** Decided (2026-10-26, founder). The payout rail is still Open.
- **Decision:** Charak doesn't push scheduled payouts.
  - Each consultation fee is credited to the practitioner's **earnings balance** in the
    doctor app.
  - A fee can be withdrawn **between 48 and 72 hours after the prescription is sent**
    (refined 2026-10-26):
    - The default is **72 hours**.
    - At the 48-hour mark the system checks whether the patient has opened the
      prescription. If they opened it within those 48 hours, the fee can be withdrawn
      **at 48 hours**.
    - If they haven't, it waits until **72 hours**, even if they open it later.
    - A booking whose prescription is never opened is marked complete at 72 hours.
  - The practitioner **starts a withdrawal whenever they choose**, for whatever is
    withdrawable at the time.
  - Money tied to an open refund, complaint or incident stays on hold until it is resolved.
- **Proposed:** an amount kept from a late cancellation (LD-005) can be withdrawn
  48 hours after the cancellation, because there is no consultation to complete.
- **Rail (Open):** practitioners want to be paid to UPI. There are two options:
  1. Razorpay Route with UPI (VPA) settlement to each practitioner's linked account. The
     money stays in Razorpay's escrow until it is withdrawn.
  2. RazorpayX Payouts from Charak's current account. Here Charak holds the money between
     payment and withdrawal, so this depends on the LD-004 review.

  See `docs/plans/next-release-plan.md` §3.5.
- **Superseded options:** weekly payouts, and T+2 working days.
- **Constraint (kept):** money is released only after the refund window for the
  consultation has closed, so Charak never has to recover money from a practitioner.

## LD-007: Consultation recording

- **Status:** Proposed
- **Decision:** Video and audio consultations (Agora) are **never recorded** by Charak.
  The policies say so clearly.
- **Reasoning:** the Telemedicine Practice Guidelines 2020 require the practitioner to
  keep records (notes, prescription, the patient's consent), not recordings. Not
  recording reduces sensitive-data risk. The Agora integration does not record today.
- **Constraint:** turning on recording later needs a new decision, explicit patient
  consent, and updates to the Privacy Policy and Telemedicine Consent.

## LD-008: Voice notes, uploads and AI

- **Status:** Proposed
- **Decision:**
  - A patient may choose to add a voice note, photos or video when booking. They are
    shared only with the practitioner handling that booking.
  - Voice notes are **transcribed and summarised by AI** for the practitioner (Google
    Gemini on Vertex AI in the `asia-south1` (Mumbai) region; OpenAI Whisper as a
    fallback). The Privacy Policy names these processors and says when data leaves
    India.
  - Photos and video are stored and shown as they are. No AI analyses them.
  - The AI does not diagnose or triage. The practitioner remains fully responsible
    for clinical judgement.
- **To check:** whether the patient gets a clear just-in-time notice before recording
  a voice note. DPDP requires the notice to be specific to the purpose.

## LD-009: Data retention

- **Status:** Proposed
- **Decision:**

| Data | Retention | Basis |
|---|---|---|
| Clinical records (bookings, intake, transcripts, prescriptions) | 3 years from the last consultation, then purged. Kept de-identified after the patient deletes their account. | IMC (Professional Conduct) Regulations 2002, reg. 1.3.1; Telemedicine Practice Guidelines 2020 |
| Voice-note audio files | Deleted when the account is deleted. The transcript and summary stay as the clinical record. | Data minimisation (DPDP) |
| Payment and payout records | 8 years | Income Tax Act / Companies Act / GST |
| Practitioner verification documents | While the account is active, plus 3 years | Professional accountability |
| Consent records | While the account is active, plus 3 years | DPDP accountability |
| Security and access logs | 1 year | CERT-In directions (2022) require at least 180 days |
| OTP codes | Deleted within minutes of expiry | Data minimisation |
| Website registration leads and waitlist | Until onboarding or 12 months, whichever comes first | Data minimisation |

- **Implementation:** account deletion is soft-delete plus a purge of personal data
  (migration 0013, `backend/app/services/erasure.py`). The purge must match these
  periods.

## LD-010: Eligible practitioners

- **Status:** Proposed
- **Decision:** Charak lists only practitioners who hold a current registration with:
  - the **NMC or a State Medical Council**: MBBS and specialists, under the
    Telemedicine Practice Guidelines 2020;
  - the **Dental Council of India or a State Dental Council**: BDS/MDS;
  - **NCISM or NCH** (AYUSH: BAMS, BUMS, BSMS, BHMS), under their own telemedicine
    guidelines.
- The registration number is checked by hand before a practitioner goes live, and is
  shown on their profile.
- Practitioners may prescribe only within their own system of medicine and their
  registration. The Practitioner Terms make each practitioner responsible for this.
- **Open:** physiotherapists and other allied health professionals aren't regulated
  by these councils. Listing them needs a separate decision.
- **Benchmark:** Practo lists allopathic, dental and AYUSH practitioners.

## LD-011: Legal entity and Grievance Officer

- **Status:** Decided (2026-10-19, founder)
- **Legal entity:** M/s Radiant Technologies (name confirmed 2026-10-22), which operates the Charak website and
  apps.
- **Registered address:** R212, Sector 4, Airoli, Navi Mumbai, Maharashtra 400 708
- **GSTIN:** 27AAHFR2768R1ZA (Maharashtra)
- **Grievance Officer and Data Protection Officer:** Neelima Patil
  - Email: info@radianttechnologies.in
  - Phone: +91 93701 44414
- **Entity type:** not stated in the documents (decided 2026-10-22). The documents
  name the operator as "M/s Radiant Technologies", with the registered address and
  GSTIN. Indian law (Consumer Protection (E-Commerce) Rules 2020, DPDP Act 2023) asks
  for the legal name, address and contact details, not the entity type.
  - The PAN inside the GSTIN marks a firm, and the name has no "LLP" suffix. So this
    is almost certainly a partnership firm, which has no extra disclosure duty.
  - If it is ever confirmed to be an LLP, the LLP Act requires the name to end in
    "LLP" and the LLPIN to appear on official documents. Add both.
- **Grievance email:** `info@radianttechnologies.in` is the published grievance
  address. A Charak-branded address was considered and declined (2026-10-22).
- **Published in:** the `ENTITY` constant in `charak site/src/pages/Legal.jsx`.

## LD-012: Minors and geography

- **Status:** Open
- **Questions:**
  - Can a parent or guardian book for a child? If so, DPDP requires verifiable
    guardian consent for anyone under 18.
  - Is the service limited to patients and practitioners in India?

## LD-013: Drafting approach

- **Status:** Decided (2026-10-14)
- **Decision:** The documents are written in-house, based on how the product actually
  works, for Indian law: the DPDP Act 2023 and DPDP Rules 2025, the IT Act 2000 and
  its 2011 rules on sensitive personal data, the Telemedicine Practice Guidelines
  2020, the Consumer Protection (E-Commerce) Rules 2020, and RBI payment rules.
  Generic generators such as Termly are aimed at GDPR/CCPA and don't cover
  telemedicine. Termly's cookie scanner may still be used for the website Cookie
  Policy.

## LD-014: Signing the documents in the apps

- **Status:** Decided (2026-10-28, founder: "we need the full policy the user needs to
  sign … same for the doctor app as well").
- **Decision:** people sign the full documents in the app, the way established
  platforms do it (separate agreements, each accepted explicitly, the version recorded),
  not a one-line summary and a tick.
  - **Patients sign** the Terms of Use, the Privacy Policy and the Cancellation & Refund
    Policy at sign-up, and the Telemedicine Consent before their first online
    consultation.
  - **Doctors sign** the Practitioner Agreement (a contract of its own, no longer the
    patients' Terms), the Privacy Policy and the Cancellation & Refund Policy, at
    onboarding.
  - Each document opens in full in the app, its key points first. Each is agreed to
    with its own tick ("I agree to the Practitioner Agreement", the title opening the
    text); reading it is up to the person (amended 2026-10-29, founder: "why is it
    compulsory to read that"; it was read-to-the-end before "I agree"). One "Sign and
    continue" then records every signature with the version, the text's SHA-256
    fingerprint, the time, the IP address and how it was given.
  - The full text shows in the app only for versions published with it (2026-10-28
    onwards). Until those are approved in admin → Policies, the current versions are the
    2026-10-01 ones, whose words live only on the website, so the app links there.
  - At booking, the patient sees every case of the Cancellation & Refund Policy for that
    kind of booking (who cancels, when, and what is refunded), generated from the rules
    the backend enforces, and agrees to it.
  - A material new version is signed again: on opening the app, and enforced by the
    server before booking (patients) or accepting a booking (doctors) once
    `require_legal_acceptance` is on.
  - Profile → Legal shows each document, the version signed and when.
- **Source of truth:** `docs/legal/<version>/*.md`, published to the database by
  `docs/legal/publish.py` (migrations 0030–0031). Published text is never edited; a
  change is a new version, and a version applies only once approved in admin → Policies.
- **Reasoning:** clickwrap with an explicit "I agree" is enforceable in India (Indian
  Contract Act 1872, IT Act 2000 s. 10A). Recording the exact text signed answers "what
  did they agree to" in any dispute. DPDP Rules 2025, Rule 3 (in force from May 2027)
  wants the privacy notice standalone, itemised and in plain language: the Privacy Policy
  is its own document and lists each item of data with its purpose.
- **To confirm with a lawyer:** the liability cap in the Practitioner Agreement (§16:
  the fees for the bookings concerned), the indemnity (§15), the grievance timelines
  (acknowledged in 24 hours, resolved in 15 days), and whether doctors should also sign
  the patients' Terms of Use.

---

## Sources

- Apollo 24|7 Terms of Use: https://www.apollo247.com/terms (read 2026-10-19; §13.5
  jurisdiction and arbitration; cancellation windows)
- Apollo 24|7 FAQ (refund timing): https://www.apollo247.com/faq
- Tata 1mg online consultation (refund in genuine cases): https://www.1mg.com/online-consultation
- Telemedicine Practice Guidelines, MoHFW / Board of Governors in supersession of MCI, 2020
- Indian Medical Council (Professional Conduct, Etiquette and Ethics) Regulations 2002
- Digital Personal Data Protection Act 2023 and DPDP Rules 2025
- CERT-In Directions under section 70B(6) of the IT Act, 28 April 2022

## Change history

| Date | Change |
|---|---|
| 2026-10-28 | LD-014 decided: full documents signed in the apps. Version 2026-10-28 of all five documents drafted in `docs/legal/2026-10-28/`, including the first Practitioner Agreement and a standalone Cancellation & Refund Policy. |
| 2026-10-26 | LD-006 refined again: withdrawable at 72 h after the prescription is sent, or at 48 h if the patient opened it within the first 48 h. |
| 2026-10-26 | LD-006 refined: withdrawable 48 h after the prescription is opened, or 72 h after it was sent if never opened (whichever is first). |
| 2026-10-26 | LD-006 decided: earnings balance, withdrawal on demand, 48 h after completion. Payout rail still open. |
| 2026-10-26 | LD-005 home-visit rows decided: full refund ≥ 2 h before the slot, 50% if < 2 h and not yet travelling, none once travelling. |
| 2026-10-22 | LD-011: grievance email stays info@radianttechnologies.in. |
| 2026-10-22 | LD-011: entity type left out of the documents; name, address and GSTIN are enough. |
| 2026-10-22 | LD-011: Grievance Officer's name corrected to "Neelima Patil"; entity name confirmed. |
| 2026-10-22 | LD-011 decided (M/s Radiant Technologies; Grievance Officer Neelima Patil). |
| 2026-10-22 | Log created. LD-001 decided (Mumbai courts). Research from 2026-10-19 recorded. |
