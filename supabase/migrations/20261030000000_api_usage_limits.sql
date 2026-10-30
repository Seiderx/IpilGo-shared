-- Per-user daily quotas for the external-api edge function, which now holds
-- the Gemini, OpenWeather and Google Maps (web service) keys server-side.
-- Once billing is enabled on those keys, a signed-in user (or a script using a
-- stolen session) can only spend up to the daily limit, not run up the bill.
--
-- Only the edge function (service_role) reads or writes this table.

create table if not exists public.api_usage (
  user_id uuid not null references auth.users (id) on delete cascade,
  day date not null,
  kind text not null,
  count integer not null default 0,
  primary key (user_id, day, kind)
);

alter table public.api_usage enable row level security;
-- No policies: clients have no access at all.

-- Counts one call and reports whether it is still within the limit.
-- "Day" follows Philippine time so quotas reset at local midnight.
create or replace function public.bump_api_usage(p_user uuid, p_kind text, p_limit integer)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  insert into public.api_usage as u (user_id, day, kind, count)
  values (p_user, (now() at time zone 'Asia/Manila')::date, p_kind, 1)
  on conflict (user_id, day, kind)
  do update set count = u.count + 1
  returning u.count into v_count;
  return v_count <= p_limit;
end;
$$;

revoke all on function public.bump_api_usage(uuid, text, integer) from public, anon, authenticated;
grant execute on function public.bump_api_usage(uuid, text, integer) to service_role;
