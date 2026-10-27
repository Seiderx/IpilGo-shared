-- Booking rework: spot-owner services, deposits, refunds, payment ledger.
--
-- Ipil has no tour guide association, so bookings are now for services a
-- registered spot owner offers (boat, cottage, entrance, guide, ...), each
-- with its own price. Owners can require a down payment before accepting;
-- if they decline or don't answer within 24h it is refunded automatically.
--
--   destination_services  what an owner offers, with prices
--   destinations.deposit_* the owner's down-payment rule
--   booking_items         the services in one booking, price snapshotted
--   booking_payments      every payment/refund (the "inventory of payments")
--   create_booking()      the only way to create a booking: totals, deposit
--                         and payment status are computed here, never by the app

-- 1. Services ---------------------------------------------------------------
create table if not exists public.destination_services (
  id uuid primary key default gen_random_uuid(),
  destination_id uuid not null references public.destinations(id) on delete cascade,
  name text not null check (length(trim(name)) between 1 and 80),
  kind text not null default 'other'
    check (kind in ('guide', 'boat', 'cottage', 'entrance', 'other')),
  description text,
  price numeric(10, 2) not null default 0 check (price >= 0),
  price_unit text not null default 'per_person'
    check (price_unit in ('per_person', 'per_group', 'per_hour', 'per_item')),
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);
create index if not exists destination_services_destination_idx
  on public.destination_services (destination_id);

alter table public.destination_services enable row level security;

create policy "Anyone can view active services of approved destinations"
  on public.destination_services for select to anon, authenticated
  using (
    is_active and exists (
      select 1 from public.destinations d
      where d.id = destination_id and d.status = 'approved'
    )
  );

create policy "Owners manage services of own destinations"
  on public.destination_services for all to authenticated
  using (exists (
    select 1 from public.destinations d
    where d.id = destination_id and d.owner_id = (select auth.uid())
  ))
  with check (exists (
    select 1 from public.destinations d
    where d.id = destination_id and d.owner_id = (select auth.uid())
  ));

create policy "Admins have full access to services"
  on public.destination_services for all to authenticated
  using (public.has_role('admin'::public.user_role))
  with check (public.has_role('admin'::public.user_role));

-- 2. Owner's down-payment rule ------------------------------------------------
alter table public.destinations
  add column if not exists deposit_type text not null default 'none'
    check (deposit_type in ('none', 'fixed', 'percent')),
  add column if not exists deposit_value numeric(10, 2) not null default 0
    check (deposit_value >= 0),
  add column if not exists deposit_refundable boolean not null default true;

-- 3. Payment states -----------------------------------------------------------
alter type public.payment_status add value if not exists 'not_required';
alter type public.payment_status add value if not exists 'pay_on_site';
alter type public.payment_status add value if not exists 'deposit_paid';

-- 4. Money on the booking -----------------------------------------------------
alter table public.bookings
  add column if not exists payment_choice text not null default 'online'
    check (payment_choice in ('online', 'on_site')),
  add column if not exists deposit_amount numeric(10, 2) not null default 0,
  add column if not exists amount_due_now numeric(10, 2) not null default 0,
  add column if not exists amount_paid numeric(10, 2) not null default 0,
  add column if not exists deposit_refundable boolean not null default true,
  add column if not exists respond_by timestamptz,
  add column if not exists refund_due boolean not null default false,
  add column if not exists refund_amount numeric(10, 2) not null default 0,
  add column if not exists refunded_at timestamptz;

-- 5. Services in a booking ----------------------------------------------------
create table if not exists public.booking_items (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.bookings(id) on delete cascade,
  service_id uuid references public.destination_services(id) on delete set null,
  name text not null,
  kind text not null,
  unit_price numeric(10, 2) not null,
  price_unit text not null,
  quantity integer not null check (quantity > 0),
  line_total numeric(10, 2) not null
);
create index if not exists booking_items_booking_idx on public.booking_items (booking_id);

alter table public.booking_items enable row level security;

create policy "Booking parties can view items"
  on public.booking_items for select to authenticated
  using (exists (
    select 1 from public.bookings b
    where b.id = booking_id
      and (b.tourist_id = (select auth.uid()) or b.owner_id = (select auth.uid()))
  ));

create policy "Admins have full access to booking items"
  on public.booking_items for all to authenticated
  using (public.has_role('admin'::public.user_role))
  with check (public.has_role('admin'::public.user_role));

-- 6. Payment ledger -----------------------------------------------------------
create table if not exists public.booking_payments (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.bookings(id) on delete cascade,
  kind text not null check (kind in ('deposit', 'full', 'balance', 'refund')),
  amount numeric(10, 2) not null check (amount > 0),
  method text,
  reference text unique,
  recorded_by text not null check (recorded_by in ('paymongo', 'owner', 'system')),
  created_at timestamptz not null default now()
);
create index if not exists booking_payments_booking_idx on public.booking_payments (booking_id);

alter table public.booking_payments enable row level security;

create policy "Booking parties can view payments"
  on public.booking_payments for select to authenticated
  using (exists (
    select 1 from public.bookings b
    where b.id = booking_id
      and (b.tourist_id = (select auth.uid()) or b.owner_id = (select auth.uid()))
  ));

create policy "Admins have full access to payments"
  on public.booking_payments for all to authenticated
  using (public.has_role('admin'::public.user_role))
  with check (public.has_role('admin'::public.user_role));

-- 7. Money fields are server-only ---------------------------------------------
-- Before this, a tourist could edit total_amount on their own booking and the
-- checkout would charge that amount. Every money field is now locked to the
-- service role (edge functions) and admins.
create or replace function public.protect_booking_payment_fields()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  jwt_role text := coalesce(auth.jwt() ->> 'role', '');
begin
  -- service role (edge functions), admins and scheduled jobs (no JWT) are trusted
  if jwt_role = 'service_role' or auth.uid() is null or has_role('admin'::user_role) then
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

  -- tourists (non-owners of the row) may only cancel
  if auth.uid() = old.tourist_id and auth.uid() is distinct from old.owner_id then
    if new.status is distinct from old.status and new.status <> 'cancelled' then
      raise exception 'Tourists can only cancel their bookings';
    end if;
  end if;

  return new;
end;
$function$;

-- 8. Refund rules -------------------------------------------------------------
-- Owner declines, or nobody answered in time: full refund. Tourist cancels
-- before the owner accepted: full refund. Tourist cancels after acceptance:
-- the deposit is kept if the owner marked it non-refundable.
create or replace function public.booking_refund_rules()
 returns trigger
 language plpgsql
 set search_path to ''
as $function$
declare
  full_refund boolean;
begin
  if new.status in ('rejected', 'cancelled')
     and old.status not in ('rejected', 'cancelled')
     and new.amount_paid > 0
     and new.refunded_at is null then
    full_refund := new.status = 'rejected' or old.status = 'pending' or new.deposit_refundable;
    new.refund_amount := case when full_refund then new.amount_paid
                              else greatest(0, new.amount_paid - new.deposit_amount) end;
    new.refund_due := new.refund_amount > 0;
  end if;
  return new;
end;
$function$;

create trigger bookings_refund_rules
  before update on public.bookings
  for each row execute function public.booking_refund_rules();

-- 9. Creating a booking -------------------------------------------------------
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
as $$
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

  -- Price every line from the owner's current price list.
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
$$;

revoke all on function public.create_booking(uuid, date, integer, text, text, jsonb, text) from public;
grant execute on function public.create_booking(uuid, date, integer, text, text, jsonb, text) to authenticated;

-- 10. Notifications wording: bookings are for services, not only guides -------
create or replace function public.notify_booking_changes()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_dest text;
  v_date text;
begin
  select name into v_dest from public.destinations where id = new.destination_id;
  v_date := to_char(new.booking_date, 'FMMonth FMDD, YYYY');

  if tg_op = 'INSERT' then
    perform public.notify(new.owner_id, 'New booking request',
      coalesce(new.contact_name, 'A tourist') || ' wants to book ' || coalesce(v_dest, 'your spot') ||
      ' on ' || v_date || ' (' || new.num_guests || ' guest' || case when new.num_guests > 1 then 's' else '' end || ').' ||
      case when new.deposit_amount > 0 then ' Their down payment is due within 24 hours.' else '' end,
      'booking_request');
    return new;
  end if;

  if new.status is distinct from old.status then
    perform public.notify(new.tourist_id,
      case new.status
        when 'confirmed' then 'Booking confirmed'
        when 'rejected' then 'Booking declined'
        when 'cancelled' then 'Booking cancelled'
        when 'completed' then 'Trip completed'
        else 'Booking updated'
      end,
      case new.status
        when 'confirmed' then 'Your booking at ' || coalesce(v_dest, 'your destination') || ' on ' || v_date || ' was accepted.'
        when 'rejected' then 'Sorry, your booking at ' || coalesce(v_dest, 'your destination') || ' on ' || v_date || ' was declined.'
        when 'cancelled' then 'Your booking at ' || coalesce(v_dest, 'your destination') || ' on ' || v_date || ' was cancelled.'
        when 'completed' then 'Thanks for visiting ' || coalesce(v_dest, 'Ipil') || '! You can now leave a review.'
        else 'Your booking at ' || coalesce(v_dest, 'your destination') || ' was updated.'
      end ||
      case when new.refund_due and not old.refund_due
        then ' A refund of ₱' || new.refund_amount || ' is on its way to your account.' else '' end,
      'booking_status');
  end if;

  if new.amount_paid > old.amount_paid then
    perform public.notify(new.owner_id,
      case when new.payment_status = 'paid' then 'Payment received' else 'Down payment received' end,
      coalesce(new.contact_name, 'A tourist') || ' paid ₱' || (new.amount_paid - old.amount_paid) ||
      ' for the ' || v_date || ' booking at ' || coalesce(v_dest, 'your spot') || '.',
      'payment');
  end if;

  if new.refunded_at is not null and old.refunded_at is null then
    perform public.notify(new.tourist_id, 'Refund sent',
      '₱' || new.refund_amount || ' for your ' || coalesce(v_dest, 'Ipil') || ' booking was refunded to your e-wallet.',
      'payment');
  end if;
  return new;
end;
$function$;

-- 11. No answer in 24h: cancel (which makes any down payment refund_due) -----
create or replace function public.expire_unanswered_bookings()
returns integer
language sql
security definer
set search_path to ''
as $$
  with expired as (
    update public.bookings
       set status = 'cancelled'
     where status = 'pending'
       and respond_by is not null
       and respond_by < now()
    returning 1
  )
  select count(*)::integer from expired;
$$;

revoke all on function public.expire_unanswered_bookings() from public, anon, authenticated;
