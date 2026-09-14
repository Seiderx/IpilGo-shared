-- Admin-only RPC exposing auth.users email verification status.
--
-- auth.users isn't reachable through PostgREST, and the admin panel only
-- holds a publishable (anon) key, so this follows the same security-definer
-- + has_role('admin') pattern as has_role()/tourist_booked_with_me() to let
-- admins see which tourists/owners have confirmed their email without
-- exposing auth.users more broadly.

create or replace function public.get_email_verification_status()
returns table (id uuid, email_confirmed_at timestamptz)
language sql
stable
security definer
set search_path to ''
as $function$
  select u.id, u.email_confirmed_at
  from auth.users u
  where public.has_role('admin'::public.user_role);
$function$;

revoke all on function public.get_email_verification_status() from public;
grant execute on function public.get_email_verification_status() to authenticated;
