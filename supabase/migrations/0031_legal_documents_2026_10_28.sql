-- ═══════════════════════════════════════════════════════════════════════════
-- 0031: legal documents, version 2026-10-28. Generated; do not edit.
--
--   python3 docs/legal/publish.py 2026-10-28 0031
--
-- From docs/legal/2026-10-28/. Each version applies only once it is
-- approved in admin → Policies (the review gate, migration 0029). Until
-- then the apps keep showing the version people already accepted.
--
-- Fingerprints (legal_documents.sha256, set by the database from the body):
--   tos                  4040163bc03e169f32c6d365a294c900eb0ab1bee7de530eddd9f6257fb23772
--   practitioner_terms   93635ff47121828ab74e4aeb38ee55987b36879b513b6ff7fd8a4bad78c55acb
--   privacy              97280e1c6f65f0f60b498baeaae43bb7542ee80b66b35a5b638156d3a3b76813
--   refund_policy        04e17b9e01843f84251f70bf308d56e8f878a8f06b5a3a34afd2a0a4c2b036af
--   telemedicine         7b2a0b3c704963e9f25855503e7b1cc4a6f192ff83c033029f43b3eacd69e14f
--
-- Idempotent: safe to re-run in the SQL Editor.
-- ═══════════════════════════════════════════════════════════════════════════

-- Terms of Use
insert into legal_documents (type, version, title, url, audience, material, summary, highlights, body)
values (
  'tos', '2026-10-28', 'Terms of Use',
  'https://www.charak.care/terms', '{patient}', true,
  'The agreement between you and Charak for booking consultations and home visits.',
  jsonb_build_array(
    'Charak connects you with independent, verified practitioners. It does not provide medical care itself, and the doctor makes every clinical decision.',
    'Charak is not for emergencies. In an emergency, call 112 or go to the nearest hospital.',
    'You pay only after the doctor accepts your request. The fee is set by the doctor, and Charak keeps none of it.',
    'Cancellations and refunds follow the Cancellation & Refund Policy, which you accept together with these terms.',
    'If something goes wrong, tell us first. These terms are governed by Indian law, and your rights as a consumer are not affected.'),
  $doc$These terms are an agreement between you and M/s Radiant Technologies, R212, Sector 4, Airoli, Navi Mumbai, Maharashtra 400 708 (GSTIN 27AAHFR2768R1ZA), which operates Charak ("Charak", "we", "us"). They cover your use of the Charak patient app and the Charak website to find practitioners and book online consultations and home visits.

You accept these terms by tapping "I agree" in the app. The Privacy Policy, the Cancellation & Refund Policy and, for online consultations, the Telemedicine Consent form part of this agreement. Please read them together.

## 1. What Charak is, and what it isn't

Charak is a technology platform. It helps you find registered healthcare practitioners ("doctors"), send them a request, pay them, and consult them by video or at home.

- The doctors on Charak are independent professionals. They are not our employees or agents, and we do not direct or supervise their clinical work.
- The doctor alone decides whether to take your case, what advice to give, and whether to prescribe. We are not a party to the consultation between you and the doctor.
- We check each doctor's registration with the relevant medical council by hand before they can take bookings. Verification confirms their credentials. It does not guarantee the outcome of any consultation or treatment.
- Nothing in the app, other than the advice your doctor gives you in a consultation, is medical advice.

**Charak is not for emergencies.** If you or someone else needs urgent care, call 112 or go to the nearest hospital. Do not wait for a doctor on Charak.

## 2. Your account

- You must be at least 18 years old to create an account.
- You sign in with your Google account. You give us your mobile number so the doctor on a booking can reach you about it.
- Keep your details accurate and up to date. You are responsible for what happens through your account, so don't share access to it.
- You may book for someone else, such as your child or a parent, only if you are their parent, guardian or authorised representative. You are responsible for the information you give about them, and for passing on the doctor's advice.

## 3. Booking a consultation or home visit

1. You choose a doctor, a type of consultation and a time, and describe the problem in text, a voice note, photos or video.
2. The doctor reads it and accepts or declines. A request that isn't answered before its time expires.
3. When the doctor accepts, the slot is held for 10 minutes while you pay. The booking is confirmed once the payment is.
4. For a home visit, your full address is shared with the doctor only once they accept. Before that they see only the area and how far away it is. Home visits are offered only inside the area each doctor serves.

The doctor may decline a request, or advise an in-person visit, tests or another specialist, if they judge that is right for you.

## 4. Fees and payment

- The fee for each type of consultation is set by the doctor and shown before you send a request. It includes the length of the consultation.
- Charak charges no fee to you or to the doctor. The full fee goes to the doctor.
- Payments are collected by our payment processor, Razorpay, on the doctor's behalf. We never see or store your card details or UPI PIN.
- A booking counts as paid only when Razorpay confirms the payment to us.
- During a home visit, the doctor may bill you for a procedure or supplies. You see the bill, item by item, in the app before you pay it.
- Follow-up consultations with the same doctor may be charged at the doctor's follow-up price, within the period the doctor sets.

## 5. Cancellations, refunds and when things go wrong

The Cancellation & Refund Policy sets out what happens when a booking is cancelled, moved or missed, by you or by the doctor. The rules for your booking, including when free cancellation ends, are shown before you send the request. In short:

- Withdrawing a request before the doctor accepts never costs anything.
- If the doctor cancels, doesn't attend, or can't keep the time, you get a full refund or a new time, whichever you choose.
- Refunds go back to the way you paid, usually within 5 to 7 working days.

## 6. Online consultations

- Consultations take place by video call in the app. Calls are not recorded by Charak.
- Join from a private place with a reliable connection, at the time booked.
- Before your first online consultation you are asked to accept the Telemedicine Consent, which explains the limits of remote care.

## 7. Prescriptions and records

- A prescription is given only if the doctor judges it appropriate, and only within the rules for prescribing remotely. Some medicines cannot be prescribed in an online consultation.
- Prescriptions are sent to you in the app. If the doctor corrects one, the new version replaces the old one and you are told.
- We keep your consultation records, including prescriptions, for as long as the law requires, as set out in the Privacy Policy.

## 8. Reviews

After a completed consultation you can rate the doctor and write a review.

- Reviews must be your own honest experience of that consultation.
- Don't include anyone's personal or health details, abuse, or anything unrelated to the consultation.
- We don't edit reviews. We may hide a review that breaks these rules, including after a doctor or another user reports it. We never hide a review just because it is negative.

## 9. How you must use Charak

You must not:

- give false information, or impersonate anyone;
- book a consultation you don't intend to attend, or misuse cancellations and refunds;
- harass, threaten or abuse a doctor or our team;
- ask a doctor to take payment outside Charak for a booking made on Charak;
- upload anything unlawful, or that you don't have the right to share;
- try to break, overload or get around the security of the app or our systems, or copy data from them.

## 10. Your content

What you share, such as your description of the problem, photos, video and voice notes, remains yours. You allow us to store and process it only to run your booking: to show it to your doctor, to turn voice notes into text, and to keep the records the law requires. The Privacy Policy explains this in full.

## 11. Our content

The Charak name, logo, apps and website belong to us. You may use the apps for your own personal, non-commercial use. You may not copy, modify or resell them.

## 12. Availability and changes to the service

We work to keep Charak available and accurate, but we can't promise it will always be uninterrupted or error-free. We may change, add or remove features. If a change materially affects a booking you have already made, we will tell you, and the Cancellation & Refund Policy protects your payment.

## 13. Our responsibility

- The doctor is responsible for the care they give you.
- To the extent Indian law allows, we are not liable for what a doctor does or fails to do, or for indirect or consequential loss arising from your use of Charak.
- Nothing in these terms limits our liability for death or personal injury caused by our negligence, for fraud, or for anything else the law doesn't allow us to limit. Nothing in these terms limits your rights under the Consumer Protection Act, 2019.

## 14. Suspending or closing your account

- You can delete your account at any time in the app (Profile → Delete account). Your personal data is then handled as the Privacy Policy describes.
- We may suspend or close an account that breaks these terms, or puts doctors, patients or our team at risk. Where we can, we tell you why first.
- Bookings already paid for are handled under the Cancellation & Refund Policy.

## 15. Complaints

Tell us about any problem through Submit a complaint in the app, or write to upcharchikitsa@gmail.com. If you aren't satisfied with our answer, contact our Grievance Officer:

- Neelima Patil, Grievance Officer and Data Protection Officer
- Email: info@radianttechnologies.in
- Phone: +91 93701 44414
- Address: R212, Sector 4, Airoli, Navi Mumbai, Maharashtra 400 708

We acknowledge every complaint within 24 hours and resolve it within 15 days.

## 16. Governing law and disputes

These terms are governed by the laws of India. If a dispute isn't resolved through our complaints process, the courts at Mumbai have exclusive jurisdiction. This doesn't stop you from approaching a Consumer Commission under the Consumer Protection Act, 2019.

## 17. Changes to these terms

If we change these terms materially, we will publish the new version and ask you to accept it in the app before you make another booking. The version you accepted, and when, is shown in the app under Profile → Legal.
$doc$
)
on conflict (type, version) do nothing;

-- Practitioner Agreement
insert into legal_documents (type, version, title, url, audience, material, summary, highlights, body)
values (
  'practitioner_terms', '2026-10-28', 'Practitioner Agreement',
  'https://www.charak.care/practitioner-terms', '{doctor}', true,
  'The agreement between you and Charak for taking consultations and home visits through the doctor app.',
  jsonb_build_array(
    'You practise independently. Charak is a technology platform, not your employer, and every clinical decision is yours.',
    'You set your own fees. Charak takes no commission today and will give you 30 days'' notice before charging any fee.',
    'A fee becomes withdrawable 72 hours after you send the prescription, or 48 hours if the patient opens it within 48 hours.',
    'You follow the Telemedicine Practice Guidelines, 2020 and your council''s code of ethics, and you never record consultations.',
    'Cancelling within 2 hours of a booking or not attending refunds the patient in full and counts against your reliability.'),
  $doc$This agreement is between you, the practitioner, and M/s Radiant Technologies, R212, Sector 4, Airoli, Navi Mumbai, Maharashtra 400 708 (GSTIN 27AAHFR2768R1ZA), which operates Charak ("Charak", "we", "us"). It covers your use of the Charak doctor app to receive requests from patients and to provide online consultations and home visits.

You accept this agreement by tapping "I agree" in the doctor app. The Privacy Policy and the Cancellation & Refund Policy form part of it. Together they are the whole agreement between you and us about Charak.

## 1. Meaning of some words

- **Patient**: a person who books you through Charak, or the person they book for.
- **Booking**: a consultation or home visit a patient has requested through Charak, from the request onwards.
- **Fee**: the price you set for a type of consultation, as shown to the patient.
- **Earnings balance**: the record in the doctor app of what you have earned through Charak and what you can withdraw.

## 2. Who can practise on Charak

You may take bookings on Charak only if you hold a current registration with one of:

- the National Medical Commission or a State Medical Council;
- the Dental Council of India or a State Dental Council; or
- the National Commission for Indian System of Medicine or the National Commission for Homoeopathy, for the system of medicine you are registered in.

Before you go live we check your registration number and the documents you upload by hand. We usually finish within 24 to 48 hours of receiving everything we need, and we may ask for more. Your registration number is shown on your profile.

You must tell us within 7 days if your registration is suspended, lapses, or has conditions placed on it, or if any disciplinary action is taken against you. We may then pause your profile until it is resolved.

Registering and being verified is free. We will never ask you to pay to be listed.

## 3. You practise independently

- You are an independent professional. Nothing in this agreement makes you our employee, partner or agent, except that you appoint us to collect fees for you as described in section 9.
- You alone decide whether a case is suitable for you, what advice to give, and what to prescribe. We do not direct or supervise your clinical work.
- You remain professionally and legally responsible for the care you provide, and for meeting the standards of your profession.
- You are free to practise elsewhere. Do not present yourself as employed by, or speaking for, Charak.

## 4. Your profile, fees and availability

- Keep your profile, qualifications, photo, fees, availability and service area accurate and up to date.
- You set your fee and session length (10 to 60 minutes) for each type of consultation you offer, and your follow-up price and how long a follow-up stays valid. Patients see them before they book.
- You choose your hours, and can pause new requests at any time.
- For home visits, you choose the area you serve around your base location. Patients outside it can't book you for a visit.
- We decide how profiles are shown and ordered in search, using things like relevance to the patient's search, distance, availability and ratings. Nobody can pay for a better position.

## 5. Requests and bookings

1. A patient sends a request with a description of the problem. You read it and accept or decline. A request you don't answer expires at its start time.
2. When you accept, the patient has 10 minutes to pay. Only a paid booking goes ahead. If they don't pay, the slot is released back to your calendar.
3. For a home visit, you see the patient's full address only once you accept.

You must not ask or allow a patient to pay you outside Charak for a booking made through Charak, or move a Charak patient's booking off Charak.

## 6. Online consultations

- Follow the Telemedicine Practice Guidelines, 2020 (and, for AYUSH practitioners, the telemedicine guidelines for your system), including identifying yourself and the patient, and deciding whether the case is suitable for a remote consultation.
- Consult from a private place, join at the booked time, and give the patient the full session.
- **Never record a consultation**, by any means, and never let anyone else watch or listen without the patient's consent.
- If the call fails, use the app to propose new times (section 10).

## 7. Home visits

- Tap Start Journey only when you actually set out for the visit. It can only be used in the 2 hours before the visit, and the patient is told at once. Starting a journey changes what the patient is refunded if they cancel, so it must be true.
- Use the patient's address and phone number only for that visit.
- Any procedure or supplies beyond the visit fee must be billed through the app, item by item, before the patient pays. Large bills are reviewed by our team. Do not take cash or any other payment.

## 8. Prescriptions and records

- Prescribe only within your system of medicine, your qualifications and your registration, and within the rules for prescribing remotely.
- Write and send prescriptions through the app. To correct one, send a new version: the patient is told, and the earlier one is kept as a record.
- Keep the records your profession and the law require. Charak stores the consultation record (the request, the patient's description and media, your notes and prescriptions) for you, for the periods in the Privacy Policy.

## 9. Fees, payments and your earnings

- **No commission.** Charak takes no fee or commission from you at present. If we ever introduce a fee, we will tell you at least 30 days before it applies, and you can stop taking bookings before then.
- **Collection.** You appoint us as your limited agent to collect fees from patients through our payment processor, Razorpay. A fee counts as received only when Razorpay confirms the payment.
- **Your earnings balance.** The full fee for each booking is credited to your earnings balance.
- **When you can withdraw.** A fee becomes withdrawable 72 hours after you send the prescription for that booking, or 48 hours after, if the patient opened the prescription within those 48 hours. A booking whose prescription is never opened is treated as complete at 72 hours.
- **Withdrawing.** You withdraw whenever you choose, for whatever is withdrawable at that time, to the UPI ID or bank account you give us in the app.
- **Holds and reversals.** Money for a booking stays on hold while a refund, complaint or case about it is open. If a patient is refunded under the Cancellation & Refund Policy, the matching credit is reversed. If a reversal is larger than your balance, it is taken from your future earnings.
- **Taxes.** You are responsible for income tax and any GST on the services you provide. The fee shown to patients is the full amount they pay.

## 10. Cancellations, moved bookings and reliability

- You can cancel a booking at any time. The patient always gets a full refund.
- If you can't keep a time, or a call fails, propose up to three new times in the app and say why. The patient picks one or takes a refund. If they don't answer within 24 hours, they are refunded.
- Patients can tell us if you haven't joined an online consultation 10 minutes after its start, or haven't arrived for a home visit 30 minutes after its start. Where the app's records support it, the patient is offered a refund or another doctor straight away.
- You can give your account of any case in the app, and appeal a decision within 7 days of it. Our team decides on the evidence.

**Reliability.** The doctor app shows you the share of your visits kept in the last 90 days, and every case behind it. A case counts against you when:

- you cancel less than 2 hours before a booking;
- you move a booking because you weren't available, or because of your own device or connection; or
- our team confirms you didn't attend.

Reliability is kept separate from your patients' ratings and never changes them. If your reliability is persistently low, we may pause your profile, after telling you why.

## 11. Patients' information

- Keep everything you learn about a patient confidential, to the standard your profession requires.
- Use a patient's information only to care for that patient and to keep the records the law requires. Don't contact patients for marketing, and don't copy their data off Charak except as your care or records require.
- Follow the Digital Personal Data Protection Act, 2023 and the rules on medical records that apply to you.
- If you think a patient's information has been lost, misused or seen by someone who shouldn't have seen it, tell us within 24 hours at info@radianttechnologies.in.

## 12. Ratings and reviews

Patients may rate and review you after a completed consultation. You can report a review that is abusive, irrelevant, or reveals someone's personal details. We don't hide a review just because it is negative. Do not offer anything in return for a review, or write or arrange reviews of yourself.

## 13. Conduct

- Treat every patient with dignity, and without discrimination.
- Do not harass or abuse patients or our team.
- Do not give false information or credentials. Doing so ends your account immediately, and we may report it to your council.
- Do not try to break, overload or get around the security of the app or our systems.

## 14. The app and our content

The Charak name, logo and apps belong to us. You may use the doctor app only to provide care to patients through Charak. You give us permission to show your name, photo, qualifications, registration number, fees, ratings and reviews on Charak and in our marketing of Charak.

## 15. Your promises and indemnity

You confirm that everything you tell us about your qualifications and registration is true and complete. You will cover us against claims, losses and costs that arise from the care you provide, from your breach of this agreement or the law, or from false information you give us, except to the extent they were caused by our own fault.

## 16. Our responsibility

To the extent Indian law allows, we are not liable for indirect or consequential loss, or for loss of income or goodwill, arising from your use of Charak, and our total liability to you is limited to the fees due to you for the bookings the claim relates to. Nothing in this agreement limits liability for fraud, or anything else the law doesn't allow us to limit.

## 17. Suspension and ending this agreement

- You can stop taking requests at any time, and close your account from the doctor app (Profile → Delete account). Open bookings must be completed or cancelled first.
- We may pause or close your account if we can't verify your registration, if it lapses or is suspended, if you break this agreement, or if your conduct puts patients at risk. Where we can, we tell you why first and give you a chance to respond.
- When your account closes, fees you have already earned are paid to you once their holds clear. Sections 8, 9, 11, 15, 16 and 18 continue to apply.

## 18. Disputes and governing law

This agreement is governed by the laws of India.

1. Raise any dispute with us first, in the app or with our Grievance Officer: Neelima Patil, info@radianttechnologies.in, +91 93701 44414.
2. If it isn't resolved within 30 days, either of us may refer it to arbitration by a sole arbitrator under the Arbitration and Conciliation Act, 1996. The seat of arbitration is Mumbai, and it is conducted in English.
3. Subject to this, the courts at Mumbai have exclusive jurisdiction, including for urgent interim relief.

## 19. Changes to this agreement

If we change this agreement materially, we will tell you in the app and by email at least 30 days before the change applies, unless the law requires it sooner. You will be asked to accept the new version before you accept further bookings. The version you accepted, and when, is shown in the app under Profile → Legal.

## 20. General

- Neither of us is responsible for a failure caused by events beyond reasonable control, such as natural disasters or a widespread network outage.
- You may not transfer this agreement. We may transfer it to a company that takes over Charak, and we will tell you if we do.
- If any part of this agreement can't be enforced, the rest still applies. If we don't enforce a right straight away, we haven't given it up.
- We send notices in the app and to the email address on your account. You can reach us at upcharchikitsa@gmail.com.
$doc$
)
on conflict (type, version) do nothing;

-- Privacy Policy
insert into legal_documents (type, version, title, url, audience, material, summary, highlights, body)
values (
  'privacy', '2026-10-28', 'Privacy Policy',
  'https://www.charak.care/privacy', '{patient,doctor}', true,
  'What personal data we collect, why, who sees it, how long we keep it, and your rights over it.',
  jsonb_build_array(
    'We collect only what we need to run bookings, payments and practitioner verification.',
    'A patient''s health information goes only to the doctor on that booking, and is never sold or used for advertising.',
    'Consultations are never recorded. Voice notes are turned into text by AI so the doctor can read them; photos and video are never analysed.',
    'Your data is stored in India, in Mumbai. The few providers that handle some of it outside India are named here.',
    'You can see, correct and delete your data, and withdraw your consent, from the app or by email.'),
  $doc$This policy explains what personal data Charak collects through the Charak patient app, the Charak doctor app and the Charak website, why we collect it, who we share it with, how long we keep it, and the rights you have over it. We have written it in plain language.

## 1. Who is responsible for your data

M/s Radiant Technologies, R212, Sector 4, Airoli, Navi Mumbai, Maharashtra 400 708 (GSTIN 27AAHFR2768R1ZA), which operates Charak ("Charak", "we", "us"), is the Data Fiduciary for the personal data described here, under the Digital Personal Data Protection Act, 2023 ("DPDP Act").

Our Data Protection Officer is Neelima Patil (info@radianttechnologies.in, +91 93701 44414). For everyday questions, write to upcharchikitsa@gmail.com.

## 2. What we collect, and why

We collect only what each part of the service needs.

**Everyone with an account**

- Name, email address and Google account identifier, from Google when you sign in. We never receive your Google password. *Purpose: to create your account and sign you in.*
- Mobile number. *Purpose: so the patient or doctor on a booking can reach you about it, and to prevent duplicate accounts.*
- Device notification token. *Purpose: to send you notifications about your bookings.*
- The versions of our terms and policies you accepted, and when. *Purpose: to keep a record of your consent, as the law requires.*
- Server logs: IP address, device and app version, and times of use. *Purpose: to keep the service secure, prevent fraud and fix problems.*

**Patients**

- Saved addresses and their map location. *Purpose: to check an address is inside a doctor's service area, and to tell the doctor where to go for a home visit.*
- What you share about a health problem: text, voice notes and their transcripts, photos and video. *Purpose: so the doctor can understand the problem before and during the consultation.*
- Bookings, prescriptions, follow-ups, payments, refunds, ratings, reviews, complaints and reports of problems. *Purpose: to run your bookings, keep medical and financial records, and handle complaints.*

**Doctors and other practitioners**

- Qualifications, specialty, registration number and council, verification documents and certificates, and photo. *Purpose: to verify you before you can take bookings, and to show patients who you are.*
- Fees, availability, base location and service area. *Purpose: to match you with patients and show your prices.*
- UPI ID or bank account details. *Purpose: to pay you.*
- Earnings, payouts, ratings, reviews, reliability and cases. *Purpose: to pay you correctly, keep financial records, and keep patients safe.*
- Your signature image, if you upload one. *Purpose: to sign the prescriptions you send.*

**Website registrations and waitlist**

- What you enter on the practitioner registration form or the waitlist: your name, mobile number, what you practise, where, your qualification and registration details, and optionally your email address, HPR ID or NUID. *Purpose: to verify you, and to set up your doctor account so you don't have to enter the same details again.*

We do not collect card numbers or UPI PINs: payments are handled entirely by our payment processor. We do not use advertising or third-party tracking tools in the apps or on the website.

## 3. Health information

The health information a patient shares is sensitive, and we treat it that way.

- It is shared only with the doctor on that booking, and with the few members of our team who need it to run the service, for example to look into a complaint.
- For a home visit, the doctor sees your full address only once they accept your request.
- **Consultations are never recorded**, by video or audio.
- **Voice notes are transcribed and summarised by AI** so the doctor can read them quickly. This is done by Google Gemini on Vertex AI in Google's Mumbai region, or, if that is unavailable, by OpenAI. The AI does not diagnose or advise. Photos and video are stored and shown to the doctor as they are, and no AI analyses them.
- It is never used for advertising and never sold.

## 4. The basis for using your data

We use your personal data on the basis of the consent you give when you create an account and accept this policy, and, for patients, the Telemedicine Consent you give before your first online consultation. Some records, such as payment and medical records, we must keep by law even after you withdraw consent.

## 5. Who we share it with

We share personal data only in these situations:

- **Between the patient and the doctor on a booking**: the doctor sees the patient's name and what they shared about the problem, and once they accept, the patient's mobile number and, for a home visit, the address. The patient sees the doctor's profile.
- **With the service providers that process data for us**, listed below, only as much as each needs.
- **With professional councils or registries**, only to verify a practitioner's registration.
- **When the law requires it**: a court order, or a lawful request from a government authority.

We do not sell personal data, and we do not give it to data brokers or advertisers.

### Our service providers

| Provider | What they do for us |
|---|---|
| Supabase, on Amazon Web Services in Mumbai | Our database and file storage |
| Google Cloud, in Mumbai | Our servers, and voice-note transcription |
| Google Firebase | Sign-in and notifications |
| Agora | Video calls, which pass through Agora's network and are not stored |
| Razorpay | Payments, refunds and payouts |
| OpenAI | Voice-note transcription, only when Google's service is unavailable |

## 6. Where your data is stored

Our database, uploaded files and servers are in Mumbai, India. Google Firebase, Agora and, when it is used, OpenAI may process some data outside India, only for the purposes above. We transfer data outside India only as the DPDP Act allows.

## 7. How long we keep it

| Data | How long |
|---|---|
| Your account details | While you have an account. Erased after you delete it, following a 30-day grace period in which you can change your mind. |
| Consultation records: requests, descriptions, transcripts and prescriptions | 3 years from the last consultation, as medical-record rules require. Kept in de-identified form once you delete your account. |
| Voice-note recordings | Deleted when you delete your account. The transcript stays as part of the record. |
| Payment, refund and payout records | 8 years, as tax law requires. |
| Practitioner verification documents | While the account is active, and 3 years after. |
| Records of your consent | While the account is active, and 3 years after. |
| Security and server logs | 1 year. |
| Website registrations that were rejected or never completed | Up to 12 months. |
| Waitlist sign-ups | Until launch, or until you unsubscribe. |

## 8. Your rights

Under the DPDP Act you have the right to:

- see the personal data we hold about you, and who we have shared it with;
- correct anything inaccurate, or complete anything missing;
- have your data erased: you can do this yourself in the app (Profile → Delete account);
- withdraw your consent at any time, as easily as you gave it;
- nominate someone to exercise these rights for you if you die or become unable to;
- complain to us, and if we don't resolve it, to the Data Protection Board of India.

To use any of these rights, write to upcharchikitsa@gmail.com or to our Data Protection Officer at info@radianttechnologies.in. We acknowledge every request within 24 hours and respond within 15 days.

If you withdraw consent, we stop using your data and delete it, except the records the law requires us to keep (section 7). We will then no longer be able to provide the service to you.

## 9. Security

The apps and website talk to our servers only over encrypted connections, and stored data is encrypted by our hosting providers. On your phone, the apps keep your sign-in in the device's secure storage. Access to personal data is limited to the members of our team who need it, and every administrative action is logged. No system is perfectly secure: if a breach affects your data, we will tell you and the Data Protection Board, as the law requires.

## 10. Children

You must be 18 or older to create an account. A parent or guardian may book a consultation for a child, and is responsible for the information they share about the child. We don't knowingly collect data directly from children. If you think a child has given us data, tell us and we will delete it.

## 11. Changes to this policy

If we change this policy materially, we will publish the new version and ask you to accept it in the app. Where a change affects how we use data you have already given us, we will also tell you directly. The version you accepted, and when, is shown in the app under Profile → Legal.
$doc$
)
on conflict (type, version) do nothing;

-- Cancellation & Refund Policy
insert into legal_documents (type, version, title, url, audience, material, summary, highlights, body)
values (
  'refund_policy', '2026-10-28', 'Cancellation & Refund Policy',
  'https://www.charak.care/refunds', '{patient,doctor}', true,
  'What happens to your money when a booking is cancelled, moved or missed, by either side.',
  jsonb_build_array(
    'You pay only after the doctor accepts your request, so withdrawing a request never costs anything.',
    'Online consultations: cancel any time before the consultation starts for a full refund.',
    'Home visits: a full refund up to 2 hours before, 50% after that until the doctor sets out, and nothing once they are on the way.',
    'If the doctor cancels, doesn''t come or can''t keep the time, you get a full refund or a new time, whichever you choose.',
    'Refunds go back to the way you paid, usually within 5 to 7 working days.'),
  $doc$This policy explains what happens to a payment when a booking on Charak is cancelled, moved or missed. It applies to patients and to the practitioners who take bookings on Charak, and it forms part of the Charak Terms of Use and the Practitioner Agreement.

Charak is operated by M/s Radiant Technologies ("Charak", "we", "us"). Charak keeps no fee from any booking: the whole fee belongs to the practitioner, and every refund described here comes out of that fee.

## 1. Which version applies to your booking

Each booking keeps the version of this policy that was shown to you when you sent the request. You see the rules for your booking, including the exact time free cancellation ends, on the Review & confirm screen, and you agree to them before the request is sent. If we change this policy later, bookings already made keep the version they were made under.

## 2. Before the doctor accepts

Sending a request is free. The doctor reads what you have told them and then accepts or declines.

- You can withdraw a request at any time before the doctor accepts it. Nothing is charged.
- If the doctor declines, nothing is charged.
- If the doctor doesn't answer before the time you asked for, the request expires and nothing is charged.

## 3. Paying for an accepted booking

When the doctor accepts, the slot is held for you for **10 minutes** while you pay.

- If you don't complete the payment in that time, the slot is released and nothing is charged.
- If money left your account but the payment didn't complete in time, it is refunded to you automatically.
- A booking is confirmed only when our payment processor, Razorpay, confirms your payment to us. Returning from your UPI app is not, on its own, confirmation.

## 4. If you cancel an online consultation

- **Any time before the consultation starts: full refund.**
- Once the consultation has started, it can no longer be cancelled.

## 5. If you cancel a home visit

A home visit needs the doctor to plan their day and travel to you, so the refund depends on how early you cancel and whether the doctor has already set out.

- **2 hours or more before the visit: full refund.**
- **Less than 2 hours before the visit, before the doctor has started travelling: 50% refund.**
- **After the doctor has started travelling: no refund.**

"Started travelling" means the doctor tapped Start Journey in the Charak doctor app. They can only do this in the 2 hours before your visit. You are told straight away when it happens, and the cancel screen shows the time ("Your doctor started travelling at 10:12").

The cancel screen always shows the exact amount you will get back before you confirm. If the doctor starts travelling while you are cancelling, and that changes the amount, you are shown the new amount and asked to confirm again.

## 6. If the doctor cancels

If the doctor cancels a booking you have paid for, at any time, **you get a full refund**.

## 7. If the doctor needs to move your booking

If the doctor can't make the time, or a call fails and has to be done again, the doctor proposes up to three new times and tells you why.

- Pick one of the new times and the same booking moves there, at the same price.
- Or take a full refund instead.
- If you don't answer within 24 hours, you are refunded in full.

## 8. If the doctor doesn't join or doesn't arrive

If the doctor hasn't joined your online consultation 10 minutes after it was due to start, or hasn't arrived for a home visit 30 minutes after it was due, you can tell us in the app ("Doctor hasn't joined" or "Doctor hasn't arrived").

- When the app's records support what you report, you choose straight away: **a full refund**, or **another doctor** paid from the same payment. If the other doctor costs less, the difference is refunded to you.
- If you don't choose within 24 hours, you are refunded in full.
- If the records don't settle it (for example, the doctor had started travelling), our team reviews the case, hears from the doctor, and decides. If they find the doctor at fault, you get the same choice.

## 9. If the call fails

If an online consultation can't go ahead or is cut off because of a technical problem, tell us in the app ("Call failed"). You get a new time or a full refund, whichever you choose, as in section 7.

## 10. If you miss your booking

If you don't join an online consultation, or aren't at the address for a home visit, the fee is not refunded. If something outside your control stopped you, tell us through Submit a complaint in the app and our team will look at it.

## 11. Home-visit procedure charges

During a home visit the doctor may need to carry out a procedure or use supplies that cost extra. These are billed separately through the app, item by item, and you see the bill before you pay it. Large bills are checked by our team first. If a bill is withdrawn or found to be wrong after you paid it, the amount is refunded to you.

## 12. If you're unhappy with the consultation

The fee pays for the doctor's time and professional judgement, not for a particular outcome, so there is no automatic refund because you are unhappy with a consultation. If you think something went wrong, tell us through Submit a complaint in the app. Our team looks at each case on its own facts and may refund you in full or in part.

## 13. How and when refunds are paid

- Refunds go back to the method you paid with: your UPI account, card or bank account.
- They usually reach you within **5 to 7 working days**, depending on your bank.
- Where only part of a payment is refunded, the amount is rounded down to the nearest paisa.
- You get a notification when a refund is sent, and the booking shows its status.

## 14. For practitioners

- When a patient cancels late and keeps less than a full refund under sections 5 and 10, the amount the patient doesn't get back is credited to your earnings.
- When a patient is refunded because you cancelled, moved a booking, didn't attend, or a case was decided against you, the credit for that booking is reversed.
- Money for a booking stays on hold while a refund, complaint or case about it is open.
- Cancelling less than 2 hours before a booking, and not attending, count towards your reliability as described in the Practitioner Agreement.

## 15. Questions and complaints

Ask us anything about a refund through Submit a complaint in the app, or write to upcharchikitsa@gmail.com. If you aren't satisfied with our answer, contact our Grievance Officer, Neelima Patil, at info@radianttechnologies.in or +91 93701 44414 (R212, Sector 4, Airoli, Navi Mumbai, Maharashtra 400 708). We acknowledge every complaint within 24 hours and resolve it within 15 days. Nothing in this policy limits your rights under the Consumer Protection Act, 2019.
$doc$
)
on conflict (type, version) do nothing;

-- Telemedicine Consent
insert into legal_documents (type, version, title, url, audience, material, summary, highlights, body)
values (
  'telemedicine', '2026-10-28', 'Telemedicine Consent',
  'https://www.charak.care/telemedicine', '{patient}', true,
  'What an online consultation can and can''t do, and what you agree to before your first one.',
  jsonb_build_array(
    'An online consultation can''t replace an in-person examination. The doctor may ask you to visit in person or get tests done.',
    'The doctor decides whether your problem is suitable for a remote consultation, and may decline or refer you.',
    'Some medicines can''t be prescribed in an online consultation.',
    'Consultations are never recorded. Your doctor sees what you share, and voice notes are turned into text by AI.',
    'In an emergency, don''t use Charak. Call 112 or go to the nearest hospital.'),
  $doc$You are asked to accept this consent before your first online consultation on Charak. It follows the Telemedicine Practice Guidelines, 2020 issued in India. Charak is operated by M/s Radiant Technologies ("Charak", "we", "us").

## 1. Please read before you consult

- An online consultation takes place remotely, by video call, together with the information you share about the problem. It is **not a substitute for an in-person examination**, and it has limits: the doctor can't examine you physically, and may ask you to visit in person or get tests done.
- The doctor decides whether your problem is suitable for an online consultation, and may decline it or refer you to someone else.
- A prescription is given only if the doctor judges it appropriate, and only within the rules for prescribing remotely. **Some medicines can't be prescribed in an online consultation.**
- **In an emergency, don't use Charak.** Call 112 or go to the nearest hospital.

## 2. What you agree to

By accepting, you agree to:

- consult a registered practitioner through Charak remotely, by video call;
- share the information you choose to give about the problem, including text, photos, video and voice notes, with that practitioner;
- Charak processing that information so the consultation can take place and be recorded in writing, including turning voice notes into text and a short summary with AI, as the Privacy Policy describes; and
- Charak and the practitioner keeping the consultation record (your description, the doctor's notes and any prescription) for as long as the law requires.

The video call itself is never recorded.

## 3. What you confirm

- The information you give is accurate and complete, to the best of your knowledge.
- You understand the limits of remote care described above.
- You will join from a private place where you can speak freely.
- If you are booking for someone else, such as a child, you are their parent, guardian or authorised representative, and you will be with them during the consultation.

## 4. Your choices

- You can choose a home visit instead, where the doctor offers one, or see a doctor in person outside Charak.
- You can stop a consultation at any time.
- You can withdraw this consent at any time by cancelling your booking, deleting your account in the app, or writing to upcharchikitsa@gmail.com. Withdrawing doesn't affect care you have already received, or records we must keep by law.
$doc$
)
on conflict (type, version) do nothing;

notify pgrst, 'reload schema';
