begin;

-- Reuse the existing owner-protected tracking sessions. Legacy tracking rows
-- remain untouched; the snapshot retains both legs and the GTFS service date.
alter table public.tracking_sessions add column journey_snapshot jsonb;
alter table public.tracking_sessions add constraint tracking_journey_snapshot_object
  check (journey_snapshot is null or jsonb_typeof(journey_snapshot) = 'object');
create unique index tracking_sessions_one_passenger_journey
  on public.tracking_sessions(user_id)
  where status = 'active' and journey_snapshot is not null;

-- Invoker functions retain the existing RLS ownership rules. The lock and unique
-- index prevent two devices from starting separate current journeys at once.
create function public.start_passenger_journey(p_snapshot jsonb, p_replace_id uuid default null)
returns uuid language plpgsql security invoker set search_path = public as $$
declare
  owner_id uuid := auth.uid();
  current_row public.tracking_sessions;
  result_id uuid;
  r jsonb := p_snapshot->'recommendation';
  arrival_at timestamptz;
begin
  if owner_id is null then raise exception 'Sign in required'; end if;
  if (p_snapshot->>'version') is distinct from '1'
    or coalesce(r->>'type', '') not in ('direct', 'transfer') then
    raise exception 'Invalid journey snapshot';
  end if;
  arrival_at := ((p_snapshot->>'service_date')::date::timestamp at time zone 'Asia/Kuala_Lumpur')
    + (r->>'arrivalSeconds')::integer * interval '1 second';
  if arrival_at is null then raise exception 'Journey arrival required'; end if;
  perform pg_advisory_xact_lock(hashtextextended(owner_id::text, 0));
  select * into current_row from public.tracking_sessions
    where user_id = owner_id and status = 'active' and journey_snapshot is not null for update;
  if found then
    if current_row.journey_snapshot = p_snapshot then
      return current_row.tracking_session_id;
    end if;
    if p_replace_id is distinct from current_row.tracking_session_id then
      raise exception 'Confirm replacing the current active journey';
    end if;
    update public.tracking_sessions set status = 'cancelled', last_updated_at = now()
      where tracking_session_id = current_row.tracking_session_id and user_id = owner_id;
  end if;
  insert into public.tracking_sessions(user_id, trip_id, boarding_stop_id,
    destination_stop_id, estimated_arrival_at, journey_snapshot)
  values (owner_id, case when r->>'type' = 'direct' then r->>'tripId' else r->>'firstTripId' end,
    r->>'originStopId', r->>'destinationStopId', arrival_at, p_snapshot)
  returning tracking_session_id into result_id;
  return result_id;
end;
$$;

create function public.finish_passenger_journey(p_id uuid, p_completed boolean)
returns void language plpgsql security invoker set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Sign in required'; end if;
  update public.tracking_sessions
    set status = case when p_completed then 'completed'::public.tracking_status
      else 'cancelled'::public.tracking_status end,
      completed_at = case when p_completed then now() else null end,
      last_updated_at = now()
    where tracking_session_id = p_id and user_id = auth.uid()
      and status = 'active' and journey_snapshot is not null
      and (not p_completed or estimated_arrival_at <= now());
  if not found then raise exception 'Journey is no longer active or has not reached its expected arrival'; end if;
end;
$$;
revoke all on function public.start_passenger_journey(jsonb, uuid) from public;
revoke all on function public.finish_passenger_journey(uuid, boolean) from public;
grant execute on function public.start_passenger_journey(jsonb, uuid) to authenticated;
grant execute on function public.finish_passenger_journey(uuid, boolean) to authenticated;
commit;
