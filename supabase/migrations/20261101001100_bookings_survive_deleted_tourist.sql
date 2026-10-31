-- Bookings survive their tourist: when an account is deleted, tourist_id
-- becomes NULL instead of the booking (and its payment ledger) being cascaded
-- away. Same constraint name, because the apps embed
-- profiles!bookings_tourist_id_fkey. Run in the SQL editor (the MCP declines
-- constraint drops); prepare_account_deletion() refuses to run until this is in.
alter table public.bookings alter column tourist_id drop not null;
alter table public.bookings
  drop constraint bookings_tourist_id_fkey,
  add constraint bookings_tourist_id_fkey
    foreign key (tourist_id) references public.profiles (id) on delete set null;
