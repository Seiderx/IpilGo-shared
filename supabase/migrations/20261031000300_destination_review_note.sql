-- The admin says why a spot was not approved, so the owner knows what to fix.
-- Shown in the owner's notification and on My Spot while the spot is rejected.

alter table public.destinations add column if not exists review_note text;

create or replace function public.notify_destination_status()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  if new.status is distinct from old.status and new.owner_id is not null then
    if new.status = 'approved' then
      perform public.notify(new.owner_id, 'Your spot is live!',
        new.name || ' was approved and tourists can now see it in IpilGo.', 'destination_status');
    elsif new.status = 'rejected' then
      perform public.notify(new.owner_id, 'Changes needed',
        new.name || ' was not approved. ' ||
        coalesce('Reason: ' || nullif(trim(new.review_note), '') || ' ', '') ||
        'Update your details and save again to send it back for review.', 'destination_status');
    end if;
  end if;
  return new;
end;
$$;
