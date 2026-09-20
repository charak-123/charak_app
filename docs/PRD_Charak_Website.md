# PRD — Charak Website (Doctor Registration + Official Pages)

**Version:** 1.0 — 2026-08-24
**Status:** Draft
**Scope:** Marketing site + doctor registration funnel. Temporary acquisition surface until native apps launch; all collected data must be directly reusable in the app backend without re-entry.

---

## 1. Objective

Launch a lightweight, trustworthy web presence for Charak that:
1. Explains what Charak does (patients ↔ verified doctors, online consult + home visit).
2. Captures verified doctor leads via a dedicated registration flow.
3. Satisfies legal/official requirements (privacy policy, terms, disclosures).
4. Stores data in final-schema-compatible form so migration to app = zero re-collection.

Success = doctors can self-register; site is shareable/legal-complete; ops can export/verify leads.

## 2. Non-Goals (V1)

- No patient booking, payment, or login on web.
- No doctor dashboard/login on web (form → backend only).
- No CMS/blog, no multi-language, no SEO-heavy content engine.

## 3. Users

- **Primary:** Doctors (MBBS/BDS/BAMS + specialists) exploring Charak before app launch.
- **Secondary:** Patients/visitors seeking legitimacy, plus ops/admin reviewing registrations.

## 4. Site Map

| Route | Purpose | Indexable |
|---|---|---|
| `/` | Landing — what Charak is, how it works, trust/verification promise, CTA → `/register` | Yes |
| `/register` | **Dedicated** doctor registration form (not embedded on `/`). Standalone page with own URL for ads/QR/share. | No (noindex until launch) or Yes if acquisition |
| `/register/success` | Confirmation after submit (reference ID, next steps, timeline) | No |
| `/privacy` | Privacy Policy | Yes |
| `/terms` | Terms of Service | Yes |
| `/contact` | Contact / Grievance Officer (DPDPA/IT Act) | Yes |
| `/disclaimer` | Medical disclaimer (non-emergency, no triage/diagnosis by platform) | Yes |

Footer links to all legal pages on every route. Header CTA on `/` → `/register`.

## 5. Landing (`/`) — Content Requirements

- One-line positioning (e.g., verified doctors, online + home-visit bookings).
- 3-step how-it-works (register → get verified → go live in directory).
- Value props for doctors (channels, schedule control, pricing control, Radius, procedure billing).
- Verification/trust signal (manual license check, senior review for high-value bills).
- FAQ: eligibility, fees/commission (TBD placeholder), verification SLA, data reuse consent.
- Footer: legal links, contact email/phone, ©.

No form on this page — only link to `/register`.

## 6. Doctor Registration (`/register`) — Functional Spec

### 6.1 Fields

| Field | Type | Required | Validation |
|---|---|---|---|
| Full name | text | Yes | 2–80 chars, trim |
| Phone | tel (+91 default) | Yes | 10-digit, OTP-verified before submit (see 6.2) |
| Email | email | No (recommended) | RFC-valid if provided |
| Specialty / Category | single-select | Yes | From canonical list: General Physician, Orthopedic, Cardiology, Dermatology, Gynecology, Pediatrics, Dentistry, Physiotherapy, Nurse, etc. (seed from `CHARAK_Prototype_Reference.md §4.2`) |
| Registration / License number | text | Yes | Alphanumeric, 5–30 chars |
| Highest qualification | text/select | Yes | e.g., MBBS, BDS, MD… |
| Years of experience | number | No | 0–60 |
| Preferred channel(s) | multi-check | Yes | Online Consult / Home Visit / Both — at least one |
| City + State | text | Yes | Free text V1 (district optional) |
| ID / Certificate upload | file | Yes | PDF/JPG/PNG, ≤10MB, 1 file V1 (license or degree cert). Stored to Supabase Storage |
| Consent checkbox | boolean | Yes | "I agree to Privacy Policy & Terms and consent to Charak storing/processing my data for verification and future app onboarding" — links to `/privacy`, `/terms` |

Optional V1-nice-to-have (if not bloating): bio (≤500 chars), profile photo.

### 6.2 OTP Verification

- Phone field triggers OTP send → 6-digit verify. Submit disabled until `otp_verified=true`.
- Stub provider V1 (Supabase phone auth or MSG91/Twilio stub); resend with 30s cooldown, 3 attempts lockout.
- Store `otp_verified`, `verified_at`.

### 6.3 Submission & Storage

- On submit: create `doctors_pending` (or `users` + `doctors` with `verification_status='pending'`) — **same schema as app backend** (`CHARAK_MVP_Build_Plan.md § Day 2` entities: `users`, `doctors`, `categories`).
- Fields map 1:1 to app fields so app launch can flip `pending → approved` without migration: `name`, `phone`, `email`, `specialty/category_id`, `license_number`, `qualification`, `channels`, `city/state`, `verification_status`, `consent_at`, `source='website'`.
- File upload → `supabase storage / verification_docs/{doctor_id}/{filename}`; store URL in `doctors.verification_doc_url`.
- Return reference ID (e.g., `CHR-XXXXXX`) on `/register/success`; also send confirmation SMS/WhatsApp + email (if provided).
- Duplicate guard: phone unique; re-submit → show "already registered, status: pending" with contact link.
- Rate limit: 5 submits/IP/hour, honeypot + server-side validation.

### 6.4 Ops

- Admin read: list + filter (pending/approved/rejected) + doc preview. V1 can be Supabase dashboard; no custom admin required.
- Export CSV: all fields + doc URL + timestamps + OTP status.

## 7. Legal / Official Pages

### 7.1 `/privacy` — must cover

- Data Controller: Charak (legal entity name, address, contact — placeholder until filled).
- Data collected: §6.1 fields + IP, timestamps, OTP metadata.
- Purpose & legal basis: verification, onboarding to app, communication; consent (DPDPA 2023).
- Storage & retention: stored in Supabase (region), retained until deletion request or 24 months of inactivity; docs retained for verification audit.
- Sharing: no sale; only verification staff/processors (storage, SMS provider); no diagnostic/AI processing of intake (hard boundary per requirements).
- User rights: access, correction, deletion, withdraw consent → via `/contact` / grievance email; SLA 30 days.
- Security measures, cookies (if any), children's data (no), cross-border transfer (no).
- Effective date, changelog, contact for DPO/Grievance Officer (name, email, address per IT Rules 2021).
- Reuse disclosure: data collected on website will pre-fill app profile on same phone number; no duplicate documents required after verification.

### 7.2 `/terms`

- Eligibility, account merely registration ≠ listing guarantee (verification required).
- Verification is manual; Charak may reject incomplete/fraudulent docs.
- No fee to register (V1); future commission/payout terms TBD — reference will be updated.
- Code of conduct, listing accuracy, IP, limitation of liability, governing law (India).
- Link to Privacy Policy + Disclaimer.

### 7.3 `/disclaimer`

- Charak is a booking/intermediary platform, not a medical provider; no emergency services; no ambulance/triage/AI diagnosis; advice is doctor-to-patient only.

### 7.4 `/contact`

- Support email, phone, registered address, Grievance Officer details (name/title/email/address) — required for IT Rules compliance.

## 8. Data Reuse Contract (Website → App)

- Phone is the join key. On app OTP login with same phone, backend looks up `doctors` row; if `verification_status` is `pending/approved`, pre-fill Profile Setup + Verification Submission screens — no re-upload if already approved.
- `source='website'` and `consent_at` preserved; app onboarding skips fields where data exists, allows edit.
- No second verification doc collection if website doc already approved.
- Migration is zero-ETL: same tables, same bucket. Only status transition.

## 9. Non-Functional

- Performance: LCP <2.5s, form submit <2s P95.
- Accessibility: WCAG 2.1 AA for form + legal pages (labels, focus, error announcements).
- Security: HTTPS, server-side validation, signed upload URLs, no PII in logs, secrets in env.
- SEO: sitemap, meta, OG for `/`, `/privacy`, `/terms`; noindex for `/register/success`.
- Analytics (minimal): page views + `register_viewed / otp_sent / otp_verified / register_submitted / register_failed` events; no PII in analytics.

## 10. Open Questions (resolve before build)

1. Legal entity name + registered address + DPO/Grievance Officer details for Privacy/Contact.
2. Final specialty list — reuse V1 list from app requirements or trimmed set for website launch?
3. Keep OTP mandatory V1 or allow email-only fallback if SMS delivery is unstable?
4. Commission/payout disclosure — placeholder vs. concrete % to publish on Terms/FAQ?

## 11. Acceptance Criteria

- [ ] `/` live with footer legal links; every legal page renders from single source of truth.
- [ ] `/register` is standalone (not embedded) and reachable directly; submit blocked until OTP verified + consent checked.
- [ ] Submission creates row with app-compatible schema + stored doc; reference ID shown + SMS/email sent.
- [ ] Duplicate phone handled gracefully.
- [ ] Privacy/Terms/Disclaimer/Contact cover DPDPA + IT Rules basics and explicitly disclose website→app data reuse.
- [ ] CSV export + admin list of pending registrations works.
