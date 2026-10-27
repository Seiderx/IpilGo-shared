-- Scheduled booking jobs.
--   * every 10 min: cancel deposit bookings the owner hasn't answered within
--     24h (booking_refund_rules then marks any down payment refund_due)
--   * every 5 min, only when something is due: call the booking-refunds edge
--     function, which sends the PayMongo refunds
--
-- The edge function is authenticated with a random secret generated here and
-- kept in Supabase Vault; the function reads it back through
-- booking_refunds_secret() (service role only), so it is never typed or shown.

create extension if not exists pg_net with schema extensions;

select vault.create_secret(
  replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''),
  'booking_refunds_cron_secret',
  'Shared secret pg_cron sends to the booking-refunds edge function'
);

create or replace function public.booking_refunds_secret()
returns text
language sql
stable
security definer
set search_path to ''
as $$
  select decrypted_secret from vault.decrypted_secrets
  where name = 'booking_refunds_cron_secret'
  limit 1;
$$;

revoke all on function public.booking_refunds_secret() from public, anon, authenticated;
grant execute on function public.booking_refunds_secret() to service_role;

select cron.schedule(
  'expire-unanswered-bookings',
  '*/10 * * * *',
  $$select public.expire_unanswered_bookings()$$
);

select cron.schedule(
  'process-booking-refunds',
  '*/5 * * * *',
  $$
  select net.http_post(
    url := 'https://dbkqemjfxtksjxrwrclf.supabase.co/functions/v1/booking-refunds',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', public.booking_refunds_secret()
    ),
    body := '{}'::jsonb
  )
  where exists (select 1 from public.bookings where refund_due)
  $$
);
