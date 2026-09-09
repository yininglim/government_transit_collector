-- Saved snapshots from the administrator's operational-analysis features.
-- This table is intentionally separate from analysis_reports and
-- ai_recommendations, which belong to the generic/AI analysis workflow.

create type public.saved_operational_report_type as enum (
  'route_performance',
  'peak_operation'
);

create type public.saved_operational_report_status as enum (
  'draft',
  'reviewed',
  'needs_attention',
  'resolved'
);

create table public.saved_operational_reports (
  report_id uuid primary key default gen_random_uuid(),
  admin_id uuid not null references public.profiles(user_id) on delete restrict,
  report_type public.saved_operational_report_type not null,
  route_id text references public.gtfs_routes(route_id) on delete set null,
  route_name_snapshot text not null,
  period_start timestamptz not null,
  period_end timestamptz not null,
  title text not null,
  result_snapshot jsonb not null,
  admin_notes text,
  status public.saved_operational_report_status not null default 'draft',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint saved_operational_reports_period_valid check (
    period_end > period_start
  ),
  constraint saved_operational_reports_title_present check (
    length(btrim(title)) > 0
  ),
  constraint saved_operational_reports_route_name_present check (
    length(btrim(route_name_snapshot)) > 0
  ),
  constraint saved_operational_reports_snapshot_object check (
    jsonb_typeof(result_snapshot) = 'object'
  )
);

comment on table public.saved_operational_reports is
  'Admin-managed immutable snapshots from Route Performance and Peak Operation analyses; never an input to analysis or AI calculations.';
comment on column public.saved_operational_reports.route_name_snapshot is
  'Display label preserved at save time, including the All Routes scope for a network-wide Peak Operation report.';
comment on column public.saved_operational_reports.result_snapshot is
  'Immutable JSON object containing the exact calculated result and coverage context displayed when the report was saved.';

create trigger saved_operational_reports_set_updated_at
before update on public.saved_operational_reports
for each row execute function public.set_updated_at();

-- Only management metadata may be edited. ON DELETE SET NULL on route_id must
-- remain possible so deleting an obsolete GTFS route does not delete or block its
-- historical reports. A direct route_id edit is rejected while the old route exists.
create or replace function public.protect_saved_operational_report_snapshot()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'INSERT' then
    if new.report_type =
          'route_performance'::public.saved_operational_report_type
       and new.route_id is null then
      raise exception 'Route Performance reports require a route';
    end if;
    return new;
  end if;

  if new.report_id is distinct from old.report_id
     or new.admin_id is distinct from old.admin_id
     or new.report_type is distinct from old.report_type
     or new.route_name_snapshot is distinct from old.route_name_snapshot
     or new.period_start is distinct from old.period_start
     or new.period_end is distinct from old.period_end
     or new.result_snapshot is distinct from old.result_snapshot
     or new.created_at is distinct from old.created_at then
    raise exception 'Saved operational report snapshot fields cannot be changed';
  end if;

  if new.route_id is distinct from old.route_id
     and not (
       new.route_id is null
       and old.route_id is not null
       and not exists (
         select 1
         from public.gtfs_routes
         where route_id = old.route_id
       )
     ) then
    raise exception 'Saved operational report route cannot be changed';
  end if;

  return new;
end;
$$;

comment on function public.protect_saved_operational_report_snapshot() is
  'Allows title, admin_notes, status, and automatic updated_at changes while protecting saved analysis snapshot fields.';

revoke all on function public.protect_saved_operational_report_snapshot()
from public, anon, authenticated, service_role;

create trigger saved_operational_reports_protect_snapshot
before insert or update on public.saved_operational_reports
for each row execute function public.protect_saved_operational_report_snapshot();

create index saved_operational_reports_type_created_idx
  on public.saved_operational_reports (report_type, created_at desc);
create index saved_operational_reports_status_created_idx
  on public.saved_operational_reports (status, created_at desc);
create index saved_operational_reports_route_created_idx
  on public.saved_operational_reports (route_id, created_at desc)
  where route_id is not null;
create index saved_operational_reports_admin_created_idx
  on public.saved_operational_reports (admin_id, created_at desc);

alter table public.saved_operational_reports enable row level security;

-- Reports are shared across administrators, matching the existing admin analysis
-- tables. Passengers fail public.is_admin() and therefore receive no row access.
create policy saved_operational_reports_admin_select
on public.saved_operational_reports for select
to authenticated
using (public.is_admin());

create policy saved_operational_reports_admin_insert
on public.saved_operational_reports for insert
to authenticated
with check (public.is_admin() and admin_id = auth.uid());

create policy saved_operational_reports_admin_update
on public.saved_operational_reports for update
to authenticated
using (public.is_admin())
with check (public.is_admin());

create policy saved_operational_reports_admin_delete
on public.saved_operational_reports for delete
to authenticated
using (public.is_admin());

grant select, insert, update, delete
on public.saved_operational_reports
to authenticated;
