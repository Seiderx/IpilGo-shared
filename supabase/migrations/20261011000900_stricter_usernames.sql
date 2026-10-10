-- Round 2 / step 3: "aaaa", "____" and "12345678" were accepted as usernames.
-- A username now must:
--   * be 3-20 chars of letters, digits, '.' or '_' and start with a letter
--   * contain at least 3 letters
--   * not have two separators in a row ("__", "._") or end with one
--   * not repeat the same character 4+ times in a row ("aaaa")
create or replace function public.is_valid_username(p text)
returns boolean
language sql
immutable
set search_path to ''
as $$
  select p ~ '^[A-Za-z][A-Za-z0-9._]{2,19}$'
     and length(regexp_replace(p, '[^A-Za-z]', '', 'g')) >= 3
     and p !~ '[._]{2}'
     and p !~ '[._]$'
     and p !~ '(.)\1\1\1';
$$;

alter table public.profiles drop constraint if exists profiles_username_format;
alter table public.profiles add constraint profiles_username_format
  check (username is null or public.is_valid_username(username));

create or replace function public.is_username_available(p_username text)
returns boolean
language sql
stable
security definer
set search_path to ''
as $$
  select public.is_valid_username(p_username)
     and not exists (
       select 1 from public.profiles where lower(username) = lower(p_username)
     );
$$;
