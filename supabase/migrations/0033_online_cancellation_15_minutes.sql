-- 0033: the online late-cancellation rule (LD-005, D3), decided 2026-10-29.
--
-- Online consultations: a full refund up to 15 minutes before the start,
-- nothing after that. Until now an online booking got a full refund any time
-- before the consultation (version 2026-10-26).
--
-- A new version, never an edit (runbook §6c): bookings already made keep the
-- version they were made under. Like every version since 0029, it is offered
-- to new bookings only once someone approves it in admin → Policies. Approve
-- it together with the matching Cancellation & Refund Policy text (0034,
-- docs/legal/2026-10-29), which says the same thing.
--
-- Idempotent: safe to re-run in the SQL Editor.

insert into policies (kind, channel, version, rules, summary, decision_ref) values
  ('cancellation', 'online_consult', '2026-10-29',
   '[{"when": {"minutes_before_start_lt": 15}, "refund_pct": 0},
     {"when": {}, "refund_pct": 100}]',
   'Free cancellation up to 15 minutes before your consultation. After that the fee '
   'isn''t refunded. If the doctor cancels or doesn''t join, you get a full refund.',
   'LD-005 / D3')
on conflict (kind, channel, version) do nothing;
