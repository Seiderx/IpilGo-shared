-- Admin activity log: every change an admin makes to listings, people, bookings,
-- fares, services, reviews, events and safety alerts, written by triggers so the
-- admin panel cannot skip or edit it.
create table if not exists public.admin_audit_log (
  id bigint generated always as identity primary key,
  actor_id uuid references public.profiles(id) on delete set null,
  action text not null,
  target_type text not null,
  target_id text,
  target_label text,
  detail text,
  created_at timestamptz not null default now()
);
create index if not exists admin_audit_log_created_at_idx on public.admin_audit_log (created_at desc);

alter table public.admin_audit_log enable row level security;
create policy "Admins read the audit log" on public.admin_audit_log
  for select to authenticated using (public.has_role('admin'::public.user_role));

create or replace function public.log_admin_action()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  o jsonb := case when tg_op <> 'INSERT' then to_jsonb(old) end;
  n jsonb := case when tg_op <> 'DELETE' then to_jsonb(new) end;
  r jsonb := coalesce(n, o);
  act text;
  det text;
begin
  if (select auth.uid()) is null or not public.has_role('admin'::public.user_role) then
    return null;
  end if;

  if tg_op = 'INSERT' then
    act := 'created';
  elsif tg_op = 'DELETE' then
    act := 'deleted';
  else
    select string_agg(e.key, ', ' order by e.key) into det
    from jsonb_each(n) e
    where e.value is distinct from o -> e.key
      and e.key not in ('approved_snapshot', 'avg_rating', 'updated_at');
    if det is null then
      return null;
    end if;
    act := case
      when tg_table_name in ('destinations', 'bookings') and n->>'status' is distinct from o->>'status'
        then n->>'status'
      when tg_table_name = 'profiles' and n->>'owner_status' is distinct from o->>'owner_status'
        then 'owner ' || (n->>'owner_status')
      when tg_table_name = 'profiles' and n->>'admin_status' is distinct from o->>'admin_status'
        then 'admin ' || (n->>'admin_status')
      when tg_table_name = 'destination_services' and n->>'is_active' is distinct from o->>'is_active'
        then case when (n->>'is_active')::boolean then 'shown' else 'hidden' end
      when tg_table_name = 'safety_alerts' and n->>'active' is distinct from o->>'active'
        then case when (n->>'active')::boolean then 'activated' else 'ended' end
      else 'edited'
    end;
    -- Keep the changed-field list only for plain edits; a status change says it all.
    if act <> 'edited' then
      det := null;
    end if;
    if tg_table_name = 'destinations' and act = 'rejected' then
      det := n->>'review_note';
    end if;
  end if;

  insert into public.admin_audit_log (actor_id, action, target_type, target_id, target_label, detail)
  values ((select auth.uid()), act, tg_table_name, r->>'id',
          coalesce(r->>'name', r->>'full_name', r->>'label', r->>'message', left(r->>'comment', 80)),
          det);
  return null;
end;
$function$;

revoke all on function public.log_admin_action() from public, anon, authenticated;

create or replace trigger zz_audit_destinations after insert or update or delete on public.destinations
  for each row execute function public.log_admin_action();
create or replace trigger zz_audit_profiles after update or delete on public.profiles
  for each row execute function public.log_admin_action();
create or replace trigger zz_audit_bookings after update on public.bookings
  for each row execute function public.log_admin_action();
create or replace trigger zz_audit_fare_rules after insert or update or delete on public.fare_rules
  for each row execute function public.log_admin_action();
create or replace trigger zz_audit_destination_services after update or delete on public.destination_services
  for each row execute function public.log_admin_action();
create or replace trigger zz_audit_destination_reviews after update or delete on public.destination_reviews
  for each row execute function public.log_admin_action();
create or replace trigger zz_audit_safety_alerts after insert or update or delete on public.safety_alerts
  for each row execute function public.log_admin_action();
create or replace trigger zz_audit_events after insert or update or delete on public.events
  for each row execute function public.log_admin_action();
