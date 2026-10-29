-- Owner signups now pick a username too (one account = tourist + owner), so
-- the verify trigger claims the metadata username for owners as well.
-- Owners always send a real full_name, which is left untouched.

create or replace function public.handle_user_email_confirmed()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  wanted text := nullif(trim(new.raw_user_meta_data->>'username'), '');
  chosen text;
begin
  if wanted is null or not exists (
    select 1 from public.profiles
    where id = new.id and role in ('tourist', 'owner') and username is null
  ) then
    return new;
  end if;

  chosen := case when public.is_username_available(wanted) then wanted
                 else (public.suggest_usernames(wanted, 1))[1] end;
  if chosen is null then
    return new;
  end if;

  -- Never let a username race fail the verification itself.
  begin
    update public.profiles
       set username = chosen,
           full_name = case when coalesce(full_name, '') = '' then chosen else full_name end
     where id = new.id;
  exception when unique_violation then
    null;
  end;
  return new;
end;
$function$;
