-- Signup email guard + cleanup of never-verified accounts.
--
-- 1. public.hook_before_user_created(event) is a "Before User Created" auth hook
--    (enable it in Dashboard > Authentication > Hooks). It rejects email/password
--    signups whose domain is a known disposable-email provider, or whose domain
--    cannot receive mail (no MX and no A record, checked over DNS-over-HTTPS).
--    OAuth signups (Google/Facebook) skip the checks: the provider already
--    verified the address. Any lookup failure fails open so a DNS hiccup never
--    blocks a real user.
-- 2. public.purge_unverified_users() deletes accounts that never confirmed their
--    email within 24 hours; pg_cron runs it every hour.

create extension if not exists http with schema extensions;
create extension if not exists pg_cron;

-- Disposable domains (seeded by the next migration).
create table if not exists public.blocked_email_domains (
  domain text primary key,
  created_at timestamptz not null default now()
);
alter table public.blocked_email_domains enable row level security;
revoke all on public.blocked_email_domains from anon, authenticated;

-- True when DNS says the domain can receive mail. NULL when the lookup failed.
create or replace function public.email_domain_accepts_mail(p_domain text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  rtype text;
  resp extensions.http_response;
  body jsonb;
begin
  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT_MS', '1500');
  foreach rtype in array array['MX', 'A'] loop
    resp := extensions.http_get(
      'https://dns.google/resolve?name=' || extensions.urlencode(p_domain) || '&type=' || rtype
    );
    if resp.status <> 200 then
      return null;
    end if;
    body := resp.content::jsonb;
    -- Status 3 = NXDOMAIN: the domain does not exist at all.
    if (body->>'Status')::int = 3 then
      return false;
    end if;
    if (body->>'Status')::int <> 0 then
      return null;
    end if;
    if jsonb_array_length(coalesce(body->'Answer', '[]'::jsonb)) > 0 then
      return true;
    end if;
  end loop;
  return false;
exception when others then
  return null;
end;
$$;

create or replace function public.hook_before_user_created(event jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email text := lower(trim(coalesce(event->'user'->>'email', '')));
  v_provider text := coalesce(event->'user'->'app_metadata'->>'provider', 'email');
  v_domain text;
begin
  if v_provider <> 'email' or v_email = '' then
    return '{}'::jsonb;
  end if;

  v_domain := split_part(v_email, '@', 2);

  if exists (
    select 1 from public.blocked_email_domains b
    where b.domain = v_domain or v_domain like '%.' || b.domain
  ) then
    return jsonb_build_object('error', jsonb_build_object(
      'http_code', 400,
      'message', 'Disposable email addresses are not allowed. Please use your personal email.'
    ));
  end if;

  -- Big providers always accept mail; skip the network lookup for them.
  if v_domain in (
    'gmail.com', 'googlemail.com', 'yahoo.com', 'ymail.com', 'outlook.com', 'hotmail.com',
    'live.com', 'msn.com', 'icloud.com', 'me.com', 'proton.me', 'protonmail.com', 'aol.com',
    'gmx.com', 'zoho.com', 'yandex.com', 'mail.com'
  ) then
    return '{}'::jsonb;
  end if;

  if public.email_domain_accepts_mail(v_domain) is false then
    return jsonb_build_object('error', jsonb_build_object(
      'http_code', 400,
      'message', 'This email domain cannot receive mail. Please check the spelling of your email.'
    ));
  end if;

  return '{}'::jsonb;
end;
$$;

grant usage on schema public to supabase_auth_admin;
grant execute on function public.hook_before_user_created(jsonb) to supabase_auth_admin;
revoke execute on function public.hook_before_user_created(jsonb) from public, anon, authenticated;
revoke execute on function public.email_domain_accepts_mail(text) from public, anon, authenticated;
grant select on public.blocked_email_domains to supabase_auth_admin;

-- Never-verified cleanup. Admin accounts and anyone owning a destination are kept.
create or replace function public.purge_unverified_users()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  n integer;
begin
  delete from auth.users u
  where u.email_confirmed_at is null
    and u.phone_confirmed_at is null
    and u.created_at < now() - interval '24 hours'
    and not exists (select 1 from public.profiles p where p.id = u.id and p.role = 'admin')
    and not exists (select 1 from public.destinations d where d.owner_id = u.id);
  get diagnostics n = row_count;
  return n;
end;
$$;
revoke execute on function public.purge_unverified_users() from public, anon, authenticated;

select cron.unschedule(jobid) from cron.job where jobname = 'purge-unverified-users';
select cron.schedule('purge-unverified-users', '0 * * * *', 'select public.purge_unverified_users()');
