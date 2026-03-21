-- 999_master_idempotent_schema_repair.sql
-- One-file safe schema repair for SprayMap Pro.
-- Idempotent: keeps existing data and only adds missing objects.

begin;

-- -------------------------
-- Extensions
-- -------------------------
create extension if not exists pgcrypto;

-- -------------------------
-- Core Tables (create if missing)
-- -------------------------
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null unique,
  role text default 'hobbyist',
  tier text default 'hobbyist',
  active_maps_count integer default 0,
  overlap_threshold numeric default 25,
  first_login boolean default true,
  created_at timestamptz default now()
);

create table if not exists public.properties (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  address text,
  latitude numeric,
  longitude numeric,
  acreage numeric,
  notes text,
  assigned_to uuid[] default array[]::uuid[],
  map_geojson jsonb,
  orthomosaic_url text,
  exclusion_zones jsonb default '[]'::jsonb,
  special_zones jsonb default '[]'::jsonb,
  outer_boundary jsonb,
  recommended_path jsonb,
  treatment_type text,
  last_application date,
  frequency_days integer,
  next_due date,
  application_rate_per_acre numeric,
  application_rate_unit text,
  chemical_cost_per_unit numeric,
  default_tank_capacity_gallons numeric,
  created_at timestamptz default now()
);

create table if not exists public.tracking_sessions (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references public.properties(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  start_time timestamptz not null,
  end_time timestamptz,
  is_completed boolean default false,
  paths jsonb default '[]'::jsonb,
  coverage_polygons jsonb default '[]'::jsonb,
  coverage_percent numeric,
  total_distance_miles numeric,
  duration_seconds integer,
  proof_pdf_url text,
  notes text,
  swath_width_feet numeric,
  tank_capacity_gallons numeric,
  application_rate_per_acre numeric,
  application_rate_unit text,
  chemical_cost_per_unit numeric,
  overlap_percent numeric,
  overlap_savings_estimate numeric,
  overlap_threshold numeric,
  partial_completion_reason text,
  checklist_data jsonb,
  raw_gnss_data text,
  created_at timestamptz default now()
);

-- -------------------------
-- Add Missing Columns (safe)
-- -------------------------
alter table if exists public.profiles
  add column if not exists role text default 'hobbyist',
  add column if not exists tier text default 'hobbyist',
  add column if not exists active_maps_count integer default 0,
  add column if not exists overlap_threshold numeric default 25,
  add column if not exists first_login boolean default true,
  add column if not exists created_at timestamptz default now();

alter table if exists public.properties
  add column if not exists address text,
  add column if not exists latitude numeric,
  add column if not exists longitude numeric,
  add column if not exists acreage numeric,
  add column if not exists notes text,
  add column if not exists assigned_to uuid[] default array[]::uuid[],
  add column if not exists map_geojson jsonb,
  add column if not exists orthomosaic_url text,
  add column if not exists exclusion_zones jsonb default '[]'::jsonb,
  add column if not exists special_zones jsonb default '[]'::jsonb,
  add column if not exists outer_boundary jsonb,
  add column if not exists recommended_path jsonb,
  add column if not exists treatment_type text,
  add column if not exists last_application date,
  add column if not exists frequency_days integer,
  add column if not exists next_due date,
  add column if not exists application_rate_per_acre numeric,
  add column if not exists application_rate_unit text,
  add column if not exists chemical_cost_per_unit numeric,
  add column if not exists default_tank_capacity_gallons numeric,
  add column if not exists created_at timestamptz default now();

alter table if exists public.tracking_sessions
  add column if not exists end_time timestamptz,
  add column if not exists is_completed boolean default false,
  add column if not exists paths jsonb default '[]'::jsonb,
  add column if not exists coverage_polygons jsonb default '[]'::jsonb,
  add column if not exists coverage_percent numeric,
  add column if not exists total_distance_miles numeric,
  add column if not exists duration_seconds integer,
  add column if not exists proof_pdf_url text,
  add column if not exists notes text,
  add column if not exists swath_width_feet numeric,
  add column if not exists tank_capacity_gallons numeric,
  add column if not exists application_rate_per_acre numeric,
  add column if not exists application_rate_unit text,
  add column if not exists chemical_cost_per_unit numeric,
  add column if not exists overlap_percent numeric,
  add column if not exists overlap_savings_estimate numeric,
  add column if not exists overlap_threshold numeric,
  add column if not exists partial_completion_reason text,
  add column if not exists checklist_data jsonb,
  add column if not exists raw_gnss_data text,
  add column if not exists created_at timestamptz default now();

-- -------------------------
-- Data Normalization (safe)
-- -------------------------
update public.profiles
set overlap_threshold = 25
where overlap_threshold is null;

update public.profiles
set first_login = true
where first_login is null;

update public.properties
set exclusion_zones = '[]'::jsonb
where exclusion_zones is null;

update public.properties
set special_zones = '[]'::jsonb
where special_zones is null;

update public.tracking_sessions
set paths = '[]'::jsonb
where paths is null;

-- -------------------------
-- Indexes
-- -------------------------
create index if not exists idx_properties_owner_id on public.properties(owner_id);
create index if not exists idx_properties_assigned_to on public.properties using gin (assigned_to);
create index if not exists idx_tracking_sessions_property_id on public.tracking_sessions(property_id);
create index if not exists idx_tracking_sessions_user_id on public.tracking_sessions(user_id);
create index if not exists idx_tracking_sessions_start_time on public.tracking_sessions(start_time desc);

-- -------------------------
-- Function: increment_active_maps (hardened)
-- -------------------------
create or replace function public.increment_active_maps(user_id uuid)
returns void as $$
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if auth.uid() <> user_id then
    raise exception 'Forbidden: cannot modify another user''s map count';
  end if;

  update public.profiles
  set active_maps_count = coalesce(active_maps_count, 0) + 1
  where id = user_id;
end;
$$ language plpgsql security definer set search_path = public;

revoke all on function public.increment_active_maps(uuid) from public;
grant execute on function public.increment_active_maps(uuid) to authenticated;

-- -------------------------
-- Functions: tier limits + check
-- -------------------------
create or replace function public.tier_max_maps(input_tier text)
returns integer as $$
declare
  normalized text := lower(trim(coalesce(input_tier, 'hobbyist')));
begin
  if normalized in ('corporate', 'solo_professional', 'premium_solo') then
    return -1;
  end if;

  if normalized = 'individual' then
    return 3;
  end if;

  if normalized in ('hobby', 'hobbyist', 'individual_large_land') then
    return 1;
  end if;

  return 1;
end;
$$ language plpgsql immutable;

create or replace function public.check_map_limit()
returns table (
  allowed boolean,
  active_count integer,
  max_maps integer,
  tier text,
  message text
) as $$
declare
  current_uid uuid := auth.uid();
begin
  if current_uid is null then
    raise exception 'Not authenticated';
  end if;

  return query
  with profile as (
    select
      coalesce(p.active_maps_count, 0) as current_count,
      coalesce(p.tier, 'hobbyist') as current_tier,
      public.tier_max_maps(p.tier) as tier_limit
    from public.profiles p
    where p.id = current_uid
  )
  select
    case
      when profile.tier_limit < 0 then true
      else profile.current_count < profile.tier_limit
    end as allowed,
    profile.current_count,
    profile.tier_limit,
    profile.current_tier,
    case
      when profile.tier_limit < 0 then 'Unlimited maps allowed.'
      when profile.current_count >= profile.tier_limit then 'Max maps reached - upgrade?'
      else 'Map available.'
    end as message
  from profile;
end;
$$ language plpgsql security definer set search_path = public;

revoke all on function public.check_map_limit() from public;
grant execute on function public.check_map_limit() to authenticated;

-- -------------------------
-- Trigger: enforce map limit on property insert
-- -------------------------
create or replace function public.enforce_map_limit_on_property_insert()
returns trigger as $$
declare
  current_uid uuid := auth.uid();
  current_count integer;
  current_tier text;
  tier_limit integer;
begin
  if current_uid is null then
    raise exception 'Not authenticated';
  end if;

  if new.owner_id <> current_uid then
    raise exception 'Forbidden: owner mismatch';
  end if;

  select coalesce(p.active_maps_count, 0), coalesce(p.tier, 'hobbyist'), public.tier_max_maps(p.tier)
  into current_count, current_tier, tier_limit
  from public.profiles p
  where p.id = current_uid
  for update;

  if current_count is null then
    raise exception 'Profile not found';
  end if;

  if tier_limit >= 0 and current_count >= tier_limit then
    raise exception 'Map limit reached for tier % (%/%). Upgrade required.', current_tier, current_count, tier_limit;
  end if;

  update public.profiles
  set active_maps_count = coalesce(active_maps_count, 0) + 1
  where id = current_uid;

  return new;
end;
$$ language plpgsql security definer set search_path = public;

do $$
begin
  if not exists (
    select 1
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where t.tgname = 'trg_enforce_map_limit_on_property_insert'
      and n.nspname = 'public'
      and c.relname = 'properties'
      and not t.tgisinternal
  ) then
    execute '
      create trigger trg_enforce_map_limit_on_property_insert
      before insert on public.properties
      for each row
      execute function public.enforce_map_limit_on_property_insert()
    ';
  end if;
end
$$;

-- -------------------------
-- RLS: enable
-- -------------------------
alter table if exists public.profiles enable row level security;
alter table if exists public.properties enable row level security;
alter table if exists public.tracking_sessions enable row level security;

-- -------------------------
-- RLS policy guards (create only if missing)
-- -------------------------
-- Profiles
 do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'profiles' and policyname = 'users_select_own_profile'
  ) then
    execute '
      create policy users_select_own_profile
      on public.profiles
      for select
      using (auth.uid() = id)
    ';
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'profiles' and policyname = 'users_insert_own_profile'
  ) then
    execute '
      create policy users_insert_own_profile
      on public.profiles
      for insert
      with check (auth.uid() = id)
    ';
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'profiles' and policyname = 'users_update_own_profile'
  ) then
    execute '
      create policy users_update_own_profile
      on public.profiles
      for update
      using (auth.uid() = id)
      with check (auth.uid() = id)
    ';
  end if;
end
$$;

-- Properties
 do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'properties' and policyname = 'owners_select_own_properties'
  ) then
    execute '
      create policy owners_select_own_properties
      on public.properties
      for select
      using (auth.uid() = owner_id)
    ';
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'properties' and policyname = 'workers_see_assigned_properties'
  ) then
    execute '
      create policy workers_see_assigned_properties
      on public.properties
      for select
      using (
        auth.uid() = owner_id
        or auth.uid()::text = any(coalesce(assigned_to::text[], array[]::text[]))
      )
    ';
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'properties' and policyname = 'owners_insert_own_properties'
  ) then
    execute '
      create policy owners_insert_own_properties
      on public.properties
      for insert
      with check (auth.uid() = owner_id)
    ';
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'properties' and policyname = 'owners_update_own_properties'
  ) then
    execute '
      create policy owners_update_own_properties
      on public.properties
      for update
      using (auth.uid() = owner_id)
      with check (auth.uid() = owner_id)
    ';
  end if;
end
$$;

-- Tracking Sessions
 do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'tracking_sessions' and policyname = 'users_select_own_tracking_sessions'
  ) then
    execute '
      create policy users_select_own_tracking_sessions
      on public.tracking_sessions
      for select
      using (auth.uid() = user_id)
    ';
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'tracking_sessions' and policyname = 'users_insert_own_tracking_sessions'
  ) then
    execute '
      create policy users_insert_own_tracking_sessions
      on public.tracking_sessions
      for insert
      with check (auth.uid() = user_id)
    ';
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'tracking_sessions' and policyname = 'users_update_own_tracking_sessions'
  ) then
    execute '
      create policy users_update_own_tracking_sessions
      on public.tracking_sessions
      for update
      using (auth.uid() = user_id)
      with check (auth.uid() = user_id)
    ';
  end if;
end
$$;

commit;
