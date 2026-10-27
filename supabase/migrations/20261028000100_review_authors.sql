-- Reviewer names on a destination's reviews.
--
-- profiles RLS only lets a user read their own row, so the tourist app's
-- `destination_reviews -> profiles(full_name)` join came back null for every
-- other reviewer and showed "Tourist". This exposes just the public part
-- (display name + avatar) and only for people who reviewed that destination.

create or replace function public.review_authors(p_destination_id uuid)
returns table (user_id uuid, display_name text, avatar_url text)
language sql
stable
security definer
set search_path to ''
as $$
  select p.id,
         coalesce(nullif(p.username, ''), nullif(p.full_name, ''), 'Tourist'),
         p.avatar_url
  from public.profiles p
  where p.id in (
    select r.user_id from public.destination_reviews r
    where r.destination_id = p_destination_id
  );
$$;

revoke all on function public.review_authors(uuid) from public;
grant execute on function public.review_authors(uuid) to anon, authenticated;
