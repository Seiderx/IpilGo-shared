-- "Not received" leaves a mark on the booking, so the tourist's booking page
-- can say "Payment not found: check your GCash, then pay again" instead of
-- just showing the pay button again with no reason.
-- Set by owner_review_payment(false); cleared by tourist_mark_paid and by
-- owner_review_payment(true).

alter table public.bookings add column if not exists payment_not_found_at timestamptz;

create or replace function public.tourist_mark_paid(p_booking_id uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  b public.bookings;
begin
  select * into b from public.bookings where id = p_booking_id for update;
  if not found or b.tourist_id is distinct from auth.uid() then
    raise exception 'Booking not found.';
  end if;
  if b.status <> 'confirmed' or b.deposit_amount <= 0 or b.amount_paid >= b.deposit_amount then
    raise exception 'This booking has no down payment to pay.';
  end if;
  if b.paid_claimed_at is not null then
    return;
  end if;

  perform set_config('ipilgo.server_write', 'on', true);
  update public.bookings
     set paid_claimed_at = now(),
         payment_not_found_at = null
   where id = p_booking_id;
  perform set_config('ipilgo.server_write', 'off', true);
end;
$$;

create or replace function public.owner_review_payment(p_booking_id uuid, p_received boolean)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  b public.bookings;
  v_amount numeric(10, 2);
  v_paid numeric(10, 2);
begin
  select * into b from public.bookings where id = p_booking_id for update;
  if not found or b.owner_id is distinct from auth.uid() then
    raise exception 'Booking not found.';
  end if;
  if b.paid_claimed_at is null then
    raise exception 'The tourist has not said they paid yet.';
  end if;
  if b.status <> 'confirmed' then
    raise exception 'This booking is no longer active.';
  end if;

  perform set_config('ipilgo.server_write', 'on', true);
  if p_received then
    v_amount := b.deposit_amount - b.amount_paid;
    v_paid := b.amount_paid + v_amount;
    insert into public.booking_payments (booking_id, kind, amount, method, recorded_by)
    values (p_booking_id,
            case when b.amount_paid = 0 and v_paid >= b.total_amount then 'full' else 'deposit' end,
            v_amount, 'gcash', 'owner');
    update public.bookings
       set amount_paid = v_paid,
           payment_method = 'gcash',
           payment_status = case when v_paid >= total_amount then 'paid'::public.payment_status
                                 else 'deposit_paid'::public.payment_status end,
           deposit_paid_at = now(),
           paid_claimed_at = null,
           payment_not_found_at = null
     where id = p_booking_id;
  else
    update public.bookings
       set paid_claimed_at = null,
           payment_not_found_at = now(),
           pay_by = greatest(coalesce(pay_by, now()), now() + interval '2 hours')
     where id = p_booking_id;
  end if;
  perform set_config('ipilgo.server_write', 'off', true);
end;
$$;
