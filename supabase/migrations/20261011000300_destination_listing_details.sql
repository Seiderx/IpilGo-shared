-- Item 7: listing details owners keep fresh (scope doc, "Owner app").
--   listing_type     spot | hotel | restaurant (hotels/restaurants are
--                    showcase-only: no room booking, no ordering)
--   closed_until     "Closed today" = today's date; closed through that date
--   closed_reason    shown to tourists and fed to the safety/itinerary agents
--   facebook_url, website_url   own page / own booking site
--   price_from       hotels: "Rooms from PHP X"
--   price_range      restaurants: '₱' | '₱₱' | '₱₱₱'
--   featured_items   restaurants: [{ "name": text, "price": number|null, "image": url|null }]
alter table public.destinations
  add column if not exists listing_type text not null default 'spot',
  add column if not exists closed_until date,
  add column if not exists closed_reason text,
  add column if not exists facebook_url text,
  add column if not exists website_url text,
  add column if not exists price_from numeric,
  add column if not exists price_range text,
  add column if not exists featured_items jsonb not null default '[]'::jsonb;

alter table public.destinations drop constraint if exists destinations_listing_type_check;
alter table public.destinations add constraint destinations_listing_type_check
  check (listing_type in ('spot', 'hotel', 'restaurant'));

alter table public.destinations drop constraint if exists destinations_price_range_check;
alter table public.destinations add constraint destinations_price_range_check
  check (price_range is null or price_range in ('₱', '₱₱', '₱₱₱'));

alter table public.destinations drop constraint if exists destinations_featured_items_array;
alter table public.destinations add constraint destinations_featured_items_array
  check (jsonb_typeof(featured_items) = 'array');

-- Applied as a second migration (classify_existing_listings): classify the
-- existing rows by category, and make hotels/restaurants never bookable.
update public.destinations
  set listing_type = 'restaurant', offers_guided_tours = false
  where lower(coalesce(category, '')) in ('cafe', 'café', 'restaurant', 'food', 'restaurants', 'cafes')
     or lower(coalesce(category, '')) like '%restaurant%';

update public.destinations
  set listing_type = 'hotel', offers_guided_tours = false
  where lower(coalesce(category, '')) in ('hotel', 'hotels', 'resort', 'resorts', 'inn', 'lodging', 'accommodation');

alter table public.destinations drop constraint if exists destinations_only_spots_bookable;
alter table public.destinations add constraint destinations_only_spots_bookable
  check (listing_type = 'spot' or not offers_guided_tours);
