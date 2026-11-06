-- Phone notifications while the app is closed. Every row in public.notifications
-- is forwarded to the owner's devices by the send-push edge function.

create table public.device_push_tokens (
  token text primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  app text not null check (app in ('tourist', 'owner')),
  updated_at timestamptz not null default now()
);
create index device_push_tokens_user_id_idx on public.device_push_tokens (user_id);

-- No policies: apps go through the functions below, send-push uses the service role.
alter table public.device_push_tokens enable row level security;

-- A phone keeps its token across logins, so the newest user takes it over.
create or replace function public.register_push_token(p_token text, p_app text)
returns void
language plpgsql
security definer
set search_path to ''
as $$
begin
  if (select auth.uid()) is null then
    raise exception 'Sign in required';
  end if;
  insert into public.device_push_tokens (token, user_id, app)
  values (p_token, (select auth.uid()), p_app)
  on conflict (token) do update
    set user_id = excluded.user_id, app = excluded.app, updated_at = now();
end;
$$;

create or replace function public.unregister_push_token(p_token text)
returns void
language sql
security definer
set search_path to ''
as $$
  delete from public.device_push_tokens
  where token = p_token and user_id = (select auth.uid());
$$;

revoke all on function public.register_push_token(text, text) from public, anon;
revoke all on function public.unregister_push_token(text) from public, anon;
grant execute on function public.register_push_token(text, text) to authenticated;
grant execute on function public.unregister_push_token(text) to authenticated;

-- Shared secret between this trigger and send-push; never leaves the database
-- except to the service role.
select vault.create_secret(encode(extensions.gen_random_bytes(32), 'hex'), 'push_webhook_secret');

create or replace function public.push_webhook_secret()
returns text
language sql
security definer
set search_path to ''
as $$
  select decrypted_secret from vault.decrypted_secrets where name = 'push_webhook_secret';
$$;

revoke all on function public.push_webhook_secret() from public, anon, authenticated;
grant execute on function public.push_webhook_secret() to service_role;

-- A push failure must never stop the notification itself from being saved.
create or replace function public.forward_notification_to_push()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  perform net.http_post(
    url := 'https://dbkqemjfxtksjxrwrclf.supabase.co/functions/v1/send-push',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-secret', public.push_webhook_secret()
    ),
    body := jsonb_build_object(
      'user_id', new.user_id,
      'title', new.title,
      'body', new.body,
      'type', new.type
    )
  );
  return null;
exception when others then
  return null;
end;
$$;

create trigger notifications_forward_to_push
  after insert on public.notifications
  for each row execute function public.forward_notification_to_push();
