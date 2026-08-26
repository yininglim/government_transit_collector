# Historical realtime vehicle collector

This standalone Dart process fetches the MyBAS Johor GTFS Realtime protobuf
feed and stores genuine vehicle observations in `public.vehicle_positions`.
It is independent of the Flutter passenger UI and defaults to a sequential
two-minute collection interval.

Before writing a snapshot, the collector checks distinct exact realtime
`trip_id` values against `public.gtfs_trips` in batches. Observations for trips
that are absent from the currently imported GTFS Static feed are reported and
skipped, preserving the existing foreign key. Pure dry-run mode has no
Supabase configuration and reports static-trip matching as not checked.

For writes, set `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` in the process
environment. Never put a service-role key in Flutter configuration, source
control, or `.env.example`.

```powershell
# Fetch, decode, and validate once without Supabase access or writes.
dart run scripts/realtime_history_collector.dart --dry-run

# Write one snapshot, then exit.
dart run scripts/realtime_history_collector.dart --once

# Run until Ctrl+C (two-minute default).
dart run scripts/realtime_history_collector.dart

# Use a different interval.
dart run scripts/realtime_history_collector.dart --interval-minutes=5
```

Verify recent rows in the Supabase SQL Editor with read-only queries:

```sql
select position_id, vehicle_id, trip_id, route_id, latitude, longitude,
       recorded_at as vehicle_timestamp, received_at as collected_at
from public.vehicle_positions
order by recorded_at desc
limit 100;

select count(*) as total_historical_records
from public.vehicle_positions;

select route_id, count(*) as observation_count
from public.vehicle_positions
group by route_id
order by observation_count desc;

select min(recorded_at) as first_vehicle_timestamp,
       max(recorded_at) as latest_vehicle_timestamp,
       min(received_at) as first_collected_at,
       max(received_at) as latest_collected_at
from public.vehicle_positions;
```

This history measures vehicle, trip, and route operational activity. It does
not measure passenger counts or passenger demand.
