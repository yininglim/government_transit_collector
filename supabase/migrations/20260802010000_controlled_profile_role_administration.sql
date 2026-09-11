
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

revoke all on function public.protect_profile_columns()
from public, anon, authenticated, service_role;

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


