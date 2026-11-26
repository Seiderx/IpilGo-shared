-- Town event notices (Event Monitoring agent, server side). Runs daily at
-- 8 AM Manila time:
--   * 3 days before (or as soon as an event is posted inside that window):
--     tell every tourist, and add the event to each saved trip that is on
--     its dates, with why, so the tourist can keep it or remove it.
--   * On the start day: tell every tourist again.
-- Each notice goes out once per event (event_notices). Inserting into
-- notifications also sends the phone push (notifications_forward_to_push).

create table if not exists public.event_notices (
  event_id uuid not null references public.events(id) on delete cascade,
  kind text not null check (kind in ('soon', 'today')),
  sent_at timestamptz not null default now(),
  primary key (event_id, kind)
);
alter table public.event_notices enable row level security;
-- No policies: only the job below writes it.

create or replace function public.send_town_event_notices()
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_today date := (now() at time zone 'Asia/Manila')::date;
  ev record;
  v_when text;
begin
  for ev in
    select e.* from public.events e
    where e.destination_id is null and e.kind = 'event'
      and e.start_date between v_today and v_today + 3
      and not exists (select 1 from public.event_notices n where n.event_id = e.id and n.kind = 'soon')
  loop
    insert into public.event_notices (event_id, kind) values (ev.id, 'soon');
    -- Starts today: the 'today' notice below tells everyone instead.
    if ev.start_date > v_today then
      v_when := case ev.start_date - v_today when 1 then 'tomorrow' else 'in ' || (ev.start_date - v_today) || ' days' end;
      insert into public.notifications (user_id, title, body, type, read)
      select p.id, ev.name || ' ' || v_when,
             'Town event in Ipil on ' || to_char(ev.start_date, 'FMDay, Mon FMDD') ||
             coalesce(' at ' || ev.place_name, '') || '. Open IpilGo to see what''s on.',
             'general', false
      from public.profiles p where p.role = 'tourist';
    end if;

    -- Saved trips on the event's dates get it on the matching day.
    with hit as (
      select i.id, i.user_id,
             (greatest(ev.start_date, i.start_date) - i.start_date) + 1 as day_number
      from public.itineraries i
      where not i.is_draft and i.start_date is not null
        and i.start_date <= coalesce(ev.end_date, ev.start_date)
        and coalesce(i.end_date, i.start_date) >= ev.start_date
        and not exists (select 1 from public.itinerary_items x where x.itinerary_id = i.id and x.event_id = ev.id)
    ), added as (
      insert into public.itinerary_items
        (itinerary_id, kind, event_id, title, day_number, scheduled_time, order_index, is_suggested, notes)
      select hit.id, 'event', ev.id, ev.name, hit.day_number, coalesce(ev.start_time, '09:00'), 99, true,
             'A town event happens on this day of your trip' || coalesce(' at ' || ev.place_name, '') ||
             '. Keep it, or tap X to remove it.'
      from hit
      returning itinerary_id
    )
    insert into public.notifications (user_id, title, body, type, read)
    select distinct hit.user_id, 'Added to your trip: ' || ev.name,
           'It falls on your trip dates, so the Event agent added it. Open your trip to keep it or remove it.',
           'recommendation', false
    from hit join added on added.itinerary_id = hit.id;
  end loop;

  for ev in
    select e.* from public.events e
    where e.destination_id is null and e.kind = 'event'
      and e.start_date = v_today
      and not exists (select 1 from public.event_notices n where n.event_id = e.id and n.kind = 'today')
  loop
    insert into public.event_notices (event_id, kind) values (ev.id, 'today');
    insert into public.notifications (user_id, title, body, type, read)
    select p.id, 'Today in Ipil: ' || ev.name,
           coalesce('Starts ' || to_char(date '2000-01-01' + ev.start_time, 'FMHH12:MI AM'), 'Happening today') ||
           coalesce(' at ' || ev.place_name, '') || '. Open IpilGo to see what''s on.',
           'general', false
    from public.profiles p where p.role = 'tourist';
  end loop;
end;
$$;

revoke all on function public.send_town_event_notices() from public, anon, authenticated;

-- 00:00 UTC = 8:00 AM Manila.
select cron.schedule('town-event-notices', '0 0 * * *', $$select public.send_town_event_notices()$$);
