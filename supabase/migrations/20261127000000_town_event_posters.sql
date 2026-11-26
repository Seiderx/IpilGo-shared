-- Town events: poster, start time and place (name + map pin).
-- Posters live in destination-images/admin/events/ (admin policy already allows it).
alter table public.events
  add column if not exists image_url text,
  add column if not exists start_time time,
  add column if not exists place_name text,
  add column if not exists lat double precision,
  add column if not exists lng double precision;

alter table public.events drop constraint if exists events_pin_pair;
alter table public.events add constraint events_pin_pair
  check ((lat is null) = (lng is null)
         and (lat is null or (lat between -90 and 90 and lng between -180 and 180)));
