-- Migration 008: Hotfix tracking session start failures
-- Safe to run multiple times.

begin;

-- =========================
-- TRACKING SESSIONS COLUMNS
-- =========================
alter table if exists public.tracking_sessions
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
  add column if not exists raw_gnss_data text;

-- Normalize common nullable JSON payloads
update public.tracking_sessions
set paths = '[]'::jsonb
where paths is null;

-- =========================
-- RLS POLICY GUARDS (SAFE)
-- =========================
-- Ensure the table has RLS enabled.
alter table if exists public.tracking_sessions enable row level security;

-- Allow users to insert their own sessions.
do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'tracking_sessions'
      and policyname = 'users_insert_own_tracking_sessions'
  ) then
    execute '
      create policy users_insert_own_tracking_sessions
      on public.tracking_sessions
      for insert
      with check (auth.uid() = user_id)
    ';
  end if;
end
$$;

-- Allow users to read their own sessions.
do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'tracking_sessions'
      and policyname = 'users_select_own_tracking_sessions'
  ) then
    execute '
      create policy users_select_own_tracking_sessions
      on public.tracking_sessions
      for select
      using (auth.uid() = user_id)
    ';
  end if;
end
$$;

-- Allow users to update their own sessions.
do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'tracking_sessions'
      and policyname = 'users_update_own_tracking_sessions'
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
