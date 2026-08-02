-- Controlled profile-role administration
--
-- Direct role updates remain blocked by profiles_protect_columns. Role changes must
-- go through one of the SECURITY DEFINER functions below from a trusted PostgreSQL
-- administration session, such as the Supabase SQL Editor running as postgres.
-- These functions must never be granted to anon/authenticated/service_role or called
-- from Flutter. The mobile application needs only the publishable key and RLS.

-- The guard is SECURITY INVOKER so that an UPDATE issued inside one of the controlled
-- SECURITY DEFINER functions retains that function's effective postgres role. A
-- transaction-local marker distinguishes the narrowly scoped function update from an
-- ordinary direct UPDATE. An untrusted client can set the same custom setting, but it
-- cannot become current_user postgres, so the marker alone cannot bypass protection.
create or replace function public.protect_profile_columns()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog
as $$
declare
  trusted_role_operation boolean :=
    current_user = 'postgres'
    and pg_catalog.current_setting(
      'government_transit_collector.role_admin_operation',
      true
    ) = 'allowed';
begin
  if new.user_id is distinct from old.user_id
     or new.created_at is distinct from old.created_at then
    raise exception 'Protected profile identity columns cannot be changed';
  end if;

  if new.role is distinct from old.role and not trusted_role_operation then
    raise exception 'Profile roles must be changed through a controlled administrative function';
  end if;

  return new;
end;
$$;

comment on function public.protect_profile_columns() is
  'Blocks profile identity changes and permits role changes only from controlled postgres-owned administrative functions.';

-- Trigger functions do not need to be callable through PostgREST. Revoking direct
-- execution does not prevent the existing profiles_protect_columns trigger from
-- invoking this function.
revoke all on function public.protect_profile_columns()
from public, anon, authenticated, service_role;

-- Promote exactly one existing profile. The function changes only profiles.role;
-- normal RLS and trigger protection remain unchanged for every client operation.
create or replace function public.promote_user_to_admin(target_user_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  affected_rows integer;
begin
  perform pg_catalog.set_config(
    'government_transit_collector.role_admin_operation',
    'allowed',
    true
  );

  update public.profiles
  set role = 'admin'::public.app_role
  where user_id = target_user_id;

  get diagnostics affected_rows = row_count;

  perform pg_catalog.set_config(
    'government_transit_collector.role_admin_operation',
    'blocked',
    true
  );

  if affected_rows = 0 then
    raise exception 'No profile exists for user ID %', target_user_id;
  end if;
exception
  when others then
    perform pg_catalog.set_config(
      'government_transit_collector.role_admin_operation',
      'blocked',
      true
    );
    raise;
end;
$$;

alter function public.promote_user_to_admin(uuid) owner to postgres;

comment on function public.promote_user_to_admin(uuid) is
  'SQL Editor administration only: promotes an existing profile to admin. Never expose or call from Flutter.';

revoke all on function public.promote_user_to_admin(uuid)
from public, anon, authenticated, service_role;
grant execute on function public.promote_user_to_admin(uuid) to postgres;

-- Demote exactly one existing profile using the same restricted mechanism.
create or replace function public.demote_admin_to_passenger(target_user_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  affected_rows integer;
begin
  perform pg_catalog.set_config(
    'government_transit_collector.role_admin_operation',
    'allowed',
    true
  );

  update public.profiles
  set role = 'passenger'::public.app_role
  where user_id = target_user_id;

  get diagnostics affected_rows = row_count;

  perform pg_catalog.set_config(
    'government_transit_collector.role_admin_operation',
    'blocked',
    true
  );

  if affected_rows = 0 then
    raise exception 'No profile exists for user ID %', target_user_id;
  end if;
exception
  when others then
    perform pg_catalog.set_config(
      'government_transit_collector.role_admin_operation',
      'blocked',
      true
    );
    raise;
end;
$$;

alter function public.demote_admin_to_passenger(uuid) owner to postgres;

comment on function public.demote_admin_to_passenger(uuid) is
  'SQL Editor administration only: demotes an existing admin profile to passenger. Never expose or call from Flutter.';

revoke all on function public.demote_admin_to_passenger(uuid)
from public, anon, authenticated, service_role;
grant execute on function public.demote_admin_to_passenger(uuid) to postgres;

-- After applying this migration, call from the Supabase SQL Editor as postgres:
--   select public.promote_user_to_admin('00000000-0000-0000-0000-000000000000'::uuid);
-- To reverse the change:
--   select public.demote_admin_to_passenger('00000000-0000-0000-0000-000000000000'::uuid);

