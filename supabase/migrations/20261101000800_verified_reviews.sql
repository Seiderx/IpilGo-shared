-- Verified reviews (test-pass finding 10, user chose option 2).
--
-- Any signed-in tourist could review any live spot without going there. A
-- review now needs a visit: a completed booking at that spot, or an "I'm here"
-- GPS check-in within 200 m (unlocks reviewing for 7 days). Accounts younger
-- than 24 hours can't review. One review per tourist per place was already
-- enforced by destination_reviews_destination_id_user_id_key.
--
-- Also: reviews carry a "Verified visit" flag, owners can report a review to
-- the admin, and owners get a notice when a new review arrives.

-- ── Visits ───────────────────────────────────────────────────────────────
create table if not exists public.visits (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  destination_id uuid not null references public.destinations(id) on delete cascade,
  kind text not null check (kind in ('booking', 'checkin')),
  booking_id uuid unique references public.bookings(id) on delete cascade,
  distance_m integer,
  created_at timestamptz not null default now(),
  -- Check-ins unlock reviewing for 7 days; a completed booking never expires.
  expires_at timestamptz
);

create index if not exists idx_visits_user_destination on public.visits (user_id, destination_id);
create index if not exists idx_visits_destination on public.visits (destination_id);

alter table public.visits enable row level security;

-- Rows are written only by the booking trigger and check_in(); tourists read
-- their own, admins read all.
create policy "Users read own visits" on public.visits
  for select to authenticated using (user_id = (select auth.uid()));
create policy "Admins read visits" on public.visits
  for select to authenticated using (public.has_role('admin'::public.user_role));

-- A booking marked completed (by the owner or the nightly job) is a visit.
create or replace function public.record_booking_visit()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  if new.status = 'completed' and old.status is distinct from 'completed' then
    insert into public.visits (user_id, destination_id, kind, booking_id)
    values (new.tourist_id, new.destination_id, 'booking', new.id)
    on conflict (booking_id) do nothing;
  end if;
  return new;
end;
$$;

drop trigger if exists bookings_record_visit on public.bookings;
create trigger bookings_record_visit
  after update of status on public.bookings
  for each row execute function public.record_booking_visit();

insert into public.visits (user_id, destination_id, kind, booking_id, created_at)
select b.tourist_id, b.destination_id, 'booking', b.id, b.created_at
from public.bookings b
where b.status = 'completed'
on conflict (booking_id) do nothing;

-- "I'm here": the server measures the distance from the reported position to
-- the spot's pin, so the client can't just claim a visit.
create or replace function public.check_in(p_destination_id uuid, p_lat double precision, p_lng double precision)
returns table (ok boolean, distance_m integer, expires_at timestamptz)
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_lat double precision;
  v_lng double precision;
  v_dist integer;
  v_exp timestamptz := now() + interval '7 days';
begin
  if v_uid is null then
    raise exception 'Please sign in first';
  end if;
  if p_lat is null or p_lng is null or abs(p_lat) > 90 or abs(p_lng) > 180 then
    raise exception 'Your location could not be read. Please try again.';
  end if;

  select d.latitude::double precision, d.longitude::double precision
    into v_lat, v_lng
  from public.destinations d
  where d.id = p_destination_id and d.status = 'approved'::public.destination_status;
  if not found then
    raise exception 'Destination not found';
  end if;
  if v_lat is null or v_lng is null then
    raise exception 'This spot has no map pin yet, so check-in is not available.';
  end if;

  -- Haversine, earth radius 6371 km.
  v_dist := round(2 * 6371000 * asin(sqrt(
    power(sin(radians(p_lat - v_lat) / 2), 2) +
    cos(radians(v_lat)) * cos(radians(p_lat)) * power(sin(radians(p_lng - v_lng) / 2), 2)
  )));

  if v_dist > 200 then
    return query select false, v_dist, null::timestamptz;
    return;
  end if;

  -- One live check-in per spot: refresh it instead of piling up rows.
  update public.visits v
     set created_at = now(), expires_at = v_exp, distance_m = v_dist
   where v.user_id = v_uid and v.destination_id = p_destination_id and v.kind = 'checkin';
  if not found then
    insert into public.visits (user_id, destination_id, kind, distance_m, expires_at)
    values (v_uid, p_destination_id, 'checkin', v_dist, v_exp);
  end if;

  return query select true, v_dist, v_exp;
end;
$$;

revoke all on function public.check_in(uuid, double precision, double precision) from public, anon;
grant execute on function public.check_in(uuid, double precision, double precision) to authenticated;

-- ── Review rule ──────────────────────────────────────────────────────────
alter table public.destination_reviews
  add column if not exists verified_visit boolean not null default false;

-- Existing reviews by tourists with a completed booking there count as verified.
update public.destination_reviews r
   set verified_visit = true
 where not r.verified_visit
   and exists (
     select 1 from public.visits v
     where v.user_id = r.user_id and v.destination_id = r.destination_id and v.kind = 'booking'
   );

-- What the tourist app shows in place of the review form.
--   ok          can review (verified visit found)
--   reviewed    already reviewed this place
--   new_account account is less than 24 hours old (available_at = when)
--   no_visit    needs a completed booking or an "I'm here" check-in
create or replace function public.review_eligibility(p_destination_id uuid)
returns table (status text, available_at timestamptz, checkin_expires_at timestamptz)
language plpgsql
stable
security definer
set search_path to ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_created timestamptz;
  v_checkin timestamptz;
begin
  if v_uid is null then
    return query select 'no_visit'::text, null::timestamptz, null::timestamptz;
    return;
  end if;

  if exists (select 1 from public.destination_reviews r
             where r.user_id = v_uid and r.destination_id = p_destination_id) then
    return query select 'reviewed'::text, null::timestamptz, null::timestamptz;
    return;
  end if;

  select u.created_at into v_created from auth.users u where u.id = v_uid;
  if v_created > now() - interval '24 hours' then
    return query select 'new_account'::text, v_created + interval '24 hours', null::timestamptz;
    return;
  end if;

  if exists (select 1 from public.visits v
             where v.user_id = v_uid and v.destination_id = p_destination_id and v.kind = 'booking') then
    return query select 'ok'::text, null::timestamptz, null::timestamptz;
    return;
  end if;

  select max(v.expires_at) into v_checkin
  from public.visits v
  where v.user_id = v_uid and v.destination_id = p_destination_id
    and v.kind = 'checkin' and v.expires_at > now();
  if v_checkin is not null then
    return query select 'ok'::text, null::timestamptz, v_checkin;
    return;
  end if;

  return query select 'no_visit'::text, null::timestamptz, null::timestamptz;
end;
$$;

revoke all on function public.review_eligibility(uuid) from public, anon;
grant execute on function public.review_eligibility(uuid) to authenticated;

-- Enforced on every tourist insert; verified_visit can't be set by the client.
create or replace function public.guard_review_visit()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_status text;
begin
  if (select auth.uid()) is null or public.has_role('admin'::public.user_role) then
    return new;
  end if;

  if tg_op = 'UPDATE' then
    new.verified_visit := old.verified_visit;
    return new;
  end if;

  select e.status into v_status
  from public.review_eligibility(new.destination_id) e;

  if v_status = 'reviewed' then
    raise exception 'You already reviewed this place.';
  elsif v_status = 'new_account' then
    raise exception 'New accounts can post reviews 24 hours after signing up.';
  elsif v_status is distinct from 'ok' then
    raise exception 'Only visitors can review. Book this place, or tap "I''m here" when you are at the spot.';
  end if;

  new.verified_visit := true;
  return new;
end;
$$;

drop trigger if exists guard_review_visit on public.destination_reviews;
create trigger guard_review_visit
  before insert or update on public.destination_reviews
  for each row execute function public.guard_review_visit();

-- ── Owner notice on a new review ─────────────────────────────────────────
alter table public.notifications
  drop constraint if exists notifications_type_check,
  add constraint notifications_type_check check (type = any (array[
    'booking', 'recommendation', 'alert', 'general', 'booking_request', 'booking_status',
    'payment', 'destination_status', 'owner_status', 'review'
  ]));

create or replace function public.notify_new_review()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_owner uuid;
  v_dest text;
begin
  select d.owner_id, d.name into v_owner, v_dest
  from public.destinations d where d.id = new.destination_id;
  perform public.notify(v_owner, 'New review',
    'A visitor rated ' || coalesce(v_dest, 'your spot') || ' ' || new.rating || ' star' ||
    case when new.rating > 1 then 's' else '' end || '. Tap to read and reply.',
    'review');
  return new;
end;
$$;

drop trigger if exists reviews_notify_owner on public.destination_reviews;
create trigger reviews_notify_owner
  after insert on public.destination_reviews
  for each row execute function public.notify_new_review();

-- ── Reported reviews ─────────────────────────────────────────────────────
create table if not exists public.review_reports (
  id uuid primary key default gen_random_uuid(),
  review_id uuid not null references public.destination_reviews(id) on delete cascade,
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  reason text not null check (length(reason) between 3 and 500),
  status text not null default 'open' check (status in ('open', 'dismissed')),
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  unique (review_id, reporter_id)
);

create index if not exists idx_review_reports_status on public.review_reports (status);

alter table public.review_reports enable row level security;

create policy "Owners read own reports" on public.review_reports
  for select to authenticated using (reporter_id = (select auth.uid()));
create policy "Admins manage reports" on public.review_reports
  for all to authenticated
  using (public.has_role('admin'::public.user_role))
  with check (public.has_role('admin'::public.user_role));

-- Owner of the reviewed spot flags a review for the admin. Reporting again
-- reopens it with the new reason.
create or replace function public.report_review(p_review_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_reason text := nullif(trim(p_reason), '');
begin
  if not public.is_approved_owner() then
    raise exception 'Only approved owners can report reviews';
  end if;
  if not exists (
    select 1
    from public.destination_reviews r
    join public.destinations d on d.id = r.destination_id
    where r.id = p_review_id and d.owner_id = (select auth.uid())
  ) then
    raise exception 'Review not found for your destination';
  end if;
  if v_reason is null or length(v_reason) < 3 then
    raise exception 'Please say briefly why you are reporting this review.';
  end if;
  if length(v_reason) > 500 then
    raise exception 'Reason is too long (max 500 characters)';
  end if;

  insert into public.review_reports (review_id, reporter_id, reason)
  values (p_review_id, (select auth.uid()), v_reason)
  on conflict (review_id, reporter_id)
  do update set reason = excluded.reason, status = 'open', created_at = now(), resolved_at = null;
end;
$$;

revoke all on function public.report_review(uuid, text) from public, anon;
grant execute on function public.report_review(uuid, text) to authenticated;
