-- Admin guardrails: an approved admin moderates, but cannot rewrite other
-- people's content, money or private data. Every rule is enforced here so a
-- script using the admin's session cannot skip what the panel hides.
--
-- 1. Listings an owner manages: admin may approve/reject (with reason), hide
--    services and set the Food level. Content, prices and deposits stay the
--    owner's. Admin-created listings (owner_id null) stay fully editable.
-- 2. Listings of a suspended owner cannot be approved.
-- 3. Bookings: admin may decline a pending booking or cancel an active one
--    (full refund, reason shown to tourist and owner). Admin cannot accept
--    for the owner, mark completed, or touch any payment field.
-- 4. Reviews: admin may remove, never edit.
-- 5. Accounts: admin may only change owner/admin approval of others; never
--    names, phones, roles, their own status, or delete a profile.
-- 6. Tourist private data (itineraries, preferences, payments, AI logs) is
--    read-only to admins.
-- 7. admin_set_account_disabled(): block / unblock sign-in of a tourist or
--    owner (auth.users.banned_until). Token refresh is refused too, so an
--    open session ends when its access token expires (at most 1 hour).

-- ---------------------------------------------------------------- 1 + 2
create or replace function public.guard_admin_destination_writes()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  food_keys text[] := array['food', 'snacks', 'meals'];
  free_keys text[] := array['status', 'review_note', 'tags', 'avg_rating', 'approved_snapshot', 'updated_at'];
  old_food text[];
  new_food text[];
begin
  if current_setting('ipilgo.server_write', true) = 'on'
     or (select auth.uid()) is null
     or not public.has_role('admin') then
    return coalesce(new, old);
  end if;

  if tg_op = 'INSERT' then
    if new.owner_id is not null then
      raise exception 'Owners add their own listings. A listing the admin adds has no owner.';
    end if;
    return new;
  end if;

  if tg_op = 'DELETE' then
    if old.owner_id is not null then
      raise exception 'This listing belongs to an owner. Reject it with a reason instead of deleting it.';
    end if;
    return old;
  end if;

  -- UPDATE
  if new.status = 'approved' and old.status is distinct from 'approved' and new.owner_id is not null
     and not exists (select 1 from public.profiles p
                     where p.id = new.owner_id and p.role = 'owner' and p.owner_status = 'approved') then
    raise exception 'The owner of this listing is not approved or is suspended. Reinstate the owner first.';
  end if;

  if old.owner_id is null then
    if new.owner_id is not null then
      raise exception 'Listings cannot be handed to an owner from the panel.';
    end if;
    return new;
  end if;

  if new.owner_id is distinct from old.owner_id then
    raise exception 'A listing cannot be moved to another owner.';
  end if;

  -- entrance_fee follows the active entrance service when there is one.
  if public.entrance_service_price(new.id) is not null then
    free_keys := free_keys || 'entrance_fee'::text;
  end if;

  if (to_jsonb(old) - free_keys) is distinct from (to_jsonb(new) - free_keys) then
    raise exception 'This listing belongs to its owner. Reject it with a reason so the owner can fix it.';
  end if;

  -- Tags: only the Food level (food / snacks / meals) is the admin's call.
  if array(select lower(t) from unnest(coalesce(old.tags, '{}')) t where lower(t) <> all (food_keys) order by 1)
     is distinct from
     array(select lower(t) from unnest(coalesce(new.tags, '{}')) t where lower(t) <> all (food_keys) order by 1) then
    raise exception 'Only the Food level of an owner''s listing can be changed by the admin.';
  end if;

  old_food := array(select lower(t) from unnest(coalesce(old.tags, '{}')) t where lower(t) = any (food_keys) order by 1);
  new_food := array(select lower(t) from unnest(coalesce(new.tags, '{}')) t where lower(t) = any (food_keys) order by 1);
  if old_food is distinct from new_food then
    perform public.notify(new.owner_id, 'Food level updated',
      'The IpilGo admin set ' || new.name || ' to "' ||
      case when 'meals' = any (new_food) then 'Full meals'
           when 'snacks' = any (new_food) then 'Snacks only'
           else 'No food' end ||
      '" so the itinerary planner schedules it correctly. You can change it in your listing.',
      'destination_status');
  end if;

  return new;
end;
$$;

create trigger destinations_guard_admin
  before insert or update or delete on public.destinations
  for each row execute function public.guard_admin_destination_writes();

-- Admin hides/shows an owner's service: tell the owner.
create or replace function public.notify_admin_service_toggle()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  d record;
begin
  if new.is_active is distinct from old.is_active
     and (select auth.uid()) is not null and public.has_role('admin') then
    select name, owner_id into d from public.destinations where id = new.destination_id;
    perform public.notify(d.owner_id,
      case when new.is_active then 'Service shown again' else 'Service hidden' end,
      'The IpilGo admin ' || case when new.is_active then 'made "' || new.name || '" visible again'
                                  else 'hid "' || new.name || '" from tourists' end ||
      ' at ' || coalesce(d.name, 'your listing') || '.', 'destination_status');
  end if;
  return new;
end;
$$;

create trigger destination_services_notify_admin_toggle
  after update on public.destination_services
  for each row execute function public.notify_admin_service_toggle();

-- ---------------------------------------------------------------- 3
alter table public.bookings add column if not exists cancel_reason text;

create or replace function public.protect_booking_payment_fields()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  jwt_role text := coalesce(auth.jwt() ->> 'role', '');
  is_owner boolean := auth.uid() = old.owner_id;
  is_admin boolean := auth.uid() is not null and has_role('admin'::user_role);
  manila_today date := (now() at time zone 'Asia/Manila')::date;
begin
  if jwt_role = 'service_role' or auth.uid() is null
     or current_setting('ipilgo.server_write', true) = 'on' then
    return new;
  end if;

  if new.payment_status is distinct from old.payment_status
     or new.payment_reference is distinct from old.payment_reference
     or new.payment_method is distinct from old.payment_method
     or new.total_amount is distinct from old.total_amount
     or new.deposit_amount is distinct from old.deposit_amount
     or new.amount_due_now is distinct from old.amount_due_now
     or new.amount_paid is distinct from old.amount_paid
     or new.payment_choice is distinct from old.payment_choice
     or new.deposit_refundable is distinct from old.deposit_refundable
     or new.refund_due is distinct from old.refund_due
     or new.refund_amount is distinct from old.refund_amount
     or new.refunded_at is distinct from old.refunded_at
     or new.respond_by is distinct from old.respond_by then
    raise exception 'Payment fields can only be updated by verified server-side payment processing';
  end if;

  if is_admin then
    if (to_jsonb(new) - array['status', 'cancel_reason'])
       is distinct from (to_jsonb(old) - array['status', 'cancel_reason']) then
      raise exception 'Admins can only decline or cancel a booking';
    end if;
    if new.status is not distinct from old.status then
      return new;
    end if;
    if not ((old.status = 'pending' and new.status = 'rejected')
            or (old.status in ('pending', 'confirmed') and new.status = 'cancelled')) then
      raise exception 'Admins can decline a pending booking or cancel an active one. Accepting and completing are the owner''s call.';
    end if;
    if nullif(trim(coalesce(new.cancel_reason, '')), '') is null then
      raise exception 'Give the tourist a reason';
    end if;
    return new;
  end if;

  if new.status is not distinct from old.status then
    return new;
  end if;

  if is_owner then
    if old.status = 'pending' and new.status = 'confirmed' then
      if old.deposit_amount > 0 and old.amount_paid < old.deposit_amount then
        raise exception 'Waiting for the tourist''s down payment before this booking can be accepted';
      end if;
    elsif old.status = 'pending' and new.status = 'rejected' then
      null;
    elsif old.status = 'confirmed' and new.status = 'completed' then
      if old.booking_date > manila_today then
        raise exception 'A booking can only be marked completed on or after its date';
      end if;
    else
      raise exception 'Owners can only accept or decline pending bookings, or mark accepted bookings completed';
    end if;
  elsif auth.uid() = old.tourist_id then
    if new.status <> 'cancelled' then
      raise exception 'Tourists can only cancel their bookings';
    end if;
  end if;

  return new;
end;
$$;

-- Admin cancellation is never the tourist's fault: full refund.
create or replace function public.booking_refund_rules()
returns trigger
language plpgsql
set search_path to ''
as $$
declare
  full_refund boolean;
begin
  if new.status in ('rejected', 'cancelled')
     and old.status not in ('rejected', 'cancelled')
     and new.amount_paid > 0
     and new.refunded_at is null then
    full_refund := new.status = 'rejected' or old.status = 'pending' or new.deposit_refundable
                   or ((select auth.uid()) is not null and public.has_role('admin'));
    new.refund_amount := case when full_refund then new.amount_paid
                              else greatest(0, new.amount_paid - new.deposit_amount) end;
    new.refund_due := new.refund_amount > 0;
  end if;
  return new;
end;
$$;

create or replace function public.notify_booking_changes()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_dest text;
  v_date text;
  v_reason text := coalesce(' Reason: ' || nullif(trim(new.cancel_reason), '') || '.', '');
  by_admin boolean := tg_op = 'UPDATE' and (select auth.uid()) is not null and public.has_role('admin');
begin
  select name into v_dest from public.destinations where id = new.destination_id;
  v_date := to_char(new.booking_date, 'FMMonth FMDD, YYYY');

  if tg_op = 'INSERT' then
    perform public.notify(new.owner_id, 'New booking request',
      coalesce(new.contact_name, 'A tourist') || ' wants to book ' || coalesce(v_dest, 'your spot') ||
      ' on ' || v_date || ' (' || new.num_guests || ' guest' || case when new.num_guests > 1 then 's' else '' end || ').' ||
      case when new.deposit_amount > 0 then ' Their down payment is due within 24 hours.' else '' end,
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
        when 'confirmed' then 'Your booking at ' || coalesce(v_dest, 'your destination') || ' on ' || v_date || ' was accepted.'
        when 'rejected' then 'Sorry, your booking at ' || coalesce(v_dest, 'your destination') || ' on ' || v_date || ' was declined' ||
          case when by_admin then ' by IpilGo.' || v_reason else '.' end
        when 'cancelled' then 'Your booking at ' || coalesce(v_dest, 'your destination') || ' on ' || v_date || ' was cancelled' ||
          case when by_admin then ' by IpilGo.' || v_reason else '.' end
        when 'completed' then 'Thanks for visiting ' || coalesce(v_dest, 'Ipil') || '! You can now leave a review.'
        else 'Your booking at ' || coalesce(v_dest, 'your destination') || ' was updated.'
      end ||
      case when new.refund_due and not old.refund_due
        then ' A refund of ₱' || new.refund_amount || ' is on its way to your account.' else '' end,
      'booking_status');
    if by_admin then
      perform public.notify(new.owner_id,
        case new.status when 'rejected' then 'Booking declined by IpilGo' else 'Booking cancelled by IpilGo' end,
        'The ' || v_date || ' booking of ' || coalesce(new.contact_name, 'a tourist') || ' at ' ||
        coalesce(v_dest, 'your spot') || ' was ' || case new.status when 'rejected' then 'declined' else 'cancelled' end ||
        ' by the IpilGo admin.' || v_reason, 'booking_status');
    end if;
  end if;

  if new.amount_paid > old.amount_paid then
    if (select auth.uid()) = new.owner_id then
      perform public.notify(new.tourist_id, 'Cash payment recorded',
        coalesce(v_dest, 'The owner') || ' recorded ₱' || (new.amount_paid - old.amount_paid) ||
        ' cash from you for your ' || v_date || ' booking.' ||
        case when new.amount_paid >= new.total_amount then ' Your booking is fully paid.'
             else ' Remaining balance: ₱' || (new.total_amount - new.amount_paid) || '.' end,
        'payment');
    else
      perform public.notify(new.owner_id,
        case when new.payment_status = 'paid' then 'Payment received' else 'Down payment received' end,
        coalesce(new.contact_name, 'A tourist') || ' paid ₱' || (new.amount_paid - old.amount_paid) ||
        ' for the ' || v_date || ' booking at ' || coalesce(v_dest, 'your spot') || '.',
        'payment');
    end if;
  end if;

  if new.refunded_at is not null and old.refunded_at is null then
    perform public.notify(new.tourist_id, 'Refund sent',
      '₱' || new.refund_amount || ' for your ' || coalesce(v_dest, 'Ipil') || ' booking was refunded to your e-wallet.',
      'payment');
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------- 4
create or replace function public.guard_admin_review_edits()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  if (select auth.uid()) is not null and public.has_role('admin') then
    raise exception 'Admins can remove a review but not change what a tourist or owner wrote.';
  end if;
  return new;
end;
$$;

create trigger destination_reviews_guard_admin
  before insert or update on public.destination_reviews
  for each row execute function public.guard_admin_review_edits();

-- ---------------------------------------------------------------- 5
create or replace function public.guard_admin_profile_writes()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  me uuid := (select auth.uid());
begin
  if me is null or current_setting('ipilgo.oauth_owner_claim', true) = 'on'
     or not public.has_role('admin') then
    return coalesce(new, old);
  end if;

  if tg_op = 'DELETE' then
    raise exception 'Accounts are blocked, not deleted. Use Block sign-in instead.';
  end if;

  if old.id = me then
    if new.role is distinct from old.role or new.admin_status is distinct from old.admin_status
       or new.owner_status is distinct from old.owner_status then
      raise exception 'You cannot change your own role or approval.';
    end if;
    return new;
  end if;

  if (to_jsonb(new) - array['owner_status', 'admin_status'])
     is distinct from (to_jsonb(old) - array['owner_status', 'admin_status']) then
    raise exception 'Admins can approve, decline or suspend accounts, not edit their details.';
  end if;
  if new.owner_status is distinct from old.owner_status and old.role <> 'owner' then
    raise exception 'Only owner accounts have an owner approval.';
  end if;
  if new.admin_status is distinct from old.admin_status and old.role <> 'admin' then
    raise exception 'Only admin accounts have an admin approval.';
  end if;
  return new;
end;
$$;

create trigger profiles_guard_admin
  before update or delete on public.profiles
  for each row execute function public.guard_admin_profile_writes();

-- ---------------------------------------------------------------- 6
create or replace function public.guard_admin_private_data()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  if (select auth.uid()) is not null and public.has_role('admin') then
    raise exception 'Tourist trip, preference and payment records are read-only for admins.';
  end if;
  return coalesce(new, old);
end;
$$;

create trigger itineraries_guard_admin before insert or update or delete on public.itineraries
  for each row execute function public.guard_admin_private_data();
create trigger itinerary_items_guard_admin before insert or update or delete on public.itinerary_items
  for each row execute function public.guard_admin_private_data();
create trigger tourist_preferences_guard_admin before insert or update or delete on public.tourist_preferences
  for each row execute function public.guard_admin_private_data();
create trigger booking_items_guard_admin before insert or update or delete on public.booking_items
  for each row execute function public.guard_admin_private_data();
create trigger booking_payments_guard_admin before insert or update or delete on public.booking_payments
  for each row execute function public.guard_admin_private_data();
create trigger ai_recommendation_logs_guard_admin before insert or update or delete on public.ai_recommendation_logs
  for each row execute function public.guard_admin_private_data();

-- ---------------------------------------------------------------- 7
create or replace function public.get_account_states()
returns table (id uuid, email text, email_confirmed_at timestamptz,
               last_sign_in_at timestamptz, banned_until timestamptz)
language sql
stable
security definer
set search_path to ''
as $$
  select u.id, u.email::text, u.email_confirmed_at, u.last_sign_in_at, u.banned_until
  from auth.users u
  where public.has_role('admin');
$$;

revoke execute on function public.get_account_states() from public, anon;
grant execute on function public.get_account_states() to authenticated;

create or replace function public.admin_set_account_disabled(p_user uuid, p_disabled boolean, p_reason text default null)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  target public.profiles;
begin
  if not public.has_role('admin') then
    raise exception 'Only an approved admin can do this';
  end if;
  select * into target from public.profiles where id = p_user;
  if not found then
    raise exception 'Account not found';
  end if;
  if target.role = 'admin' then
    raise exception 'Admin accounts are managed on the Admins page, not blocked.';
  end if;
  if p_disabled and nullif(trim(coalesce(p_reason, '')), '') is null then
    raise exception 'Give a reason for blocking this account';
  end if;

  update auth.users
     set banned_until = case when p_disabled then 'infinity'::timestamptz else null end
   where id = p_user;

  insert into public.admin_audit_log (actor_id, action, target_type, target_id, target_label, detail)
  values ((select auth.uid()), case when p_disabled then 'blocked' else 'unblocked' end,
          'profiles', p_user::text, target.full_name, nullif(trim(coalesce(p_reason, '')), ''));
end;
$$;

revoke execute on function public.admin_set_account_disabled(uuid, boolean, text) from public, anon;
grant execute on function public.admin_set_account_disabled(uuid, boolean, text) to authenticated;
