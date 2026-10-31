-- destination-images bucket: only images, at most 10 MB each (it had no limit,
-- so any file type of any size could be published from a public URL).
-- Admins may write only to the admin/ folder: owners' photos are theirs, as
-- with listing content (see 20261101000100_admin_guardrails.sql).

update storage.buckets
   set file_size_limit = 10485760,
       allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp']
 where id = 'destination-images';

alter policy "Admins manage destination images" on storage.objects
  using (bucket_id = 'destination-images' and public.has_role('admin'::public.user_role)
         and (storage.foldername(name))[1] = 'admin')
  with check (bucket_id = 'destination-images' and public.has_role('admin'::public.user_role)
              and (storage.foldername(name))[1] = 'admin');
