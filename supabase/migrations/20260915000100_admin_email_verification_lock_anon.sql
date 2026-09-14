-- Advisor flagged get_email_verification_status() as anon-executable even
-- after revoking from public -- Supabase's default ALTER DEFAULT PRIVILEGES
-- grants EXECUTE on new public-schema functions to anon separately. The
-- function body already gates on has_role('admin') so a non-admin caller
-- just gets zero rows, but locking the grant down is cheap and matches the
-- authenticated-only intent.

revoke execute on function public.get_email_verification_status() from anon;
