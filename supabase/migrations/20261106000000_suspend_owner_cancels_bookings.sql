-- Suspending an owner cancels their upcoming bookings so tourists are not left
-- with a trip to a hidden place. booking_refund_rules gives a full refund on
-- paid bookings, notify_booking_changes tells the tourist and the owner, and the
-- process-booking-refunds job sends the money. Unpaid bookings just cancel.
create or replace function public.cancel_bookings_of_suspended_owner()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  if old.owner_status = 'approved' and new.owner_status = 'rejected' then
    update public.bookings
       set status = 'cancelled',
           cancel_reason = 'This place is no longer available on IpilGo'
     where owner_id = new.id
       and status in ('pending', 'confirmed')
       and booking_date >= (now() at time zone 'Asia/Manila')::date;
  end if;
  return new;
end;
$$;

revoke execute on function public.cancel_bookings_of_suspended_owner() from public, anon, authenticated;

create trigger profiles_cancel_suspended_owner_bookings
  after update of owner_status on public.profiles
  for each row execute function public.cancel_bookings_of_suspended_owner();
