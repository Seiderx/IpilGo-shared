-- Fix: hiding or deleting the last entrance service left its price on
-- destinations.entrance_fee, so tourists still saw a fee that no longer
-- existed. Now the fee is cleared when the change removed the last active
-- entrance service. A fee typed in by hand (no entrance service involved)
-- is left alone.
create or replace function public.sync_entrance_fee()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  dest uuid := coalesce(new.destination_id, old.destination_id);
  svc_price numeric := public.entrance_service_price(dest);
  was_entrance boolean := tg_op <> 'INSERT' and old.kind = 'entrance' and old.is_active;
begin
  if svc_price is not null then
    perform set_config('ipilgo.server_write', 'on', true);
    update public.destinations set entrance_fee = svc_price
     where id = dest and entrance_fee is distinct from svc_price;
    perform set_config('ipilgo.server_write', 'off', true);
  elsif was_entrance then
    perform set_config('ipilgo.server_write', 'on', true);
    update public.destinations set entrance_fee = null
     where id = dest and entrance_fee is not null;
    perform set_config('ipilgo.server_write', 'off', true);
  end if;
  return null;
end;
$function$;
