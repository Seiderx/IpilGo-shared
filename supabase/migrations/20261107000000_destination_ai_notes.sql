-- What the AI saw in a place's photos and menus. Written only by the
-- place-notes edge function (service role). Read by AI Search for reasoning.
alter table public.destinations
  add column if not exists ai_notes text,
  add column if not exists ai_notes_at timestamptz;

comment on column public.destinations.ai_notes is
  'AI reading of the place photos and menus. Never a source for halal or other dietary claims.';
