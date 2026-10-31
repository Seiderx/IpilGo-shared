-- Events: tourists (and the Event agent) only see town-wide events
-- (destination_id null, posted by the Tourism Office) or events of approved
-- listings. Before, events of pending/rejected/suspended listings leaked.
--
-- Admin: creates and edits town-wide events; may remove an owner's event
-- (moderation, owner notified) but never rewrite it.

alter policy "Anyone can view events" on public.events
  using (destination_id is null
         or exists (select 1 from public.destinations d
                    where d.id = events.destination_id and d.status = 'approved'));

create or replace function public.guard_admin_event_writes()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  d record;
begin
  if (select auth.uid()) is null or not public.has_role('admin') then
    return coalesce(new, old);
  end if;

  if tg_op = 'INSERT' then
    if new.destination_id is not null then
      raise exception 'Owners post events for their own listing. The Tourism Office posts town-wide events.';
    end if;
    return new;
  end if;

  if tg_op = 'UPDATE' then
    if old.destination_id is not null or new.destination_id is not null then
      raise exception 'This event belongs to an owner. Remove it if it breaks the rules instead of editing it.';
    end if;
    return new;
  end if;

  -- DELETE of an owner's event: tell the owner.
  if old.destination_id is not null then
    select name, owner_id into d from public.destinations where id = old.destination_id;
    perform public.notify(d.owner_id, 'Event removed',
      'The IpilGo admin removed "' || old.name || '" from ' || coalesce(d.name, 'your listing') ||
      '. Contact the IpilGo Tourism Office for details.', 'destination_status');
  end if;
  return old;
end;
$$;

create trigger events_guard_admin
  before insert or update or delete on public.events
  for each row execute function public.guard_admin_event_writes();
