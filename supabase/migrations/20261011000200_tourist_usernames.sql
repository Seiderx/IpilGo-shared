-- Item 6: tourists sign up with a username instead of a full name.
-- * profiles.username: unique (case-insensitive), 3-20 letters/digits/_.
--   Null for owners/admins (they keep real names for approval) and for
--   Google/Facebook tourists (their provider name is used).
-- * For username signups full_name is filled with the username too, so every
--   existing screen that shows full_name (reviews, owner booking lists) keeps
--   working without changes.
-- * bookings.contact_name / contact_phone: the real name + number the guide
--   needs, asked on the booking form since a username isn't a real name.

alter table public.profiles add column if not exists username text;

alter table public.profiles drop constraint if exists profiles_username_format;
alter table public.profiles add constraint profiles_username_format
  check (username is null or username ~ '^[A-Za-z0-9_]{3,20}$');

create unique index if not exists profiles_username_lower_key
  on public.profiles (lower(username));

alter table public.bookings add column if not exists contact_name text;
alter table public.bookings add column if not exists contact_phone text;

-- Signup screen calls this while the user types (before an account exists).
create or replace function public.is_username_available(p_username text)
returns boolean
language sql
stable
security definer
set search_path to ''
as $$
  select p_username ~ '^[A-Za-z0-9_]{3,20}$'
     and not exists (
       select 1 from public.profiles where lower(username) = lower(p_username)
     );
$$;

revoke all on function public.is_username_available(text) from public;
grant execute on function public.is_username_available(text) to anon, authenticated;

create or replace function public.handle_new_user()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  signup_role text := new.raw_user_meta_data->>'signup_role';
  wants_owner boolean := signup_role = 'owner';
  wants_admin boolean := signup_role = 'admin';
  -- Usernames are a tourist-only signup field.
  uname text := case when wants_owner or wants_admin then null
                     else nullif(trim(new.raw_user_meta_data->>'username'), '') end;
begin
  insert into public.profiles (id, full_name, username, avatar_url, phone, role, owner_status, admin_status, terms_accepted_at)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data->>'full_name', ''), uname, ''),
    uname,
    new.raw_user_meta_data->>'avatar_url',
    new.raw_user_meta_data->>'phone',
    case
      when wants_admin then 'admin'::public.user_role
      when wants_owner then 'owner'::public.user_role
      else 'tourist'::public.user_role
    end,
    case when wants_owner then 'pending'::public.owner_approval_status else null end,
    case when wants_admin then 'pending'::public.owner_approval_status else null end,
    (new.raw_user_meta_data->>'terms_accepted_at')::timestamptz
  )
  on conflict (id) do nothing;
  return new;
end;
$function$;
