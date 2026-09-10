create table public.recommendation_follow_ups (
  follow_up_id uuid primary key default gen_random_uuid(),
  recommendation_id uuid not null unique references public.ai_recommendations(recommendation_id) on delete cascade,
  action_text text not null,
  due_date date not null,
  follow_up_status text not null default 'pending',
  follow_up_notes text,
  created_by uuid not null references public.profiles(user_id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz,
  constraint recommendation_follow_ups_action_nonempty check (btrim(action_text) <> ''),
  constraint recommendation_follow_ups_status_valid check (
    follow_up_status in ('pending', 'in_progress', 'completed')
  ),
  constraint recommendation_follow_ups_completion_consistent check (
    (follow_up_status = 'completed' and completed_at is not null)
    or (follow_up_status <> 'completed' and completed_at is null)
  )
);

create index recommendation_follow_ups_due_status_idx
on public.recommendation_follow_ups (follow_up_status, due_date);

create trigger recommendation_follow_ups_set_updated_at
before update on public.recommendation_follow_ups
for each row execute function public.set_updated_at();

alter table public.recommendation_follow_ups enable row level security;

create policy recommendation_follow_ups_admin_select
on public.recommendation_follow_ups for select
to authenticated
using (public.is_admin());

create policy recommendation_follow_ups_admin_insert
on public.recommendation_follow_ups for insert
to authenticated
with check (
  public.is_admin()
  and created_by = auth.uid()
  and due_date >= current_date
  and exists (
    select 1
    from public.ai_recommendations recommendation
    where recommendation.recommendation_id = recommendation_follow_ups.recommendation_id
      and recommendation.status = 'accepted'::public.recommendation_status
  )
);

create policy recommendation_follow_ups_admin_update
on public.recommendation_follow_ups for update
to authenticated
using (public.is_admin())
with check (public.is_admin());

create policy recommendation_follow_ups_admin_delete
on public.recommendation_follow_ups for delete
to authenticated
using (public.is_admin());

grant select, insert, update, delete on public.recommendation_follow_ups to authenticated;
