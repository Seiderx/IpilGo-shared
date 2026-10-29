-- Owner booking actions for owner app v1.2.0.
--
--   * Owners record cash payments through owner_record_payment(); money
--     fields stay locked for direct updates.
--   * Owner status changes follow fixed rules: accept or decline a pending
--     booking, mark an accepted booking completed once its date has come.
--     Accepting needs the down payment to be paid first.
--   * destinations.entrance_fee follows the owner's active 'entrance' service,
--     so tourist cards and the AI budget use the real bookable price.
--
-- Server-side writes from these functions set the transaction-local flag
-- ipilgo.server_write, which the guard triggers trust. Clients can't set it:
-- PostgREST only exposes functions in the public schema, not set_config.

-- 1. Guard trigger: trust server writes, owner status rules, deposit gate ----
create or replace function public.protect_booking_payment_fields()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  jwt_role text := coalesce(auth.jwt() ->> 'role', '');
  is_owner boolean := auth.uid() = old.owner_id;
  manila_today date := (now() at time zone 'Asia/Manila')::date;
begin
  -- service role (edge functions), admins, scheduled jobs (no JWT) and our
  -- own security-definer functions are trusted
  if jwt_role = 'service_role' or auth.uid() is null or has_role('admin'::user_role)
     or current_setting('ipilgo.server_write', true) = 'on' then
    return new;
  end if;

  if new.payment_status is distinct from old.payment_status
     or new.payment_reference is distinct from old.payment_reference
     or new.payment_method is distinct from old.payment_method
     or new.total_amount is distinct from old.total_amount
     or new.deposit_amount is distinct from old.deposit_amount
     or new.amount_due_now is distinct from old.amount_due_now
     or new.amount_paid is distinct from old.amount_paid
     or new.payment_choice is distinct from old.payment_choice
     or new.deposit_refundable is distinct from old.deposit_refundable
     or new.refund_due is distinct from old.refund_due
     or new.refund_amount is distinct from old.refund_amount
     or new.refunded_at is distinct from old.refunded_at
     or new.respond_by is distinct from old.respond_by then
    raise exception 'Payment fields can only be updated by verified server-side payment processing';
  end if;

  if new.status is not distinct from old.status then
    return new;
  end if;

  if is_owner then
    if old.status = 'pending' and new.status = 'confirmed' then
      if old.deposit_amount > 0 and old.amount_paid < old.deposit_amount then
        raise exception 'Waiting for the tourist''s down payment before this booking can be accepted';
      end if;
    elsif old.status = 'pending' and new.status = 'rejected' then
      null;
    elsif old.status = 'confirmed' and new.status = 'completed' then
      if old.booking_date > manila_today then
        raise exception 'A booking can only be marked completed on or after its date';
      end if;
    else
      raise exception 'Owners can only accept or decline pending bookings, or mark accepted bookings completed';
    end if;
  elsif auth.uid() = old.tourist_id then
    -- tourists may only cancel
    if new.status <> 'cancelled' then
      raise exception 'Tourists can only cancel their bookings';
    end if;
  end if;

  return new;
end;
$function$;

-- 2. Owner records a cash payment -------------------------------------------
create or replace function public.owner_record_payment(p_booking_id uuid, p_amount numeric)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  b public.bookings%rowtype;
  new_paid numeric;
begin
  select * into b from public.bookings where id = p_booking_id for update;
  if not found or b.owner_id is distinct from auth.uid() then
    raise exception 'Booking not found';
  end if;
  if b.status not in ('confirmed', 'completed') then
    raise exception 'Cash can only be recorded for accepted or completed bookings';
  end if;
  p_amount := round(p_amount, 2);
  if p_amount is null or p_amount <= 0 then
    raise exception 'Enter an amount greater than zero';
  end if;
  if p_amount > b.total_amount - b.amount_paid then
    raise exception 'That is more than the remaining balance of ₱%', b.total_amount - b.amount_paid;
  end if;

  new_paid := b.amount_paid + p_amount;

  insert into public.booking_payments (booking_id, kind, amount, method, recorded_by)
  values (p_booking_id,
          case when b.amount_paid = 0 and new_paid >= b.total_amount then 'full' else 'balance' end,
          p_amount, 'cash', 'owner');

  perform set_config('ipilgo.server_write', 'on', true);
  update public.bookings
     set amount_paid = new_paid,
         payment_status = case
           when new_paid >= total_amount then 'paid'::public.payment_status
           when deposit_amount > 0 and new_paid >= deposit_amount then 'deposit_paid'::public.payment_status
           else payment_status
         end
   where id = p_booking_id;
  perform set_config('ipilgo.server_write', 'off', true);
end;
$$;

revoke all on function public.owner_record_payment(uuid, numeric) from public, anon;
grant execute on function public.owner_record_payment(uuid, numeric) to authenticated;

-- 3. Entrance fee follows the active entrance service -----------------------
-- Several entrance services (adult/child) -> the lowest price, like "from ₱X".
create or replace function public.entrance_service_price(p_destination_id uuid)
returns numeric
language sql
stable
set search_path to ''
as $$
  select min(price) from public.destination_services
   where destination_id = p_destination_id and kind = 'entrance' and is_active;
$$;

-- Owner edits can't override it while an entrance service exists.
create or replace function public.destination_entrance_fee_from_service()
 returns trigger
 language plpgsql
 set search_path to ''
as $$
declare
  svc_price numeric := public.entrance_service_price(new.id);
begin
  if svc_price is not null then
    new.entrance_fee := svc_price;
  end if;
  return new;
end;
$$;

-- Named to fire before destinations_enforce_approval (triggers run by name),
-- so an overridden fee doesn't count as an edit needing re-approval.
create or replace trigger destinations_a_entrance_fee
  before update on public.destinations
  for each row execute function public.destination_entrance_fee_from_service();

create or replace function public.sync_entrance_fee()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $$
declare
  dest uuid := coalesce(new.destination_id, old.destination_id);
  svc_price numeric := public.entrance_service_price(dest);
begin
  if svc_price is not null then
    perform set_config('ipilgo.server_write', 'on', true);
    update public.destinations set entrance_fee = svc_price
     where id = dest and entrance_fee is distinct from svc_price;
    perform set_config('ipilgo.server_write', 'off', true);
  end if;
  return null;
end;
$$;

create or replace trigger destination_services_sync_entrance_fee
  after insert or update or delete on public.destination_services
  for each row execute function public.sync_entrance_fee();

-- A price change from a service is not a listing edit: no re-approval.
create or replace function public.enforce_destination_approval()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  if current_setting('ipilgo.server_write', true) = 'on' then
    return new;
  end if;
  if (select auth.uid()) is not null and not public.has_role('admin') then
    if tg_op = 'INSERT' then
      new.status := 'pending';
      new.avg_rating := 0;
    elsif (select auth.uid()) = old.owner_id then
      new.avg_rating := old.avg_rating;
      if (new.name, new.description, new.category, new.tags, new.address,
          new.latitude, new.longitude, new.operating_hours, new.entrance_fee,
          new.amenities, new.images, new.panoramic_360_url,
          new.contact_number, new.contact_email)
         is distinct from
         (old.name, old.description, old.category, old.tags, old.address,
          old.latitude, old.longitude, old.operating_hours, old.entrance_fee,
          old.amenities, old.images, old.panoramic_360_url,
          old.contact_number, old.contact_email) then
        new.status := 'pending';
      else
        new.status := old.status;
      end if;
    elsif new.status is distinct from old.status then
      new.status := old.status;
    end if;
  end if;
  return new;
end;
$function$;

-- No backfill: no spot had an entrance service when this was applied.
