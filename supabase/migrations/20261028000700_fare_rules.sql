-- Official fares per vehicle type (panel requirement: "destination route and
-- price of the different vehicle").
--
-- Ipil Municipal Ordinance No. 03-748-2026 sets the tricycle fare at ₱20.00
-- for the first kilometer and ₱5.00 for each succeeding kilometer, per
-- passenger, no discounts. Kept as data so the admin can update it when the
-- LGU changes the ordinance, without an app release. Only tricycles have an
-- official rate; the app shows other vehicles without a made-up price.
--
-- fare = base_fare + per_km × max(0, ceil(km) − base_km)
--
-- fare_reference_points holds every row of the LGU's published Tricycle Fare
-- Guide (origin: Ipil Rotunda) so fare_accuracy can show how the formula
-- compares with the official table — the accuracy figure for the thesis.

create table if not exists public.fare_rules (
  id uuid primary key default gen_random_uuid(),
  vehicle_type text not null unique,
  label text not null,
  base_fare numeric(8, 2) not null check (base_fare >= 0),
  base_km numeric(6, 2) not null default 1 check (base_km >= 0),
  per_km numeric(8, 2) not null default 0 check (per_km >= 0),
  charged_per text not null default 'passenger' check (charged_per in ('passenger', 'trip')),
  source text,
  effective_date date,
  is_active boolean not null default true,
  updated_at timestamptz not null default now()
);

alter table public.fare_rules enable row level security;

create policy "Anyone can view active fare rules"
  on public.fare_rules for select to anon, authenticated
  using (is_active);

create policy "Admins manage fare rules"
  on public.fare_rules for all to authenticated
  using (public.has_role('admin'::public.user_role))
  with check (public.has_role('admin'::public.user_role));

insert into public.fare_rules (vehicle_type, label, base_fare, base_km, per_km, charged_per, source, effective_date)
values ('tricycle', 'Tricycle', 20, 1, 5, 'passenger', 'Ipil Municipal Ordinance No. 03-748-2026', '2026-01-01')
on conflict (vehicle_type) do nothing;

create or replace function public.fare_for_km(p_vehicle_type text, p_km numeric)
returns numeric
language sql
stable
set search_path to ''
as $$
  select r.base_fare + r.per_km * greatest(0, ceil(p_km) - r.base_km)
  from public.fare_rules r
  where r.vehicle_type = p_vehicle_type and r.is_active;
$$;

create table if not exists public.fare_reference_points (
  id uuid primary key default gen_random_uuid(),
  vehicle_type text not null default 'tricycle',
  route_group text not null,
  origin text not null default 'Ipil Rotunda',
  destination text not null,
  distance_km numeric(6, 2) not null,
  official_fare numeric(8, 2) not null,
  source text not null default 'Ipil Tricycle Fare Guide (Ord. 03-748-2026)'
);

alter table public.fare_reference_points enable row level security;

create policy "Anyone can view fare reference points"
  on public.fare_reference_points for select to anon, authenticated
  using (true);

create policy "Admins manage fare reference points"
  on public.fare_reference_points for all to authenticated
  using (public.has_role('admin'::public.user_role))
  with check (public.has_role('admin'::public.user_role));

insert into public.fare_reference_points (route_group, destination, distance_km, official_fare) values
  ('Poblacion', 'Poblacion Brgy. Hall', 0.50, 20),
  ('Poblacion', 'Health Center', 0.45, 20),
  ('Poblacion', 'Public Market', 0.85, 20),
  ('Poblacion', 'McDonald''s', 0.70, 20),
  ('Poblacion', 'Marcelo Spinola School', 1.10, 25),
  ('Poblacion', 'Don Andres Elem. School', 1.60, 25),
  ('Taway', 'Lower Taway Brgy. Hall', 0.70, 20),
  ('Taway', 'DPWH', 0.85, 20),
  ('Taway', 'Roderic''s Resort', 1.40, 25),
  ('Taway', 'EMCOR Taway', 2.00, 25),
  ('Taway', 'Ipil Municipal Bldg.', 3.20, 35),
  ('Taway', 'NFA', 2.60, 30),
  ('Taway', 'Autumn Woods', 3.10, 35),
  ('Taway', 'Taway Boundary', 5.00, 40),
  ('Guituan - Timalang', 'Tirso Babiera', 0.60, 20),
  ('Guituan - Timalang', 'Ipil Heights Brgy. Hall', 1.10, 25),
  ('Guituan - Timalang', 'Capitol', 2.30, 30),
  ('Guituan - Timalang', 'DAR', 1.70, 25),
  ('Guituan - Timalang', 'Suclema Brgy. Hall', 5.00, 40),
  ('Guituan - Timalang', 'Guituan Brgy. Hall', 5.70, 45),
  ('Guituan - Timalang', 'Lumbia Brgy. Hall', 5.70, 45),
  ('Guituan - Timalang', 'Timalang Brgy. Hall', 9.80, 65),
  ('Tenan', 'LTO', 0.50, 20),
  ('Tenan', 'RTMI (Terminal)', 0.75, 20),
  ('Tenan', 'Sanito Elem. School', 1.30, 25),
  ('Tenan', 'Budgetwise', 1.40, 25),
  ('Tenan', 'Robinsons', 1.70, 25),
  ('Tenan', 'BIR', 2.00, 25),
  ('Tenan', 'Airport Building', 2.20, 30),
  ('Tenan', 'PPO', 2.30, 30),
  ('Tenan', 'BJMP', 2.60, 30),
  ('Tenan', 'WESMIARC', 3.40, 35),
  ('Tenan', 'ZAMSURECO', 3.50, 35),
  ('Tenan', 'DepEd Division Office', 3.70, 35),
  ('Tenan', 'Upper Pangi int. Diversion Rd.', 4.30, 40),
  ('Tenan', 'Provincial Hospital (GTHMC)', 7.20, 55),
  ('Tenan', 'Tenan Brgy. Hall', 7.70, 55),
  ('Tenan', 'Bacalan Brgy. Hall', 10.40, 70),
  ('Tenan', 'Logan Elem School', 12.00, 75),
  ('Tenan', 'Domandan Brgy. Hall', 12.40, 80),
  ('Buluan', 'Yamaha', 1.00, 20),
  ('Buluan', 'Veterans Village Brgy. Hall', 2.20, 30),
  ('Buluan', 'Medina / TopMars 2', 2.30, 30),
  ('Buluan', 'Tiayon Brgy. Hall', 4.90, 40),
  ('Buluan', 'Caparan Brgy. Hall', 7.80, 55),
  ('Buluan', 'Labi Brgy. Hall', 10.10, 70),
  ('Buluan', 'Makilas Brgy. Hall', 8.80, 60),
  ('Buluan', 'Maasin Brgy. Hall', 10.50, 70),
  ('Buluan', 'Doña Josefa', 10.30, 70),
  ('Buluan', 'Tomitom Elem. School', 11.50, 75),
  ('Buluan', 'Buluan Brgy. Hall', 10.80, 70),
  ('Palid', 'AMMC', 0.55, 20),
  ('Palid', 'Bangkerohan Brgy. Hall', 1.10, 25),
  ('Palid', 'NESORICOM', 2.60, 30),
  ('Palid', 'Palid Beach', 4.00, 35),
  ('Palid', 'Magdaup Brgy. Hall', 4.20, 40);

create or replace view public.fare_accuracy
with (security_invoker = true) as
select p.route_group,
       p.destination,
       p.distance_km,
       p.official_fare,
       public.fare_for_km(p.vehicle_type, p.distance_km) as computed_fare,
       public.fare_for_km(p.vehicle_type, p.distance_km) = p.official_fare as matches
from public.fare_reference_points p;
