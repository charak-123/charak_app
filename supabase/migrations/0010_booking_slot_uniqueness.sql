-- Close the double-booking race.
--
-- bookings.create checked for a conflicting row and then inserted, which leaves a
-- window between the SELECT and the INSERT: two patients tapping the same slot
-- concurrently both saw it free and both got a booking. The check is still worth
-- keeping — it produces the friendly 409 in the common case — but the guarantee
-- has to live in the database, where concurrent transactions actually serialise.
--
-- Partial, because only live bookings hold a slot. A declined or cancelled booking
-- releases it, and the same doctor/time must then be bookable again. These three
-- statuses mirror SLOT_HOLDING_STATUSES in app/routers/bookings.py — changing one
-- without the other reopens the race.

create unique index if not exists uq_booking_doctor_slot_active
  on bookings (doctor_id, scheduled_start)
  where status in ('requested', 'accepted', 'paid');

-- If this migration fails with "could not create unique index", the table already
-- holds a double-booking. Find them first, then resolve each by hand — refunding
-- or rescheduling the later one — before re-running:
--
--   select doctor_id, scheduled_start, count(*), array_agg(id order by created_at)
--     from bookings
--    where status in ('requested', 'accepted', 'paid')
--    group by doctor_id, scheduled_start
--   having count(*) > 1;
