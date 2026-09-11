begin;

alter table public.bus_feedback
  add column service_date date,
  add column scheduled_departure_seconds integer,
  add constraint bus_feedback_schedule_pair check (
    (service_date is null and scheduled_departure_seconds is null)
    or (service_date is not null and scheduled_departure_seconds is not null
        and scheduled_departure_seconds >= 0
        and route_id is not null and stop_id is not null)
  );

create unique index bus_feedback_user_scheduled_event_key
  on public.bus_feedback
    (user_id, route_id, stop_id, service_date, scheduled_departure_seconds)
  where service_date is not null and scheduled_departure_seconds is not null;

create function public.validate_bus_feedback_scheduled_event()
returns trigger language plpgsql set search_path = public as $$
begin
  if TG_OP = 'UPDATE' then
    if row(new.user_id, new.route_id, new.stop_id, new.trip_id,
           new.service_date, new.scheduled_departure_seconds)
       is not distinct from
       row(old.user_id, old.route_id, old.stop_id, old.trip_id,
           old.service_date, old.scheduled_departure_seconds) then
      return new;
    end if;
    if old.service_date is null and old.scheduled_departure_seconds is null
       and new.service_date is null and new.scheduled_departure_seconds is null then
      return new;
    end if;
  end if;
  if auth.uid() is null or new.user_id is distinct from auth.uid() then
    raise exception 'Sign in as the report owner before submitting a report.' using errcode = '42501';
  end if;
  if new.route_id is null or new.stop_id is null then
    raise exception 'Select a route and stop before submitting a report.' using errcode = '23514';
  end if;
  if new.service_date is null or new.scheduled_departure_seconds is null then
    raise exception 'Select a scheduled service before submitting a report.' using errcode = '23514';
  end if;
  if not exists (
    select 1 from public.gtfs_trips t
    join public.gtfs_calendar c on c.service_id = t.service_id
      and c.source_import_id = t.source_import_id
    join public.gtfs_stop_times st on st.trip_id = t.trip_id
      and st.source_import_id = t.source_import_id
    where t.route_id = new.route_id and st.stop_id = new.stop_id
      and (new.trip_id is null or t.trip_id = new.trip_id)
      and st.departure_seconds = new.scheduled_departure_seconds
      and new.service_date between c.start_date and c.end_date
      and (array[c.monday,c.tuesday,c.wednesday,c.thursday,c.friday,c.saturday,c.sunday])
          [extract(isodow from new.service_date)::integer]
  ) then
    raise exception 'This scheduled departure is no longer available. Please select it again.' using errcode = '23514';
  end if;
  return new;
end;
$$;

create trigger bus_feedback_validate_scheduled_event
before insert or update on public.bus_feedback
for each row execute function public.validate_bus_feedback_scheduled_event();

commit;
