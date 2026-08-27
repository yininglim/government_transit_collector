create policy bus_feedback_admin_select
on public.bus_feedback for select
to authenticated
using (public.is_admin());
