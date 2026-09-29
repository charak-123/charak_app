-- Performance indexes for paths that had none.
--
-- Each of these backs a query that runs on a user-facing request or on the
-- cron job, against a table that grows without bound. Postgres creates an
-- index for a UNIQUE constraint but not for a plain foreign key, which is why
-- several booking_id columns were unindexed.

-- ── payments ────────────────────────────────────────────────────────────────
-- payments.booking_id is a plain FK, so it had no index at all, and payments
-- grows with every attempt (not every booking). Three paths hit it:
--   create_order / _amount_due   → (booking_id, type)
--   get_payment                  → (booking_id)
--   release_expired_holds        → (booking_id) IN (...) AND status='initiated'
create index if not exists idx_payments_booking_type
  on payments (booking_id, type);

-- The cleanup job only ever looks for initiated rows; a partial index keeps it
-- small and stops it growing with completed payment history.
create index if not exists idx_payments_initiated
  on payments (booking_id)
  where status = 'initiated';

-- ── bookings ────────────────────────────────────────────────────────────────
-- idx_bookings_doctor_status (0002) is partial on status='requested', so it
-- serves /doctor/incoming and nothing else. These three do not have a usable
-- index and all run on tab switches:
--   /bookings/doctor/active   → status in (accepted, paid)
--   /bookings/doctor/history  → status in (completed, declined, cancelled, no_show)
--   /earnings/me              → status = 'completed'
create index if not exists idx_bookings_doctor_status_all
  on bookings (doctor_id, status);

-- get_available_slots filters by doctor and a scheduled_start range, then the
-- status set. idx_bookings_doctor_start covers the first two; adding status
-- lets the whole predicate be satisfied from the index on the busiest read in
-- the product (every patient browsing any doctor).
create index if not exists idx_bookings_doctor_start_status
  on bookings (doctor_id, scheduled_start, status);

-- The patient's own list sorts by scheduled_start; idx_bookings_patient (0002)
-- covers the filter but leaves the sort to be done in memory.
create index if not exists idx_bookings_patient_start
  on bookings (patient_id, scheduled_start desc);

-- ── complaints ──────────────────────────────────────────────────────────────
-- Plain FK, no index. Read per booking from both apps and listed in admin.
create index if not exists idx_complaints_booking
  on complaints (booking_id);
