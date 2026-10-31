-- Accepted bookings stayed 'confirmed' forever once their date passed unless
-- the owner tapped "Mark as completed", so tourists were never asked for a
-- review and past trips still showed as upcoming. A nightly job now marks
-- accepted bookings from before today (Manila time) completed.
--
-- The existing notify_booking_changes trigger sends the tourist
-- "Trip completed ... You can now leave a review." for each one. Cron runs
-- without a user, so protect_booking_payment_fields lets the update through.
-- Owners can still record cash on completed bookings.

create or replace function public.complete_past_bookings()
returns integer
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_count integer;
begin
  update public.bookings
     set status = 'completed'
   where status = 'confirmed'
     and booking_date < (now() at time zone 'Asia/Manila')::date;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function public.complete_past_bookings() from public, anon, authenticated;

-- 00:15 Asia/Manila (UTC+8) = 16:15 UTC.
select cron.schedule(
  'complete-past-bookings',
  '15 16 * * *',
  $$select public.complete_past_bookings()$$
);
