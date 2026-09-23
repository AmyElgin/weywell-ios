-- Apply after schema.sql. Devices and watches are private to an anonymous
-- Supabase Auth user; the publishable key cannot read anyone else's data.
create table if not exists public.push_devices (
  user_id uuid not null references auth.users(id) on delete cascade,
  revenue_cat_user_id text not null check (char_length(revenue_cat_user_id) between 1 and 128),
  token text not null check (token ~ '^[0-9a-f]{64}$'),
  environment text not null check (environment in ('sandbox', 'production')),
  updated_at timestamptz not null default now(),
  primary key (user_id, token)
);

create table if not exists public.push_watches (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 80),
  kind text not null check (kind in ('area', 'route')),
  radius_km integer not null check (radius_km between 1 and 60),
  latitude double precision check (latitude between -35 and -22),
  longitude double precision check (longitude between 16 and 33),
  route_points jsonb,
  enabled boolean not null default true,
  updated_at timestamptz not null default now(),
  constraint watch_geometry check (
    (kind = 'area' and latitude is not null and longitude is not null and route_points is null)
    or (kind = 'route' and latitude is null and longitude is null and jsonb_typeof(route_points) = 'array' and jsonb_array_length(route_points) between 2 and 501)
  )
);

create index if not exists push_watches_user_idx on public.push_watches (user_id);

-- One delivery per device/report, even if its owner follows overlapping
-- places and routes. Removing a watch does not erase delivery history.
create table if not exists public.push_deliveries (
  watch_id uuid not null,
  notice_id uuid not null references public.safety_notices(id) on delete cascade,
  token text not null,
  delivered_at timestamptz not null default now(),
  primary key (notice_id, token)
);

alter table public.push_devices enable row level security;
alter table public.push_watches enable row level security;
alter table public.push_deliveries enable row level security;

drop policy if exists "manage own push devices" on public.push_devices;
drop policy if exists "manage own push watches" on public.push_watches;
create policy "manage own push devices" on public.push_devices
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "manage own push watches" on public.push_watches
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
-- Deliveries are visible only to the server; clients cannot fake a sent alert.

grant select, insert, update, delete on public.push_devices to authenticated;
grant select, insert, update, delete on public.push_watches to authenticated;

-- Enable Anonymous Sign-Ins in Authentication > Sign In / Providers before
-- running the iOS app. Configure the push-notice Edge Function webhook to
-- receive UPDATE events on safety_notices when a reviewer approves a report.
