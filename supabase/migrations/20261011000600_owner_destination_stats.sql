-- Item 10: simple stats for owners — views, saves, AI recommendations.

-- One row per tourist per destination per day (repeat opens the same day
-- don't inflate the count). Written only through record_destination_view().
create table if not exists public.destination_views (
  destination_id uuid not null references public.destinations(id) on delete cascade,
  viewer_id uuid not null references auth.users(id) on delete cascade,
  view_date date not null default current_date,
  primary key (destination_id, viewer_id, view_date)
);

alter table public.destination_views enable row level security;
-- No policies: no direct reads/writes; RPCs below are the only access.

create index if not exists destination_views_dest_date_idx
  on public.destination_views (destination_id, view_date);

create or replace function public.record_destination_view(p_destination_id uuid)
returns void
language sql
security definer
set search_path to ''
as $$
  insert into public.destination_views (destination_id, viewer_id)
  select p_destination_id, (select auth.uid())
  where (select auth.uid()) is not null
  on conflict do nothing;
$$;

revoke all on function public.record_destination_view(uuid) from public;
grant execute on function public.record_destination_view(uuid) to authenticated;

-- Stats for the caller's own destination. "Recommended" counts AI runs where
-- the place ranked in the top 3 (the log stores the full ranking, best first).
create or replace function public.owner_destination_stats(p_destination_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $$
begin
  if not exists (
    select 1 from public.destinations
    where id = p_destination_id and owner_id = (select auth.uid())
  ) and not public.has_role('admin'::public.user_role) then
    raise exception 'Not your destination';
  end if;

  return jsonb_build_object(
    'views_7d', (select count(*) from public.destination_views
                 where destination_id = p_destination_id and view_date > current_date - 7),
    'views_30d', (select count(*) from public.destination_views
                  where destination_id = p_destination_id and view_date > current_date - 30),
    'views_total', (select count(*) from public.destination_views
                    where destination_id = p_destination_id),
    'saves', (select count(*) from public.tourist_favorites
              where destination_id = p_destination_id),
    'recommended_30d', (select count(*) from public.ai_recommendation_logs
                        where created_at > now() - interval '30 days'
                          and p_destination_id = any (recommended_destination_ids[1:3])),
    'recommended_total', (select count(*) from public.ai_recommendation_logs
                          where p_destination_id = any (recommended_destination_ids[1:3]))
  );
end;
$$;

revoke all on function public.owner_destination_stats(uuid) from public;
grant execute on function public.owner_destination_stats(uuid) to authenticated;
