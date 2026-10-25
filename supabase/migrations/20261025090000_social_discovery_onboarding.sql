-- Persist the social-discovery onboarding independently from interest/role prompts.
alter table public.user_onboarding
  add column if not exists social_discovery_started_at timestamptz,
  add column if not exists social_discovery_completed_at timestamptz;

create or replace function public.start_social_discovery_onboarding()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_row public.user_onboarding;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;

  insert into public.user_onboarding (user_id)
  values (v_uid)
  on conflict (user_id) do nothing;

  update public.user_onboarding
     set social_discovery_started_at = coalesce(social_discovery_started_at, now()),
         updated_at = now()
   where user_id = v_uid
   returning * into v_row;

  return jsonb_build_object(
    'started', v_row.social_discovery_started_at is not null,
    'completed', v_row.social_discovery_completed_at is not null
  );
end;
$$;

create or replace function public.get_social_discovery_onboarding_state()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_row public.user_onboarding;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;

  select * into v_row
    from public.user_onboarding
   where user_id = v_uid;

  return jsonb_build_object(
    'started', coalesce(v_row.social_discovery_started_at is not null, false),
    'completed', coalesce(v_row.social_discovery_completed_at is not null, false)
  );
end;
$$;

create or replace function public.complete_social_discovery_onboarding()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_row public.user_onboarding;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;

  insert into public.user_onboarding (user_id)
  values (v_uid)
  on conflict (user_id) do nothing;

  update public.user_onboarding
     set social_discovery_started_at = coalesce(social_discovery_started_at, now()),
         social_discovery_completed_at = coalesce(social_discovery_completed_at, now()),
         updated_at = now()
   where user_id = v_uid
   returning * into v_row;

  return jsonb_build_object('started', true, 'completed', true);
end;
$$;

revoke all on function public.start_social_discovery_onboarding() from public;
revoke all on function public.get_social_discovery_onboarding_state() from public;
revoke all on function public.complete_social_discovery_onboarding() from public;
grant execute on function public.start_social_discovery_onboarding() to authenticated;
grant execute on function public.get_social_discovery_onboarding_state() to authenticated;
grant execute on function public.complete_social_discovery_onboarding() to authenticated;
