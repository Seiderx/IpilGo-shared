-- Security advisor follow-up: these RPCs already refuse without a session,
-- but signed-out (anon) callers shouldn't reach them at all. Supabase's
-- default privileges grant anon EXECUTE separately from PUBLIC.
-- (is_username_available stays anon-callable: signup needs it.)
revoke execute on function public.owner_destination_stats(uuid) from anon;
revoke execute on function public.record_destination_view(uuid) from anon;
revoke execute on function public.reply_to_review(uuid, text) from anon;
