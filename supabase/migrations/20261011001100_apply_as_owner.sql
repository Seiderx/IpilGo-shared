-- Round 2 / step 7: one account can be a tourist AND an owner. Tourist-side
-- data is keyed on the user id (not the role), so owners already use the
-- tourist app. This lets an existing tourist apply as an owner with the same
-- email: role becomes 'owner' with owner_status 'pending' (admin approves as
-- usual). Their username, preferences, favorites and bookings are untouched.
create or replace function public.apply_as_owner(p_full_name text, p_phone text)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_role public.user_role;
  v_name text := regexp_replace(trim(p_full_name), '\s+', ' ', 'g');
  v_phone text := regexp_replace(coalesce(p_phone, ''), '[\s-]', '', 'g');
begin
  select role into v_role from public.profiles where id = (select auth.uid());
  if v_role is null then
    raise exception 'Not signed in';
  end if;
  if v_role = 'owner' then
    return; -- already an owner (pending or approved)
  end if;
  if v_role <> 'tourist' then
    raise exception 'Only tourist accounts can apply as an owner';
  end if;
  if v_name !~ '^[A-Za-zÀ-ÖØ-öø-ÿÑñ][A-Za-zÀ-ÖØ-öø-ÿÑñ.'' -]*$'
     or array_length(regexp_split_to_array(v_name, ' '), 1) < 2 then
    raise exception 'Please enter your real first and last name';
  end if;
  if v_phone !~ '^(\+?63|0)9[0-9]{9}$' then
    raise exception 'Please enter a valid mobile number';
  end if;

  -- prevent_role_change() only lets admins change roles; this vetted path
  -- reuses the bypass flag the OAuth owner-claim flow already uses.
  perform set_config('ipilgo.oauth_owner_claim', 'on', true);
  update public.profiles
    set role = 'owner',
        owner_status = 'pending',
        full_name = v_name,
        phone = v_phone
    where id = (select auth.uid());
  perform set_config('ipilgo.oauth_owner_claim', '', true);
end;
$$;

revoke all on function public.apply_as_owner(text, text) from public, anon;
grant execute on function public.apply_as_owner(text, text) to authenticated;
