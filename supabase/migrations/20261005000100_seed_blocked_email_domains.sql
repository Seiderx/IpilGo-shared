-- Seed public.blocked_email_domains from the community-maintained list at
-- https://github.com/disposable-email-domains/disposable-email-domains
-- (~9,200 domains as of 2026-10-05). Re-run this to refresh the list.
insert into public.blocked_email_domains (domain)
select distinct lower(trim(line))
from regexp_split_to_table(
  (extensions.http_get(
    'https://raw.githubusercontent.com/disposable-email-domains/disposable-email-domains/main/disposable_email_blocklist.conf'
  )).content,
  E'\n'
) as line
where trim(line) <> '' and line not like '#%'
on conflict (domain) do nothing;
