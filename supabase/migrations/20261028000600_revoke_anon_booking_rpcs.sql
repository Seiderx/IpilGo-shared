-- Security advisor follow-up for this round's functions. Supabase grants
-- EXECUTE to anon/authenticated by default, so revoking from PUBLIC alone
-- left these callable:
--   * create_booking: signed-in tourists only (it already rejected anon).
--   * handle_user_email_confirmed: a trigger function, never an RPC.
revoke execute on function public.create_booking(uuid, date, integer, text, text, jsonb, text) from anon;
revoke execute on function public.handle_user_email_confirmed() from anon, authenticated;
