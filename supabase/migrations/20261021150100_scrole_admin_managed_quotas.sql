-- Dynamic, admin-managed quotas for the Scrole certification and event model.
-- Applied to the active Supabase project; test functional flows in an isolated project before production rollout.

create table if not exists public.scrole_quota_settings (
  quota_key text primary key,
  value integer not null check (value >= 0),
  label text not null,
  description text not null default '',
  category text not null check (category in ('agenda', 'events', 'team', 'subscriptions')),
  min_value integer not null default 0,
  max_value integer not null default 100000,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null,
  constraint scrole_quota_settings_range_valid check (min_value >= 0 and max_value >= min_value and value between min_value and max_value)
);

alter table public.scrole_quota_settings enable row level security;
revoke all on public.scrole_quota_settings from anon, authenticated;

insert into public.scrole_quota_settings
  (quota_key, value, label, description, category, min_value, max_value)
values
  ('noncert_agenda_max_events', 2, 'Événements dans l’agenda', 'Nombre maximal d’événements distincts dans l’agenda d’un compte sans certification de profil active.', 'agenda', 0, 1000),
  ('noncert_agenda_horizon_months', 2, 'Horizon de l’agenda (mois)', 'Horizon maximal des événements ajoutés à l’agenda par un compte sans certification de profil active.', 'agenda', 1, 60),
  ('noncert_event_horizon_months', 2, 'Horizon de création d’événement (mois)', 'Délai maximal de planification d’un événement non certifié.', 'events', 1, 60),
  ('noncert_event_max_duration_days', 2, 'Durée d’un événement non certifié (jours)', 'Durée maximale en jours entre le début et la fin d’un événement non certifié.', 'events', 1, 365),
  ('noncert_event_agenda_max_people', 100, 'Ajouts à l’agenda par événement non certifié', 'Nombre maximal de personnes pouvant ajouter un événement non certifié à leur agenda.', 'events', 0, 1000000),
  ('noncert_event_max_cofounders', 1, 'Cofondateurs par événement non certifié', 'Nombre maximal de cofondateurs en plus du fondateur pour un événement non certifié.', 'team', 0, 1000),
  ('noncert_event_max_staff', 5, 'Membres du personnel par événement non certifié', 'Nombre maximal de membres du personnel pour un événement non certifié.', 'team', 0, 10000),
  ('pro_included_certified_events', 1, 'Événements certifiés inclus dans Pro', 'Nombre de certifications d’événement incluses dans Pro.', 'subscriptions', 0, 1000),
  ('pro_included_certified_communities', 1, 'Communautés certifiées incluses dans Pro', 'Nombre de certifications de communauté incluses dans Pro.', 'subscriptions', 0, 1000),
  ('premium_included_certified_events', 4, 'Événements certifiés inclus dans Premium', 'Nombre de certifications d’événement incluses dans Premium.', 'subscriptions', 0, 1000),
  ('premium_included_certified_communities', 4, 'Communautés certifiées incluses dans Premium', 'Nombre de certifications de communauté incluses dans Premium.', 'subscriptions', 0, 1000)
on conflict (quota_key) do nothing;

create or replace function public.scrole_subscription_quotas(p_plan_code text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_events integer;
  v_communities integer;
begin
  if p_plan_code not in ('pro', 'premium') then
    raise exception 'invalid_subscription_plan' using errcode = '22023';
  end if;

  select value into v_events
  from public.scrole_quota_settings
  where quota_key = p_plan_code || '_included_certified_events';

  select value into v_communities
  from public.scrole_quota_settings
  where quota_key = p_plan_code || '_included_certified_communities';

  if v_events is null or v_communities is null then
    raise exception 'subscription_quotas_not_configured' using errcode = '55000';
  end if;

  return jsonb_build_object('events', v_events, 'communities', v_communities);
end;
$$;

revoke all on function public.scrole_subscription_quotas(text) from public, anon;
grant execute on function public.scrole_subscription_quotas(text) to authenticated;

create or replace function public.admin_get_scrole_quotas()
returns table (
  quota_key text,
  value integer,
  label text,
  description text,
  category text,
  min_value integer,
  max_value integer,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'authentication_required' using errcode = '28000';
  end if;
  if not public.is_super_admin()
     and not exists (
       select 1 from public.admin_permissions_for_current_user() p
       where p.permission = 'certifications.manage'
     ) then
    raise exception 'quota_management_forbidden' using errcode = '42501';
  end if;

  return query
  select q.quota_key, q.value, q.label, q.description, q.category,
         q.min_value, q.max_value, q.updated_at
  from public.scrole_quota_settings q
  order by case q.category when 'agenda' then 1 when 'events' then 2 when 'team' then 3 else 4 end,
           q.label;
end;
$$;

create or replace function public.admin_update_scrole_quota(
  p_quota_key text,
  p_value integer
)
returns public.scrole_quota_settings
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_before public.scrole_quota_settings%rowtype;
  v_after public.scrole_quota_settings%rowtype;
begin
  if v_actor is null then
    raise exception 'authentication_required' using errcode = '28000';
  end if;
  if not public.is_super_admin()
     and not exists (
       select 1 from public.admin_permissions_for_current_user() p
       where p.permission = 'certifications.manage'
     ) then
    raise exception 'quota_management_forbidden' using errcode = '42501';
  end if;
  if p_quota_key is null or p_value is null then
    raise exception 'quota_key_and_value_required' using errcode = '22023';
  end if;

  select * into v_before
  from public.scrole_quota_settings
  where quota_key = p_quota_key
  for update;

  if not found then
    raise exception 'unknown_quota_key' using errcode = '22023';
  end if;
  if p_value < v_before.min_value or p_value > v_before.max_value then
    raise exception 'quota_value_out_of_range' using errcode = '22023',
      detail = format('Valeur autorisée : %s à %s.', v_before.min_value, v_before.max_value);
  end if;

  update public.scrole_quota_settings
  set value = p_value, updated_at = now(), updated_by = v_actor
  where quota_key = p_quota_key
  returning * into v_after;

  insert into public.scrole_certification_audit(
    actor_user_id, entity_type, entity_id, action, previous_status, new_status, details
  ) values (
    v_actor, 'subscription', null, 'quota_updated',
    v_before.value::text, v_after.value::text,
    jsonb_build_object('quota_key', p_quota_key, 'label', v_after.label,
      'previous_value', v_before.value, 'new_value', v_after.value)
  );

  return v_after;
end;
$$;

revoke all on function public.admin_get_scrole_quotas() from public, anon;
revoke all on function public.admin_update_scrole_quota(text, integer) from public, anon;
grant execute on function public.admin_get_scrole_quotas() to authenticated;
grant execute on function public.admin_update_scrole_quota(text, integer) to authenticated;

-- Safe read-only subset for mobile clients to present the current limits in forms.
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
    'noncert_event_agenda_max_people', (select value from public.scrole_quota_settings where quota_key = 'noncert_event_agenda_max_people')
  );
$$;

revoke all on function public.get_scrole_public_quota_settings() from public;
grant execute on function public.get_scrole_public_quota_settings() to anon, authenticated;

-- Event-specific limits are enforced server-side, including updates that bypass the UI.
create or replace function public.scrole_enforce_event_quota_limits()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_certified boolean := false;
  v_horizon integer;
  v_max_days integer;
begin
  select exists (
    select 1 from public.event_certifications ec
    where ec.event_id = new.id and ec.status = 'active'
      and (ec.valid_until is null or ec.valid_until > now())
  ) or exists (
    select 1 from public.community_certifications cc
    where cc.community_id = new.community_id and cc.status = 'active'
      and (cc.valid_until is null or cc.valid_until > now())
  ) into v_certified;

  if v_certified then
    return new;
  end if;

  select value into v_horizon from public.scrole_quota_settings
  where quota_key = 'noncert_event_horizon_months';
  select value into v_max_days from public.scrole_quota_settings
  where quota_key = 'noncert_event_max_duration_days';

  if new.starts_at is not null and new.starts_at > now() + make_interval(months => coalesce(v_horizon, 2)) then
    raise exception 'noncertified_event_horizon_exceeded'
      using errcode = '22023',
      detail = format('Un événement non certifié doit commencer dans les %s prochains mois.', coalesce(v_horizon, 2));
  end if;

  if new.ends_at is not null and new.starts_at is not null
     and (new.ends_at::date - new.starts_at::date) > coalesce(v_max_days, 2) then
    raise exception 'noncertified_event_duration_exceeded'
      using errcode = '22023',
      detail = format('Un événement non certifié ne peut pas dépasser %s jours.', coalesce(v_max_days, 2));
  end if;

  return new;
end;
$$;

drop trigger if exists scrole_event_quota_limits on public.events;
create trigger scrole_event_quota_limits
before insert or update of starts_at, ends_at, community_id on public.events
for each row execute function public.scrole_enforce_event_quota_limits();

-- Agenda limits apply centrally to every insert path, not only a particular RPC.
create or replace function public.scrole_enforce_calendar_quota_limits()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_start timestamptz;
  v_is_profile_certified boolean;
  v_is_event_certified boolean;
  v_count integer;
  v_limit integer;
  v_horizon integer;
  v_event_people_limit integer;
begin
  if new.user_id is null then
    raise exception 'agenda_user_required' using errcode = '22023';
  end if;

  select e.starts_at into v_start
  from public.events e where e.id = new.event_id;
  if not found then
    raise exception 'event_not_found' using errcode = 'P0002';
  end if;

  select exists (
    select 1 from public.user_certifications uc
    where uc.user_id = new.user_id
      and uc.status::text = 'active'
      and uc.issued_at <= now()
      and (uc.expires_at is null or uc.expires_at > now())
  ) into v_is_profile_certified;

  select exists (
    select 1 from public.event_certifications ec
    where ec.event_id = new.event_id and ec.status = 'active'
      and (ec.valid_until is null or ec.valid_until > now())
  ) or exists (
    select 1 from public.events e
    join public.community_certifications cc on cc.community_id = e.community_id
    where e.id = new.event_id and cc.status = 'active'
      and (cc.valid_until is null or cc.valid_until > now())
  ) into v_is_event_certified;

  if not v_is_profile_certified then
    select value into v_limit from public.scrole_quota_settings where quota_key = 'noncert_agenda_max_events';
    select value into v_horizon from public.scrole_quota_settings where quota_key = 'noncert_agenda_horizon_months';

    select count(*) into v_count from public.event_calendar ec
    where ec.user_id = new.user_id and ec.event_id <> new.event_id;

    if v_count >= coalesce(v_limit, 2) then
      raise exception 'agenda_event_quota_exceeded'
        using errcode = '22023',
        detail = format('Votre agenda est limité à %s événements sans certification active.', coalesce(v_limit, 2));
    end if;

    if v_start > now() + make_interval(months => coalesce(v_horizon, 2)) then
      raise exception 'agenda_horizon_exceeded'
        using errcode = '22023',
        detail = format('Vous pouvez ajouter un événement situé dans les %s prochains mois.', coalesce(v_horizon, 2));
    end if;
  end if;

  if not v_is_event_certified then
    select value into v_event_people_limit from public.scrole_quota_settings
    where quota_key = 'noncert_event_agenda_max_people';
    select count(*) into v_count from public.event_calendar ec
    where ec.event_id = new.event_id and ec.user_id <> new.user_id;

    if v_count >= coalesce(v_event_people_limit, 100) then
      raise exception 'event_agenda_people_quota_exceeded'
        using errcode = '22023',
        detail = format('Cet événement non certifié a atteint sa limite de %s personnes.', coalesce(v_event_people_limit, 100));
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists scrole_calendar_quota_limits on public.event_calendar;
create trigger scrole_calendar_quota_limits
before insert on public.event_calendar
for each row execute function public.scrole_enforce_calendar_quota_limits();

-- Selected participation dates are subject to the same configurable horizon.
create or replace function public.scrole_enforce_calendar_day_horizon()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_is_profile_certified boolean;
  v_horizon integer;
begin
  select exists (
    select 1 from public.user_certifications uc
    where uc.user_id = new.user_id
      and uc.status::text = 'active'
      and uc.issued_at <= now()
      and (uc.expires_at is null or uc.expires_at > now())
  ) into v_is_profile_certified;

  if not v_is_profile_certified then
    select value into v_horizon
    from public.scrole_quota_settings
    where quota_key = 'noncert_agenda_horizon_months';

    if new.event_date > (now() + make_interval(months => coalesce(v_horizon, 2)))::date then
      raise exception 'agenda_selected_day_horizon_exceeded'
        using errcode = '22023',
        detail = format('Les jours de participation doivent être dans les %s prochains mois.', coalesce(v_horizon, 2));
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists scrole_calendar_day_horizon on public.event_calendar_days;
create trigger scrole_calendar_day_horizon
before insert or update of event_date on public.event_calendar_days
for each row execute function public.scrole_enforce_calendar_day_horizon();

create or replace function public.scrole_enforce_event_team_quota_limits()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_certified boolean := false;
  v_limit integer;
  v_count integer;
begin
  select exists (
    select 1 from public.event_certifications ec
    where ec.event_id = new.event_id and ec.status = 'active'
      and (ec.valid_until is null or ec.valid_until > now())
  ) into v_certified;

  if v_certified then
    return new;
  end if;

  if tg_table_name = 'event_co_creators' then
    select value into v_limit from public.scrole_quota_settings where quota_key = 'noncert_event_max_cofounders';
    select count(*) into v_count from public.event_co_creators x
    where x.event_id = new.event_id
      and x.status::text in ('en_attente', 'acceptee', 'accepted', 'acceptee')
      and (tg_op = 'INSERT' or x.id <> new.id);
    if v_count >= coalesce(v_limit, 1) then
      raise exception 'noncertified_event_cofounder_quota_exceeded'
        using errcode = '22023',
        detail = format('Un événement non certifié est limité à %s cofondateur(s).', coalesce(v_limit, 1));
    end if;
  elsif tg_table_name = 'event_staff' then
    select value into v_limit from public.scrole_quota_settings where quota_key = 'noncert_event_max_staff';
    select count(*) into v_count from public.event_staff x
    where x.event_id = new.event_id
      and x.status::text in ('en_attente', 'acceptee', 'accepted', 'acceptee')
      and (tg_op = 'INSERT' or x.id <> new.id);
    if v_count >= coalesce(v_limit, 5) then
      raise exception 'noncertified_event_staff_quota_exceeded'
        using errcode = '22023',
        detail = format('Un événement non certifié est limité à %s membres du personnel.', coalesce(v_limit, 5));
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists scrole_cofounder_quota_limits on public.event_co_creators;
create trigger scrole_cofounder_quota_limits
before insert or update of status on public.event_co_creators
for each row execute function public.scrole_enforce_event_team_quota_limits();

drop trigger if exists scrole_staff_quota_limits on public.event_staff;
create trigger scrole_staff_quota_limits
before insert or update of status on public.event_staff
for each row execute function public.scrole_enforce_event_team_quota_limits();

revoke all on function public.scrole_enforce_event_quota_limits() from public, anon, authenticated;
revoke all on function public.scrole_enforce_calendar_quota_limits() from public, anon, authenticated;
revoke all on function public.scrole_enforce_calendar_day_horizon() from public, anon, authenticated;
revoke all on function public.scrole_enforce_event_team_quota_limits() from public, anon, authenticated;
