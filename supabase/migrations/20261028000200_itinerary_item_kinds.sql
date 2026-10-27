-- Itinerary items can be meals and overnight stays, not only spot visits.
--
-- The Itinerary Agent now plans a whole trip: visits, breakfast/lunch/dinner
-- and where to sleep. Meals and stays point at a registered restaurant/hotel
-- when one exists; otherwise they are a plain slot ("Lunch break near ...")
-- with no destination, so destination_id becomes optional for those kinds.
-- is_suggested marks spots the agent added on its own (shown as "Suggested").

alter table public.itinerary_items
  add column if not exists kind text not null default 'visit',
  add column if not exists title text,
  add column if not exists is_suggested boolean not null default false;

alter table public.itinerary_items
  alter column destination_id drop not null;

alter table public.itinerary_items
  drop constraint if exists itinerary_items_kind_check,
  add constraint itinerary_items_kind_check
    check (kind in ('visit', 'meal', 'stay'));

-- A visit is always to a real destination; meals/stays need a venue or a title.
alter table public.itinerary_items
  drop constraint if exists itinerary_items_target_check,
  add constraint itinerary_items_target_check
    check (
      (kind = 'visit' and destination_id is not null)
      or (kind <> 'visit' and (destination_id is not null or nullif(title, '') is not null))
    );
