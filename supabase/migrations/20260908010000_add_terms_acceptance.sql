-- Phase 2: Terms & Conditions acceptance
--
-- Adds a nullable terms_accepted_at column to profiles, and extends
-- handle_new_user() to populate it from signup metadata -- same pattern
-- already used for full_name/phone/signup_role, so no client-side profile
-- update (and no dependency on having an active session right after signUp)
-- is needed.

alter table public.profiles
  add column if not exists terms_accepted_at timestamptz;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  wants_owner boolean := (new.raw_user_meta_data->>'signup_role') = 'owner';
begin
  insert into public.profiles (id, full_name, avatar_url, phone, role, owner_status, terms_accepted_at)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', ''),
    new.raw_user_meta_data->>'avatar_url',
    new.raw_user_meta_data->>'phone',
    case when wants_owner then 'owner'::public.user_role else 'tourist'::public.user_role end,
    case when wants_owner then 'pending'::public.owner_approval_status else null end,
    (new.raw_user_meta_data->>'terms_accepted_at')::timestamptz
  )
  on conflict (id) do nothing;
  return new;
end;
$function$;
