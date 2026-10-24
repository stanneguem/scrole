-- Final lifecycle wiring: configurable certified-event horizon, included grants and expiry schedule.
-- Existing records are retained; no destructive schema/data operations.

insert into public.scrole_quota_settings
  (quota_key, value, label, description, category, min_value, max_value)
values
  ('certified_event_horizon_months', 6, 'Horizon d’un événement certifié (mois)', 'Délai maximal de planification d’un événement certifié. Indépendant de la certification du profil et de la communauté.', 'events', 1, 120)
on conflict (quota_key) do nothing;

create unique index if not exists scrole_subscriptions_one_active_per_user_idx
  on public.scrole_subscriptions (user_id)
  where status = 'active';

-- Profile certifications included in Pro/Premium are tracked separately from
-- independently purchased/admin-granted profile certifications.
create table if not exists public.profile_certification_entitlements (
  id uuid primary key default gen_random_uuid(),
  user_certification_id uuid not null unique references public.user_certifications(id) on delete restrict,
  subscription_id uuid not null references public.scrole_subscriptions(id) on delete restrict,
  status text not null default 'active' check (status in ('active','suspended','expired')),
  valid_until timestamptz,
  suspended_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists profile_certification_entitlements_subscription_status_idx
  on public.profile_certification_entitlements(subscription_id,status);
alter table public.profile_certification_entitlements enable row level security;
revoke all on public.profile_certification_entitlements from anon,authenticated;

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
    select value into v_horizon from public.scrole_quota_settings
    where quota_key = 'certified_event_horizon_months';
    if new.starts_at is not null
       and new.starts_at > now() + make_interval(months => coalesce(v_horizon, 6)) then
      raise exception 'certified_event_horizon_exceeded'
        using errcode = '22023',
        detail = format('Un événement certifié doit commencer dans les %s prochains mois.', coalesce(v_horizon, 6));
    end if;
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

-- Trusted payment backend only: grants or reactivates one included certification
-- without duplicating history and enforces the current plan quota.
create or replace function public.scrole_grant_included_certification(
  p_subscription_id uuid,
  p_entity_type text,
  p_entity_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_sub public.scrole_subscriptions%rowtype;
  v_quota integer;
  v_active_count integer;
  v_existing_id uuid;
  v_status text;
  v_entity_owner uuid;
begin
  if p_entity_type not in ('event','community') or p_entity_id is null then
    raise exception 'invalid_certification_target' using errcode = '22023';
  end if;

  select * into v_sub from public.scrole_subscriptions
  where id = p_subscription_id for update;
  if not found then raise exception 'subscription_not_found' using errcode = 'P0002'; end if;
  if v_sub.status <> 'active' or v_sub.ends_at is not null and v_sub.ends_at <= now() then
    raise exception 'active_subscription_required' using errcode = '22023';
  end if;

  if p_entity_type = 'event' then
    select creator_id into v_entity_owner from public.events where id = p_entity_id;
    if not found then raise exception 'event_not_found' using errcode = 'P0002'; end if;
    if v_entity_owner <> v_sub.user_id then raise exception 'entity_not_owned_by_subscriber' using errcode = '42501'; end if;
    select value into v_quota from public.scrole_quota_settings where quota_key = v_sub.plan_code || '_included_certified_events';
    select id,status into v_existing_id,v_status from public.event_certifications
      where event_id=p_entity_id and subscription_id=p_subscription_id and source='subscription_included'
      order by created_at desc limit 1 for update;
    select count(*) into v_active_count from public.event_certifications
      where subscription_id=p_subscription_id and source='subscription_included'
        and status='active' and (valid_until is null or valid_until > now())
        and event_id <> p_entity_id;

    if v_existing_id is not null and v_status='active' and exists (select 1 from public.event_certifications where id=v_existing_id and (valid_until is null or valid_until > now())) then
      return jsonb_build_object('entity_type',p_entity_type,'entity_id',p_entity_id,'status','active','already_active',true);
    end if;
    if v_active_count >= coalesce(v_quota,0) then raise exception 'included_event_certification_quota_exceeded' using errcode = '22023'; end if;

    if v_existing_id is null then
      insert into public.event_certifications(event_id,source,status,subscription_id,valid_until)
      values(p_entity_id,'subscription_included','active',p_subscription_id,v_sub.ends_at)
      returning id into v_existing_id;
    else
      update public.event_certifications set status='active',valid_until=v_sub.ends_at,suspended_at=null,updated_at=now()
      where id=v_existing_id;
    end if;
  else
    select creator_id into v_entity_owner from public.communities where id = p_entity_id;
    if not found then raise exception 'community_not_found' using errcode = 'P0002'; end if;
    if v_entity_owner <> v_sub.user_id then raise exception 'entity_not_owned_by_subscriber' using errcode = '42501'; end if;
    select value into v_quota from public.scrole_quota_settings where quota_key = v_sub.plan_code || '_included_certified_communities';
    select id,status into v_existing_id,v_status from public.community_certifications
      where community_id=p_entity_id and subscription_id=p_subscription_id and source='subscription_included'
      order by created_at desc limit 1 for update;
    select count(*) into v_active_count from public.community_certifications
      where subscription_id=p_subscription_id and source='subscription_included'
        and status='active' and (valid_until is null or valid_until > now())
        and community_id <> p_entity_id;

    if v_existing_id is not null and v_status='active' and exists (select 1 from public.community_certifications where id=v_existing_id and (valid_until is null or valid_until > now())) then
      return jsonb_build_object('entity_type',p_entity_type,'entity_id',p_entity_id,'status','active','already_active',true);
    end if;
    if v_active_count >= coalesce(v_quota,0) then raise exception 'included_community_certification_quota_exceeded' using errcode = '22023'; end if;

    if v_existing_id is null then
      insert into public.community_certifications(community_id,source,status,subscription_id,valid_until)
      values(p_entity_id,'subscription_included','active',p_subscription_id,v_sub.ends_at)
      returning id into v_existing_id;
    else
      update public.community_certifications set status='active',valid_until=v_sub.ends_at,suspended_at=null,updated_at=now()
      where id=v_existing_id;
    end if;
  end if;

  insert into public.scrole_certification_audit(
    actor_user_id,subscription_id,entity_type,entity_id,action,new_status,details
  ) values (
    v_sub.user_id,p_subscription_id,p_entity_type,p_entity_id,'included_certification_granted','active',
    jsonb_build_object('plan_code',v_sub.plan_code,'quota',v_quota,'valid_until',v_sub.ends_at)
  );

  return jsonb_build_object('entity_type',p_entity_type,'entity_id',p_entity_id,'status','active','certification_id',v_existing_id);
end;
$function$;

revoke all on function public.scrole_grant_included_certification(uuid,text,uuid) from public, anon, authenticated;
grant execute on function public.scrole_grant_included_certification(uuid,text,uuid) to service_role;

-- Grant the profile tier included in a Pro/Premium subscription after the
-- trusted payment backend confirms activation. Existing independently granted
-- certifications are left untouched.
create or replace function public.scrole_grant_included_profile_certification(p_subscription_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_sub public.scrole_subscriptions%rowtype;
  v_type_id uuid;
  v_cert_id uuid;
  v_entitlement_id uuid;
  v_code text;
begin
  select * into v_sub from public.scrole_subscriptions
  where id=p_subscription_id for update;
  if not found then raise exception 'subscription_not_found' using errcode='P0002'; end if;
  if v_sub.status <> 'active' or (v_sub.ends_at is not null and v_sub.ends_at <= now()) then
    raise exception 'active_subscription_required' using errcode='22023';
  end if;

  select id into v_type_id from public.certification_type
  where lower(code)=v_sub.plan_code and est_actif=true
  limit 1;
  if v_type_id is null then raise exception 'profile_certification_type_not_configured' using errcode='55000'; end if;

  select pce.id, pce.user_certification_id
  into v_entitlement_id, v_cert_id
  from public.profile_certification_entitlements pce
  where pce.subscription_id=p_subscription_id
  order by pce.created_at desc limit 1 for update;

  if v_cert_id is null then
    select uc.id into v_cert_id
    from public.user_certifications uc
    where uc.user_id=v_sub.user_id and uc.certification_type_id=v_type_id
      and uc.status::text='active'
      and uc.issued_at <= now()
      and (uc.expires_at is null or uc.expires_at > now())
      and not exists (
        select 1 from public.profile_certification_entitlements pce
        where pce.user_certification_id=uc.id
      )
    order by uc.issued_at desc limit 1;
    if v_cert_id is not null then
      return jsonb_build_object('status','already_certified_independently','user_certification_id',v_cert_id);
    end if;

    v_code := upper(substr(replace(gen_random_uuid()::text,'-',''),1,12));
    insert into public.user_certifications(
      user_id,certification_type_id,status,issued_at,expires_at,certification_code
    ) values (
      v_sub.user_id,v_type_id,'active'::public.status_certification,now(),v_sub.ends_at,v_code
    ) returning id into v_cert_id;

    insert into public.profile_certification_entitlements(
      user_certification_id,subscription_id,status,valid_until
    ) values(v_cert_id,p_subscription_id,'active',v_sub.ends_at)
    returning id into v_entitlement_id;
  else
    update public.user_certifications
    set certification_type_id=v_type_id,status='active'::public.status_certification,
        issued_at=coalesce(issued_at,now()),expires_at=v_sub.ends_at
    where id=v_cert_id and user_id=v_sub.user_id;
    update public.profile_certification_entitlements
    set status='active',valid_until=v_sub.ends_at,suspended_at=null,updated_at=now()
    where id=v_entitlement_id;
  end if;

  insert into public.scrole_certification_audit(
    actor_user_id,subscription_id,entity_type,entity_id,action,new_status,details
  ) values (
    v_sub.user_id,p_subscription_id,'profile',v_sub.user_id,'included_profile_certification_granted','active',
    jsonb_build_object('user_certification_id',v_cert_id,'plan_code',v_sub.plan_code,'valid_until',v_sub.ends_at)
  );

  return jsonb_build_object('status','active','user_certification_id',v_cert_id,'entitlement_id',v_entitlement_id);
end;
$function$;

revoke all on function public.scrole_grant_included_profile_certification(uuid) from public,anon,authenticated;
grant execute on function public.scrole_grant_included_profile_certification(uuid) to service_role;

-- Keep the subscription-included profile badge in sync on plan downgrade, expiry,
-- cancellation and renewal. Independently granted profile certifications are not linked
-- to this table and therefore remain untouched.
create or replace function public.scrole_sync_included_profile_certification()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_type_id uuid;
  v_ent record;
begin
  if new.status='active' and (new.ends_at is null or new.ends_at > now()) then
    select id into v_type_id from public.certification_type
    where lower(code)=new.plan_code and est_actif=true limit 1;

    for v_ent in
      update public.profile_certification_entitlements
      set status='active',valid_until=new.ends_at,suspended_at=null,updated_at=now()
      where subscription_id=new.id and status in ('active','suspended')
      returning id,user_certification_id
    loop
      update public.user_certifications
      set status='active'::public.status_certification,
          certification_type_id=coalesce(v_type_id,certification_type_id),
          expires_at=new.ends_at
      where id=v_ent.user_certification_id;

      insert into public.scrole_certification_audit(
        actor_user_id,subscription_id,entity_type,entity_id,action,previous_status,new_status,details
      ) values (
        new.user_id,new.id,'profile',new.user_id,'included_profile_certification_reactivated',
        'suspended','active',jsonb_build_object('user_certification_id',v_ent.user_certification_id,'valid_until',new.ends_at)
      );
    end loop;
  else
    for v_ent in
      update public.profile_certification_entitlements
      set status='suspended',suspended_at=coalesce(suspended_at,now()),updated_at=now()
      where subscription_id=new.id and status='active'
      returning id,user_certification_id
    loop
      update public.user_certifications
      set expires_at=least(coalesce(expires_at,now()),now())
      where id=v_ent.user_certification_id;

      insert into public.scrole_certification_audit(
        actor_user_id,subscription_id,entity_type,entity_id,action,previous_status,new_status,details
      ) values (
        new.user_id,new.id,'profile',new.user_id,'included_profile_certification_suspended',
        'active','suspended',jsonb_build_object('user_certification_id',v_ent.user_certification_id)
      );
    end loop;
  end if;
  return new;
end;
$function$;

drop trigger if exists scrole_sync_included_profile_certification on public.scrole_subscriptions;
create trigger scrole_sync_included_profile_certification
after update of status,ends_at,plan_code on public.scrole_subscriptions
for each row execute function public.scrole_sync_included_profile_certification();

-- Expiration is processed every 15 minutes; included certifications are suspended,
-- not deleted, and every transition is recorded in the audit log.
create or replace function public.scrole_suspend_expired_subscription_certifications()
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_sub public.scrole_subscriptions%rowtype;
  v_cert record;
  v_changed integer := 0;
begin
  for v_sub in
    select * from public.scrole_subscriptions
    where status='active' and ends_at is not null and ends_at <= now()
    for update
  loop
    update public.scrole_subscriptions set status='expired',updated_at=now()
    where id=v_sub.id and status='active';
    if not found then continue; end if;

    for v_cert in
      update public.event_certifications
      set status='suspended',suspended_at=coalesce(suspended_at,now()),updated_at=now()
      where subscription_id=v_sub.id and source='subscription_included' and status='active'
      returning id,event_id
    loop
      insert into public.scrole_certification_audit(
        actor_user_id,subscription_id,entity_type,entity_id,action,previous_status,new_status,details
      ) values (v_sub.user_id,v_sub.id,'event',v_cert.event_id,'subscription_expired','active','suspended',
        jsonb_build_object('certification_id',v_cert.id));
      v_changed := v_changed + 1;
    end loop;

    for v_cert in
      update public.community_certifications
      set status='suspended',suspended_at=coalesce(suspended_at,now()),updated_at=now()
      where subscription_id=v_sub.id and source='subscription_included' and status='active'
      returning id,community_id
    loop
      insert into public.scrole_certification_audit(
        actor_user_id,subscription_id,entity_type,entity_id,action,previous_status,new_status,details
      ) values (v_sub.user_id,v_sub.id,'community',v_cert.community_id,'subscription_expired','active','suspended',
        jsonb_build_object('certification_id',v_cert.id));
      v_changed := v_changed + 1;
    end loop;

    insert into public.scrole_certification_audit(
      actor_user_id,subscription_id,entity_type,entity_id,action,previous_status,new_status,details
    ) values (v_sub.user_id,v_sub.id,'subscription',v_sub.id,'subscription_expired',v_sub.status,'expired',
      jsonb_build_object('previous_ends_at',v_sub.ends_at,'plan_code',v_sub.plan_code));
  end loop;

  return v_changed;
end;
$function$;

revoke all on function public.scrole_suspend_expired_subscription_certifications() from public, anon, authenticated;
grant execute on function public.scrole_suspend_expired_subscription_certifications() to service_role;

do $function$
begin
  if not exists (
    select 1 from cron.job where jobname = 'scrole-expire-subscription-certifications'
  ) then
    perform cron.schedule(
      'scrole-expire-subscription-certifications',
      '*/15 * * * *',
      'select public.scrole_suspend_expired_subscription_certifications();'
    );
  end if;
end;
$function$;
