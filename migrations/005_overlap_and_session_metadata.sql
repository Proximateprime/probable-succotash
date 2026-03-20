-- Migration 005: Add overlap settings, chemical defaults, and session metadata

alter table profiles
  add column if not exists overlap_threshold numeric default 25;

update profiles
set overlap_threshold = 25
where overlap_threshold is null;

alter table properties
  add column if not exists application_rate_per_acre numeric,
  add column if not exists application_rate_unit text,
  add column if not exists chemical_cost_per_unit numeric,
  add column if not exists default_tank_capacity_gallons numeric;

alter table tracking_sessions
  add column if not exists swath_width_feet numeric,
  add column if not exists tank_capacity_gallons numeric,
  add column if not exists application_rate_per_acre numeric,
  add column if not exists application_rate_unit text,
  add column if not exists chemical_cost_per_unit numeric,
  add column if not exists overlap_percent numeric,
  add column if not exists overlap_savings_estimate numeric,
  add column if not exists overlap_threshold numeric,
  add column if not exists partial_completion_reason text,
  add column if not exists checklist_data jsonb;

comment on column profiles.overlap_threshold is
  'User-configured overlap highlight threshold percentage for summaries.';
comment on column properties.application_rate_per_acre is
  'Default chemical usage rate per acre for the property.';
comment on column properties.application_rate_unit is
  'Unit for chemical usage rate, typically gal or oz.';
comment on column properties.chemical_cost_per_unit is
  'Optional chemical cost per gal or oz for overlap savings estimates.';
comment on column properties.default_tank_capacity_gallons is
  'Optional default tank capacity used to seed tracking session start dialog.';
comment on column tracking_sessions.overlap_percent is
  'Estimated overlap percentage for the completed session.';
comment on column tracking_sessions.overlap_savings_estimate is
  'Estimated savings opportunity in dollars based on overlap and chemical cost.';
comment on column tracking_sessions.checklist_data is
  'Job completion checklist state and optional notes.';
