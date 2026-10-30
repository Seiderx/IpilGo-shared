-- Pending requests also expire once their trip date has passed. Bookings made
-- before respond_by existed have it null, so the old rule never closed them:
-- they sat as "pending" forever and inflated "Bookings awaiting owners".
-- Runs from the existing expire-unanswered-bookings cron job (every 10 min).

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
       and (
         (respond_by is not null and respond_by < now())
         or booking_date < (now() at time zone 'Asia/Manila')::date
       )
    returning 1
  )
  select count(*)::integer from expired;
$$;
