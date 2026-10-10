-- Item 9: owners read reviews of their destination and reply publicly.
alter table public.destination_reviews
  add column if not exists owner_reply text,
  add column if not exists owner_replied_at timestamptz;

-- Replies go only through reply_to_review(). Tourists may update their own
-- review row (existing policy), so without this guard a tourist could forge
-- an "owner reply" on their own review.
create or replace function public.guard_review_owner_reply()
returns trigger
language plpgsql
set search_path to ''
as $$
begin
  if (new.owner_reply is distinct from old.owner_reply
      or new.owner_replied_at is distinct from old.owner_replied_at)
     and coalesce(current_setting('ipilgo.review_reply', true), '') <> 'on'
     and not public.has_role('admin'::public.user_role) then
    raise exception 'Owner replies can only be set through reply_to_review()';
  end if;
  return new;
end;
$$;

drop trigger if exists guard_review_owner_reply on public.destination_reviews;
create trigger guard_review_owner_reply
  before update on public.destination_reviews
  for each row execute function public.guard_review_owner_reply();

-- Approved owner of the reviewed destination sets (or clears, with an empty
-- reply) the public reply.
create or replace function public.reply_to_review(p_review_id uuid, p_reply text)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_reply text := nullif(trim(p_reply), '');
begin
  if not public.is_approved_owner() then
    raise exception 'Only approved owners can reply to reviews';
  end if;
  if not exists (
    select 1
    from public.destination_reviews r
    join public.destinations d on d.id = r.destination_id
    where r.id = p_review_id and d.owner_id = (select auth.uid())
  ) then
    raise exception 'Review not found for your destination';
  end if;
  if length(v_reply) > 1000 then
    raise exception 'Reply is too long (max 1000 characters)';
  end if;

  perform set_config('ipilgo.review_reply', 'on', true);
  update public.destination_reviews
    set owner_reply = v_reply,
        owner_replied_at = case when v_reply is null then null else now() end
    where id = p_review_id;
  perform set_config('ipilgo.review_reply', '', true);
end;
$$;

revoke all on function public.reply_to_review(uuid, text) from public;
grant execute on function public.reply_to_review(uuid, text) to authenticated;

-- Applied as a follow-up migration (review_owner_reply_guard_insert): tourists
-- only INSERT reviews, so the guard must also cover inserts — otherwise a new
-- review could arrive with a forged owner reply already filled in.
create or replace function public.guard_review_owner_reply()
returns trigger
language plpgsql
set search_path to ''
as $$
begin
  if coalesce(current_setting('ipilgo.review_reply', true), '') = 'on'
     or public.has_role('admin'::public.user_role) then
    return new;
  end if;
  if tg_op = 'INSERT' then
    if new.owner_reply is not null or new.owner_replied_at is not null then
      raise exception 'Owner replies can only be set through reply_to_review()';
    end if;
  elsif new.owner_reply is distinct from old.owner_reply
        or new.owner_replied_at is distinct from old.owner_replied_at then
    raise exception 'Owner replies can only be set through reply_to_review()';
  end if;
  return new;
end;
$$;

drop trigger if exists guard_review_owner_reply on public.destination_reviews;
create trigger guard_review_owner_reply
  before insert or update on public.destination_reviews
  for each row execute function public.guard_review_owner_reply();
