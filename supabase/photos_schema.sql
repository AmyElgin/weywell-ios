-- Private user-submitted photos. Files become readable only after the
-- attached notice is approved and remains active.
alter table public.safety_notices add column if not exists photo_path text;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('community-report-photos', 'community-report-photos', false, 5242880, array['image/jpeg'])
on conflict (id) do update set public = false, file_size_limit = 5242880, allowed_mime_types = array['image/jpeg'];

drop policy if exists "upload own community report photos" on storage.objects;
drop policy if exists "read approved community report photos" on storage.objects;
drop policy if exists "delete unsubmitted community report photos" on storage.objects;

create policy "upload own community report photos" on storage.objects
for insert to authenticated
with check (
  bucket_id = 'community-report-photos'
  and (storage.foldername(name))[1] = auth.uid()::text
  and lower(storage.filename(name)) like '%.jpg'
);

create policy "read approved community report photos" on storage.objects
for select to anon, authenticated
using (
  bucket_id = 'community-report-photos'
  and exists (
    select 1 from public.safety_notices n
    where n.photo_path = storage.objects.name
      and n.status = 'approved'
      and n.expires_at > now()
  )
);

create policy "delete unsubmitted community report photos" on storage.objects
for delete to authenticated
using (
  bucket_id = 'community-report-photos'
  and (storage.foldername(name))[1] = auth.uid()::text
  and not exists (
    select 1 from public.safety_notices n
    where n.photo_path = storage.objects.name and n.status = 'approved'
  )
);
