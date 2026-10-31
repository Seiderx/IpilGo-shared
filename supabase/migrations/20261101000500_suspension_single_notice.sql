-- Suspending an owner hides their listings (notify_owner_status) and sends
-- one "Owner account suspended" notice. Skip the per-listing "Changes needed"
-- notice in that case so the owner isn't told twice.

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
    elsif new.status = 'rejected'
          and new.review_note is distinct from 'The owner account was suspended by the IpilGo admin.' then
      perform public.notify(new.owner_id, 'Changes needed',
        new.name || ' was not approved. ' ||
        coalesce('Reason: ' || nullif(trim(new.review_note), '') || ' ', '') ||
        'Update your details and save again to send it back for review.', 'destination_status');
    end if;
  end if;
  return new;
end;
$$;
