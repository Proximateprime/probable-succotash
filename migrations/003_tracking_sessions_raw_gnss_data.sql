alter table if exists tracking_sessions
  add column if not exists raw_gnss_data text;