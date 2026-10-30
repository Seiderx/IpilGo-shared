-- Remember what the admin last approved, so a re-review can show what the owner changed.
alter table public.destinations add column if not exists approved_snapshot jsonb;

-- Spots live today are the baseline for their next edit (runs before the trigger,
-- which would otherwise keep the old empty value).
update public.destinations set approved_snapshot = jsonb_build_object(
  'name', name, 'description', description, 'category', category,
  'tags', tags, 'address', address, 'latitude', latitude,
  'longitude', longitude, 'operating_hours', operating_hours,
  'entrance_fee', entrance_fee, 'amenities', amenities, 'images', images,
  'panoramic_360_url', panoramic_360_url, 'contact_number', contact_number,
  'contact_email', contact_email, 'approved_at', now())
where status = 'approved' and approved_snapshot is null;

create or replace function public.destination_approved_snapshot()
returns trigger
language plpgsql
set search_path to ''
as $function$
begin
  if new.status = 'approved' and (tg_op = 'INSERT' or old.status is distinct from 'approved') then
    new.approved_snapshot := jsonb_build_object(
      'name', new.name, 'description', new.description, 'category', new.category,
      'tags', new.tags, 'address', new.address, 'latitude', new.latitude,
      'longitude', new.longitude, 'operating_hours', new.operating_hours,
      'entrance_fee', new.entrance_fee, 'amenities', new.amenities, 'images', new.images,
      'panoramic_360_url', new.panoramic_360_url, 'contact_number', new.contact_number,
      'contact_email', new.contact_email, 'approved_at', now());
  elsif tg_op = 'UPDATE' then
    -- Only an approval writes the snapshot; nobody can edit it by hand.
    new.approved_snapshot := old.approved_snapshot;
  else
    new.approved_snapshot := null;
  end if;
  return new;
end;
$function$;

-- "zz_" so it runs after destinations_enforce_approval has settled the status.
create or replace trigger zz_destination_approved_snapshot
  before insert or update on public.destinations
  for each row execute function public.destination_approved_snapshot();
