-- 0020: direct-to-doctor payouts and doctor-set session length.
--
-- Charak keeps no fee at launch: every rupee a patient pays goes to the
-- doctor. Many doctors would rather be paid on UPI than to a bank account, so
-- a payout destination is now a UPI ID, a bank account, or both, never
-- neither. Bank details still come as a pair (number + IFSC).

alter table doctor_bank_accounts alter column account_number drop not null;
alter table doctor_bank_accounts alter column ifsc           drop not null;

alter table doctor_bank_accounts drop constraint if exists doctor_bank_accounts_destination;
alter table doctor_bank_accounts add constraint doctor_bank_accounts_destination check (
  ((account_number is null) = (ifsc is null))
  and (account_number is not null or upi_id is not null)
);

-- doctor_pricing.base_duration_min already exists (0001, default 15). It is
-- now set by the doctor, as is the length of each extra-time block, which
-- extra_rate_per_15min is charged per (the column name predates this; it is
-- the rate per extra_duration_min block).
alter table doctor_pricing add column if not exists extra_duration_min int not null default 15;

alter table doctor_pricing drop constraint if exists doctor_pricing_base_duration_min;
alter table doctor_pricing add constraint doctor_pricing_base_duration_min
  check (base_duration_min between 5 and 120 and base_duration_min % 5 = 0);
alter table doctor_pricing drop constraint if exists doctor_pricing_extra_duration_min;
alter table doctor_pricing add constraint doctor_pricing_extra_duration_min
  check (extra_duration_min between 5 and 120 and extra_duration_min % 5 = 0);
