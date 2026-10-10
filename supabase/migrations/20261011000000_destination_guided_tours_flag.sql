-- Scope decision (docs/IpilGo_Scope_Decisions.md): IpilGo books tour guides
-- only. A destination shows the Book button only when it offers guided tours;
-- hotels, restaurants and self-guided spots are showcase-only.
alter table public.destinations
  add column if not exists offers_guided_tours boolean not null default false;

comment on column public.destinations.offers_guided_tours is
  'True when tourists can book a tour guide for this destination (shows the Book button).';

-- Every destination was bookable before this flag existed; keep them that way
-- so nothing disappears. Owners/admins switch it off where there are no guides.
update public.destinations set offers_guided_tours = true;
