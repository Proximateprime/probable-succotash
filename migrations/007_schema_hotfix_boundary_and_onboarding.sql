-- Migration 007: Schema hotfix for boundary save + onboarding completion
-- Safe to run multiple times.

begin;

-- =========================
-- PROFILES TABLE HOTFIX
-- =========================
alter table if exists public.profiles
  add column if not exists first_login boolean default true;

update public.profiles
set first_login = true
where first_login is null;

alter table if exists public.profiles
  add column if not exists overlap_threshold numeric default 25;

update public.profiles
set overlap_threshold = 25
where overlap_threshold is null;

-- =========================
-- PROPERTIES TABLE HOTFIX
-- =========================
alter table if exists public.properties
  add column if not exists map_geojson jsonb,
  add column if not exists outer_boundary jsonb,
  add column if not exists special_zones jsonb default '[]'::jsonb,
  add column if not exists exclusion_zones jsonb default '[]'::jsonb,
  add column if not exists assigned_to uuid[] default array[]::uuid[],
  add column if not exists orthomosaic_url text,
  add column if not exists recommended_path jsonb,
  add column if not exists application_rate_per_acre numeric,
  add column if not exists application_rate_unit text,
  add column if not exists chemical_cost_per_unit numeric,
  add column if not exists default_tank_capacity_gallons numeric;

update public.properties
set special_zones = '[]'::jsonb
where special_zones is null;

update public.properties
set exclusion_zones = '[]'::jsonb
where exclusion_zones is null;

-- =========================
-- INDEXES (SAFE)
-- =========================
create index if not exists idx_properties_assigned_to
  on public.properties using gin (assigned_to);

-- =========================
-- RLS POLICY GUARDS (SAFE)
-- =========================
-- Allow owners to update their own properties.
do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'properties'
      and policyname = 'owners_update_own_properties'
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

-- Allow users to update their own profile (first_login, overlap_threshold, etc).
do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'profiles'
      and policyname = 'users_update_own_profile'
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

commit;
