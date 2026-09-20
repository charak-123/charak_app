# Emergent Prompt — Charak Website

Copy-paste into Emergent to generate initial design.

---

```
Build a marketing + doctor acquisition site for CHARAK — a verified-doctor platform for online consults and home visits (India). This is a pre-app site. Goal: explain Charak and capture doctors via a dedicated registration page. Tone: calm, trustworthy, premium — like a well-designed banking app, not clinical/hospital.

SITE MAP (build all):
/ — Landing
/register — Doctor Registration (STANDALONE page, not a section on /)
/register/success — Confirmation after submit
/privacy — Privacy Policy
/terms — Terms of Service
/disclaimer — Medical Disclaimer
/contact — Contact & Grievance Officer
Header on / links to /register. Footer on every page links to all legal pages.

---
COPY TO USE EXACTLY:

[HEADER]
Logo: CHARAK
Nav: How it works | For Doctors | FAQ | Contact
CTA button: Register as Doctor → /register

[HERO — /]
Headline: Healthcare that comes to you.
Subhead: Charak connects patients with verified doctors for online consultations and home visits. Scheduled slots, transparent pricing, and real human verification — no instant-booking pressure.
Primary CTA: Register as Doctor
Secondary CTA: How it works
Trust line: Manual license verification • No AI diagnosis • Senior review for high-value bills

[HOW IT WORKS — /]
Section title: How Charak works
Step 1 — Register: Submit your details and license in under 3 minutes.
Step 2 — Get verified: Our team manually verifies your credentials. Typical review: 24–48 hours.
Step 3 — Go live: Set your channels, schedule, and fees. Appear in the patient directory.

[FOR DOCTORS — /]
Section title: Built for how you actually practice
Card 1 — Your channels, your choice: Offer online consults, home visits, or both.
Card 2 — Your schedule, your radius: Weekly recurring slots. For home visits, pick 2/3/5 km radius from your base.
Card 3 — Your pricing, your procedures: Set base 15-min fee + extra-15-min rate. Fixed procedure prices — bills above your threshold go through senior review before the patient pays.
Card 4 — Verification that means something: Every doctor is manually verified. No anonymous listings.

[TRUST — /]
Title: Verification you can stand behind
Body: Charak never substitutes triage or AI diagnosis. Patient intake is reviewed by the doctor directly. Every listing shows verification status, and every home-visit procedure bill is at your fixed rates — nothing hidden.

[FAQ — /]
Q1: Who can register? — MBBS/BDS/BAMS and specialists with a valid registration/license number.
Q2: Is there a fee to register? — No. Registration is free. Future commission/payout terms will be shared before you go live and updated in our Terms.
Q3: How long does verification take? — Usually 24–48 hours after you submit your certificate.
Q4: What happens to my data? — Your website registration pre-fills your app profile on the same phone number. No duplicate document upload if already approved. See Privacy Policy.
Q5: Do I need to offer home visits? — No. Choose online only, home only, or both.
Q6: Is this for emergencies? — No. Charak is for scheduled consultations and visits. Not for emergency, ambulance, or triage services.

[FOOTER — every page]
Tagline: Verified doctors. Online or at home.
Links: Privacy Policy | Terms of Service | Medical Disclaimer | Contact & Grievance Officer
Contact: support@charak.health | +91-XXXXX XXXXX | [Registered Address — placeholder]
Legal: © 2026 Charak. All rights reserved.

---
[/register — DOCTOR REGISTRATION — standalone page]
Headline: Register as a Charak Doctor
Subhead: Takes ~3 minutes. You'll get a reference ID on submission and an SMS confirmation. Your data will pre-fill your app profile when the app launches — no need to submit again.
Form labels (in order):
- Full name * (placeholder: Dr. Full Name)
- Phone number * (+91 — OTP verified)
  [Send OTP] → [Enter 6-digit OTP] → [Verify] — helper: Submit is enabled only after verification. Resend in 0:30.
- Email (optional) (placeholder: name@hospital.com)
- Specialty / Category * (dropdown: General Physician, Orthopedic, Cardiology, Dermatology, Gynecology, Pediatrics, Dentistry, Physiotherapy, Nurse, Other)
- Registration / License number *
- Highest qualification * (placeholder: MBBS, MD, BDS...)
- Years of experience (optional) (placeholder: e.g., 8)
- Preferred channels * (checkboxes: Online Consult / Home Visit — select at least one)
- City * + State *
- Upload license/certificate * (PDF/JPG/PNG, max 10MB, 1 file) helper: Upload your medical registration certificate or degree certificate.
- Bio (optional, max 500 chars)
- Consent * checkbox: I agree to the Privacy Policy and Terms and consent to Charak storing and processing my data for verification and future app onboarding. [links]
CTA: Submit Registration
Error states: show inline under each field. Duplicate phone → "This number is already registered — Status: Pending. Need help? Contact us."
On success → redirect to /register/success

[/register/success]
Title: Registration received
Body: Thank you, Dr. [Name]. Your reference ID is CHR-XXXXXX. We've sent a confirmation to your phone. Our team will verify your documents within 24–48 hours and contact you on the same number. You don't need to submit again — this will pre-fill your Charak app profile.
CTAs: Back to Home | Contact Support

[/privacy] — render full legal placeholder with these headings: Data Controller, Data we collect, Why we collect it, Legal basis & consent, How we store & how long, Who we share with (no sale), Your rights (access/correction/deletion/withdraw), Security, Cookies, Children's data, Data reuse (website → app pre-fill on same phone), Grievance Officer contact, Effective date & changes.

[/terms] — headings: Eligibility, Registration ≠ guaranteed listing, Verification & rejection rights, No registration fee (V1), Code of conduct, IP, Limitation of liability, Governing law (India).

[/disclaimer] — Body: Charak is a booking and facilitation platform, not a medical provider. We do not provide emergency, ambulance, triage, or AI diagnosis services. Medical advice is solely between doctor and patient.

[/contact]
Title: Contact & Grievance Officer
Body: For support, data requests, or grievances (IT Rules 2021 / DPDPA):
Email: grievance@charak.health
Phone: +91-XXXXX XXXXX
Address: [Registered Address]
Grievance Officer: [Name, Title, Email, Address]
Response SLA: 30 days. For verification status, include your reference ID (CHR-XXXXXX).

---
REQUIREMENTS FOR EMERGENT:
- /register must be a separate route, not a section on /. Deep-linkable for ads/QR.
- OTP gate: disable Submit until phone is verified.
- Legal pages must be real routes with the headings above — use placeholder body copy where needed but keep headings exact.
- All CTAs on / that say "Register as Doctor" go to /register.
```
