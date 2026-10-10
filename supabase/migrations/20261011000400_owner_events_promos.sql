-- Item 8: owners post events and promos for their own destinations; the
-- tourist app lists them and the Event Monitoring Agent reads them.
alter table public.events
  add column if not exists kind text not null default 'event',
  add column if not exists created_at timestamptz not null default now();

alter table public.events drop constraint if exists events_kind_check;
alter table public.events add constraint events_kind_check check (kind in ('event', 'promo'));

alter table public.events drop constraint if exists events_dates_order;
alter table public.events add constraint events_dates_order
  check (end_date is null or start_date is null or end_date >= start_date);

create index if not exists events_destination_id_idx on public.events (destination_id);

-- Approved owners manage events only for destinations they own.
drop policy if exists "Owners manage events of own destinations" on public.events;
create policy "Owners manage events of own destinations" on public.events
  for all to authenticated
  using (
    public.is_approved_owner()
    and exists (
      select 1 from public.destinations d
      where d.id = events.destination_id and d.owner_id = (select auth.uid())
    )
  )
  with check (
    public.is_approved_owner()
    and exists (
      select 1 from public.destinations d
      where d.id = events.destination_id and d.owner_id = (select auth.uid())
    )
  );
