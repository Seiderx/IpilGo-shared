-- "Delete all" in the tourist's Trips > Bookings only hides finished and
-- cancelled bookings from the tourist's own list. The rows stay for the owner,
-- the admin and the payment record.
alter table public.bookings
  add column if not exists hidden_by_tourist boolean not null default false;

comment on column public.bookings.hidden_by_tourist is
  'The tourist cleared this finished or cancelled booking from their list. Owner and admin still see it.';
