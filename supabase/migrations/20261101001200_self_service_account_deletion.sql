-- Self-service account deletion (tourist and owner apps, no admin approval).
-- The delete-account edge function calls prepare_account_deletion() with the
-- service role, then deletes the auth user; the foreign keys do the rest.
--
-- Kept after deletion: past bookings and their payment ledger, with the
-- tourist's name replaced by 'Deleted user' (money records the owner and the
-- Tourism Office still need). Removed: profile, preferences, favorites,
-- itineraries, AI logs, notifications, visits and the tourist's reviews (the
-- destination rating is recalculated by the existing review trigger).

-- 1. A listing whose owner deleted their account is taken off the app with a
--    reason the admin can read, instead of landing in the review queue.
create or replace function public.hide_orphaned_destination()
returns trigger
language plpgsql
set search_path to ''
as $$
begin
  if old.owner_id is not null and new.owner_id is null then
    new.status := 'rejected';
    new.review_note := 'The owner deleted their IpilGo account.';
  end if;
  return new;
end;
$$;

-- 2. What stops an account from being deleted right now. The app shows this
--    list before the warning; the server checks it again before deleting.
create or replace function public.account_deletion_blockers(p_user uuid default null)
returns table (booking_id uuid, booking_date date, destination text, reason text)
language plpgsql
stable
security definer
set search_path to ''
as $$
declare
  v_user uuid := coalesce(p_user, (select auth.uid()));
  v_today date := (now() at time zone 'Asia/Manila')::date;
begin
  -- Only the service role may ask about someone else.
  if p_user is not null and p_user is distinct from (select auth.uid())
     and coalesce(auth.jwt() ->> 'role', '') <> 'service_role' then
    raise exception 'Not allowed';
  end if;
  if v_user is null then
    raise exception 'Not signed in';
  end if;

  if exists (select 1 from public.profiles where id = v_user and role = 'admin') then
    return query select null::uuid, null::date, null::text,
      'Admin accounts are removed by another admin, not from the app.'::text;
    return;
  end if;

  -- Tourist: an upcoming booking with money already paid must be cancelled
  -- first through the normal flow, so any refund is sent to them.
  return query
    select b.id, b.booking_date, d.name,
      'You paid ₱' || b.amount_paid || ' for this booking. Cancel it first so any refund reaches you.'
    from public.bookings b
    left join public.destinations d on d.id = b.destination_id
    where b.tourist_id = v_user
      and b.status in ('pending', 'confirmed')
      and b.booking_date >= v_today
      and b.amount_paid > 0
    order by b.booking_date;

  -- Owner: tourists are still counting on any upcoming booking.
  return query
    select b.id, b.booking_date, d.name,
      'A tourist booked ' || coalesce(d.name, 'your spot') || ' for this date. Decline or finish it first.'
    from public.bookings b
    left join public.destinations d on d.id = b.destination_id
    where b.owner_id = v_user
      and b.status in ('pending', 'confirmed')
      and b.booking_date >= v_today
    order by b.booking_date;
end;
$$;

revoke all on function public.account_deletion_blockers(uuid) from public, anon;
grant execute on function public.account_deletion_blockers(uuid) to authenticated, service_role;

-- 3. Everything the database does before the auth user is deleted. Service
--    role only (called by the delete-account edge function).
create or replace function public.prepare_account_deletion(p_user uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  b record;
  v_today date := (now() at time zone 'Asia/Manila')::date;
begin
  -- Without migration 20261101001100 deleting the user would cascade away
  -- their bookings and payment records.
  if (select confdeltype from pg_constraint where conrelid = 'public.bookings'::regclass and conname = 'bookings_tourist_id_fkey') <> 'n' then
    raise exception 'Account deletion is not set up yet (bookings would be lost)';
  end if;
  if exists (select 1 from public.account_deletion_blockers(p_user)) then
    raise exception 'This account still has bookings to settle';
  end if;

  perform set_config('ipilgo.server_write', 'on', true);

  -- Unpaid upcoming bookings are cancelled, and the owner is told.
  for b in
    select bk.id, bk.owner_id, bk.booking_date, bk.contact_name, d.name as dest
    from public.bookings bk
    left join public.destinations d on d.id = bk.destination_id
    where bk.tourist_id = p_user
      and bk.status in ('pending', 'confirmed')
      and bk.booking_date >= v_today
  loop
    update public.bookings
      set status = 'cancelled', cancel_reason = 'The tourist deleted their IpilGo account.'
      where id = b.id;
    perform public.notify(b.owner_id, 'Booking cancelled',
      coalesce(b.contact_name, 'A tourist') || ' deleted their IpilGo account, so the ' ||
      to_char(b.booking_date, 'FMMonth FMDD, YYYY') || ' booking at ' || coalesce(b.dest, 'your spot') ||
      ' was cancelled.', 'booking_status');
  end loop;

  -- Past bookings stay for the owner's and the Tourism Office's records,
  -- without the tourist's personal details.
  update public.bookings
    set contact_name = 'Deleted user', contact_phone = null
    where tourist_id = p_user;
  -- Reviews, visits, favorites etc. go with the profile (on delete cascade);
  -- the review trigger recalculates each destination's rating.
end;
$$;

revoke all on function public.prepare_account_deletion(uuid) from public, anon, authenticated;
grant execute on function public.prepare_account_deletion(uuid) to service_role;
