-- Payments move from PayMongo to the owner's own GCash QR.
--
--   * Owner saves their GCash QR (the decoded QR Ph text) in Profile > Payments.
--     An owner can't confirm a booking that needs a down payment without it.
--   * After the owner confirms, the tourist scans the QR (the app puts the
--     amount inside it), pays in GCash, and taps "I've paid".
--     While the owner checks, the pay deadline is paused.
--   * Owner taps Received (payment recorded) or Not received (tourist pays
--     again, deadline pushed at least 2 hours).
--   * Refunds: tourist cancels = no refund. Owner, admin or system closes a
--     paid booking = the owner sends it back by GCash within 3 days and taps
--     "I've refunded". Late refunds show in the admin panel.
--   * The 12-hour free cancellation window is gone.
--   * The PayMongo auto-refund job is stopped (the edge functions go next).

-- 1. Owner's GCash QR ------------------------------------------------------------
alter table public.profiles
  add column if not exists gcash_qr text
    check (gcash_qr is null or (gcash_qr like '000201%' and length(gcash_qr) between 20 and 512));

comment on column public.profiles.gcash_qr is
  'Owner''s GCash QR Ph payload (EMVCo text). The tourist app adds the amount and redraws it.';

-- 2. Booking fields ----------------------------------------------------------------
alter table public.bookings
  add column if not exists paid_claimed_at timestamptz,
  add column if not exists refund_by timestamptz;

comment on column public.bookings.paid_claimed_at is
  'Tourist tapped "I''ve paid"; the owner has not checked yet. Pauses pay_by.';
comment on column public.bookings.refund_by is
  'The owner must send the refund back by GCash before this.';

-- 3. Stop the PayMongo auto-refund job (refund_due now means "the owner owes it")
do $$
begin
  if exists (select 1 from cron.job where jobname = 'process-booking-refunds') then
    perform cron.unschedule('process-booking-refunds');
  end if;
end $$;

-- 4. Who may change what -------------------------------------------------------------
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
     or new.free_cancel_until is distinct from old.free_cancel_until
     or new.paid_claimed_at is distinct from old.paid_claimed_at
     or new.refund_by is distinct from old.refund_by then
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
      if old.deposit_amount > 0 and not exists (
        select 1 from profiles where id = old.owner_id and gcash_qr is not null
      ) then
        raise exception 'Add your GCash QR in Profile > Payments first, so the tourist can pay the down payment';
      end if;
    elsif old.status = 'pending' and new.status = 'rejected' then
      if nullif(trim(coalesce(new.cancel_reason, '')), '') is null then
        new.cancel_reason := 'The owner could not take this booking';
      end if;
    elsif old.status = 'confirmed' and new.status = 'cancelled' then
      if old.paid_claimed_at is not null then
        raise exception 'The tourist says they paid. Check your GCash and tap Received or Not received first';
      end if;
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
    if old.paid_claimed_at is not null then
      raise exception 'The owner is checking your payment. Wait for their answer before cancelling';
    end if;
  end if;

  return new;
end;
$function$;

-- 5. Deadlines and refunds -----------------------------------------------------------
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

  -- Booking closed with money in it.
  if new.status::text = any(closed)
     and not (old.status::text = any(closed))
     and new.amount_paid > 0
     and new.refunded_at is null then
    if actor is not null and actor = new.tourist_id then
      -- Tourist cancelled: the down payment is never refunded.
      new.refund_amount := 0;
    else
      -- Owner, admin or the system closed it: the owner sends it all back.
      new.refund_amount := new.amount_paid;
    end if;
    new.refund_due := new.refund_amount > 0;
    new.refund_by := case when new.refund_due then now() + interval '3 days' end;
  end if;

  return new;
end;
$function$;

-- 6. Close requests nobody answered and unpaid bookings (not while the owner checks)
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
     and paid_claimed_at is null
     and pay_by is not null
     and pay_by < now();
  get diagnostics v_b = row_count;

  return v_a + v_b;
end;
$function$;

-- 7. Tourist: the owner's QR for a booking they must pay ------------------------------
create or replace function public.booking_payment_qr(p_booking_id uuid)
returns text
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  b public.bookings;
  v_qr text;
begin
  select * into b from public.bookings where id = p_booking_id;
  if not found or b.tourist_id is distinct from auth.uid() then
    raise exception 'Booking not found.';
  end if;
  if b.status <> 'confirmed' or b.deposit_amount <= 0 or b.amount_paid >= b.deposit_amount then
    return null;
  end if;
  select gcash_qr into v_qr from public.profiles where id = b.owner_id;
  return v_qr;
end;
$function$;

revoke all on function public.booking_payment_qr(uuid) from public, anon;
grant execute on function public.booking_payment_qr(uuid) to authenticated;

-- 8. Tourist: "I've paid" ----------------------------------------------------------------
create or replace function public.tourist_mark_paid(p_booking_id uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
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
    return; -- already told the owner
  end if;

  perform set_config('ipilgo.server_write', 'on', true);
  update public.bookings set paid_claimed_at = now() where id = p_booking_id;
  perform set_config('ipilgo.server_write', 'off', true);
end;
$function$;

revoke all on function public.tourist_mark_paid(uuid) from public, anon;
grant execute on function public.tourist_mark_paid(uuid) to authenticated;

-- 9. Owner: Received / Not received ------------------------------------------------------
create or replace function public.owner_review_payment(p_booking_id uuid, p_received boolean)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
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
           paid_claimed_at = null
     where id = p_booking_id;
  else
    -- Back to "Pay down payment", with at least 2 hours to try again.
    update public.bookings
       set paid_claimed_at = null,
           pay_by = greatest(coalesce(pay_by, now()), now() + interval '2 hours')
     where id = p_booking_id;
  end if;
  perform set_config('ipilgo.server_write', 'off', true);
end;
$function$;

revoke all on function public.owner_review_payment(uuid, boolean) from public, anon;
grant execute on function public.owner_review_payment(uuid, boolean) to authenticated;

-- 10. Owner: "I've refunded" -------------------------------------------------------------
create or replace function public.owner_mark_refunded(p_booking_id uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  b public.bookings;
begin
  select * into b from public.bookings where id = p_booking_id for update;
  if not found or b.owner_id is distinct from auth.uid() then
    raise exception 'Booking not found.';
  end if;
  if not b.refund_due or b.refunded_at is not null or b.refund_amount <= 0 then
    raise exception 'There is no refund to send for this booking.';
  end if;

  insert into public.booking_payments (booking_id, kind, amount, method, recorded_by)
  values (p_booking_id, 'refund', b.refund_amount, 'gcash', 'owner');

  perform set_config('ipilgo.server_write', 'on', true);
  update public.bookings
     set refund_due = false,
         refunded_at = now(),
         payment_status = 'refunded'
   where id = p_booking_id;
  perform set_config('ipilgo.server_write', 'off', true);
end;
$function$;

revoke all on function public.owner_mark_refunded(uuid) from public, anon;
grant execute on function public.owner_mark_refunded(uuid) to authenticated;

-- 11. Admin problem reports: "refund" now means the owner sends GCash money back --------
create or replace function public.admin_resolve_booking_problem(p_problem_id uuid, p_refund boolean, p_note text)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_note text := nullif(trim(coalesce(p_note, '')), '');
  p public.booking_problems;
  b public.bookings;
  v_online numeric;
  v_dest text;
  v_label text;
begin
  if v_uid is null or not public.has_role('admin'::public.user_role) then
    raise exception 'Only an admin can do this.';
  end if;
  select * into p from public.booking_problems where id = p_problem_id for update;
  if not found then
    raise exception 'Report not found.';
  end if;
  if p.status <> 'open' then
    raise exception 'This report was already handled.';
  end if;
  select * into b from public.bookings where id = p.booking_id for update;
  select name into v_dest from public.destinations where id = b.destination_id;

  if p_refund then
    if b.status in ('cancelled', 'rejected') or b.refunded_at is not null then
      raise exception 'This booking is already closed or refunded.';
    end if;
    -- Money paid by e-wallet (GCash, or PayMongo on older bookings); cash stays out.
    select coalesce(sum(case when kind = 'refund' then -amount else amount end), 0) into v_online
    from public.booking_payments
    where booking_id = b.id and method is distinct from 'cash';
    if v_online <= 0 then
      raise exception 'Nothing was paid by GCash for this booking, so there is nothing to refund.';
    end if;
    v_label := case p.kind
      when 'owner_no_show' then 'the owner did not show up'
      when 'closed' then 'the place was closed'
      when 'not_as_booked' then 'the service was not as booked'
      else 'a problem was reported' end;

    -- Closing as the admin makes booking_refund_rules() ask the owner to refund.
    perform set_config('ipilgo.server_write', 'on', true);
    update public.bookings
       set status = 'cancelled',
           cancel_reason = 'Refund ordered by IpilGo because ' || v_label
     where id = b.id;
    update public.bookings
       set refund_amount = v_online, refund_due = true
     where id = b.id and refund_amount is distinct from v_online;
    perform set_config('ipilgo.server_write', 'off', true);

    update public.booking_problems
       set status = 'refunded', admin_note = v_note, resolved_by = v_uid, resolved_at = now()
     where id = p.id;
  else
    if v_note is null then
      raise exception 'Write a short note so the tourist knows why.';
    end if;
    update public.booking_problems
       set status = 'dismissed', admin_note = v_note, resolved_by = v_uid, resolved_at = now()
     where id = p.id;
    perform public.notify(p.reporter_id, 'Your problem report was reviewed',
      'IpilGo reviewed your report about ' || coalesce(v_dest, 'your booking') || ' on ' ||
      to_char(b.booking_date, 'FMMonth FMDD, YYYY') || '. No refund was made. Note from IpilGo: ' ||
      regexp_replace(v_note, '([^.!?])$', '\1.'),
      'booking_status');
  end if;
end;
$function$;

-- 12. Notifications for the GCash flow --------------------------------------------------
create or replace function public.notify_booking_changes()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_dest text;
  v_date text;
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
          then ' Pay the ₱' || new.deposit_amount || ' down payment by GCash before ' ||
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
          then ' The ₱' || v_kept || ' down payment is not refunded.' else '' end;
    elsif new.status = 'completed' then
      v_body := 'Thanks for visiting ' || coalesce(v_dest, 'Ipil') || '! You can now leave a review.';
    else
      v_body := 'Your booking at ' || coalesce(v_dest, 'your destination') || ' was updated.';
    end if;

    perform public.notify(new.tourist_id, v_title,
      v_body || case when new.refund_due and not old.refund_due
        then ' The owner will send ₱' || new.refund_amount || ' back to your GCash within 3 days.' else '' end,
      'booking_status');

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
        ' The date is free again.' ||
        case when new.refund_due and not old.refund_due
          then ' Send ₱' || new.refund_amount || ' back to the tourist''s GCash within 3 days, then tap "I''ve refunded".'
          else '' end,
        'booking_status');
    elsif new.status = 'cancelled' and by_owner and new.refund_due and not old.refund_due then
      perform public.notify(new.owner_id, 'Refund needed',
        'Send ₱' || new.refund_amount || ' back to ' || v_who || '''s GCash for the ' || v_date ||
        ' booking (' || v_ref || ') within 3 days, then tap "I''ve refunded".',
        'payment');
    end if;
  end if;

  -- Tourist tapped "I've paid".
  if new.paid_claimed_at is not null and old.paid_claimed_at is null then
    perform public.notify(new.owner_id, 'Check your GCash',
      v_who || ' says they paid the ₱' || (new.deposit_amount - new.amount_paid) || ' down payment for the ' ||
      v_date || ' booking (' || v_ref || '). Check your GCash, then tap Received or Not received.',
      'payment');
  end if;

  -- Owner said Not received.
  if old.paid_claimed_at is not null and new.paid_claimed_at is null
     and new.amount_paid = old.amount_paid and new.status = 'confirmed' then
    perform public.notify(new.tourist_id, 'Payment not received',
      'The owner of ' || coalesce(v_dest, 'your booking') || ' did not find your ₱' ||
      (new.deposit_amount - new.amount_paid) || ' GCash payment (' || v_ref || '). Check your GCash history, then pay again before ' ||
      to_char(new.pay_by at time zone 'Asia/Manila', 'FMMon FMDD, FMHH12:MI AM') || '.',
      'payment');
  end if;

  if new.amount_paid > old.amount_paid then
    if v_actor = new.owner_id and old.paid_claimed_at is not null then
      perform public.notify(new.tourist_id,
        case when new.payment_status = 'paid' then 'Payment received' else 'Down payment received' end,
        'The owner received your ₱' || (new.amount_paid - old.amount_paid) || ' for ' || coalesce(v_dest, 'your booking') ||
        ' on ' || v_date || ' (' || v_ref || ').' ||
        case when new.amount_paid >= new.total_amount then ' Your booking is fully paid.'
             else ' Pay the remaining ₱' || (new.total_amount - new.amount_paid) || ' at the spot.' end,
        'payment');
    elsif v_actor = new.owner_id then
      perform public.notify(new.tourist_id, 'Cash payment recorded',
        coalesce(v_dest, 'The owner') || ' recorded ₱' || (new.amount_paid - old.amount_paid) ||
        ' cash from you for your ' || v_date || ' booking (' || v_ref || ').' ||
        case when new.amount_paid >= new.total_amount then ' Your booking is fully paid.'
             else ' Remaining balance: ₱' || (new.total_amount - new.amount_paid) || '.' end,
        'payment');
    end if;
  end if;

  if new.refunded_at is not null and old.refunded_at is null then
    perform public.notify(new.tourist_id, 'Refund sent',
      'The owner sent ₱' || new.refund_amount || ' for your ' || coalesce(v_dest, 'Ipil') ||
      ' booking (' || v_ref || ') back to your GCash. Check your GCash.',
      'payment');
  end if;
  return new;
end;
$function$;
