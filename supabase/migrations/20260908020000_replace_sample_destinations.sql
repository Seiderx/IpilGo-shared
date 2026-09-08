-- Phase 6: replace synthetic sample destinations with real ones.
--
-- Safety check done before writing this (see chat history / audit): the 4
-- "Sample X" rows have zero destination_reviews, zero bookings, zero
-- itinerary_items referencing them. The only other place their ids appear
-- is ai_recommendation_logs.recommended_destination_ids, a uuid[] with no
-- FK constraint -- deleting is safe, it just leaves old log entries
-- referencing an id that no longer resolves (cosmetic only, not enforced).
--
-- Descriptions below are short, factual, and based only on the place name/
-- category/photos supplied -- no invented coordinates, fees, hours, or
-- ratings. Those stay null until real data is available, same as every
-- other destination in the table today.

delete from public.destinations
where owner_id is null
  and name in (
    'Sample Falls',
    'Sample Agri-Farm Park',
    'Sample Heritage Plaza',
    'Sample Beach Cove'
  );

insert into public.destinations (name, description, category, tags, address, status, owner_id, images)
select 'Stonehill Farms Ipil',
       'Stonehill Farms Ipil is a farm and elevated viewing deck in Ipil, Zamboanga Sibugay, known for its scenic overlook of the coastline and surrounding greenery -- a popular spot for photos and casual visits.',
       'Eco Tourism',
       array['farm', 'nature', 'photography', 'sightseeing'],
       'Ipil, Zamboanga Sibugay',
       'approved', null, '{}'
where not exists (
  select 1 from public.destinations where name = 'Stonehill Farms Ipil' and owner_id is null
);

insert into public.destinations (name, description, category, tags, address, status, owner_id, images)
select 'Ipil Multipurpose Government Center',
       'The Ipil Multipurpose Government Center, also known as Bayan ng Ipil, is the municipal government building of Ipil, Zamboanga Sibugay, serving as a civic landmark in the town center.',
       'Heritage',
       array['culture', 'sightseeing'],
       'Ipil, Zamboanga Sibugay',
       'approved', null, '{}'
where not exists (
  select 1 from public.destinations where name = 'Ipil Multipurpose Government Center' and owner_id is null
);

insert into public.destinations (name, description, category, tags, address, status, owner_id, images)
select 'Buluan Island',
       'Buluan Island is a small island off the coast of Ipil, Zamboanga Sibugay, known for its beach and forested interior -- a scenic spot for island-hopping and day trips.',
       'Beaches',
       array['beaches', 'swimming', 'sightseeing', 'photography'],
       'Ipil, Zamboanga Sibugay',
       'approved', null, '{}'
where not exists (
  select 1 from public.destinations where name = 'Buluan Island' and owner_id is null
);

insert into public.destinations (name, description, category, tags, address, status, owner_id, images)
select 'Provincial Capitol',
       'The Zamboanga Sibugay Provincial Capitol is the seat of the provincial government, set on a hilltop with panoramic views of the surrounding area -- a notable landmark in the province.',
       'Heritage',
       array['culture', 'sightseeing', 'photography'],
       'Ipil, Zamboanga Sibugay',
       'approved', null, '{}'
where not exists (
  select 1 from public.destinations where name = 'Provincial Capitol' and owner_id is null
);
