-- Admin registration with approval flow
--
-- Self-service admin sign-up (admin panel Register tab) sends
-- signup_role='admin'. The profile is created with role='admin' but
-- admin_status='pending', mirroring the owner_status flow. An existing
-- approved admin approves/rejects from the Pending Admins screen.
--
-- SECURITY: has_role('admin') backs every admin RLS policy, so it must
-- treat a pending/rejected admin as NOT an admin — otherwise a fresh
-- sign-up would get full admin access (including the ability to approve
-- itself) before anyone reviewed it. That change and the backfill of the
-- existing admin to 'approved' ship in this same migration so the current
-- admin is never locked out between steps.

-- 1. Column (reuses the owner_approval_status enum: pending|approved|rejected)
alter table public.profiles
  add column if not exists admin_status public.owner_approval_status;

comment on column public.profiles.admin_status is
  'Only set for role=admin. Self-registered admins start pending; an approved admin approves via Admin Panel Pending Admins screen. Rejection is final.';

-- 2. Backfill: every admin that exists today was provisioned manually and
--    is trusted. Must run before has_role() is redefined below.
update public.profiles
   set admin_status = 'approved'
 where role = 'admin'
   and admin_status is null;

-- 3. has_role: admin only counts once approved. Other roles unchanged.
create or replace function public.has_role(required public.user_role)
returns boolean
language sql
stable security definer
set search_path to ''
as $function$
  select exists (
    select 1 from public.profiles
    where id = (select auth.uid())
      and role = required
      and (required <> 'admin' or admin_status = 'approved')
  );
$function$;

-- 4. New-user trigger: recognise signup_role='admin' alongside 'owner'.
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
begin
  insert into public.profiles (id, full_name, avatar_url, phone, role, owner_status, admin_status, terms_accepted_at)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', ''),
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

-- 5. Only (approved) admins may change admin_status — same guard as role
--    and owner_status. "Users can update own profile" RLS otherwise lets a
--    pending admin update its own row.
create or replace function public.prevent_role_change()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
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
$function$;
