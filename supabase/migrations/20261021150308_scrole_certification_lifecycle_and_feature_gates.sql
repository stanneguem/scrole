-- Follow-up hardening for Scrole certification entitlements and configurable quotas.
-- Additive/corrective migration. Existing user data is not deleted.

-- A certified community does not automatically certify every linked event.
create or replace function public.scrole_enforce_event_quota_limits()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_certified boolean := false;
  v_horizon integer;
  v_max_days integer;
begin
  select exists (
    select 1 from public.event_certifications ec
    where ec.event_id = new.id and ec.status = 'active'
      and (ec.valid_until is null or ec.valid_until > now())
  ) into v_certified;

  if v_certified then
    return new;
  end if;

  select value into v_horizon from public.scrole_quota_settings
  where quota_key = 'noncert_event_horizon_months';
  select value into v_max_days from public.scrole_quota_settings
  where quota_key = 'noncert_event_max_duration_days';

  if new.starts_at is not null
     and new.starts_at > now() + make_interval(months => coalesce(v_horizon, 2)) then
    raise exception 'noncertified_event_horizon_exceeded'
      using errcode = '22023',
      detail = format('Un événement non certifié doit commencer dans les %s prochains mois.', coalesce(v_horizon, 2));
  end if;

  if new.ends_at is not null and new.starts_at is not null
     and new.ends_at - new.starts_at > make_interval(days => coalesce(v_max_days, 2)) then
    raise exception 'noncertified_event_duration_exceeded'
      using errcode = '22023',
      detail = format('Un événement non certifié ne peut pas dépasser %s jours.', coalesce(v_max_days, 2));
  end if;

  return new;
end;
$function$;

create or replace function public.scrole_enforce_calendar_quota_limits()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
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
  ) into v_is_event_certified;

  if not v_is_profile_certified then
    select value into v_limit from public.scrole_quota_settings
    where quota_key = 'noncert_agenda_max_events';
    select value into v_horizon from public.scrole_quota_settings
    where quota_key = 'noncert_agenda_horizon_months';

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
$function$;

create or replace function public.scrole_enforce_event_team_quota_limits()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
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
      and x.status in ('en_attente', 'acceptee', 'accepted')
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
      and x.status in ('en_attente', 'acceptee', 'accepted')
      and (tg_op = 'INSERT' or x.id <> new.id);
    if v_count >= coalesce(v_limit, 5) then
      raise exception 'noncertified_event_staff_quota_exceeded'
        using errcode = '22023',
        detail = format('Un événement non certifié est limité à %s membres du personnel.', coalesce(v_limit, 5));
    end if;
  end if;

  return new;
end;
$function$;

-- Guests, sponsors and ticketing are only available for an event with its own
-- active event certification. A community certification does not imply one.
create or replace function public.scrole_require_event_certification_for_management()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_event_id uuid;
begin
  v_event_id := new.event_id;
  if not exists (
    select 1 from public.event_certifications ec
    where ec.event_id = v_event_id
      and ec.status = 'active'
      and (ec.valid_until is null or ec.valid_until > now())
  ) then
    raise exception 'event_certification_required'
      using errcode = '42501',
      detail = 'La certification de cet événement est nécessaire pour les invitations Guest, les sponsors et la billetterie.';
  end if;
  return new;
end;
$function$;

drop trigger if exists scrole_guest_requires_event_certification on public.event_guest_invitations;
create trigger scrole_guest_requires_event_certification
before insert or update on public.event_guest_invitations
for each row execute function public.scrole_require_event_certification_for_management();

drop trigger if exists scrole_sponsor_requires_event_certification on public.event_sponsor_invitations;
create trigger scrole_sponsor_requires_event_certification
before insert or update on public.event_sponsor_invitations
for each row execute function public.scrole_require_event_certification_for_management();

drop trigger if exists scrole_ticket_requires_event_certification on public.event_tickets;
create trigger scrole_ticket_requires_event_certification
before insert or update on public.event_tickets
for each row execute function public.scrole_require_event_certification_for_management();

-- Event statistics require event-level certification, independent of profile/community tier.
create or replace function public.get_event_statistics(p_event_id uuid)
returns jsonb
language plpgsql
stable
set search_path = ''
as $function$
begin
  if not exists (
    select 1 from public.event_certifications ec
    where ec.event_id = p_event_id
      and ec.status = 'active'
      and (ec.valid_until is null or ec.valid_until > now())
  ) then
    raise exception 'event_certification_required_for_statistics'
      using errcode = '42501';
  end if;
  return private.get_event_statistics(p_event_id);
end;
$function$;

-- Configurable Premium -> Pro selection. The previous single-ID RPC remains
-- available for compatibility; new clients should use this array-based RPC.
create or replace function public.scrole_change_subscription_plan_v2(
  p_subscription_id uuid,
  p_new_plan text,
  p_keep_event_ids uuid[] default '{}'::uuid[],
  p_keep_community_ids uuid[] default '{}'::uuid[]
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user uuid := auth.uid();
  v_sub public.scrole_subscriptions%rowtype;
  v_event_quota integer;
  v_community_quota integer;
  v_event_count integer;
  v_community_count integer;
begin
  if v_user is null then raise exception 'authentication_required' using errcode = '28000'; end if;
  if p_new_plan is distinct from 'pro' then
    raise exception 'only_premium_to_pro_downgrade_supported' using errcode = '22023';
  end if;

  select * into v_sub from public.scrole_subscriptions
  where id = p_subscription_id and user_id = v_user for update;
  if not found then raise exception 'subscription_not_found_or_not_owned' using errcode = '42501'; end if;
  if v_sub.status <> 'active' or v_sub.plan_code <> 'premium' then
    raise exception 'active_premium_subscription_required' using errcode = '22023';
  end if;

  select value into v_event_quota from public.scrole_quota_settings where quota_key = 'pro_included_certified_events';
  select value into v_community_quota from public.scrole_quota_settings where quota_key = 'pro_included_certified_communities';

  if cardinality(coalesce(p_keep_event_ids, '{}'::uuid[])) > coalesce(v_event_quota, 1)
     or cardinality(coalesce(p_keep_community_ids, '{}'::uuid[])) > coalesce(v_community_quota, 1) then
    raise exception 'selected_certifications_exceed_current_quota' using errcode = '22023';
  end if;

  if cardinality(coalesce(p_keep_event_ids, '{}'::uuid[])) <>
       cardinality(array(select distinct x from unnest(coalesce(p_keep_event_ids, '{}'::uuid[])) x))
     or cardinality(coalesce(p_keep_community_ids, '{}'::uuid[])) <>
       cardinality(array(select distinct x from unnest(coalesce(p_keep_community_ids, '{}'::uuid[])) x)) then
    raise exception 'duplicate_certification_selection' using errcode = '22023';
  end if;

  if exists (
    select 1 from unnest(coalesce(p_keep_event_ids, '{}'::uuid[])) chosen(id)
    where not exists (
      select 1 from public.event_certifications ec join public.events e on e.id = ec.event_id
      where ec.event_id = chosen.id and e.creator_id = v_user
        and ec.subscription_id = p_subscription_id and ec.source = 'subscription_included'
        and ec.status in ('active','suspended')
    )
  ) then raise exception 'selected_event_certification_not_eligible' using errcode = '22023'; end if;

  if exists (
    select 1 from unnest(coalesce(p_keep_community_ids, '{}'::uuid[])) chosen(id)
    where not exists (
      select 1 from public.community_certifications cc join public.communities c on c.id = cc.community_id
      where cc.community_id = chosen.id and c.creator_id = v_user
        and cc.subscription_id = p_subscription_id and cc.source = 'subscription_included'
        and cc.status in ('active','suspended')
    )
  ) then raise exception 'selected_community_certification_not_eligible' using errcode = '22023'; end if;

  update public.event_certifications ec
  set status = case when ec.event_id = any(coalesce(p_keep_event_ids, '{}'::uuid[])) then 'active' else 'suspended' end,
      suspended_at = case when ec.event_id = any(coalesce(p_keep_event_ids, '{}'::uuid[])) then null else coalesce(ec.suspended_at, now()) end,
      valid_until = v_sub.ends_at, updated_at = now()
  from public.events e
  where e.id = ec.event_id and e.creator_id = v_user
    and ec.subscription_id = p_subscription_id and ec.source = 'subscription_included'
    and ec.status in ('active','suspended');

  update public.community_certifications cc
  set status = case when cc.community_id = any(coalesce(p_keep_community_ids, '{}'::uuid[])) then 'active' else 'suspended' end,
      suspended_at = case when cc.community_id = any(coalesce(p_keep_community_ids, '{}'::uuid[])) then null else coalesce(cc.suspended_at, now()) end,
      valid_until = v_sub.ends_at, updated_at = now()
  from public.communities c
  where c.id = cc.community_id and c.creator_id = v_user
    and cc.subscription_id = p_subscription_id and cc.source = 'subscription_included'
    and cc.status in ('active','suspended');

  update public.scrole_subscriptions set plan_code = 'pro', updated_at = now()
  where id = p_subscription_id;

  select count(*) into v_event_count from unnest(coalesce(p_keep_event_ids, '{}'::uuid[]));
  select count(*) into v_community_count from unnest(coalesce(p_keep_community_ids, '{}'::uuid[]));

  insert into public.scrole_certification_audit(
    actor_user_id, subscription_id, entity_type, entity_id, action, previous_status, new_status, details
  ) values (
    v_user, p_subscription_id, 'subscription', p_subscription_id, 'plan_changed',
    v_sub.plan_code, 'pro',
    jsonb_build_object('kept_event_ids', coalesce(p_keep_event_ids, '{}'::uuid[]),
      'kept_community_ids', coalesce(p_keep_community_ids, '{}'::uuid[]),
      'active_event_quota', v_event_quota, 'active_community_quota', v_community_quota)
  );

  return jsonb_build_object('subscription_id', p_subscription_id, 'previous_plan', v_sub.plan_code,
    'new_plan', 'pro', 'kept_event_ids', coalesce(p_keep_event_ids, '{}'::uuid[]),
    'kept_community_ids', coalesce(p_keep_community_ids, '{}'::uuid[]));
end;
$function$;

create or replace function public.scrole_change_subscription_plan(
  p_subscription_id uuid,
  p_new_plan text,
  p_keep_event_id uuid default null,
  p_keep_community_id uuid default null
)
returns jsonb
language sql
security definer
set search_path = ''
as $function$
  select public.scrole_change_subscription_plan_v2(
    p_subscription_id, p_new_plan,
    case when p_keep_event_id is null then '{}'::uuid[] else array[p_keep_event_id] end,
    case when p_keep_community_id is null then '{}'::uuid[] else array[p_keep_community_id] end
  );
$function$;

-- Trusted payment backend calls this only after it has verified a successful renewal.
create or replace function public.scrole_renew_subscription(
  p_subscription_id uuid,
  p_new_ends_at timestamptz,
  p_keep_event_ids uuid[] default '{}'::uuid[],
  p_keep_community_ids uuid[] default '{}'::uuid[]
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_sub public.scrole_subscriptions%rowtype;
  v_event_quota integer;
  v_community_quota integer;
begin
  if p_new_ends_at is null or p_new_ends_at <= now() then
    raise exception 'invalid_subscription_end_date' using errcode = '22023';
  end if;

  select * into v_sub from public.scrole_subscriptions
  where id = p_subscription_id for update;
  if not found then raise exception 'subscription_not_found' using errcode = 'P0002'; end if;

  select value into v_event_quota from public.scrole_quota_settings
  where quota_key = v_sub.plan_code || '_included_certified_events';
  select value into v_community_quota from public.scrole_quota_settings
  where quota_key = v_sub.plan_code || '_included_certified_communities';

  if cardinality(coalesce(p_keep_event_ids, '{}'::uuid[])) > coalesce(v_event_quota, 0)
     or cardinality(coalesce(p_keep_community_ids, '{}'::uuid[])) > coalesce(v_community_quota, 0) then
    raise exception 'selected_certifications_exceed_current_quota' using errcode = '22023';
  end if;

  if exists (
    select 1 from unnest(coalesce(p_keep_event_ids, '{}'::uuid[])) chosen(id)
    where not exists (
      select 1 from public.event_certifications ec join public.events e on e.id = ec.event_id
      where ec.event_id = chosen.id and e.creator_id = v_sub.user_id
        and ec.subscription_id = p_subscription_id and ec.source = 'subscription_included'
        and ec.status in ('active','suspended')
    )
  ) then raise exception 'selected_event_certification_not_eligible' using errcode = '22023'; end if;

  if exists (
    select 1 from unnest(coalesce(p_keep_community_ids, '{}'::uuid[])) chosen(id)
    where not exists (
      select 1 from public.community_certifications cc join public.communities c on c.id = cc.community_id
      where cc.community_id = chosen.id and c.creator_id = v_sub.user_id
        and cc.subscription_id = p_subscription_id and cc.source = 'subscription_included'
        and cc.status in ('active','suspended')
    )
  ) then raise exception 'selected_community_certification_not_eligible' using errcode = '22023'; end if;

  update public.scrole_subscriptions
  set status = 'active', starts_at = coalesce(starts_at, now()), ends_at = p_new_ends_at, updated_at = now()
  where id = p_subscription_id;

  update public.event_certifications ec
  set status = case when ec.event_id = any(coalesce(p_keep_event_ids, '{}'::uuid[])) then 'active' else 'suspended' end,
      suspended_at = case when ec.event_id = any(coalesce(p_keep_event_ids, '{}'::uuid[])) then null else coalesce(ec.suspended_at, now()) end,
      valid_until = p_new_ends_at, updated_at = now()
  where ec.subscription_id = p_subscription_id and ec.source = 'subscription_included'
    and ec.status in ('active','suspended');

  update public.community_certifications cc
  set status = case when cc.community_id = any(coalesce(p_keep_community_ids, '{}'::uuid[])) then 'active' else 'suspended' end,
      suspended_at = case when cc.community_id = any(coalesce(p_keep_community_ids, '{}'::uuid[])) then null else coalesce(cc.suspended_at, now()) end,
      valid_until = p_new_ends_at, updated_at = now()
  where cc.subscription_id = p_subscription_id and cc.source = 'subscription_included'
    and cc.status in ('active','suspended');

  insert into public.scrole_certification_audit(
    actor_user_id, subscription_id, entity_type, entity_id, action, previous_status, new_status, details
  ) values (
    null, p_subscription_id, 'subscription', p_subscription_id, 'subscription_renewed',
    v_sub.status, 'active',
    jsonb_build_object('previous_ends_at', v_sub.ends_at, 'new_ends_at', p_new_ends_at,
      'kept_event_ids', coalesce(p_keep_event_ids, '{}'::uuid[]),
      'kept_community_ids', coalesce(p_keep_community_ids, '{}'::uuid[]))
  );

  return jsonb_build_object('subscription_id', p_subscription_id, 'status', 'active',
    'ends_at', p_new_ends_at, 'plan_code', v_sub.plan_code);
end;
$function$;

revoke all on function public.scrole_change_subscription_plan_v2(uuid, text, uuid[], uuid[]) from public, anon;
grant execute on function public.scrole_change_subscription_plan_v2(uuid, text, uuid[], uuid[]) to authenticated;
revoke all on function public.scrole_renew_subscription(uuid, timestamptz, uuid[], uuid[]) from public, anon, authenticated;
grant execute on function public.scrole_renew_subscription(uuid, timestamptz, uuid[], uuid[]) to service_role;

revoke all on function public.scrole_require_event_certification_for_management() from public, anon, authenticated;
