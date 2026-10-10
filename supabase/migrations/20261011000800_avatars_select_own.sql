-- Fix: replacing an avatar (upload with upsert) failed with "new row violates
-- row-level security policy" — Storage upsert also needs SELECT on the
-- existing object. Users may read objects in their own avatars folder.
-- (Public URLs keep working for everyone because the bucket is public.)
drop policy if exists "avatars: users read own" on storage.objects;
create policy "avatars: users read own" on storage.objects
  for select to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);
