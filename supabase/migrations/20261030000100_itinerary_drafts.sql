-- Itinerary drafts: a freshly generated plan is a draft the tourist reviews
-- (full itinerary screen, "Draft" badge) and either saves or regenerates.
-- Drafts stay out of the tourist's Trips list and the admin analytics, and
-- ones never saved are removed after 3 days (items go with them: the
-- itinerary_items FK cascades).
--
-- Existing itineraries default to saved (is_draft = false).

alter table public.itineraries
  add column if not exists is_draft boolean not null default false;

create or replace function public.purge_stale_itinerary_drafts()
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.itineraries
  where is_draft and created_at < now() - interval '3 days';
$$;

revoke all on function public.purge_stale_itinerary_drafts() from public, anon, authenticated;

select cron.schedule(
  'purge-stale-itinerary-drafts',
  '30 3 * * *',
  $$select public.purge_stale_itinerary_drafts()$$
);
