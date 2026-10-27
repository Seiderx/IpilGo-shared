-- Usernames are claimed when the email is verified, not at signUp.
--
-- Supabase creates the auth.users row (and our trigger the profile) the moment
-- signUp runs, before the code is entered. The profile used to take the
-- username right then, so an abandoned signup kept the name "taken" forever,
-- and re-signing up with the same unverified email kept the first username
-- (Supabase does not update user metadata on a repeat signUp).
--
-- Now:
--   * handle_new_user() leaves username null for unverified email signups.
--   * on verification, handle_user_email_confirmed() gives the profile the
--     metadata username (or a free variant if someone claimed it meanwhile).
--     The app then sets the username the tourist typed most recently.
--   * suggest_usernames() offers free alternatives on the signup form.

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
  -- Usernames are a tourist-only signup field, held only once the email is
  -- verified (see handle_user_email_confirmed).
  uname text := case when wants_owner or wants_admin or new.email_confirmed_at is null then null
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

-- Up to p_count free, valid usernames built from p_base.
create or replace function public.suggest_usernames(p_base text, p_count int default 3)
returns text[]
language plpgsql
volatile
security definer
set search_path to ''
as $$
declare
  base text := regexp_replace(coalesce(p_base, ''), '[^A-Za-z0-9._]', '', 'g');
  suffixes text[] := array[
    to_char(now(), 'YY'),
    '_ipil',
    (10 + floor(random() * 90))::int::text,
    '_' || (10 + floor(random() * 90))::int::text,
    (100 + floor(random() * 900))::int::text,
    '.' || (100 + floor(random() * 900))::int::text,
    (1000 + floor(random() * 9000))::int::text
  ];
  s text;
  cand text;
  result text[] := '{}';
begin
  foreach s in array suffixes loop
    exit when coalesce(array_length(result, 1), 0) >= p_count;
    cand := regexp_replace(left(base, 20 - length(s)), '[._]+$', '') || s;
    if public.is_valid_username(cand)
       and not (cand = any(result))
       and not exists (select 1 from public.profiles where lower(username) = lower(cand)) then
      result := result || cand;
    end if;
  end loop;
  return result;
end;
$$;

revoke all on function public.suggest_usernames(text, int) from public;
grant execute on function public.suggest_usernames(text, int) to anon, authenticated;

create or replace function public.handle_user_email_confirmed()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  wanted text := nullif(trim(new.raw_user_meta_data->>'username'), '');
  chosen text;
begin
  if wanted is null or not exists (
    select 1 from public.profiles
    where id = new.id and role = 'tourist' and username is null
  ) then
    return new;
  end if;

  chosen := case when public.is_username_available(wanted) then wanted
                 else (public.suggest_usernames(wanted, 1))[1] end;
  if chosen is null then
    return new;
  end if;

  -- Never let a username race fail the verification itself.
  begin
    update public.profiles
       set username = chosen,
           full_name = case when coalesce(full_name, '') = '' then chosen else full_name end
     where id = new.id;
  exception when unique_violation then
    null;
  end;
  return new;
end;
$function$;

drop trigger if exists on_auth_user_email_confirmed on auth.users;
create trigger on_auth_user_email_confirmed
  after update of email_confirmed_at on auth.users
  for each row
  when (old.email_confirmed_at is null and new.email_confirmed_at is not null)
  execute function public.handle_user_email_confirmed();

-- Release usernames held by signups that were never verified.
update public.profiles p
   set username = null
  from auth.users u
 where u.id = p.id
   and u.email_confirmed_at is null
   and p.username is not null;
