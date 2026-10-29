-- 0032: audit follow-ups in the database.
--
--  1. start_replacement refuses an original visit that went ahead, as
--     apply_remedy_refund already does (one payment must not fund two visits).
--  2. expire_payment_holds leaves a booking alone when its consult fee has been
--     captured, so a half-finished payment confirmation cannot end in a
--     cancelled booking with no refund.
--  3. A patient's review comments can be erased after the edit window. Scores
--     stay (the doctor's rating is built from them); the free text, which can
--     name a person or a condition, goes.

-- 1.
create or replace function start_replacement(
  p_incident_id uuid,
  p_patient_id  uuid,
  p_booking     jsonb
) returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_inc      incidents%rowtype;
  v_orig     bookings%rowtype;
  v_payment  payments%rowtype;
  v_budget   bigint;
  v_price    bigint := (p_booking->>'price_paise')::bigint;
  v_new      bookings%rowtype;
  v_result   jsonb;
begin
  select booking_id into v_orig.id from incidents where id = p_incident_id;
  if v_orig.id is null then
    return jsonb_build_object('outcome', 'not_found');
  end if;
  select * into v_orig from bookings where id = v_orig.id for update;
  select * into v_inc from incidents where id = p_incident_id for update;
  if v_inc.patient_id is distinct from p_patient_id then
    return jsonb_build_object('outcome', 'forbidden');
  end if;
  if v_inc.remedy in ('refund', 'replacement', 'rescheduled') then
    return jsonb_build_object('outcome', 'already', 'remedy', v_inc.remedy);
  end if;
  if not v_inc.remedy_eligible then
    return jsonb_build_object('outcome', 'not_eligible');
  end if;
  -- remedy_eligible is a snapshot from when the patient reported. If the visit
  -- went ahead after all (the doctor was just late), a replacement would pay a
  -- second doctor from the same payment and leave the first one's credit
  -- standing. apply_remedy_refund already refuses this; so must this.
  if v_orig.status in ('in_progress', 'consulted', 'completed') then
    return jsonb_build_object('outcome', 'not_eligible');
  end if;

  select * into v_payment from payments
   where booking_id = v_orig.id and type = 'consult_fee' and status in ('completed', 'partially_refunded')
   order by created_at limit 1 for update;
  if not found then
    return jsonb_build_object('outcome', 'not_eligible');
  end if;
  v_budget := payment_refundable_paise(v_payment.id);
  if v_price > v_budget then
    return jsonb_build_object('outcome', 'over_budget', 'budget_paise', v_budget);
  end if;

  if v_orig.status in ('paid', 'accepted', 'requested') then
    v_result := transition_booking(v_orig.id, 'cancel', 'ops', null, v_orig.status,
                                   jsonb_build_object('cancelled_by', 'ops', 'hold_expires_at', null),
                                   'replacement:' || p_incident_id::text,
                                   jsonb_build_object('reason_code', 'doctor_no_show', 'remedy', 'replacement'));
    if v_result->>'outcome' not in ('ok', 'replayed') then
      return v_result;
    end if;
    perform reverse_ledger_credit(v_orig.id, 'consult_fee', 'doctor no-show: paid to a replacement doctor', null);
  end if;

  begin
    insert into bookings (patient_id, doctor_id, channel, scheduled_start, scheduled_end, duration_min,
                          price_paise, price_confirmed, price_rule_id, visit_category, category_id,
                          status, replaces_booking_id, prepaid_from_payment_id,
                          address_id, patient_address, patient_address_lat, patient_address_lng,
                          distance_km, cancellation_policy_id)
    values (p_patient_id, (p_booking->>'doctor_id')::uuid, p_booking->>'channel',
            (p_booking->>'scheduled_start')::timestamptz,
            (p_booking->>'scheduled_start')::timestamptz + make_interval(mins => (p_booking->>'duration_min')::int),
            (p_booking->>'duration_min')::int, v_price, v_price / 100.0,
            nullif(p_booking->>'price_rule_id', '')::uuid, 'initial',
            nullif(p_booking->>'category_id', '')::uuid, 'requested', v_orig.id, v_payment.id,
            nullif(p_booking->>'address_id', '')::uuid, p_booking->>'patient_address',
            (p_booking->>'patient_address_lat')::double precision,
            (p_booking->>'patient_address_lng')::double precision,
            (p_booking->>'distance_km')::numeric,
            nullif(p_booking->>'cancellation_policy_id', '')::uuid)
    returning * into v_new;
  exception when unique_violation or exclusion_violation then
    raise exception using errcode = 'P0001', message = 'slot_taken';
  end;

  update incidents set remedy = 'replacement', remedy_booking_id = v_new.id where id = p_incident_id;
  insert into incident_events (incident_id, event, actor_role, actor_id, metadata)
  values (p_incident_id, 'remedy_replacement_requested', 'patient', p_patient_id,
          jsonb_build_object('booking_id', v_new.id, 'price_paise', v_price, 'budget_paise', v_budget));
  return jsonb_build_object('outcome', 'ok', 'booking', to_jsonb(v_new), 'budget_paise', v_budget);
end;
$$;

-- 2.
create or replace function expire_payment_holds(p_now timestamptz default now())
returns setof uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_id     uuid;
  v_result jsonb;
begin
  for v_id in
    select id from bookings
     where status = 'accepted' and hold_expires_at < p_now
       -- A booking whose consult fee was captured is not unpaid, whatever its
       -- status says: the capture's confirmation may have failed part way (the
       -- payment is recorded before the booking moves to paid). Cancelling it
       -- here would keep the patient's money and the doctor's credit with no
       -- refund. Leave it for the webhook redelivery to finish.
       and not exists (select 1 from payments p
                        where p.booking_id = bookings.id and p.type = 'consult_fee'
                          and p.status in ('completed', 'partially_refunded'))
     order by hold_expires_at
     for update skip locked
  loop
    v_result := transition_booking(
      v_id, 'hold_expire', 'system', null, 'accepted',
      jsonb_build_object('cancelled_by', 'system', 'hold_expires_at', null)
    );
    if v_result->>'outcome' = 'ok' then
      update payments set status = 'failed'
       where booking_id = v_id and status = 'initiated';
      return next v_id;
    end if;
  end loop;
end;
$$;

-- 3.
create or replace function guard_review()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    if pg_trigger_depth() <= 1
       and coalesce(current_setting('charak.retention_purge', true), '') <> 'on' then
      raise exception 'reviews are not deleted; hide one with a reason instead'
        using errcode = 'insufficient_privilege';
    end if;
    return old;
  end if;
  if (new.booking_id, new.doctor_id, new.patient_id, new.created_at, new.editable_until)
     is distinct from (old.booking_id, old.doctor_id, old.patient_id, old.created_at, old.editable_until) then
    raise exception 'a review''s author and visit are fixed' using errcode = 'insufficient_privilege';
  end if;
  if (new.overall, new.professionalism, new.communication, new.punctuality, new.comment)
     is distinct from (old.overall, old.professionalism, old.communication, old.punctuality, old.comment)
     and now() > old.editable_until
     -- Erasure (redact_patient_reviews) clears the comment after the window.
     and coalesce(current_setting('charak.retention_purge', true), '') <> 'on' then
    raise exception 'this review can no longer be edited' using errcode = 'insufficient_privilege';
  end if;
  return new;
end;
$$;

create or replace function redact_patient_reviews(p_patient_id uuid)
returns integer
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_count integer;
begin
  perform set_config('charak.retention_purge', 'on', true);   -- this transaction only
  update reviews set comment = null where patient_id = p_patient_id and comment is not null;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- Same lockdown as every function since 0021: only the backend (service_role).
revoke execute on function start_replacement(uuid, uuid, jsonb)   from public, anon, authenticated;
revoke execute on function expire_payment_holds(timestamptz)      from public, anon, authenticated;
revoke execute on function redact_patient_reviews(uuid)           from public, anon, authenticated;
grant  execute on function start_replacement(uuid, uuid, jsonb)   to service_role;
grant  execute on function expire_payment_holds(timestamptz)      to service_role;
grant  execute on function redact_patient_reviews(uuid)           to service_role;
