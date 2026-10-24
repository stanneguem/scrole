-- Remove the retired group-chat quota from the public quota payload.
-- Keep all non-group quota fields consumed by the mobile client.
create or replace function public.get_scrole_public_quota_settings()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'noncert_agenda_max_events', (select value from public.scrole_quota_settings where quota_key = 'noncert_agenda_max_events'),
    'noncert_agenda_horizon_months', (select value from public.scrole_quota_settings where quota_key = 'noncert_agenda_horizon_months'),
    'noncert_event_horizon_months', (select value from public.scrole_quota_settings where quota_key = 'noncert_event_horizon_months'),
    'noncert_event_max_duration_days', (select value from public.scrole_quota_settings where quota_key = 'noncert_event_max_duration_days'),
    'noncert_event_agenda_max_people', (select value from public.scrole_quota_settings where quota_key = 'noncert_event_agenda_max_people'),
    'certified_event_horizon_months', (select value from public.scrole_quota_settings where quota_key = 'certified_event_horizon_months')
  );
$$;

revoke all on function public.get_scrole_public_quota_settings() from public;
grant execute on function public.get_scrole_public_quota_settings() to anon, authenticated;
