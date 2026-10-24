-- User profile reporting from the external profile screen.
create table if not exists public.user_profile_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_user_id uuid not null references auth.users(id) on delete cascade,
  reported_user_id uuid not null references auth.users(id) on delete cascade,
  reason text not null check (reason in ('spam', 'fake_profile', 'harassment', 'inappropriate', 'other')),
  details text,
  status text not null default 'pending' check (status in ('pending', 'reviewing', 'resolved', 'dismissed')),
  created_at timestamptz not null default now(),
  constraint user_profile_reports_not_self check (reporter_user_id <> reported_user_id)
);

create index if not exists idx_user_profile_reports_status_created
  on public.user_profile_reports (status, created_at desc);
create index if not exists idx_user_profile_reports_reported_user
  on public.user_profile_reports (reported_user_id, created_at desc);

alter table public.user_profile_reports enable row level security;
revoke all on public.user_profile_reports from anon, authenticated;

create or replace function public.report_user_profile(
  p_reported_user_id uuid,
  p_reason text,
  p_details text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_reporter_id uuid := auth.uid();
  v_report_id uuid;
begin
  if v_reporter_id is null then
    raise exception 'authentication_required' using errcode = '28000';
  end if;
  if p_reported_user_id is null or p_reported_user_id = v_reporter_id then
    raise exception 'invalid_report_target' using errcode = '22023';
  end if;
  if p_reason not in ('spam', 'fake_profile', 'harassment', 'inappropriate', 'other') then
    raise exception 'invalid_report_reason' using errcode = '22023';
  end if;
  if not exists (select 1 from auth.users where id = p_reported_user_id) then
    raise exception 'reported_user_not_found' using errcode = '22023';
  end if;

  insert into public.user_profile_reports (
    reporter_user_id, reported_user_id, reason, details
  ) values (
    v_reporter_id,
    p_reported_user_id,
    p_reason,
    nullif(left(trim(coalesce(p_details, '')), 2000), '')
  )
  returning id into v_report_id;

  return v_report_id;
end;
$$;

revoke all on function public.report_user_profile(uuid, text, text) from public, anon;
grant execute on function public.report_user_profile(uuid, text, text) to authenticated;
