-- Owners keep a real, checkable full name (admin approves them). The owner
-- app already checks this while typing; this enforces the same rules on the
-- server for email signups as owner and for Edit profile.
-- Only applies when an owner's full_name is set or changed, so old accounts
-- keep working until they edit their name.

create or replace function public.is_valid_full_name(p_name text)
returns boolean
language plpgsql
immutable
set search_path to ''
as $$
declare
  v text := regexp_replace(trim(coalesce(p_name, '')), '\s+', ' ', 'g');
  w text;
  real_words int := 0;
begin
  if v = '' or length(v) > 60 then return false; end if;
  if v !~ '^[A-Za-zÀ-ÖØ-öø-ÿÑñ][A-Za-zÀ-ÖØ-öø-ÿÑñ.'' -]*$' then return false; end if;
  -- keyboard mashing: same letter 3x ("aaa") or a pair 3x ("bgbgbg")
  if v ~* '([a-zà-öø-ÿñ])\1\1' or v ~* '([a-zà-öø-ÿñ]{2})\1\1' then return false; end if;
  foreach w in array regexp_split_to_array(v, ' ') loop
    if length(w) > 20 then return false; end if;
    if length(regexp_replace(w, '[^A-Za-zÀ-ÖØ-öø-ÿÑñ]', '', 'g')) >= 2 then
      real_words := real_words + 1;
    end if;
  end loop;
  return real_words >= 2;
end;
$$;

create or replace function public.check_owner_full_name()
returns trigger
language plpgsql
set search_path to ''
as $$
begin
  if new.role = 'owner'
     and (tg_op = 'INSERT' or new.full_name is distinct from old.full_name)
     and not public.is_valid_full_name(new.full_name) then
    raise exception 'Please enter your real first and last name'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create or replace trigger profiles_check_owner_full_name
  before insert or update of full_name on public.profiles
  for each row execute function public.check_owner_full_name();
