begin;

create table public.journey_reminders (
  reminder_id integer generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  journey_key text not null check (length(journey_key) between 1 and 2000),
  route_label text not null,
  route_ids text[] not null,
  trip_ids text[] not null,
  origin_stop_id text not null,
  origin_stop_name text not null,
  destination_stop_id text not null,
  destination_stop_name text not null,
  service_date date not null,
  scheduled_departure_seconds integer not null check (scheduled_departure_seconds >= 0),
  scheduled_departure_at timestamptz not null,
  reminder_offset_minutes integer not null check (reminder_offset_minutes in (5, 10, 15, 30)),
  reminder_at timestamptz not null,
  created_at timestamptz not null default now(),
  unique (user_id, journey_key),
  check (reminder_at = scheduled_departure_at - make_interval(mins => reminder_offset_minutes)),
  check (scheduled_departure_at =
    (service_date::timestamp at time zone 'Asia/Singapore')
      + scheduled_departure_seconds * interval '1 second')
);
create index journey_reminders_upcoming on public.journey_reminders(user_id, scheduled_departure_at);
alter table public.journey_reminders enable row level security;
grant select, insert, delete on public.journey_reminders to authenticated;
grant usage, select on sequence public.journey_reminders_reminder_id_seq to authenticated;
create policy journey_reminders_select_own on public.journey_reminders
  for select to authenticated using (user_id = (select auth.uid()));
create policy journey_reminders_insert_own on public.journey_reminders
  for insert to authenticated with check (user_id = (select auth.uid()) and reminder_at > now());
create policy journey_reminders_delete_own on public.journey_reminders
  for delete to authenticated using (user_id = (select auth.uid()));
commit;
