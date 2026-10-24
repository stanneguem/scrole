-- REVIEW ONLY: private storage design for group attachments.
-- Do not apply until the full group schema/RPC draft is reviewed and tested locally.
-- The public direct-message bucket chat-media is deliberately untouched.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'group-chat-media',
  'group-chat-media',
  false,
  52428800,
  array['image/jpeg','image/png','image/webp','image/gif','video/mp4','audio/mpeg','audio/mp4','audio/ogg','application/pdf']
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

-- Object naming convention: <group_uuid>/<uploader_uuid>/<random_filename>.
-- Read permission is membership-based; removing/leaving a group immediately revokes
-- authenticated Storage reads through this policy. Use short-lived signed URLs only.
drop policy if exists "group_media_active_members_read" on storage.objects;
create policy "group_media_active_members_read"
on storage.objects for select to authenticated
using (
  bucket_id = 'group-chat-media'
  and public.group_is_active_member((storage.foldername(name))[1]::uuid, auth.uid())
);

drop policy if exists "group_media_members_upload_own_folder" on storage.objects;
create policy "group_media_members_upload_own_folder"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'group-chat-media'
  and (storage.foldername(name))[2] = auth.uid()::text
  and public.group_is_active_member((storage.foldername(name))[1]::uuid, auth.uid())
);

drop policy if exists "group_media_uploader_delete_own_files" on storage.objects;
create policy "group_media_uploader_delete_own_files"
on storage.objects for delete to authenticated
using (
  bucket_id = 'group-chat-media'
  and (storage.foldername(name))[2] = auth.uid()::text
  and public.group_is_active_member((storage.foldername(name))[1]::uuid, auth.uid())
);

-- Do not add UPDATE policy: uploaded objects are immutable; replace with a new object.
-- Ensure every client uploads to group-chat-media/<group_uuid>/<auth.uid()>/<uuid.ext>.
-- The UUID cast rejects malformed first folder names rather than granting access.
