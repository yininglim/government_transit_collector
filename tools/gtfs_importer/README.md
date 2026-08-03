# GTFS Static importer

This trusted local Python tool validates a GTFS Static ZIP and can upsert its seven core files into the existing Supabase GTFS tables. Dry-run validation is the default. It does not extract the ZIP permanently, alter the schema, delete existing rows, or import optional fare/area files.

## Install

Python 3.9 or newer is required. From `tools/gtfs_importer`, create and activate a virtual environment, then install the single runtime dependency:

```sh
python -m venv .venv
# Windows PowerShell
.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
```

The only direct dependency is the Supabase Python client. Dry-run validation uses only the Python standard library and works without installing it.

## Credentials

Copy the example file and edit the ignored local copy:

```powershell
Copy-Item .env.importer.example .env.importer
```

Set both values in `.env.importer`:

```dotenv
SUPABASE_URL=your_supabase_project_url
SUPABASE_SERVICE_ROLE_KEY=your_service_role_key
```

The importer deliberately reads only `tools/gtfs_importer/.env.importer`; it never reads the Flutter project `.env`.

> **Security warning:** A service-role key bypasses Row Level Security. Use it only in this trusted local importer. Never put it in Flutter code, logs, screenshots, source control, or the example file. The real `.env.importer` is ignored by Git.

## Validate (default behavior)

From `tools/gtfs_importer`:

```sh
python import_gtfs.py --zip ../../gtfs_mybas.zip --dry-run
```

`--dry-run` is optional because validation-only mode is the default:

```sh
python import_gtfs.py --zip ../../gtfs_mybas.zip
```

Validation checks required files and columns, duplicate keys, coordinates, GTFS time format, and available foreign-key references. Every `.txt` file is counted, but optional fare/area files are never imported.

## Import

Import requires an explicit flag:

```sh
python import_gtfs.py --zip ../../gtfs_mybas.zip --import --batch-size 500
```

The batch size defaults to 500. Each table is streamed from the ZIP and sent through separate bounded upsert requests; large `stop_times.txt` and `shapes.txt` files are never uploaded in one request.

The importer creates a processing metadata row first, then imports in this order:

1. `gtfs_import_metadata`
2. `gtfs_agencies`
3. `gtfs_stops`
4. `gtfs_routes`
5. `gtfs_calendar`
6. `gtfs_trips`
7. `gtfs_stop_times`
8. `gtfs_shapes`

Progress reports the table and batch number. Successful imports mark metadata `completed` and set `imported_at`. A failed request stops all remaining batches and marks metadata `failed` with a concise table/batch summary when possible.

## Reruns

Reruns use the existing primary keys as Supabase `on_conflict` targets:

- Single IDs for agencies, stops, routes, calendar, and trips
- `(trip_id, stop_sequence)` for stop times
- `(shape_id, shape_pt_sequence)` for shapes

Existing matching records are updated and receive the new `source_import_id`; duplicate GTFS records are not created. Records absent from a later feed are intentionally retained because the importer never performs automatic deletion.

## Verify in Supabase

After a completed import, compare the metadata `row_counts` with table counts in the Supabase SQL editor:

```sql
select import_id, source_filename, file_checksum, service_start_date,
       service_end_date, row_counts, status, imported_at, error_summary
from public.gtfs_import_metadata
order by created_at desc
limit 5;

select 'agency.txt' as file, count(*) from public.gtfs_agencies
union all select 'stops.txt', count(*) from public.gtfs_stops
union all select 'routes.txt', count(*) from public.gtfs_routes
union all select 'calendar.txt', count(*) from public.gtfs_calendar
union all select 'trips.txt', count(*) from public.gtfs_trips
union all select 'stop_times.txt', count(*) from public.gtfs_stop_times
union all select 'shapes.txt', count(*) from public.gtfs_shapes;
```

Because reruns upsert global GTFS primary keys and do not delete stale rows, total table counts can be greater than the latest feed's row counts. For the latest import specifically, filter each table by its `source_import_id`.
