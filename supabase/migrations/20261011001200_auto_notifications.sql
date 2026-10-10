-- Round 2 / step 8: in-app notifications created by the database itself, so
-- every path (owner app, admin panel, PayMongo webhook) produces them.
--   booking created          -> owner   "New booking request"
--   booking status changed   -> tourist "Booking confirmed / declined / …"
--   booking paid             -> owner   "Payment received"
--   destination approved/rejected -> owner
--   owner account approved/rejected -> owner
-- Realtime is enabled on notifications so open apps can pop them instantly.

create or replace function public.notify(p_user uuid, p_title text, p_body text, p_type text)
returns void
language sql
security definer
set search_path to ''
as $$
  insert into public.notifications (user_id, title, body, type, read)
  select p_user, p_title, p_body, p_type, false
  where p_user is not null;
$$;
revoke all on function public.notify(uuid, text, text, text) from public, anon, authenticated;

create or replace function public.notify_booking_changes()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_dest text;
  v_date text;
begin
  select name into v_dest from public.destinations where id = new.destination_id;
  v_date := to_char(new.booking_date, 'FMMonth FMDD, YYYY');

  if tg_op = 'INSERT' then
    perform public.notify(new.owner_id, 'New booking request',
      coalesce(new.contact_name, 'A tourist') || ' wants a guide at ' || coalesce(v_dest, 'your spot') ||
      ' on ' || v_date || ' (' || new.num_guests || ' guest' || case when new.num_guests > 1 then 's' else '' end || ').',
      'booking_request');
    return new;
  end if;

  if new.status is distinct from old.status then
    perform public.notify(new.tourist_id,
      case new.status
        when 'confirmed' then 'Booking confirmed'
        when 'rejected' then 'Booking declined'
        when 'cancelled' then 'Booking cancelled'
        when 'completed' then 'Trip completed'
        else 'Booking updated'
      end,
      case new.status
        when 'confirmed' then 'Your tour guide booking at ' || coalesce(v_dest, 'your destination') || ' on ' || v_date || ' was approved.'
        when 'rejected' then 'Sorry, your booking at ' || coalesce(v_dest, 'your destination') || ' on ' || v_date || ' was declined.'
        when 'cancelled' then 'Your booking at ' || coalesce(v_dest, 'your destination') || ' on ' || v_date || ' was cancelled.'
        when 'completed' then 'Thanks for visiting ' || coalesce(v_dest, 'Ipil') || '! You can now leave a review.'
        else 'Your booking at ' || coalesce(v_dest, 'your destination') || ' was updated.'
      end,
      'booking_status');
  end if;

  if new.payment_status = 'paid' and old.payment_status is distinct from 'paid' then
    perform public.notify(new.owner_id, 'Payment received',
      coalesce(new.contact_name, 'A tourist') || ' paid for the ' || v_date || ' booking at ' || coalesce(v_dest, 'your spot') || '.',
      'payment');
  end if;
  return new;
end;
$$;

drop trigger if exists bookings_notify on public.bookings;
create trigger bookings_notify
  after insert or update on public.bookings
  for each row execute function public.notify_booking_changes();

create or replace function public.notify_destination_status()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  if new.status is distinct from old.status and new.owner_id is not null then
    if new.status = 'approved' then
      perform public.notify(new.owner_id, 'Your spot is live!',
        new.name || ' was approved and tourists can now see it in IpilGo.', 'destination_status');
    elsif new.status = 'rejected' then
      perform public.notify(new.owner_id, 'Changes needed',
        new.name || ' was not approved. Please review your details and save again.', 'destination_status');
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists destinations_notify_status on public.destinations;
create trigger destinations_notify_status
  after update of status on public.destinations
  for each row execute function public.notify_destination_status();

create or replace function public.notify_owner_status()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  if new.owner_status is distinct from old.owner_status then
    if new.owner_status = 'approved' then
      perform public.notify(new.id, 'Owner account approved',
        'Welcome to IpilGo! You can now set up your destination in the owner app.', 'owner_status');
    elsif new.owner_status = 'rejected' then
      perform public.notify(new.id, 'Owner application declined',
        'Your owner application was not approved. Contact the IpilGo team for details.', 'owner_status');
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_notify_owner_status on public.profiles;
create trigger profiles_notify_owner_status
  after update of owner_status on public.profiles
  for each row execute function public.notify_owner_status();

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'notifications'
  ) then
    alter publication supabase_realtime add table public.notifications;
  end if;
end $$;

-- Applied as a follow-up (notifications_type_values): the existing
-- notifications_type_check only allowed booking/recommendation/alert/general,
-- which made every booking status change fail. Allow the new types.
alter table public.notifications drop constraint if exists notifications_type_check;
alter table public.notifications add constraint notifications_type_check
  check (type = any (array['booking', 'recommendation', 'alert', 'general',
    'booking_request', 'booking_status', 'payment', 'destination_status', 'owner_status']));
