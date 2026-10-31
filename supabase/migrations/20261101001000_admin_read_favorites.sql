-- Admins can count saved favorites on the Tourists page (read-only; tourists still only see their own).
create policy "Admins view favorites"
  on public.tourist_favorites for select
  to authenticated
  using (public.has_role('admin'::public.user_role));
