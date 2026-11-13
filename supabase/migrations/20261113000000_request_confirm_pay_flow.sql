-- Booking flow, round 4: request -> owner confirms -> tourist pays the down
-- payment -> the rest is paid at the spot.
--
--   * Tourist sends a request. Nothing is paid yet. The owner has 24 hours.
--   * Owner confirms. The tourist then has 24 hours to pay the down payment
--     (until the trip day starts if that is sooner; 2 hours for a same-day trip).
--     Not paid in time = the booking closes by itself.
--   * Free cancellation ends at the earlier of 12 hours after paying or
--     12:00 AM of the trip day. A same-day trip has no free cancellation.
--     After that the owner keeps the down payment.
--   * Owner declines, owner cancels, admin cancels = full refund, always.
--   * The down payment can be at most 60% of the total.
--
-- deposit_refundable and payment_choice stay as columns but no longer decide
-- anything.

alter table public.bookings
  add column if not exists confirmed_at timestamptz,
  add column if not exists pay_by timestamptz,
  add column if not exists deposit_paid_at timestamptz,
  add column if not exists free_cancel_until timestamptz;

comment on column public.bookings.pay_by is
  'Deadline for the down payment, set when the owner confirms.';
comment on column public.bookings.free_cancel_until is
  'The tourist gets the down payment back when cancelling up to this moment.';

alter table public.destinations
  add constraint destinations_deposit_percent_cap
  check (deposit_type <> 'percent' or deposit_value <= 60);

-- ---------------------------------------------------------------------------
-- create_booking: a request only. No payment before the owner confirms.
-- ---------------------------------------------------------------------------
create or replace function public.create_booking(
  p_destination_id uuid,
  p_booking_date date,
  p_num_guests integer,
  p_contact_name text,
  p_contact_phone text,
  p_items jsonb,
  p_payment_choice text
)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_today date := (now() at time zone 'Asia/Manila')::date;
  v_dest public.destinations;
  v_svc public.destination_services;
  v_item jsonb;
  v_qty integer;
  v_seen uuid[] := '{}';
  v_lines jsonb := '[]';
  v_total numeric(10, 2) := 0;
  v_deposit numeric(10, 2) := 0;
  v_status public.payment_status;
  v_booking uuid;
begin
  if v_uid is null then
    raise exception 'Please sign in to book.';
  end if;

  select * into v_dest from public.destinations
  where id = p_destination_id and status = 'approved';
  if not found then
    raise exception 'This place is not available for booking.';
  end if;
  if v_dest.owner_id is null then
    raise exception 'This place has no owner to accept bookings yet.';
  end if;
  if p_booking_date < v_today then
    raise exception 'Pick a date from today onward.';
  end if;
  if exists (
    select 1 from public.bookings
    where tourist_id = v_uid
      and destination_id = p_destination_id
      and booking_date = p_booking_date
      and status in ('pending', 'confirmed')
  ) then
    raise exception 'You already have a booking at % on %. Open it from Trips > Bookings to change or cancel it.',
      v_dest.name, to_char(p_booking_date, 'FMMon FMDD, YYYY');
  end if;
  if p_num_guests is null or p_num_guests < 1 or p_num_guests > 100 then
    raise exception 'Enter between 1 and 100 guests.';
  end if;
  if coalesce(trim(p_contact_name), '') = '' then
    raise exception 'Enter the name the owner should look for.';
  end if;
  if coalesce(p_contact_phone, '') !~ '^(09|\+639)[0-9]{9}$' then
    raise exception 'Enter a valid Philippine mobile number, e.g. 09171234567.';
  end if;
  if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Choose at least one service.';
  end if;

  for v_item in select * from jsonb_array_elements(p_items) loop
    select * into v_svc from public.destination_services
    where id = (v_item->>'service_id')::uuid
      and destination_id = p_destination_id
      and is_active;
    if not found then
      raise exception 'One of the chosen services is no longer offered.';
    end if;
    if v_svc.id = any(v_seen) then
      raise exception 'A service was added twice.';
    end if;
    v_seen := v_seen || v_svc.id;
    v_qty := coalesce((v_item->>'quantity')::integer, 0);
    if v_qty < 1 or v_qty > 100 then
      raise exception 'Quantity for % must be between 1 and 100.', v_svc.name;
    end if;
    v_lines := v_lines || jsonb_build_object(
      'service_id', v_svc.id, 'name', v_svc.name, 'kind', v_svc.kind,
      'unit_price', v_svc.price, 'price_unit', v_svc.price_unit,
      'quantity', v_qty, 'line_total', v_svc.price * v_qty);
    v_total := v_total + v_svc.price * v_qty;
  end loop;

  -- Down payment: the owner's rule, never more than 60% of the total.
  if v_total > 0 then
    v_deposit := case v_dest.deposit_type
      when 'fixed' then least(v_dest.deposit_value, round(v_total * 0.6, 2))
      when 'percent' then round(v_total * least(v_dest.deposit_value, 60) / 100, 2)
      else 0 end;
  end if;

  v_status := case
    when v_total = 0 then 'not_required'
    when v_deposit > 0 then 'unpaid'
    else 'pay_on_site'
  end;

  insert into public.bookings (
    tourist_id, destination_id, owner_id, booking_date, num_guests,
    contact_name, contact_phone, status, payment_status, total_amount,
    payment_choice, deposit_amount, amount_due_now, deposit_refundable, respond_by
  ) values (
    v_uid, p_destination_id, v_dest.owner_id, p_booking_date, p_num_guests,
    trim(p_contact_name), p_contact_phone, 'pending', v_status, v_total,
    case when v_deposit > 0 then 'online' else 'on_site' end,
    v_deposit, v_deposit, false, now() + interval '24 hours'
  )
  returning id into v_booking;

  insert into public.booking_items
    (booking_id, service_id, name, kind, unit_price, price_unit, quantity, line_total)
  select v_booking, (l->>'service_id')::uuid, l->>'name', l->>'kind',
         (l->>'unit_price')::numeric, l->>'price_unit',
         (l->>'quantity')::integer, (l->>'line_total')::numeric
  from jsonb_array_elements(v_lines) l;

  return v_booking;
end;
$function$;

-- ---------------------------------------------------------------------------
-- Who may change what on a booking.
-- ---------------------------------------------------------------------------
create or replace function public.protect_booking_payment_fields()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  jwt_role text := coalesce(auth.jwt() ->> 'role', '');
  is_owner boolean := auth.uid() = old.owner_id;
  is_admin boolean := auth.uid() is not null and has_role('admin'::user_role);
  manila_today date := (now() at time zone 'Asia/Manila')::date;
begin
  if jwt_role = 'service_role' or auth.uid() is null
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
     or new.respond_by is distinct from old.respond_by
     or new.confirmed_at is distinct from old.confirmed_at
     or new.pay_by is distinct from old.pay_by
     or new.deposit_paid_at is distinct from old.deposit_paid_at
     or new.free_cancel_until is distinct from old.free_cancel_until then
    raise exception 'Payment fields can only be updated by verified server-side payment processing';
  end if;

  if is_admin then
    if (to_jsonb(new) - array['status', 'cancel_reason'])
       is distinct from (to_jsonb(old) - array['status', 'cancel_reason']) then
      raise exception 'Admins can only decline or cancel a booking';
    end if;
    if new.status is not distinct from old.status then
      return new;
    end if;
    if not ((old.status = 'pending' and new.status = 'rejected')
            or (old.status in ('pending', 'confirmed') and new.status = 'cancelled')) then
      raise exception 'Admins can decline a pending booking or cancel an active one. Accepting and completing are the owner''s call.';
    end if;
    if nullif(trim(coalesce(new.cancel_reason, '')), '') is null then
      raise exception 'Give the tourist a reason';
    end if;
    return new;
  end if;

  if new.status is not distinct from old.status then
    return new;
  end if;

  if is_owner then
    if old.status = 'pending' and new.status = 'confirmed' then
      -- The tourist pays after this, so nothing to check.
      null;
    elsif old.status = 'pending' and new.status = 'rejected' then
      -- Older owner builds send no reason; give the tourist a plain one.
      if nullif(trim(coalesce(new.cancel_reason, '')), '') is null then
        new.cancel_reason := 'The owner could not take this booking';
      end if;
    elsif old.status = 'confirmed' and new.status = 'cancelled' then
      if nullif(trim(coalesce(new.cancel_reason, '')), '') is null then
        raise exception 'Tell the tourist why you are cancelling';
      end if;
    elsif old.status = 'confirmed' and new.status = 'completed' then
      if old.booking_date > manila_today then
        raise exception 'A booking can only be marked completed on or after its date';
      end if;
      if old.deposit_amount > 0 and old.amount_paid < old.deposit_amount then
        raise exception 'The down payment for this booking is not paid yet';
      end if;
    else
      raise exception 'Owners can confirm or decline requests, cancel confirmed bookings, or mark them completed';
    end if;
  elsif auth.uid() = old.tourist_id then
    if new.status <> 'cancelled' then
      raise exception 'Tourists can only cancel their bookings';
    end if;
  end if;

  return new;
end;
$function$;

-- ---------------------------------------------------------------------------
-- Deadlines and refunds. Runs after the trigger above (alphabetical order), so
-- only the server sets these fields.
-- ---------------------------------------------------------------------------
create or replace function public.booking_refund_rules()
returns trigger
language plpgsql
set search_path to ''
as $function$
declare
  actor uuid := (select auth.uid());
  manila_today date := (now() at time zone 'Asia/Manila')::date;
  trip_start timestamptz := new.booking_date::timestamp at time zone 'Asia/Manila';
  closed constant text[] := array['rejected', 'cancelled'];
begin
  -- Owner confirmed: start the clock for the down payment.
  if new.status = 'confirmed' and old.status = 'pending' then
    new.confirmed_at := now();
    if new.deposit_amount > 0 and new.amount_paid < new.deposit_amount then
      new.pay_by := case
        when new.booking_date <= manila_today then now() + interval '2 hours'
        else least(now() + interval '24 hours', trip_start)
      end;
    end if;
  end if;

  -- Down payment arrived online: start the free cancellation window. For a
  -- same-day trip trip_start is already past, so there is no window.
  if new.deposit_amount > 0
     and old.amount_paid < new.deposit_amount
     and new.amount_paid >= new.deposit_amount
     and new.deposit_paid_at is null
     and actor is distinct from new.owner_id then
    new.deposit_paid_at := now();
    new.free_cancel_until := least(now() + interval '12 hours', trip_start);
  end if;

  -- Booking closed with money in it.
  if new.status::text = any(closed)
     and not (old.status::text = any(closed))
     and new.amount_paid > 0
     and new.refunded_at is null then
    if actor is not null and actor = new.tourist_id
       and (new.free_cancel_until is null or now() > new.free_cancel_until) then
      -- Tourist cancelled late: the owner keeps the down payment.
      new.refund_amount := greatest(0, new.amount_paid - new.deposit_amount);
    else
      -- Tourist in time, owner, admin or the system: everything goes back.
      new.refund_amount := new.amount_paid;
    end if;
    new.refund_due := new.refund_amount > 0;
  end if;

  -- A payment that lands after the booking already closed goes straight back.
  if new.amount_paid > old.amount_paid
     and old.status::text = any(closed)
     and new.status::text = any(closed)
     and new.refunded_at is null then
    new.refund_amount := new.amount_paid;
    new.refund_due := true;
  end if;

  return new;
end;
$function$;

-- ---------------------------------------------------------------------------
-- Every 10 minutes: close requests nobody answered and confirmed bookings
-- whose down payment did not arrive in time.
-- ---------------------------------------------------------------------------
create or replace function public.expire_unanswered_bookings()
returns integer
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_today date := (now() at time zone 'Asia/Manila')::date;
  v_a integer;
  v_b integer;
begin
  update public.bookings
     set status = 'cancelled',
         cancel_reason = 'The owner did not answer in time'
   where status = 'pending'
     and ((respond_by is not null and respond_by < now()) or booking_date < v_today);
  get diagnostics v_a = row_count;

  update public.bookings
     set status = 'cancelled',
         cancel_reason = 'The down payment was not paid in time'
   where status = 'confirmed'
     and deposit_amount > 0
     and amount_paid < deposit_amount
     and pay_by is not null
     and pay_by < now();
  get diagnostics v_b = row_count;

  return v_a + v_b;
end;
$function$;

-- ---------------------------------------------------------------------------
-- Notifications in plain words, with dates and peso amounts.
-- ---------------------------------------------------------------------------
create or replace function public.notify_booking_changes()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_dest text;
  v_date text;
  -- Same booking reference the apps show (IPG-2026-1A2B3C).
  v_ref text := 'IPG-' || to_char(new.created_at at time zone 'Asia/Manila', 'YYYY') || '-' ||
    upper(left(replace(new.id::text, '-', ''), 6));
  v_reason text := coalesce(' Reason: ' || regexp_replace(nullif(trim(new.cancel_reason), ''), '([^.!?])$', '\1.'), '');
  v_actor uuid := (select auth.uid());
  by_admin boolean := tg_op = 'UPDATE' and v_actor is not null and public.has_role('admin');
  by_owner boolean := tg_op = 'UPDATE' and v_actor is not null and v_actor = new.owner_id;
  by_tourist boolean := tg_op = 'UPDATE' and v_actor is not null and v_actor = new.tourist_id;
  v_who text := coalesce(new.contact_name, 'A tourist');
  v_kept numeric;
  v_title text;
  v_body text;
begin
  select name into v_dest from public.destinations where id = new.destination_id;
  v_date := to_char(new.booking_date, 'FMMonth FMDD, YYYY');

  if tg_op = 'INSERT' then
    perform public.notify(new.owner_id, 'New booking request',
      v_who || ' wants to book ' || coalesce(v_dest, 'your spot') ||
      ' on ' || v_date || ' (' || new.num_guests || ' guest' || case when new.num_guests > 1 then 's' else '' end ||
      '). Confirm or decline within 24 hours.',
      'booking_request');
    return new;
  end if;

  if new.status is distinct from old.status then
    v_title := case new.status
      when 'confirmed' then 'Booking confirmed'
      when 'rejected' then 'Booking declined'
      when 'cancelled' then 'Booking cancelled'
      when 'completed' then 'Trip completed'
      else 'Booking updated'
    end;

    if new.status = 'confirmed' then
      v_body := 'Your booking at ' || coalesce(v_dest, 'your destination') || ' on ' || v_date || ' was confirmed.' ||
        case when new.pay_by is not null
          then ' Pay the ₱' || new.deposit_amount || ' down payment by ' ||
               to_char(new.pay_by at time zone 'Asia/Manila', 'FMMon FMDD, FMHH12:MI AM') || ' to keep it.'
          else '' end;
    elsif new.status = 'rejected' then
      v_body := 'Sorry, your booking at ' || coalesce(v_dest, 'your destination') || ' on ' || v_date || ' was declined' ||
        case when by_admin then ' by IpilGo.' else '.' end || v_reason;
    elsif new.status = 'cancelled' then
      v_kept := new.amount_paid - new.refund_amount;
      v_body := case
          when by_tourist then 'You cancelled your booking at ' || coalesce(v_dest, 'your destination') || ' on ' || v_date || '.'
          else 'Your booking at ' || coalesce(v_dest, 'your destination') || ' on ' || v_date || ' was cancelled' ||
            case when by_admin then ' by IpilGo.' when by_owner then ' by the owner.' else '.' end || v_reason
        end ||
        case when by_tourist and v_kept > 0
          then ' Free cancellation had ended, so the ₱' || v_kept || ' down payment is not refunded.' else '' end;
    elsif new.status = 'completed' then
      v_body := 'Thanks for visiting ' || coalesce(v_dest, 'Ipil') || '! You can now leave a review.';
    else
      v_body := 'Your booking at ' || coalesce(v_dest, 'your destination') || ' was updated.';
    end if;

    perform public.notify(new.tourist_id, v_title,
      v_body || case when new.refund_due and not old.refund_due
        then ' A refund of ₱' || new.refund_amount || ' is on its way to your account.' else '' end,
      'booking_status');

    -- The owner hears about every close they did not do themselves.
    if new.status in ('rejected', 'cancelled') and not by_owner then
      perform public.notify(new.owner_id,
        case when by_admin and new.status = 'rejected' then 'Booking declined by IpilGo'
             when by_admin then 'Booking cancelled by IpilGo'
             when by_tourist then 'Booking cancelled by the tourist'
             else 'Booking closed' end,
        'The ' || v_date || ' booking of ' || v_who || ' at ' || coalesce(v_dest, 'your spot') || ' (' || v_ref || ') was ' ||
        case when by_admin and new.status = 'rejected' then 'declined by the IpilGo admin.' || v_reason
             when by_admin then 'cancelled by the IpilGo admin.' || v_reason
             when by_tourist then 'cancelled by the tourist.' ||
               case when new.amount_paid - new.refund_amount > 0
                 then ' You keep the ₱' || (new.amount_paid - new.refund_amount) || ' down payment.' else '' end
             else 'closed.' || v_reason end ||
        ' The date is free again.',
        'booking_status');
    end if;
  end if;

  if new.amount_paid > old.amount_paid then
    if v_actor = new.owner_id then
      perform public.notify(new.tourist_id, 'Cash payment recorded',
        coalesce(v_dest, 'The owner') || ' recorded ₱' || (new.amount_paid - old.amount_paid) ||
        ' cash from you for your ' || v_date || ' booking (' || v_ref || ').' ||
        case when new.amount_paid >= new.total_amount then ' Your booking is fully paid.'
             else ' Remaining balance: ₱' || (new.total_amount - new.amount_paid) || '.' end,
        'payment');
    else
      perform public.notify(new.owner_id,
        case when new.payment_status = 'paid' then 'Payment received' else 'Down payment received' end,
        v_who || ' paid ₱' || (new.amount_paid - old.amount_paid) ||
        ' for the ' || v_date || ' booking at ' || coalesce(v_dest, 'your spot') || ' (' || v_ref || ').',
        'payment');
      perform public.notify(new.tourist_id,
        case when new.payment_status = 'paid' then 'Payment received' else 'Down payment received' end,
        'We received your ₱' || (new.amount_paid - old.amount_paid) || ' for ' || coalesce(v_dest, 'your booking') ||
        ' on ' || v_date || ' (' || v_ref || ').' ||
        case when new.amount_paid >= new.total_amount then ' Your booking is fully paid.'
             else ' Pay the remaining ₱' || (new.total_amount - new.amount_paid) || ' at the spot.' end,
        'payment');
    end if;
  end if;

  if new.refunded_at is not null and old.refunded_at is null then
    perform public.notify(new.tourist_id, 'Refund sent',
      '₱' || new.refund_amount || ' for your ' || coalesce(v_dest, 'Ipil') || ' booking (' || v_ref || ') was refunded to your e-wallet.',
      'payment');
  end if;
  return new;
end;
$function$;
