-- Add geometry storage for no-spray and outer spray boundaries.
alter table if exists properties
  add column if not exists exclusion_zones jsonb default '[]'::jsonb;

alter table if exists properties
  add column if not exists outer_boundary jsonb;

-- Ensure existing null exclusion arrays are normalized.
update properties
set exclusion_zones = '[]'::jsonb
where exclusion_zones is null;
