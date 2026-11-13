-- Problem reports on bookings. A tourist who arrives and finds the owner
-- absent, the place closed, or the service not as booked can report it from
-- the booking screen. The admin sees the queue and either refunds the booking
-- in full with one tap or dismisses the report with a note.

create table if not exists public.booking_problems (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.bookings(id) on delete cascade,
  reporter_id uuid references public.profiles(id) on delete set null,
  kind text not null check (kind in ('owner_no_show', 'closed', 'not_as_booked', 'other')),
  details text check (details is null or char_length(details) <= 500),
  status text not null default 'open' check (status in ('open', 'refunded', 'dismissed')),
  admin_note text,
  resolved_by uuid references public.profiles(id) on delete set null,
  resolved_at timestamptz,
  created_at timestamptz not null default now()
);

-- One report per booking keeps the queue honest.
create unique index if not exists booking_problems_one_per_booking
  on public.booking_problems (booking_id);
create index if not exists booking_problems_status on public.booking_problems (status);

alter table public.booking_problems enable row level security;

create policy "Admins manage booking problems" on public.booking_problems
  for all using (public.has_role('admin'::public.user_role))
  with check (public.has_role('admin'::public.user_role));

create policy "Tourists read own booking problems" on public.booking_problems
  for select using (reporter_id = (select auth.uid()));

-- Rows are written only through the two functions below.
revoke insert, update, delete on public.booking_problems from anon, authenticated;

alter publication supabase_realtime add table public.booking_problems;

-- ---------------------------------------------------------------------------
-- Tourist: report a problem, from the trip day up to 7 days after it.
-- ---------------------------------------------------------------------------
create or replace function public.report_booking_problem(
  p_booking_id uuid,
  p_kind text,
  p_details text
)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_today date := (now() at time zone 'Asia/Manila')::date;
  v_details text := nullif(trim(coalesce(p_details, '')), '');
  b public.bookings;
  v_dest text;
  v_id uuid;
begin
  if v_uid is null then
    raise exception 'Please sign in first.';
  end if;
  select * into b from public.bookings where id = p_booking_id and tourist_id = v_uid;
  if not found then
    raise exception 'Booking not found.';
  end if;
  if b.status not in ('confirmed', 'completed') then
    raise exception 'Only a confirmed booking can be reported.';
  end if;
  if b.booking_date > v_today then
    raise exception 'You can report a problem on your trip day or after it.';
  end if;
  if b.booking_date < v_today - 7 then
    raise exception 'A problem can be reported up to 7 days after the trip day.';
  end if;
  if p_kind not in ('owner_no_show', 'closed', 'not_as_booked', 'other') then
    raise exception 'Choose what went wrong.';
  end if;
  if p_kind = 'other' and coalesce(char_length(v_details), 0) < 10 then
    raise exception 'Please describe what happened in a few words.';
  end if;
  if char_length(coalesce(v_details, '')) > 500 then
    raise exception 'Keep the details under 500 characters.';
  end if;
  if exists (select 1 from public.booking_problems where booking_id = p_booking_id) then
    raise exception 'You already reported this booking. IpilGo is reviewing it.';
  end if;

  insert into public.booking_problems (booking_id, reporter_id, kind, details)
  values (p_booking_id, v_uid, p_kind, v_details)
  returning id into v_id;

  select name into v_dest from public.destinations where id = b.destination_id;
  perform public.notify(b.owner_id, 'Problem reported on a booking',
    coalesce(b.contact_name, 'A tourist') || ' reported a problem with the ' ||
    to_char(b.booking_date, 'FMMonth FMDD, YYYY') || ' booking at ' || coalesce(v_dest, 'your spot') ||
    '. IpilGo will review it and may refund the tourist.',
    'booking_status');
  return v_id;
end;
$function$;

-- ---------------------------------------------------------------------------
-- Admin: refund in full (what was paid online) or dismiss with a note.
-- ---------------------------------------------------------------------------
create or replace function public.admin_resolve_booking_problem(
  p_problem_id uuid,
  p_refund boolean,
  p_note text
)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_note text := nullif(trim(coalesce(p_note, '')), '');
  p public.booking_problems;
  b public.bookings;
  v_online numeric;
  v_dest text;
  v_label text;
begin
  if v_uid is null or not public.has_role('admin'::public.user_role) then
    raise exception 'Only an admin can do this.';
  end if;
  select * into p from public.booking_problems where id = p_problem_id for update;
  if not found then
    raise exception 'Report not found.';
  end if;
  if p.status <> 'open' then
    raise exception 'This report was already handled.';
  end if;
  select * into b from public.bookings where id = p.booking_id for update;
  select name into v_dest from public.destinations where id = b.destination_id;

  if p_refund then
    if b.status in ('cancelled', 'rejected') or b.refunded_at is not null then
      raise exception 'This booking is already closed or refunded.';
    end if;
    -- Only money that came through PayMongo can be sent back by IpilGo.
    select coalesce(sum(case when kind = 'refund' then -amount else amount end), 0) into v_online
    from public.booking_payments
    where booking_id = b.id and recorded_by = 'paymongo';
    if v_online <= 0 then
      raise exception 'Nothing was paid online for this booking, so there is nothing to refund.';
    end if;
    v_label := case p.kind
      when 'owner_no_show' then 'the owner did not show up'
      when 'closed' then 'the place was closed'
      when 'not_as_booked' then 'the service was not as booked'
      else 'a problem was reported' end;

    -- Closing the booking as the admin makes booking_refund_rules() refund it.
    perform set_config('ipilgo.server_write', 'on', true);
    update public.bookings
       set status = 'cancelled',
           cancel_reason = 'Refunded by IpilGo because ' || v_label
     where id = b.id;
    update public.bookings
       set refund_amount = v_online, refund_due = true
     where id = b.id and refund_amount is distinct from v_online;
    perform set_config('ipilgo.server_write', 'off', true);

    update public.booking_problems
       set status = 'refunded', admin_note = v_note, resolved_by = v_uid, resolved_at = now()
     where id = p.id;
  else
    if v_note is null then
      raise exception 'Write a short note so the tourist knows why.';
    end if;
    update public.booking_problems
       set status = 'dismissed', admin_note = v_note, resolved_by = v_uid, resolved_at = now()
     where id = p.id;
    perform public.notify(p.reporter_id, 'Your problem report was reviewed',
      'IpilGo reviewed your report about ' || coalesce(v_dest, 'your booking') || ' on ' ||
      to_char(b.booking_date, 'FMMonth FMDD, YYYY') || '. No refund was made. Note from IpilGo: ' ||
      regexp_replace(v_note, '([^.!?])$', '\1.'),
      'booking_status');
  end if;
end;
$function$;

revoke execute on function public.report_booking_problem(uuid, text, text) from public, anon;
revoke execute on function public.admin_resolve_booking_problem(uuid, boolean, text) from public, anon;
grant execute on function public.report_booking_problem(uuid, text, text) to authenticated;
grant execute on function public.admin_resolve_booking_problem(uuid, boolean, text) to authenticated;
