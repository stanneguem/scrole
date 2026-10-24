-- Personal itinerary choices for users attending events.
create table if not exists public.event_itinerary_plans (
  user_id uuid not null references auth.users(id) on delete cascade,
  event_id uuid not null references public.events(id) on delete cascade,
  planned_date date not null,
  plan jsonb not null default '{"day_start":"09:00","day_end":"18:00","activities":[]}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint event_itinerary_plans_pkey primary key (user_id, event_id, planned_date)
);

create index if not exists event_itinerary_plans_event_date_idx
  on public.event_itinerary_plans (event_id, planned_date);

alter table public.event_itinerary_plans enable row level security;
revoke all on public.event_itinerary_plans from anon, public;
grant select, insert, update, delete on public.event_itinerary_plans to authenticated;

drop policy if exists event_itinerary_plans_select_own on public.event_itinerary_plans;
create policy event_itinerary_plans_select_own
  on public.event_itinerary_plans for select to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists event_itinerary_plans_insert_own on public.event_itinerary_plans;
create policy event_itinerary_plans_insert_own
  on public.event_itinerary_plans for insert to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists event_itinerary_plans_update_own on public.event_itinerary_plans;
create policy event_itinerary_plans_update_own
  on public.event_itinerary_plans for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

drop policy if exists event_itinerary_plans_delete_own on public.event_itinerary_plans;
create policy event_itinerary_plans_delete_own
  on public.event_itinerary_plans for delete to authenticated
  using (user_id = (select auth.uid()));
