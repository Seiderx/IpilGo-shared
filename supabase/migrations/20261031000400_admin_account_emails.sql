-- Admin panel: show each account's email address, not just whether it is verified.
-- New function instead of changing get_email_verification_status's return shape.
create or replace function public.get_account_emails()
returns table (id uuid, email text, email_confirmed_at timestamptz)
language sql
stable
security definer
set search_path to ''
as $function$
  select u.id, u.email::text, u.email_confirmed_at
  from auth.users u
  where public.has_role('admin'::public.user_role);
$function$;

revoke all on function public.get_account_emails() from public;
revoke execute on function public.get_account_emails() from anon;
grant execute on function public.get_account_emails() to authenticated;
