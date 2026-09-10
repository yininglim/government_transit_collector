create or replace function public.get_vehicle_position_route_ids(
  period_start timestamptz,
  period_end_exclusive timestamptz
)
returns table(route_id text)
language sql
stable
security invoker
set search_path = ''
as $$
  select distinct vp.route_id
  from public.vehicle_positions as vp
  where vp.route_id is not null
    and vp.recorded_at >= period_start
    and vp.recorded_at < period_end_exclusive
  order by vp.route_id;
$$;

revoke all on function public.get_vehicle_position_route_ids(timestamptz, timestamptz)
from public, anon;

grant execute on function public.get_vehicle_position_route_ids(timestamptz, timestamptz)
to authenticated;
