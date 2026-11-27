-- Admins couldn't delete a town event once a tourist had it in a trip: the
-- delete cascades to itinerary_items, and the admin guard on that table
-- blocked it ("Tourist trip ... records are read-only for admins").
-- itinerary_items now has its own guard: admins still can't write trips,
-- except the cascade that removes an event stop when its event is deleted
-- (fired from the foreign key, so trigger depth > 1).

create or replace function public.guard_admin_itinerary_items()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  if (select auth.uid()) is not null and public.has_role('admin') then
    if tg_op = 'DELETE' and pg_trigger_depth() > 1 and old.kind = 'event' then
      return old;
    end if;
    raise exception 'Tourist trip, preference and payment records are read-only for admins.';
  end if;
  return coalesce(new, old);
end;
$$;

revoke all on function public.guard_admin_itinerary_items() from public, anon, authenticated;

create or replace trigger itinerary_items_guard_admin
  before insert or update or delete on public.itinerary_items
  for each row execute function public.guard_admin_itinerary_items();
