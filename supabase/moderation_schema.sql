-- Private moderator access for the Weywell community report queue.
-- Run once in Supabase SQL Editor. Add moderator users separately as described
-- in MODERATION_SETUP.md; never grant moderation from the public client.

create table if not exists public.moderators (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.moderators enable row level security;
revoke all on public.moderators from anon, authenticated;
grant select on public.moderators to authenticated;

drop policy if exists "moderators can see own grant" on public.moderators;
create policy "moderators can see own grant" on public.moderators
for select to authenticated
using (user_id = auth.uid());

alter table public.safety_notices
  add column if not exists reviewed_by uuid references auth.users(id);

drop policy if exists "moderators can review pending notices" on public.safety_notices;
create policy "moderators can review pending notices" on public.safety_notices
for select to authenticated
using (exists (select 1 from public.moderators m where m.user_id = auth.uid()));

drop policy if exists "moderators can update pending notices" on public.safety_notices;
create policy "moderators can update pending notices" on public.safety_notices
for update to authenticated
using (
  status = 'pending'
  and expires_at > now()
  and exists (select 1 from public.moderators m where m.user_id = auth.uid())
)
with check (
  status in ('approved', 'rejected')
  and reviewed_at is not null
  and reviewed_by = auth.uid()
  and exists (select 1 from public.moderators m where m.user_id = auth.uid())
);

grant update (status) on public.safety_notices to authenticated;

create or replace function public.set_notice_review_metadata()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  if old.status = 'pending' and new.status in ('approved', 'rejected') then
    new.reviewed_at := now();
    new.reviewed_by := auth.uid();
  end if;
  return new;
end;
$$;

drop trigger if exists set_notice_review_metadata_before_update on public.safety_notices;
create trigger set_notice_review_metadata_before_update
before update of status on public.safety_notices
for each row execute function public.set_notice_review_metadata();

drop policy if exists "moderators can read pending report photos" on storage.objects;
create policy "moderators can read pending report photos" on storage.objects
for select to authenticated
using (
  bucket_id = 'community-report-photos'
  and exists (
    select 1 from public.safety_notices n
    where n.photo_path = storage.objects.name and n.status = 'pending'
  )
  and exists (select 1 from public.moderators m where m.user_id = auth.uid())
);

notify pgrst, 'reload schema';
