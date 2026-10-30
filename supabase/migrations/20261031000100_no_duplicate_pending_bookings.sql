-- A tourist could book the same place for the same date again while the
-- first booking was still pending, leaving duplicate requests for the owner.
-- create_booking now refuses when the tourist already has a pending or
-- confirmed booking there on that date (cancelled/declined/expired ones
-- don't count). Only the new check differs from the previous version.

create or replace function public.create_booking(p_destination_id uuid, p_booking_date date, p_num_guests integer, p_contact_name text, p_contact_phone text, p_items jsonb, p_payment_choice text)
 returns uuid
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_dest public.destinations;
  v_svc public.destination_services;
  v_item jsonb;
  v_qty integer;
  v_seen uuid[] := '{}';
  v_lines jsonb := '[]';
  v_total numeric(10, 2) := 0;
  v_deposit numeric(10, 2) := 0;
  v_due numeric(10, 2);
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
  if p_booking_date < current_date then
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
  if p_payment_choice not in ('online', 'on_site') then
    raise exception 'Choose how you will pay.';
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

  if v_total > 0 then
    v_deposit := case v_dest.deposit_type
      when 'fixed' then least(v_dest.deposit_value, v_total)
      when 'percent' then round(v_total * least(v_dest.deposit_value, 100) / 100, 2)
      else 0 end;
  end if;

  if v_total = 0 then
    v_due := 0;
    v_status := 'not_required';
  elsif v_deposit > 0 then
    if p_payment_choice = 'on_site' then
      raise exception 'This place needs an online down payment of ₱% to hold your booking.', v_deposit;
    end if;
    v_due := v_deposit;
    v_status := 'unpaid';
  elsif p_payment_choice = 'on_site' then
    v_due := 0;
    v_status := 'pay_on_site';
  else
    v_due := v_total;
    v_status := 'unpaid';
  end if;

  insert into public.bookings (
    tourist_id, destination_id, owner_id, booking_date, num_guests,
    contact_name, contact_phone, status, payment_status, total_amount,
    payment_choice, deposit_amount, amount_due_now, deposit_refundable, respond_by
  ) values (
    v_uid, p_destination_id, v_dest.owner_id, p_booking_date, p_num_guests,
    trim(p_contact_name), p_contact_phone, 'pending', v_status, v_total,
    p_payment_choice, v_deposit, v_due, v_dest.deposit_refundable,
    case when v_deposit > 0 then now() + interval '24 hours' end
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
