-- Google/Facebook (OAuth) signup support.
--
-- OAuth signups can't carry signup metadata, so handle_new_user() gives every
-- new OAuth account a plain tourist profile with no terms_accepted_at. The apps
-- call complete_oauth_signup() right after the provider redirect to:
--   * record terms acceptance (the buttons sit under an "By continuing you agree
--     to the Terms and Privacy Policy" notice), and
--   * from the owner app, turn a brand-new, unused account into a pending owner
--     (still needs admin approval, exactly like an email/password owner signup).
-- discard_unused_oauth_account() lets the admin panel delete the stray tourist
-- account created when someone who isn't an admin tries "Sign in with Google".

-- True for an OAuth account created in the last 15 minutes that has done nothing
-- yet (still a tourist with no preferences, bookings, trips, favorites, reviews).
create or replace function public.is_unused_oauth_account(p_uid uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from auth.users u
    join public.profiles p on p.id = u.id
    where u.id = p_uid
      and coalesce(u.raw_app_meta_data->>'provider', 'email') <> 'email'
      and p.role = 'tourist'
      and p.created_at > now() - interval '15 minutes'
  )
  and not exists (select 1 from public.tourist_preferences t where t.user_id = p_uid)
  and not exists (select 1 from public.bookings b where b.tourist_id = p_uid)
  and not exists (select 1 from public.itineraries i where i.user_id = p_uid)
  and not exists (select 1 from public.tourist_favorites f where f.user_id = p_uid)
  and not exists (select 1 from public.destination_reviews r where r.user_id = p_uid);
$$;

-- prevent_role_change() blocks role/approval edits by non-admins. Let it through
-- only when complete_oauth_signup() sets this transaction-local flag.
create or replace function public.prevent_role_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if current_setting('ipilgo.oauth_owner_claim', true) = 'on' then
    return new;
  end if;
  if new.role is distinct from old.role and not public.has_role('admin') then
    raise exception 'Only admins can change user roles';
  end if;
  if new.owner_status is distinct from old.owner_status and not public.has_role('admin') then
    raise exception 'Only admins can change owner approval status';
  end if;
  if new.admin_status is distinct from old.admin_status and not public.has_role('admin') then
    raise exception 'Only admins can change admin approval status';
  end if;
  return new;
end;
$$;

-- Returns the caller's role after any changes.
create or replace function public.complete_oauth_signup(p_as_owner boolean default false)
returns public.user_role
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_provider text;
  v_role public.user_role;
begin
  if v_uid is null then
    raise exception 'Not signed in';
  end if;

  select coalesce(u.raw_app_meta_data->>'provider', 'email') into v_provider
  from auth.users u where u.id = v_uid;
  select p.role into v_role from public.profiles p where p.id = v_uid;

  if v_provider = 'email' or v_role is null then
    return v_role;
  end if;

  update public.profiles set terms_accepted_at = now()
  where id = v_uid and terms_accepted_at is null;

  if p_as_owner and v_role = 'tourist' and public.is_unused_oauth_account(v_uid) then
    perform set_config('ipilgo.oauth_owner_claim', 'on', true);
    update public.profiles set role = 'owner', owner_status = 'pending' where id = v_uid;
    perform set_config('ipilgo.oauth_owner_claim', 'off', true);
    v_role := 'owner';
  end if;

  return v_role;
end;
$$;

-- Deletes the caller's own account if it is a fresh, unused OAuth tourist account.
create or replace function public.discard_unused_oauth_account()
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null or not public.is_unused_oauth_account(v_uid) then
    return false;
  end if;
  delete from auth.users where id = v_uid;
  return true;
end;
$$;

revoke execute on function public.is_unused_oauth_account(uuid) from public, anon, authenticated;
revoke execute on function public.complete_oauth_signup(boolean) from public, anon;
revoke execute on function public.discard_unused_oauth_account() from public, anon;
grant execute on function public.complete_oauth_signup(boolean) to authenticated;
grant execute on function public.discard_unused_oauth_account() to authenticated;
