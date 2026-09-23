-- Weywell shared safety notices
-- Run this in Supabase Dashboard > SQL Editor once the project finishes provisioning.

create extension if not exists pgcrypto;

create type public.safety_category as enum (
  'route_disruption',
  'unsafe_behaviour',
  'crime_reported',
  'neighbourhood'
);

create type public.notice_status as enum ('pending', 'approved', 'rejected', 'expired');

create table public.safety_notices (
  id uuid primary key default gen_random_uuid(),
  category public.safety_category not null,
  title text not null check (char_length(title) between 3 and 100),
  location_text text not null check (char_length(location_text) between 3 and 120),
  latitude double precision not null check (latitude between -35 and -22),
  longitude double precision not null check (longitude between 16 and 33),
  detail text not null check (char_length(detail) between 3 and 500),
  photo_path text,
  status public.notice_status not null default 'pending',
  reported_at timestamptz not null default now(),
  expires_at timestamptz not null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);

create index safety_notices_active_map_idx
  on public.safety_notices (status, expires_at, category);

-- The app cannot decide how long an alert lives or self-approve it.
create or replace function public.apply_notice_safety_rules()
returns trigger
language plpgsql
as $$
begin
  new.status := 'pending';
  new.reported_at := now();
  new.expires_at := now() + case new.category
    when 'neighbourhood' then interval '7 days'
    else interval '24 hours'
  end;
  return new;
end;
$$;

create trigger apply_notice_safety_rules_before_insert
before insert on public.safety_notices
for each row execute function public.apply_notice_safety_rules();

alter table public.safety_notices enable row level security;

-- Anyone may read only moderated, unexpired, non-sensitive map context.
create policy "read approved active notices"
on public.safety_notices for select to anon, authenticated
using (status = 'approved' and expires_at > now());

-- Public reports enter a moderation queue. They never appear automatically.
create policy "submit pending notice"
on public.safety_notices for insert to anon, authenticated
with check (
  status = 'pending'
  and (photo_path is null or (auth.uid() is not null and split_part(photo_path, '/', 1) = auth.uid()::text))
);

grant usage on schema public to anon, authenticated;
grant select, insert on public.safety_notices to anon, authenticated;

-- Schedule this from the Supabase dashboard or run it from a cron job.
create or replace function public.expire_old_notices()
returns void
language sql
security definer
set search_path = public
as $$
  update public.safety_notices
  set status = 'expired'
  where status in ('pending', 'approved') and expires_at <= now();
$$;
