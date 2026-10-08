-- "Accepting requests" (design system V2, Doctor · Requests): a doctor can
-- pause new requests without leaving the platform. Paused doctors drop out of
-- search and new bookings to them are refused; existing bookings carry on.

alter table doctors
  add column if not exists accepting_requests boolean not null default true;
