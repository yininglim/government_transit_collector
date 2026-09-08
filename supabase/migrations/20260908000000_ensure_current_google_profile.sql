-- Existing Auth signup trigger remains the primary profile creation path.
-- Repair a missing Google profile without granting clients general INSERT access.
create or replace function public.ensure_current_google_profile()
returns void
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  caller_id uuid := auth.uid();
  metadata jsonb;
begin
  if caller_id is null then
    raise exception 'Authentication required';
  end if;

  if exists (select 1 from public.profiles where user_id = caller_id) then
    return;
  end if;

  if not exists (
    select 1 from auth.identities
    where user_id = caller_id and provider = 'google'
  ) then
    raise exception 'Google identity required';
  end if;

  select raw_user_meta_data into metadata from auth.users where id = caller_id;
  insert into public.profiles (user_id, full_name, role)
  values (
    caller_id,
    coalesce(
      case when jsonb_typeof(metadata -> 'full_name') = 'string'
        then nullif(btrim(metadata ->> 'full_name'), '') end,
      case when jsonb_typeof(metadata -> 'name') = 'string'
        then nullif(btrim(metadata ->> 'name'), '') end,
      ''
    ),
    'passenger'::public.app_role
  ) on conflict (user_id) do nothing;
end;
$$;

alter function public.ensure_current_google_profile() owner to postgres;
revoke all on function public.ensure_current_google_profile() from public, anon;
grant execute on function public.ensure_current_google_profile() to authenticated;
