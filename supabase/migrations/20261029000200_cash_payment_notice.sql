-- When the owner records a cash payment (owner_record_payment), tell the
-- tourist instead of notifying the owner about their own action. The tourist
-- gets a record of every peso the owner says they received.
-- Rest of the function is unchanged from 20261028000300.

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
    if (select auth.uid()) = new.owner_id then
      -- Cash the owner recorded: the tourist confirms it matches what they paid.
      perform public.notify(new.tourist_id, 'Cash payment recorded',
        coalesce(v_dest, 'The owner') || ' recorded ₱' || (new.amount_paid - old.amount_paid) ||
        ' cash from you for your ' || v_date || ' booking.' ||
        case when new.amount_paid >= new.total_amount then ' Your booking is fully paid.'
             else ' Remaining balance: ₱' || (new.total_amount - new.amount_paid) || '.' end,
        'payment');
    else
      perform public.notify(new.owner_id,
        case when new.payment_status = 'paid' then 'Payment received' else 'Down payment received' end,
        coalesce(new.contact_name, 'A tourist') || ' paid ₱' || (new.amount_paid - old.amount_paid) ||
        ' for the ' || v_date || ' booking at ' || coalesce(v_dest, 'your spot') || '.',
        'payment');
    end if;
  end if;

  if new.refunded_at is not null and old.refunded_at is null then
    perform public.notify(new.tourist_id, 'Refund sent',
      '₱' || new.refund_amount || ' for your ' || coalesce(v_dest, 'Ipil') || ' booking was refunded to your e-wallet.',
      'payment');
  end if;
  return new;
end;
$function$;
