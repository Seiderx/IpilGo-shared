-- Suspending an owner (owner_status approved -> rejected) now hides their
-- listings in the same transaction, and the owner is told it is a suspension,
-- not a declined application. Reinstating says so too.
-- Audit log: booking decline/cancel reasons and the tourist's name are kept.

create or replace function public.notify_owner_status()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  if new.owner_status is distinct from old.owner_status then
    if new.owner_status = 'approved' and old.owner_status = 'rejected' then
      perform public.notify(new.id, 'Owner account reinstated',
        'Your IpilGo owner account is active again. Open each listing and save it to send it back for review.', 'owner_status');
    elsif new.owner_status = 'approved' then
      perform public.notify(new.id, 'Owner account approved',
        'Welcome to IpilGo! You can now set up your destination in the owner app.', 'owner_status');
    elsif new.owner_status = 'rejected' and old.owner_status = 'approved' then
      update public.destinations
         set status = 'rejected',
             review_note = 'The owner account was suspended by the IpilGo admin.'
       where owner_id = new.id and status <> 'rejected';
      perform public.notify(new.id, 'Owner account suspended',
        'Your IpilGo owner account was suspended and your listings are hidden from tourists. Contact the IpilGo team for details.', 'owner_status');
    elsif new.owner_status = 'rejected' then
      perform public.notify(new.id, 'Owner application declined',
        'Your owner application was not approved. Contact the IpilGo team for details.', 'owner_status');
    end if;
  end if;
  return new;
end;
$$;

create or replace function public.log_admin_action()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  o jsonb := case when tg_op <> 'INSERT' then to_jsonb(old) end;
  n jsonb := case when tg_op <> 'DELETE' then to_jsonb(new) end;
  r jsonb := coalesce(n, o);
  act text;
  det text;
begin
  if (select auth.uid()) is null or not public.has_role('admin'::public.user_role) then
    return null;
  end if;

  if tg_op = 'INSERT' then
    act := 'created';
  elsif tg_op = 'DELETE' then
    act := 'deleted';
  else
    select string_agg(e.key, ', ' order by e.key) into det
    from jsonb_each(n) e
    where e.value is distinct from o -> e.key
      and e.key not in ('approved_snapshot', 'avg_rating', 'updated_at');
    if det is null then
      return null;
    end if;
    act := case
      when tg_table_name in ('destinations', 'bookings') and n->>'status' is distinct from o->>'status'
        then n->>'status'
      when tg_table_name = 'profiles' and n->>'owner_status' is distinct from o->>'owner_status'
        then 'owner ' || (n->>'owner_status')
      when tg_table_name = 'profiles' and n->>'admin_status' is distinct from o->>'admin_status'
        then 'admin ' || (n->>'admin_status')
      when tg_table_name = 'destination_services' and n->>'is_active' is distinct from o->>'is_active'
        then case when (n->>'is_active')::boolean then 'shown' else 'hidden' end
      when tg_table_name = 'safety_alerts' and n->>'active' is distinct from o->>'active'
        then case when (n->>'active')::boolean then 'activated' else 'ended' end
      else 'edited'
    end;
    if act <> 'edited' then
      det := null;
    end if;
    if tg_table_name = 'destinations' and act = 'rejected' then
      det := n->>'review_note';
    elsif tg_table_name = 'bookings' and act in ('rejected', 'cancelled') then
      det := n->>'cancel_reason';
    end if;
  end if;

  insert into public.admin_audit_log (actor_id, action, target_type, target_id, target_label, detail)
  values ((select auth.uid()), act, tg_table_name, r->>'id',
          coalesce(r->>'name', r->>'full_name', r->>'label', r->>'contact_name', r->>'message', left(r->>'comment', 80)),
          det);
  return null;
end;
$$;
