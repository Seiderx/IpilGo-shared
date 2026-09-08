-- ============================================================================
-- IpilGo baseline schema snapshot
--
-- This file captures the schema that was ALREADY LIVE in the shared Supabase
-- project (dbkqemjfxtksjxrwrclf) before any migration files existed in this
-- repo. It was reconstructed by reading the live database directly
-- (pg_get_functiondef, pg_get_triggerdef, pg_policies, pg_constraint, etc.)
-- on 2026-09-08 -- nothing in the live database was changed to produce it.
--
-- Purpose: give git a copy of the auth/role/approval logic that previously
-- existed ONLY inside the live database (handle_new_user, has_role,
-- is_approved_owner, enforce_destination_approval, prevent_role_change,
-- protect_booking_payment_fields, RLS policies, storage policies). Until now
-- none of this was visible from source control.
--
-- Every statement below is written to be safe to run twice (IF NOT EXISTS /
-- CREATE OR REPLACE / DROP ... IF EXISTS THEN CREATE) so it can also bootstrap
-- a fresh database if one is ever needed, without erroring against the
-- project this was captured from.
--
-- From this point forward: any new schema change should get its own new
-- migration file instead of hand-edited SQL run outside of git.
-- ============================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- Enum types
-- ---------------------------------------------------------------------------
do $$ begin
  create type public.user_role as enum ('tourist', 'owner', 'admin');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.owner_approval_status as enum ('pending', 'approved', 'rejected');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.destination_status as enum ('pending', 'approved', 'rejected');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.booking_status as enum ('pending', 'confirmed', 'rejected', 'completed', 'cancelled');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.payment_status as enum ('unpaid', 'paid', 'refunded');
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role public.user_role not null default 'tourist',
  full_name text not null default '',
  avatar_url text,
  phone text,
  created_at timestamptz not null default now(),
  owner_status public.owner_approval_status
);
comment on column public.profiles.owner_status is
  'Only set for role=owner. New owners start pending; admin approves via Admin Panel Pending Owners screen.';

create table if not exists public.tourist_preferences (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references public.profiles(id) on delete cascade,
  interests text[] not null default '{}',
  budget_range text,
  travel_style text,
  companions_count integer,
  updated_at timestamptz not null default now()
);

create table if not exists public.destinations (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid references public.profiles(id) on delete set null,
  name text not null,
  description text,
  category text,
  tags text[] not null default '{}',
  address text,
  latitude numeric,
  longitude numeric,
  operating_hours text,
  entrance_fee numeric,
  amenities text[] not null default '{}',
  images text[] not null default '{}',
  panoramic_360_url text,
  status public.destination_status not null default 'pending',
  avg_rating numeric not null default 0,
  created_at timestamptz not null default now(),
  contact_number text,
  contact_email text
);

create table if not exists public.destination_reviews (
  id uuid primary key default gen_random_uuid(),
  destination_id uuid not null references public.destinations(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  rating integer not null check (rating >= 1 and rating <= 5),
  comment text,
  created_at timestamptz not null default now()
);

create table if not exists public.bookings (
  id uuid primary key default gen_random_uuid(),
  tourist_id uuid not null references public.profiles(id) on delete cascade,
  destination_id uuid not null references public.destinations(id) on delete cascade,
  owner_id uuid references public.profiles(id) on delete set null,
  booking_date date not null,
  num_guests integer not null default 1 check (num_guests > 0),
  status public.booking_status not null default 'pending',
  payment_status public.payment_status not null default 'unpaid',
  payment_method text check (payment_method = any (array['gcash','paymaya'])),
  payment_reference text,
  total_amount numeric not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.itineraries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  start_date date,
  end_date date,
  generated_by_ai boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.itinerary_items (
  id uuid primary key default gen_random_uuid(),
  itinerary_id uuid not null references public.itineraries(id) on delete cascade,
  destination_id uuid not null references public.destinations(id) on delete cascade,
  day_number integer not null default 1,
  scheduled_time time,
  order_index integer not null default 0,
  notes text
);

create table if not exists public.ai_recommendation_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  query_text text,
  recommended_destination_ids uuid[] not null default '{}',
  justification text,
  agent_breakdown jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.events (
  id uuid primary key default gen_random_uuid(),
  destination_id uuid references public.destinations(id) on delete cascade,
  name text not null,
  description text,
  start_date date,
  end_date date,
  is_festival boolean not null default false
);

create table if not exists public.safety_alerts (
  id uuid primary key default gen_random_uuid(),
  destination_id uuid references public.destinations(id) on delete cascade,
  alert_type text not null default 'other' check (alert_type = any (array['weather','traffic','closure','other'])),
  message text not null,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.tourist_favorites (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  destination_id uuid not null references public.destinations(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  body text,
  type text not null default 'general' check (type = any (array['booking','recommendation','alert','general'])),
  read boolean not null default false,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Functions
-- ---------------------------------------------------------------------------

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  wants_owner boolean := (new.raw_user_meta_data->>'signup_role') = 'owner';
begin
  insert into public.profiles (id, full_name, avatar_url, phone, role, owner_status)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', ''),
    new.raw_user_meta_data->>'avatar_url',
    new.raw_user_meta_data->>'phone',
    case when wants_owner then 'owner'::public.user_role else 'tourist'::public.user_role end,
    case when wants_owner then 'pending'::public.owner_approval_status else null end
  )
  on conflict (id) do nothing;
  return new;
end;
$function$;

create or replace function public.has_role(required public.user_role)
returns boolean
language sql
stable security definer
set search_path to ''
as $function$
  select exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and role = required
  );
$function$;

create or replace function public.is_approved_owner()
returns boolean
language sql
stable security definer
set search_path to ''
as $function$
  select exists (
    select 1 from public.profiles
    where id = (select auth.uid())
      and role = 'owner'
      and owner_status = 'approved'
  );
$function$;

create or replace function public.tourist_booked_with_me(profile_id uuid)
returns boolean
language sql
stable security definer
set search_path to ''
as $function$
  select exists (
    select 1 from public.bookings b
    where b.tourist_id = profile_id
      and b.owner_id = (select auth.uid())
  );
$function$;

create or replace function public.enforce_destination_approval()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if (select auth.uid()) is not null and not public.has_role('admin') then
    if tg_op = 'INSERT' then
      new.status := 'pending';
      new.avg_rating := 0;
    elsif (select auth.uid()) = old.owner_id then
      new.avg_rating := old.avg_rating;
      if (new.name, new.description, new.category, new.tags, new.address,
          new.latitude, new.longitude, new.operating_hours, new.entrance_fee,
          new.amenities, new.images, new.panoramic_360_url,
          new.contact_number, new.contact_email)
         is distinct from
         (old.name, old.description, old.category, old.tags, old.address,
          old.latitude, old.longitude, old.operating_hours, old.entrance_fee,
          old.amenities, old.images, old.panoramic_360_url,
          old.contact_number, old.contact_email) then
        new.status := 'pending';
      else
        new.status := old.status;
      end if;
    elsif new.status is distinct from old.status then
      new.status := old.status;
    end if;
  end if;
  return new;
end;
$function$;

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
  return new;
end;
$function$;

create or replace function public.protect_booking_payment_fields()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  jwt_role text := coalesce(auth.jwt() ->> 'role', '');
begin
  -- service role (edge functions with service key) and admins are trusted
  if jwt_role = 'service_role' or has_role('admin'::user_role) then
    return new;
  end if;

  if new.payment_status is distinct from old.payment_status
     or new.payment_reference is distinct from old.payment_reference
     or new.payment_method is distinct from old.payment_method then
    raise exception 'Payment fields can only be updated by verified server-side payment processing';
  end if;

  -- tourists (non-owners of the row) may only cancel
  if auth.uid() = old.tourist_id and auth.uid() is distinct from old.owner_id then
    if new.status is distinct from old.status and new.status <> 'cancelled' then
      raise exception 'Tourists can only cancel their bookings';
    end if;
  end if;

  return new;
end;
$function$;

create or replace function public.refresh_destination_avg_rating()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  dest uuid := coalesce(new.destination_id, old.destination_id);
begin
  update public.destinations
  set avg_rating = coalesce(
    (select round(avg(rating)::numeric, 2)
     from public.destination_reviews
     where destination_id = dest), 0)
  where id = dest;
  return coalesce(new, old);
end;
$function$;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path to ''
as $function$
begin
  new.updated_at := now();
  return new;
end;
$function$;

-- ---------------------------------------------------------------------------
-- Triggers
-- ---------------------------------------------------------------------------

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

drop trigger if exists destinations_enforce_approval on public.destinations;
create trigger destinations_enforce_approval
  before insert or update on public.destinations
  for each row execute function public.enforce_destination_approval();

drop trigger if exists reviews_refresh_avg_rating on public.destination_reviews;
create trigger reviews_refresh_avg_rating
  after insert or delete or update on public.destination_reviews
  for each row execute function public.refresh_destination_avg_rating();

drop trigger if exists preferences_set_updated_at on public.tourist_preferences;
create trigger preferences_set_updated_at
  before update on public.tourist_preferences
  for each row execute function public.set_updated_at();

drop trigger if exists bookings_protect_payment_fields on public.bookings;
create trigger bookings_protect_payment_fields
  before update on public.bookings
  for each row execute function public.protect_booking_payment_fields();

drop trigger if exists profiles_prevent_role_change on public.profiles;
create trigger profiles_prevent_role_change
  before update on public.profiles
  for each row execute function public.prevent_role_change();

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------

alter table public.profiles enable row level security;
alter table public.tourist_preferences enable row level security;
alter table public.destinations enable row level security;
alter table public.destination_reviews enable row level security;
alter table public.bookings enable row level security;
alter table public.itineraries enable row level security;
alter table public.itinerary_items enable row level security;
alter table public.ai_recommendation_logs enable row level security;
alter table public.events enable row level security;
alter table public.safety_alerts enable row level security;
alter table public.tourist_favorites enable row level security;
alter table public.notifications enable row level security;

-- profiles
drop policy if exists "Admins have full access to profiles" on public.profiles;
create policy "Admins have full access to profiles" on public.profiles
  for all to authenticated
  using (public.has_role('admin')) with check (public.has_role('admin'));

drop policy if exists "Owners can view tourists who booked with them" on public.profiles;
create policy "Owners can view tourists who booked with them" on public.profiles
  for select to authenticated
  using (public.tourist_booked_with_me(id));

drop policy if exists "Users can insert own profile as tourist" on public.profiles;
create policy "Users can insert own profile as tourist" on public.profiles
  for insert to authenticated
  with check (id = (select auth.uid()) and role = 'tourist');

drop policy if exists "Users can update own profile" on public.profiles;
create policy "Users can update own profile" on public.profiles
  for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

drop policy if exists "Users can view own profile" on public.profiles;
create policy "Users can view own profile" on public.profiles
  for select to authenticated
  using (id = (select auth.uid()));

-- tourist_preferences
drop policy if exists "Admins have full access to preferences" on public.tourist_preferences;
create policy "Admins have full access to preferences" on public.tourist_preferences
  for all to authenticated
  using (public.has_role('admin')) with check (public.has_role('admin'));

drop policy if exists "Users manage own preferences" on public.tourist_preferences;
create policy "Users manage own preferences" on public.tourist_preferences
  for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- destinations
drop policy if exists "Admins have full access to destinations" on public.destinations;
create policy "Admins have full access to destinations" on public.destinations
  for all to authenticated
  using (public.has_role('admin')) with check (public.has_role('admin'));

drop policy if exists "Anyone can view approved destinations" on public.destinations;
create policy "Anyone can view approved destinations" on public.destinations
  for select to anon, authenticated
  using (status = 'approved');

drop policy if exists "Owners can delete own destinations" on public.destinations;
create policy "Owners can delete own destinations" on public.destinations
  for delete to authenticated
  using (owner_id = (select auth.uid()) and public.has_role('owner'));

drop policy if exists "Owners can insert own destinations" on public.destinations;
create policy "Owners can insert own destinations" on public.destinations
  for insert to authenticated
  with check (owner_id = (select auth.uid()) and public.is_approved_owner());

drop policy if exists "Owners can update own destinations" on public.destinations;
create policy "Owners can update own destinations" on public.destinations
  for update to authenticated
  using (owner_id = (select auth.uid()) and public.is_approved_owner())
  with check (owner_id = (select auth.uid()));

drop policy if exists "Owners can view own destinations" on public.destinations;
create policy "Owners can view own destinations" on public.destinations
  for select to authenticated
  using (owner_id = (select auth.uid()));

-- destination_reviews
drop policy if exists "Admins have full access to reviews" on public.destination_reviews;
create policy "Admins have full access to reviews" on public.destination_reviews
  for all to authenticated
  using (public.has_role('admin')) with check (public.has_role('admin'));

drop policy if exists "Anyone can view reviews" on public.destination_reviews;
create policy "Anyone can view reviews" on public.destination_reviews
  for select to anon, authenticated
  using (true);

drop policy if exists "Users can delete own reviews" on public.destination_reviews;
create policy "Users can delete own reviews" on public.destination_reviews
  for delete to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists "Users can review approved destinations" on public.destination_reviews;
create policy "Users can review approved destinations" on public.destination_reviews
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and exists (
      select 1 from public.destinations d
      where d.id = destination_reviews.destination_id and d.status = 'approved'
    )
  );

drop policy if exists "Users can update own reviews" on public.destination_reviews;
create policy "Users can update own reviews" on public.destination_reviews
  for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- bookings
drop policy if exists "Admins have full access to bookings" on public.bookings;
create policy "Admins have full access to bookings" on public.bookings
  for all to authenticated
  using (public.has_role('admin')) with check (public.has_role('admin'));

drop policy if exists "Owners can update bookings for their destinations" on public.bookings;
create policy "Owners can update bookings for their destinations" on public.bookings
  for update to authenticated
  using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));

drop policy if exists "Owners can view bookings for their destinations" on public.bookings;
create policy "Owners can view bookings for their destinations" on public.bookings
  for select to authenticated
  using (owner_id = (select auth.uid()));

drop policy if exists "Tourists can create own bookings" on public.bookings;
create policy "Tourists can create own bookings" on public.bookings
  for insert to authenticated
  with check (tourist_id = (select auth.uid()));

drop policy if exists "Tourists can update own bookings" on public.bookings;
create policy "Tourists can update own bookings" on public.bookings
  for update to authenticated
  using (tourist_id = (select auth.uid())) with check (tourist_id = (select auth.uid()));

drop policy if exists "Tourists can view own bookings" on public.bookings;
create policy "Tourists can view own bookings" on public.bookings
  for select to authenticated
  using (tourist_id = (select auth.uid()));

-- itineraries
drop policy if exists "Admins have full access to itineraries" on public.itineraries;
create policy "Admins have full access to itineraries" on public.itineraries
  for all to authenticated
  using (public.has_role('admin')) with check (public.has_role('admin'));

drop policy if exists "Users manage own itineraries" on public.itineraries;
create policy "Users manage own itineraries" on public.itineraries
  for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- itinerary_items
drop policy if exists "Admins have full access to itinerary items" on public.itinerary_items;
create policy "Admins have full access to itinerary items" on public.itinerary_items
  for all to authenticated
  using (public.has_role('admin')) with check (public.has_role('admin'));

drop policy if exists "Users manage items of own itineraries" on public.itinerary_items;
create policy "Users manage items of own itineraries" on public.itinerary_items
  for all to authenticated
  using (exists (select 1 from public.itineraries i where i.id = itinerary_items.itinerary_id and i.user_id = (select auth.uid())))
  with check (exists (select 1 from public.itineraries i where i.id = itinerary_items.itinerary_id and i.user_id = (select auth.uid())));

-- ai_recommendation_logs
drop policy if exists "Admins have full access to recommendation logs" on public.ai_recommendation_logs;
create policy "Admins have full access to recommendation logs" on public.ai_recommendation_logs
  for all to authenticated
  using (public.has_role('admin')) with check (public.has_role('admin'));

drop policy if exists "Users can insert own recommendation logs" on public.ai_recommendation_logs;
create policy "Users can insert own recommendation logs" on public.ai_recommendation_logs
  for insert to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists "Users can view own recommendation logs" on public.ai_recommendation_logs;
create policy "Users can view own recommendation logs" on public.ai_recommendation_logs
  for select to authenticated
  using (user_id = (select auth.uid()));

-- events
drop policy if exists "Admins have full access to events" on public.events;
create policy "Admins have full access to events" on public.events
  for all to authenticated
  using (public.has_role('admin')) with check (public.has_role('admin'));

drop policy if exists "Anyone can view events" on public.events;
create policy "Anyone can view events" on public.events
  for select to anon, authenticated
  using (true);

-- safety_alerts
drop policy if exists "Admins have full access to safety alerts" on public.safety_alerts;
create policy "Admins have full access to safety alerts" on public.safety_alerts
  for all to authenticated
  using (public.has_role('admin')) with check (public.has_role('admin'));

drop policy if exists "Anyone can view safety alerts" on public.safety_alerts;
create policy "Anyone can view safety alerts" on public.safety_alerts
  for select to anon, authenticated
  using (true);

-- tourist_favorites
drop policy if exists "Users add own favorites" on public.tourist_favorites;
create policy "Users add own favorites" on public.tourist_favorites
  for insert to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists "Users remove own favorites" on public.tourist_favorites;
create policy "Users remove own favorites" on public.tourist_favorites
  for delete to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "Users view own favorites" on public.tourist_favorites;
create policy "Users view own favorites" on public.tourist_favorites
  for select to authenticated
  using ((select auth.uid()) = user_id);

-- notifications
drop policy if exists "Users mark own notifications read" on public.notifications;
create policy "Users mark own notifications read" on public.notifications
  for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

drop policy if exists "Users view own notifications" on public.notifications;
create policy "Users view own notifications" on public.notifications
  for select to authenticated
  using ((select auth.uid()) = user_id);

-- ---------------------------------------------------------------------------
-- Storage: destination-images bucket
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public)
values ('destination-images', 'destination-images', true)
on conflict (id) do nothing;

drop policy if exists "Admins manage destination images" on storage.objects;
create policy "Admins manage destination images" on storage.objects
  for all to authenticated
  using (bucket_id = 'destination-images' and public.has_role('admin'))
  with check (bucket_id = 'destination-images' and public.has_role('admin'));

drop policy if exists "Anyone can view destination images" on storage.objects;
create policy "Anyone can view destination images" on storage.objects
  for select to anon, authenticated
  using (bucket_id = 'destination-images');

drop policy if exists "Owners delete own destination images" on storage.objects;
create policy "Owners delete own destination images" on storage.objects
  for delete to authenticated
  using (bucket_id = 'destination-images' and (storage.foldername(name))[1] = (select auth.uid())::text);

drop policy if exists "Owners update own destination images" on storage.objects;
create policy "Owners update own destination images" on storage.objects
  for update to authenticated
  using (bucket_id = 'destination-images' and (storage.foldername(name))[1] = (select auth.uid())::text);

drop policy if exists "Owners upload destination images to own folder" on storage.objects;
create policy "Owners upload destination images to own folder" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'destination-images'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and public.is_approved_owner()
  );
