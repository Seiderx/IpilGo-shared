-- Admin sidebar badges (pending owners, listings, reported reviews) listen
-- for changes on these tables, but only bookings and notifications were
-- published, so the counts stayed stale until a page refresh.
-- Realtime still applies RLS, so each client only hears about rows it can read.
alter publication supabase_realtime add table public.profiles, public.destinations, public.review_reports;
