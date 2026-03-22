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
  resolved_count integer;
  resolved_tier text;
  resolved_limit integer;
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

  select
    coalesce(p.active_maps_count, 0),
    coalesce(p.tier, 'hobbyist'),
    public.tier_max_maps(p.tier)
  into resolved_count, resolved_tier, resolved_limit
  from public.profiles p
  where p.id = requested_uid;

  if not found then
    raise exception 'Profile not found';
  end if;

  return query
  select
    case
      when resolved_limit < 0 then true
      else resolved_count < resolved_limit
    end as can_add,
    resolved_count,
    resolved_limit,
    resolved_tier,
    case
      when resolved_limit < 0 then 'Unlimited maps allowed.'
      when resolved_count >= resolved_limit then 'Max maps reached for your tier - upgrade?'
      else 'Map available.'
    end as message;
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

