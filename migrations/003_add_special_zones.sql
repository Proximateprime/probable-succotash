-- Migration 003: Add special_zones column to properties table

alter table properties
  add column if not exists special_zones jsonb default '[]'::jsonb;

update properties
set special_zones = '[]'::jsonb
where special_zones is null;

comment on column properties.special_zones is
  'Named special zones for targeted spraying. Array of {name, polygon, type, color, sprayable} objects.';
