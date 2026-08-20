-- Performance indexes

-- Bookings: doctor Requests tab query + slot conflict check
create index idx_bookings_doctor_start   on bookings (doctor_id, scheduled_start);
create index idx_bookings_doctor_status  on bookings (doctor_id, status) where status = 'requested';
create index idx_bookings_patient        on bookings (patient_id);

-- Schedule lookup
create index idx_schedules_doctor_dow    on doctor_schedules (doctor_id, day_of_week);

-- Slot blocks
create index idx_slot_blocks_doctor_date on doctor_slot_blocks (doctor_id, date);

-- Intake media
create index idx_intake_booking          on intake_media (booking_id);

-- Audit trail
create index idx_audit_entity            on audit_log (entity, entity_id);

-- Consents
create index idx_consents_user           on consents (user_id);

-- Payments — idempotency
-- razorpay_order_id already has UNIQUE constraint → implicit index
