-- Migration 004: Add treatment scheduling fields to properties table

alter table properties
  add column if not exists treatment_type text,
  add column if not exists last_application date,
  add column if not exists frequency_days int,
  add column if not exists next_due date;

comment on column properties.treatment_type is
  'Last selected treatment type (Preemergent, Postemergent, Fertilizer, Insecticide, Custom).';
comment on column properties.last_application is
  'Date of last treatment application.';
comment on column properties.frequency_days is
  'Recommended treatment interval in days.';
comment on column properties.next_due is
  'Next treatment due date (last_application + frequency_days).';
