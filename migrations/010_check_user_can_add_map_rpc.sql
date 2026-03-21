create or replace function public.check_user_can_add_map(user_id uuid)
returns table (
  can_add boolean,
  current_count integer,
  max_limit integer,
  tier text,
  message text
) as $$
declare
  requested_uid uuid := user_id;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if requested_uid is null then
    requested_uid := auth.uid();
  end if;

  if requested_uid <> auth.uid() then
    raise exception 'Forbidden';
  end if;

  return query
  with profile as (
    select
      coalesce(p.active_maps_count, 0) as current_count,
      coalesce(p.tier, 'hobbyist') as current_tier,
      public.tier_max_maps(p.tier) as tier_limit
    from public.profiles p
    where p.id = requested_uid
  )
  select
    case
      when profile.tier_limit < 0 then true
      else profile.current_count < profile.tier_limit
    end as can_add,
    profile.current_count,
    profile.tier_limit,
    profile.current_tier,
    case
      when profile.tier_limit < 0 then 'Unlimited maps allowed.'
      when profile.current_count >= profile.tier_limit then 'Max maps reached for your tier - upgrade?'
      else 'Map available.'
    end as message
  from profile;
end;
$$ language plpgsql security definer set search_path = public;

revoke all on function public.check_user_can_add_map(uuid) from public;
grant execute on function public.check_user_can_add_map(uuid) to authenticated;

drop policy if exists owners_insert_own_properties on public.properties;

create policy owners_insert_own_properties
on public.properties
for insert
with check (
  auth.uid() = owner_id
  and exists (
    select 1
    from public.check_user_can_add_map(auth.uid()) as limit_check
    where limit_check.can_add
  )
);

