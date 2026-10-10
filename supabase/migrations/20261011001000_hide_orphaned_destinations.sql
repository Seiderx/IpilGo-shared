-- Round 2 / step 6: deleting an owner's account left their spot live with no
-- owner (owner_id is ON DELETE SET NULL), which also let the same business
-- register again and appear twice. When a destination LOSES its owner it now
-- goes back to 'pending' (hidden from tourists) so the admin can reassign,
-- run, or delete it. Admin-run places that never had an owner are untouched.
create or replace function public.hide_orphaned_destination()
returns trigger
language plpgsql
set search_path to ''
as $$
begin
  if old.owner_id is not null and new.owner_id is null then
    new.status := 'pending';
  end if;
  return new;
end;
$$;

drop trigger if exists destinations_hide_when_orphaned on public.destinations;
create trigger destinations_hide_when_orphaned
  before update of owner_id on public.destinations
  for each row execute function public.hide_orphaned_destination();

-- The original "Front yard" (Cafe) lost its owner before this rule existed and
-- now duplicates the re-registered one: hide it (reversible; nothing deleted).
update public.destinations
  set status = 'pending'
  where owner_id is null and name = 'Front yard' and category = 'Cafe';
