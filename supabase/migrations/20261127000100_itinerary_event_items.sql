-- Trips can hold town events ("Add to my trip", and the Event agent adding
-- an event to a saved trip that falls on its date). The stop keeps the
-- event's name in title; removing the event removes the stop.
alter table public.itinerary_items
  add column if not exists event_id uuid references public.events(id) on delete cascade;

create index if not exists itinerary_items_event_id_idx on public.itinerary_items (event_id);

alter table public.itinerary_items
  drop constraint if exists itinerary_items_kind_check,
  add constraint itinerary_items_kind_check
    check (kind in ('visit', 'meal', 'stay', 'event'));

alter table public.itinerary_items
  drop constraint if exists itinerary_items_event_check,
  add constraint itinerary_items_event_check
    check ((kind = 'event') = (event_id is not null));
