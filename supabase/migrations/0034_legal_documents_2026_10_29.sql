-- ═══════════════════════════════════════════════════════════════════════════
-- 0034: legal documents, version 2026-10-29. Generated; do not edit.
--
--   python3 docs/legal/publish.py 2026-10-29 0034
--
-- From docs/legal/2026-10-29/. Each version applies only once it is
-- approved in admin → Policies (the review gate, migration 0029). Until
-- then the apps keep showing the version people already accepted.
--
-- Fingerprints (legal_documents.sha256, set by the database from the body):
--   refund_policy        2ded54495d6a5d08da00b8f83ad83a478f021179e8f9c2c65256f95516b81ae7
--
-- Idempotent: safe to re-run in the SQL Editor.
-- ═══════════════════════════════════════════════════════════════════════════

-- Cancellation & Refund Policy
insert into legal_documents (type, version, title, url, audience, material, summary, highlights, body)
values (
  'refund_policy', '2026-10-29', 'Cancellation & Refund Policy',
  'https://www.charak.care/refunds', '{patient,doctor}', true,
  'What happens to your money when a booking is cancelled, moved or missed, by either side.',
  jsonb_build_array(
    'You pay only after the doctor accepts your request, so withdrawing a request never costs anything.',
    'Online consultations: a full refund up to 15 minutes before the consultation, and nothing after that.',
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

- **15 minutes or more before the consultation: full refund.**
- **Less than 15 minutes before the consultation: no refund.** The doctor has kept that time for you and can't offer it to anyone else at such short notice.
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

notify pgrst, 'reload schema';
