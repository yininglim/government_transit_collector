-- Government Transit Collector: initial Supabase PostgreSQL schema
-- This migration creates the approved 15 application tables. Supabase auth.users
-- remains externally managed by Supabase Auth.

create extension if not exists pgcrypto;

-- Restrictive enums are used for stable application workflows. Add enum values in
-- a later migration if the application introduces new workflow states.
create type public.app_role as enum ('passenger', 'admin');
create type public.gtfs_feed_type as enum ('static', 'vehicle_positions');
create type public.import_status as enum ('pending', 'processing', 'completed', 'failed');
create type public.feedback_type as enum (
  'application', 'route', 'stop', 'trip', 'recommendation', 'tracking', 'other'
);
create type public.feedback_review_status as enum (
  'submitted', 'under_review', 'resolved', 'dismissed'
);
create type public.tracking_status as enum ('active', 'completed', 'cancelled');
create type public.analysis_type as enum (
  'passenger_demand',
  'peak_period',
  'route_performance',
  'feedback_analysis',
  'stop_suitability',
  'cost_analysis'
);
create type public.analysis_status as enum (
  'pending', 'running', 'completed', 'failed', 'archived'
);
create type public.recommendation_type as enum (
  'bus_frequency', 'stop_suitability', 'route_improvement', 'cost_estimate',
  'performance_warning'
);
create type public.recommendation_status as enum (
  'draft', 'pending_review', 'accepted', 'rejected', 'implemented', 'archived'
);

-- -----------------------------------------------------------------------------
-- User management
-- -----------------------------------------------------------------------------

create table public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  role public.app_role not null default 'passenger',
  phone_number text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.profiles is
  'Application profile for a Supabase Auth user. Public signups always receive the passenger role.';
comment on column public.profiles.role is
  'Protected by a trigger; clients cannot promote themselves to admin.';

-- SECURITY DEFINER avoids querying profiles through its own RLS policy and thus
-- prevents recursive RLS evaluation. The fixed search_path prevents object shadowing.
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.profiles
    where user_id = auth.uid()
      and role = 'admin'::public.app_role
  );
$$;

revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to authenticated;

-- -----------------------------------------------------------------------------
-- Import management and GTFS Static data
-- -----------------------------------------------------------------------------

create table public.gtfs_import_metadata (
  import_id uuid primary key default gen_random_uuid(),
  initiated_by uuid references public.profiles(user_id) on delete set null,
  feed_type public.gtfs_feed_type not null,
  source_name text not null,
  source_url text,
  source_filename text,
  file_checksum text,
  gtfs_realtime_version text,
  feed_timestamp timestamptz,
  service_start_date date,
  service_end_date date,
  row_counts jsonb not null default '{}'::jsonb,
  status public.import_status not null default 'pending',
  error_summary text,
  created_at timestamptz not null default now(),
  imported_at timestamptz,
  updated_at timestamptz not null default now(),
  constraint gtfs_import_service_dates_valid check (
    service_end_date is null
    or service_start_date is null
    or service_end_date >= service_start_date
  ),
  constraint gtfs_import_static_dates_present check (
    feed_type <> 'static'
    or status <> 'completed'
    or (service_start_date is not null and service_end_date is not null)
  )
);

create table public.gtfs_agencies (
  agency_id text primary key,
  source_import_id uuid not null references public.gtfs_import_metadata(import_id),
  agency_name text not null,
  agency_url text not null,
  agency_timezone text not null,
  agency_phone text,
  agency_lang text
);

create table public.gtfs_stops (
  stop_id text primary key,
  source_import_id uuid not null references public.gtfs_import_metadata(import_id),
  stop_code text,
  stop_name text not null,
  stop_desc text,
  stop_lat double precision not null,
  stop_lon double precision not null,
  zone_id text,
  stop_url text,
  location_type smallint not null default 0,
  parent_station text references public.gtfs_stops(stop_id) on delete set null,
  constraint gtfs_stops_latitude_valid check (stop_lat between -90 and 90),
  constraint gtfs_stops_longitude_valid check (stop_lon between -180 and 180),
  constraint gtfs_stops_location_type_nonnegative check (location_type >= 0),
  constraint gtfs_stops_not_own_parent check (parent_station is null or parent_station <> stop_id)
);

create table public.gtfs_routes (
  route_id text primary key,
  agency_id text not null references public.gtfs_agencies(agency_id),
  source_import_id uuid not null references public.gtfs_import_metadata(import_id),
  route_short_name text,
  route_long_name text,
  route_desc text,
  route_type smallint not null,
  route_url text,
  route_color text,
  route_text_color text,
  constraint gtfs_routes_type_nonnegative check (route_type >= 0),
  constraint gtfs_routes_name_present check (
    nullif(btrim(route_short_name), '') is not null
    or nullif(btrim(route_long_name), '') is not null
  ),
  constraint gtfs_routes_color_format check (
    route_color is null or route_color ~ '^[0-9A-Fa-f]{6}$'
  ),
  constraint gtfs_routes_text_color_format check (
    route_text_color is null or route_text_color ~ '^[0-9A-Fa-f]{6}$'
  )
);

create table public.gtfs_calendar (
  service_id text primary key,
  source_import_id uuid not null references public.gtfs_import_metadata(import_id),
  monday boolean not null,
  tuesday boolean not null,
  wednesday boolean not null,
  thursday boolean not null,
  friday boolean not null,
  saturday boolean not null,
  sunday boolean not null,
  start_date date not null,
  end_date date not null,
  constraint gtfs_calendar_dates_valid check (end_date >= start_date)
);

create table public.gtfs_trips (
  trip_id text primary key,
  route_id text not null references public.gtfs_routes(route_id),
  service_id text not null references public.gtfs_calendar(service_id),
  source_import_id uuid not null references public.gtfs_import_metadata(import_id),
  trip_headsign text,
  direction_id smallint,
  block_id text,
  shape_id text,
  wheelchair_accessible smallint not null default 0,
  constraint gtfs_trips_direction_valid check (direction_id is null or direction_id in (0, 1)),
  constraint gtfs_trips_wheelchair_valid check (wheelchair_accessible in (0, 1, 2))
);

comment on column public.gtfs_trips.shape_id is
  'Logical reference to the group of gtfs_shapes rows sharing shape_id. No conventional FK is possible because gtfs_shapes.shape_id is not unique; the importer must validate it.';

create table public.gtfs_stop_times (
  trip_id text not null references public.gtfs_trips(trip_id) on delete cascade,
  stop_sequence integer not null,
  stop_id text not null references public.gtfs_stops(stop_id),
  source_import_id uuid not null references public.gtfs_import_metadata(import_id),
  arrival_seconds integer not null,
  departure_seconds integer not null,
  arrival_time_text text,
  departure_time_text text,
  stop_headsign text,
  shape_dist_traveled double precision,
  pickup_type smallint not null default 0,
  drop_off_type smallint not null default 0,
  primary key (trip_id, stop_sequence),
  constraint gtfs_stop_times_sequence_positive check (stop_sequence > 0),
  constraint gtfs_stop_times_arrival_nonnegative check (arrival_seconds >= 0),
  constraint gtfs_stop_times_departure_nonnegative check (departure_seconds >= 0),
  constraint gtfs_stop_times_departure_not_before_arrival check (departure_seconds >= arrival_seconds),
  constraint gtfs_stop_times_shape_distance_nonnegative check (
    shape_dist_traveled is null or shape_dist_traveled >= 0
  ),
  constraint gtfs_stop_times_pickup_valid check (pickup_type between 0 and 3),
  constraint gtfs_stop_times_dropoff_valid check (drop_off_type between 0 and 3)
);

comment on column public.gtfs_stop_times.arrival_seconds is
  'Seconds from the GTFS service-day start; supports valid values beyond 24:00:00.';
comment on column public.gtfs_stop_times.departure_seconds is
  'Seconds from the GTFS service-day start; supports valid values beyond 24:00:00.';

create table public.gtfs_shapes (
  shape_id text not null,
  shape_pt_sequence integer not null,
  source_import_id uuid not null references public.gtfs_import_metadata(import_id),
  shape_pt_lat double precision not null,
  shape_pt_lon double precision not null,
  shape_dist_traveled double precision,
  primary key (shape_id, shape_pt_sequence),
  constraint gtfs_shapes_sequence_nonnegative check (shape_pt_sequence >= 0),
  constraint gtfs_shapes_latitude_valid check (shape_pt_lat between -90 and 90),
  constraint gtfs_shapes_longitude_valid check (shape_pt_lon between -180 and 180),
  constraint gtfs_shapes_distance_nonnegative check (
    shape_dist_traveled is null or shape_dist_traveled >= 0
  )
);

-- -----------------------------------------------------------------------------
-- Passenger features
-- -----------------------------------------------------------------------------

create table public.journey_searches (
  search_id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(user_id) on delete cascade,
  origin_text text not null,
  destination_text text not null,
  origin_lat double precision,
  origin_lon double precision,
  destination_lat double precision,
  destination_lon double precision,
  origin_stop_id text references public.gtfs_stops(stop_id) on delete set null,
  destination_stop_id text references public.gtfs_stops(stop_id) on delete set null,
  requested_departure_at timestamptz not null,
  selected_route_id text references public.gtfs_routes(route_id) on delete set null,
  selected_trip_id text references public.gtfs_trips(trip_id) on delete set null,
  estimated_duration_seconds integer,
  walking_distance_metres double precision,
  is_saved boolean not null default false,
  saved_name text,
  recommendation_summary jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint journey_searches_id_owner_unique unique (search_id, user_id),
  constraint journey_origin_latitude_valid check (origin_lat is null or origin_lat between -90 and 90),
  constraint journey_origin_longitude_valid check (origin_lon is null or origin_lon between -180 and 180),
  constraint journey_destination_latitude_valid check (destination_lat is null or destination_lat between -90 and 90),
  constraint journey_destination_longitude_valid check (destination_lon is null or destination_lon between -180 and 180),
  constraint journey_origin_coordinates_paired check ((origin_lat is null) = (origin_lon is null)),
  constraint journey_destination_coordinates_paired check ((destination_lat is null) = (destination_lon is null)),
  constraint journey_duration_nonnegative check (
    estimated_duration_seconds is null or estimated_duration_seconds >= 0
  ),
  constraint journey_walking_distance_nonnegative check (
    walking_distance_metres is null or walking_distance_metres >= 0
  ),
  constraint journey_saved_name_consistent check (is_saved or saved_name is null)
);

-- -----------------------------------------------------------------------------
-- Realtime tracking
-- tracking_sessions is created before feedback_reports because feedback may refer
-- to a particular tracking session.
-- -----------------------------------------------------------------------------

create table public.tracking_sessions (
  tracking_session_id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(user_id) on delete cascade,
  trip_id text not null references public.gtfs_trips(trip_id),
  search_id uuid,
  boarding_stop_id text references public.gtfs_stops(stop_id) on delete set null,
  destination_stop_id text references public.gtfs_stops(stop_id) on delete set null,
  last_estimated_stop_id text references public.gtfs_stops(stop_id) on delete set null,
  status public.tracking_status not null default 'active',
  last_estimated_stop_sequence integer,
  estimated_arrival_at timestamptz,
  progress_confidence double precision,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  last_updated_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint tracking_sessions_id_owner_unique unique (tracking_session_id, user_id),
  constraint tracking_sessions_search_owner_fk
    foreign key (search_id, user_id)
    references public.journey_searches(search_id, user_id)
    on delete set null (search_id),
  constraint tracking_sequence_nonnegative check (
    last_estimated_stop_sequence is null or last_estimated_stop_sequence >= 0
  ),
  constraint tracking_confidence_valid check (
    progress_confidence is null or progress_confidence between 0 and 1
  ),
  constraint tracking_completion_time_valid check (
    completed_at is null or completed_at >= started_at
  ),
  constraint tracking_completed_status_consistent check (
    status <> 'completed' or completed_at is not null
  )
);

create table public.feedback_reports (
  feedback_id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(user_id) on delete cascade,
  feedback_type public.feedback_type not null,
  rating smallint,
  comment text not null,
  route_id text references public.gtfs_routes(route_id) on delete set null,
  trip_id text references public.gtfs_trips(trip_id) on delete set null,
  stop_id text references public.gtfs_stops(stop_id) on delete set null,
  search_id uuid,
  tracking_session_id uuid,
  review_status public.feedback_review_status not null default 'submitted',
  admin_notes text,
  reviewed_by uuid references public.profiles(user_id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint feedback_reports_search_owner_fk
    foreign key (search_id, user_id)
    references public.journey_searches(search_id, user_id)
    on delete set null (search_id),
  constraint feedback_reports_tracking_owner_fk
    foreign key (tracking_session_id, user_id)
    references public.tracking_sessions(tracking_session_id, user_id)
    on delete set null (tracking_session_id),
  constraint feedback_rating_valid check (rating is null or rating between 1 and 5),
  constraint feedback_comment_present check (length(btrim(comment)) > 0),
  constraint feedback_review_fields_consistent check (
    reviewed_at is null or reviewed_by is not null
  )
);

create table public.vehicle_positions (
  position_id uuid primary key default gen_random_uuid(),
  import_id uuid not null references public.gtfs_import_metadata(import_id) on delete cascade,
  feed_entity_id text not null,
  trip_id text not null references public.gtfs_trips(trip_id),
  route_id text not null references public.gtfs_routes(route_id),
  vehicle_id text not null,
  vehicle_label text,
  license_plate text,
  latitude double precision not null,
  longitude double precision not null,
  recorded_at timestamptz not null,
  start_date date,
  direction_id smallint,
  stop_id text references public.gtfs_stops(stop_id) on delete set null,
  current_stop_sequence integer,
  bearing double precision,
  speed double precision,
  estimated_nearest_stop_id text references public.gtfs_stops(stop_id) on delete set null,
  estimated_stop_sequence integer,
  estimated_shape_sequence integer,
  estimated_distance_along_shape double precision,
  estimation_confidence double precision,
  received_at timestamptz not null default now(),
  constraint vehicle_positions_import_entity_unique unique (import_id, feed_entity_id),
  constraint vehicle_positions_observation_unique unique (trip_id, vehicle_id, recorded_at),
  constraint vehicle_positions_latitude_valid check (latitude between -90 and 90),
  constraint vehicle_positions_longitude_valid check (longitude between -180 and 180),
  constraint vehicle_positions_direction_valid check (direction_id is null or direction_id in (0, 1)),
  constraint vehicle_positions_stop_sequence_nonnegative check (
    current_stop_sequence is null or current_stop_sequence >= 0
  ),
  constraint vehicle_positions_bearing_valid check (
    bearing is null or (bearing >= 0 and bearing < 360)
  ),
  constraint vehicle_positions_speed_nonnegative check (speed is null or speed >= 0),
  constraint vehicle_positions_estimated_stop_sequence_nonnegative check (
    estimated_stop_sequence is null or estimated_stop_sequence >= 0
  ),
  constraint vehicle_positions_estimated_shape_sequence_nonnegative check (
    estimated_shape_sequence is null or estimated_shape_sequence >= 0
  ),
  constraint vehicle_positions_estimated_distance_nonnegative check (
    estimated_distance_along_shape is null or estimated_distance_along_shape >= 0
  ),
  constraint vehicle_positions_confidence_valid check (
    estimation_confidence is null or estimation_confidence between 0 and 1
  )
);

-- The source currently omits stop_id, current_stop_sequence, bearing, and speed.
-- Those source fields remain nullable; estimated_* fields are generated by a trusted
-- process using coordinates, route shapes, and ordered stop times.
comment on table public.vehicle_positions is
  'Decoded GTFS Realtime observations plus optional system-derived progress fields.';

-- -----------------------------------------------------------------------------
-- Admin analysis
-- -----------------------------------------------------------------------------

create table public.analysis_reports (
  analysis_report_id uuid primary key default gen_random_uuid(),
  requested_by uuid references public.profiles(user_id) on delete set null,
  analysis_type public.analysis_type not null,
  title text not null,
  route_id text references public.gtfs_routes(route_id) on delete set null,
  stop_id text references public.gtfs_stops(stop_id) on delete set null,
  period_start timestamptz not null,
  period_end timestamptz not null,
  status public.analysis_status not null default 'pending',
  input_parameters jsonb not null default '{}'::jsonb,
  summary_metrics jsonb not null default '{}'::jsonb,
  summary_text text,
  method_or_model text,
  data_freshness_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint analysis_reports_period_valid check (period_end >= period_start),
  constraint analysis_reports_completion_consistent check (
    status <> 'completed' or completed_at is not null
  )
);

create table public.ai_recommendations (
  recommendation_id uuid primary key default gen_random_uuid(),
  analysis_report_id uuid not null references public.analysis_reports(analysis_report_id) on delete cascade,
  recommendation_type public.recommendation_type not null,
  route_id text references public.gtfs_routes(route_id) on delete set null,
  stop_id text references public.gtfs_stops(stop_id) on delete set null,
  title text not null,
  description text not null,
  priority smallint not null default 3,
  supporting_metrics jsonb not null default '{}'::jsonb,
  estimated_cost numeric(14, 2),
  currency text,
  status public.recommendation_status not null default 'draft',
  admin_notes text,
  reviewed_by uuid references public.profiles(user_id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ai_recommendations_priority_valid check (priority between 1 and 5),
  constraint ai_recommendations_cost_nonnegative check (
    estimated_cost is null or estimated_cost >= 0
  ),
  constraint ai_recommendations_currency_valid check (
    currency is null or currency ~ '^[A-Z]{3}$'
  ),
  constraint ai_recommendations_cost_currency_consistent check (
    estimated_cost is null or currency is not null
  ),
  constraint ai_recommendations_review_fields_consistent check (
    reviewed_at is null or reviewed_by is not null
  )
);

-- -----------------------------------------------------------------------------
-- Automatic timestamps and protected-column guards
-- -----------------------------------------------------------------------------

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

create trigger gtfs_import_metadata_set_updated_at
before update on public.gtfs_import_metadata
for each row execute function public.set_updated_at();

create trigger journey_searches_set_updated_at
before update on public.journey_searches
for each row execute function public.set_updated_at();

create trigger feedback_reports_set_updated_at
before update on public.feedback_reports
for each row execute function public.set_updated_at();

create or replace function public.set_tracking_updated_at()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  new.updated_at = now();
  new.last_updated_at = new.updated_at;
  return new;
end;
$$;

create trigger tracking_sessions_set_updated_at
before update on public.tracking_sessions
for each row execute function public.set_tracking_updated_at();

create trigger analysis_reports_set_updated_at
before update on public.analysis_reports
for each row execute function public.set_updated_at();

create trigger ai_recommendations_set_updated_at
before update on public.ai_recommendations
for each row execute function public.set_updated_at();

-- RLS cannot restrict individual updated columns. This guard prevents authenticated
-- clients from changing identity, role, or profile creation time. A service-role JWT
-- may perform controlled role administration because service_role bypasses RLS.
create or replace function public.protect_profile_columns()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if coalesce(auth.jwt() ->> 'role', '') <> 'service_role' then
    if new.user_id is distinct from old.user_id
       or new.role is distinct from old.role
       or new.created_at is distinct from old.created_at then
      raise exception 'Protected profile columns cannot be changed by this client';
    end if;
  end if;
  return new;
end;
$$;

create trigger profiles_protect_columns
before update on public.profiles
for each row execute function public.protect_profile_columns();

-- Passengers cannot modify review workflow fields. Admins editing another user's
-- feedback may change only review-related columns, not the passenger's original text.
create or replace function public.protect_feedback_columns()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  caller_is_admin boolean := public.is_admin();
  caller_is_service boolean := coalesce(auth.jwt() ->> 'role', '') = 'service_role';
begin
  if caller_is_service then
    return new;
  end if;

  if caller_is_admin and old.user_id <> auth.uid() then
    if new.feedback_id is distinct from old.feedback_id
       or new.user_id is distinct from old.user_id
       or new.feedback_type is distinct from old.feedback_type
       or new.rating is distinct from old.rating
       or new.comment is distinct from old.comment
       or new.route_id is distinct from old.route_id
       or new.trip_id is distinct from old.trip_id
       or new.stop_id is distinct from old.stop_id
       or new.search_id is distinct from old.search_id
       or new.tracking_session_id is distinct from old.tracking_session_id
       or new.created_at is distinct from old.created_at then
      raise exception 'Admins may only change feedback review fields';
    end if;
  elsif not caller_is_admin then
    if new.review_status is distinct from old.review_status
       or new.admin_notes is distinct from old.admin_notes
       or new.reviewed_by is distinct from old.reviewed_by
       or new.reviewed_at is distinct from old.reviewed_at then
      raise exception 'Passengers cannot change feedback review fields';
    end if;
  end if;

  return new;
end;
$$;

create trigger feedback_reports_protect_columns
before update on public.feedback_reports
for each row execute function public.protect_feedback_columns();

-- A trusted Auth trigger creates a passenger profile. raw_user_meta_data cannot set
-- role, so a public signup cannot create an administrator.
create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.profiles (user_id, full_name, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    'passenger'::public.app_role
  );
  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_auth_user();

-- -----------------------------------------------------------------------------
-- Query indexes
-- -----------------------------------------------------------------------------

create index gtfs_stops_coordinates_idx
  on public.gtfs_stops (stop_lat, stop_lon);
create index gtfs_stops_parent_station_idx
  on public.gtfs_stops (parent_station) where parent_station is not null;

create index gtfs_routes_agency_idx
  on public.gtfs_routes (agency_id);
create index gtfs_trips_route_idx
  on public.gtfs_trips (route_id);
create index gtfs_trips_route_service_idx
  on public.gtfs_trips (route_id, service_id);
create index gtfs_trips_service_idx
  on public.gtfs_trips (service_id);
create index gtfs_trips_shape_idx
  on public.gtfs_trips (shape_id) where shape_id is not null;

-- The primary key already supports trip_id + stop_sequence lookups.
create index gtfs_stop_times_stop_idx
  on public.gtfs_stop_times (stop_id, trip_id, stop_sequence);
-- The gtfs_shapes composite primary key already supports shape_id + sequence lookups.

create index gtfs_import_metadata_feed_time_idx
  on public.gtfs_import_metadata (feed_type, imported_at desc);
create index gtfs_import_metadata_status_idx
  on public.gtfs_import_metadata (status, created_at desc);

create index journey_searches_user_created_idx
  on public.journey_searches (user_id, created_at desc);
create index journey_searches_saved_idx
  on public.journey_searches (user_id, created_at desc) where is_saved;
create index journey_searches_route_trip_idx
  on public.journey_searches (selected_route_id, selected_trip_id);

create index feedback_reports_user_status_idx
  on public.feedback_reports (user_id, review_status, created_at desc);
create index feedback_reports_status_idx
  on public.feedback_reports (review_status, created_at desc);
create index feedback_reports_route_idx
  on public.feedback_reports (route_id) where route_id is not null;

create index tracking_sessions_user_status_idx
  on public.tracking_sessions (user_id, status, started_at desc);
create index tracking_sessions_trip_status_idx
  on public.tracking_sessions (trip_id, status);

create index vehicle_positions_trip_recorded_idx
  on public.vehicle_positions (trip_id, recorded_at desc);
create index vehicle_positions_vehicle_recorded_idx
  on public.vehicle_positions (vehicle_id, recorded_at desc);
create index vehicle_positions_route_recorded_idx
  on public.vehicle_positions (route_id, recorded_at desc);
create index vehicle_positions_recorded_idx
  on public.vehicle_positions (recorded_at desc);

create index analysis_reports_type_date_idx
  on public.analysis_reports (analysis_type, period_start desc, period_end desc);
create index analysis_reports_status_created_idx
  on public.analysis_reports (status, created_at desc);
create index ai_recommendations_report_idx
  on public.ai_recommendations (analysis_report_id, status);
create index ai_recommendations_status_priority_idx
  on public.ai_recommendations (status, priority, created_at desc);

-- -----------------------------------------------------------------------------
-- Row Level Security
-- -----------------------------------------------------------------------------

alter table public.profiles enable row level security;
alter table public.gtfs_import_metadata enable row level security;
alter table public.gtfs_agencies enable row level security;
alter table public.gtfs_stops enable row level security;
alter table public.gtfs_routes enable row level security;
alter table public.gtfs_calendar enable row level security;
alter table public.gtfs_trips enable row level security;
alter table public.gtfs_stop_times enable row level security;
alter table public.gtfs_shapes enable row level security;
alter table public.journey_searches enable row level security;
alter table public.feedback_reports enable row level security;
alter table public.tracking_sessions enable row level security;
alter table public.vehicle_positions enable row level security;
alter table public.analysis_reports enable row level security;
alter table public.ai_recommendations enable row level security;

-- Profiles
create policy profiles_select_own_or_admin
on public.profiles for select
to authenticated
using (user_id = auth.uid() or public.is_admin());

create policy profiles_update_own
on public.profiles for update
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

-- GTFS Static data is read-only to authenticated clients. No client write policies
-- are created; service-role/backend operations bypass RLS for trusted ingestion.
create policy gtfs_agencies_authenticated_read
on public.gtfs_agencies for select to authenticated using (true);
create policy gtfs_stops_authenticated_read
on public.gtfs_stops for select to authenticated using (true);
create policy gtfs_routes_authenticated_read
on public.gtfs_routes for select to authenticated using (true);
create policy gtfs_calendar_authenticated_read
on public.gtfs_calendar for select to authenticated using (true);
create policy gtfs_trips_authenticated_read
on public.gtfs_trips for select to authenticated using (true);
create policy gtfs_stop_times_authenticated_read
on public.gtfs_stop_times for select to authenticated using (true);
create policy gtfs_shapes_authenticated_read
on public.gtfs_shapes for select to authenticated using (true);

create policy gtfs_import_metadata_admin_read
on public.gtfs_import_metadata for select
to authenticated
using (public.is_admin());

-- Journey searches
create policy journey_searches_select_own_or_admin
on public.journey_searches for select
to authenticated
using (user_id = auth.uid() or public.is_admin());

create policy journey_searches_insert_own
on public.journey_searches for insert
to authenticated
with check (user_id = auth.uid());

create policy journey_searches_update_own
on public.journey_searches for update
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

create policy journey_searches_delete_own
on public.journey_searches for delete
to authenticated
using (user_id = auth.uid());

-- Feedback
create policy feedback_reports_select_own_or_admin
on public.feedback_reports for select
to authenticated
using (user_id = auth.uid() or public.is_admin());

create policy feedback_reports_insert_own
on public.feedback_reports for insert
to authenticated
with check (
  user_id = auth.uid()
  and review_status = 'submitted'::public.feedback_review_status
  and admin_notes is null
  and reviewed_by is null
  and reviewed_at is null
);

create policy feedback_reports_update_own_or_admin_review
on public.feedback_reports for update
to authenticated
using (user_id = auth.uid() or public.is_admin())
with check (user_id = auth.uid() or public.is_admin());

create policy feedback_reports_delete_own
on public.feedback_reports for delete
to authenticated
using (user_id = auth.uid());

-- Tracking sessions
create policy tracking_sessions_select_own_or_admin
on public.tracking_sessions for select
to authenticated
using (user_id = auth.uid() or public.is_admin());

create policy tracking_sessions_insert_own
on public.tracking_sessions for insert
to authenticated
with check (user_id = auth.uid());

create policy tracking_sessions_update_own
on public.tracking_sessions for update
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

create policy tracking_sessions_delete_own
on public.tracking_sessions for delete
to authenticated
using (user_id = auth.uid());

-- Vehicle positions are readable by authenticated clients and writable only by
-- trusted backend/service-role ingestion.
create policy vehicle_positions_authenticated_read
on public.vehicle_positions for select
to authenticated
using (true);

-- Admin-only analysis data
create policy analysis_reports_admin_select
on public.analysis_reports for select
to authenticated
using (public.is_admin());
create policy analysis_reports_admin_insert
on public.analysis_reports for insert
to authenticated
with check (public.is_admin() and requested_by = auth.uid());
create policy analysis_reports_admin_update
on public.analysis_reports for update
to authenticated
using (public.is_admin())
with check (public.is_admin());
create policy analysis_reports_admin_delete
on public.analysis_reports for delete
to authenticated
using (public.is_admin());

create policy ai_recommendations_admin_select
on public.ai_recommendations for select
to authenticated
using (public.is_admin());
create policy ai_recommendations_admin_insert
on public.ai_recommendations for insert
to authenticated
with check (public.is_admin());
create policy ai_recommendations_admin_update
on public.ai_recommendations for update
to authenticated
using (public.is_admin())
with check (public.is_admin());
create policy ai_recommendations_admin_delete
on public.ai_recommendations for delete
to authenticated
using (public.is_admin());

-- Explicit grants complement RLS. No credentials or service-role keys are stored.
grant usage on schema public to authenticated;
grant select, update on public.profiles to authenticated;
grant select on
  public.gtfs_agencies,
  public.gtfs_stops,
  public.gtfs_routes,
  public.gtfs_calendar,
  public.gtfs_trips,
  public.gtfs_stop_times,
  public.gtfs_shapes,
  public.gtfs_import_metadata,
  public.vehicle_positions
to authenticated;
grant select, insert, update, delete on
  public.journey_searches,
  public.feedback_reports,
  public.tracking_sessions,
  public.analysis_reports,
  public.ai_recommendations
to authenticated;
