-- Explicitly consume an included event certification during event creation.
-- A client cannot bypass the non-certified horizon without consuming a real quota.

create or replace function public.scrole_get_my_subscription_entitlements()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_user uuid := auth.uid();
  v_sub public.scrole_subscriptions%rowtype;
  v_quotas jsonb;
  v_event_used integer;
  v_community_used integer;
begin
  if v_user is null then raise exception 'authentication_required' using errcode='28000'; end if;

  select * into v_sub from public.scrole_subscriptions
  where user_id=v_user and status='active'
    and (ends_at is null or ends_at > now())
  order by ends_at desc nulls first limit 1;

  if not found then
    return jsonb_build_object('active',false,'plan_code',null,'event_remaining',0,'community_remaining',0);
  end if;

  v_quotas := public.scrole_subscription_quotas(v_sub.plan_code);

  select count(*) into v_event_used from public.event_certifications
  where subscription_id=v_sub.id and source='subscription_included'
    and status='active' and (valid_until is null or valid_until > now());
  select count(*) into v_community_used from public.community_certifications
  where subscription_id=v_sub.id and source='subscription_included'
    and status='active' and (valid_until is null or valid_until > now());

  return jsonb_build_object(
    'active',true,
    'subscription_id',v_sub.id,
    'plan_code',v_sub.plan_code,
    'ends_at',v_sub.ends_at,
    'event_quota',(v_quotas->>'events')::integer,
    'event_used',v_event_used,
    'event_remaining',greatest(0,(v_quotas->>'events')::integer-v_event_used),
    'community_quota',(v_quotas->>'communities')::integer,
    'community_used',v_community_used,
    'community_remaining',greatest(0,(v_quotas->>'communities')::integer-v_community_used)
  );
end;
$function$;

revoke all on function public.scrole_get_my_subscription_entitlements() from public,anon;
grant execute on function public.scrole_get_my_subscription_entitlements() to authenticated;

create or replace function public.scrole_enforce_event_quota_limits()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_certified boolean := false;
  v_certify_requested boolean := current_setting('scrole.certify_event_on_create', true) = 'true';
  v_horizon integer;
  v_max_days integer;
  v_subscription_id uuid;
  v_plan_code text;
  v_event_quota integer;
  v_event_used integer;
begin
  select exists (
    select 1 from public.event_certifications ec
    where ec.event_id = new.id and ec.status = 'active'
      and (ec.valid_until is null or ec.valid_until > now())
  ) into v_certified;

  if tg_op = 'INSERT' and v_certify_requested then
    select s.id,s.plan_code into v_subscription_id,v_plan_code
    from public.scrole_subscriptions s
    where s.user_id=new.creator_id and s.status='active'
      and (s.ends_at is null or s.ends_at > now())
    order by s.ends_at desc nulls first limit 1
    for update;

    if v_subscription_id is null then
      raise exception 'active_subscription_required_for_included_event_certification' using errcode='42501';
    end if;

    select value into v_event_quota from public.scrole_quota_settings
    where quota_key=v_plan_code || '_included_certified_events';
    select count(*) into v_event_used from public.event_certifications
    where subscription_id=v_subscription_id and source='subscription_included'
      and status='active' and (valid_until is null or valid_until > now());

    if v_event_used >= coalesce(v_event_quota,0) then
      raise exception 'included_event_certification_quota_exceeded' using errcode='22023';
    end if;

    select value into v_horizon from public.scrole_quota_settings
    where quota_key='certified_event_horizon_months';
    if new.starts_at is not null and new.starts_at > now()+make_interval(months=>coalesce(v_horizon,6)) then
      raise exception 'certified_event_horizon_exceeded'
        using errcode='22023',
        detail=format('Un événement certifié doit commencer dans les %s prochains mois.',coalesce(v_horizon,6));
    end if;
    return new;
  end if;

  if v_certified then
    select value into v_horizon from public.scrole_quota_settings
    where quota_key='certified_event_horizon_months';
    if new.starts_at is not null and new.starts_at > now()+make_interval(months=>coalesce(v_horizon,6)) then
      raise exception 'certified_event_horizon_exceeded'
        using errcode='22023',
        detail=format('Un événement certifié doit commencer dans les %s prochains mois.',coalesce(v_horizon,6));
    end if;
    return new;
  end if;

  select value into v_horizon from public.scrole_quota_settings
  where quota_key='noncert_event_horizon_months';
  select value into v_max_days from public.scrole_quota_settings
  where quota_key='noncert_event_max_duration_days';

  if new.starts_at is not null and new.starts_at > now()+make_interval(months=>coalesce(v_horizon,2)) then
    raise exception 'noncertified_event_horizon_exceeded'
      using errcode='22023',
      detail=format('Un événement non certifié doit commencer dans les %s prochains mois.',coalesce(v_horizon,2));
  end if;
  if new.ends_at is not null and new.starts_at is not null
     and new.ends_at-new.starts_at > make_interval(days=>coalesce(v_max_days,2)) then
    raise exception 'noncertified_event_duration_exceeded'
      using errcode='22023',
      detail=format('Un événement non certifié ne peut pas dépasser %s jours.',coalesce(v_max_days,2));
  end if;
  return new;
end;
$function$;

create or replace function public.scrole_certify_event_after_explicit_creation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_subscription public.scrole_subscriptions%rowtype;
  v_quota integer;
  v_used integer;
begin
  if current_setting('scrole.certify_event_on_create',true) <> 'true' then
    return new;
  end if;

  select * into v_subscription from public.scrole_subscriptions
  where user_id=new.creator_id and status='active'
    and (ends_at is null or ends_at > now())
  order by ends_at desc nulls first limit 1 for update;

  if not found then raise exception 'active_subscription_required_for_included_event_certification' using errcode='42501'; end if;

  select value into v_quota from public.scrole_quota_settings
  where quota_key=v_subscription.plan_code || '_included_certified_events';
  select count(*) into v_used from public.event_certifications
  where subscription_id=v_subscription.id and source='subscription_included'
    and status='active' and (valid_until is null or valid_until > now());

  if v_used >= coalesce(v_quota,0) then
    raise exception 'included_event_certification_quota_exceeded' using errcode='22023';
  end if;

  insert into public.event_certifications(event_id,source,status,subscription_id,valid_until)
  values(new.id,'subscription_included','active',v_subscription.id,v_subscription.ends_at);

  insert into public.scrole_certification_audit(
    actor_user_id,subscription_id,entity_type,entity_id,action,new_status,details
  ) values (
    new.creator_id,v_subscription.id,'event',new.id,'included_event_certification_granted','active',
    jsonb_build_object('plan_code',v_subscription.plan_code,'quota',v_quota,'valid_until',v_subscription.ends_at)
  );

  return new;
end;
$function$;

drop trigger if exists scrole_certify_event_after_explicit_creation on public.events;
create trigger scrole_certify_event_after_explicit_creation
after insert on public.events
for each row execute function public.scrole_certify_event_after_explicit_creation();

create or replace function public.create_certified_event_with_subscription(
  p_id uuid,
  p_name text,
  p_slug text,
  p_starts_at timestamptz,
  p_description text default null,
  p_photo text default null,
  p_is_virtual boolean default false,
  p_virtual_link text default null,
  p_country_id uuid default null,
  p_city_id uuid default null,
  p_address text default null,
  p_ends_at timestamptz default null,
  p_is_free boolean default false,
  p_is_public boolean default true,
  p_real_created_at date default null
)
returns public.events
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_event public.events%rowtype;
  v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'authentication_required' using errcode='28000'; end if;

  if not exists (
    select 1 from public.scrole_subscriptions s
    where s.user_id=v_user and s.status='active'
      and (s.ends_at is null or s.ends_at > now())
  ) then
    raise exception 'active_subscription_required_for_included_event_certification' using errcode='42501';
  end if;

  perform set_config('scrole.certify_event_on_create','true',true);
  v_event := public.create_event(
    p_id,p_name,p_slug,p_starts_at,p_description,p_photo,p_is_virtual,p_virtual_link,
    p_country_id,p_city_id,p_address,p_ends_at,p_is_free,p_is_public,p_real_created_at
  );
  perform set_config('scrole.certify_event_on_create','false',true);

  if not exists (
    select 1 from public.event_certifications ec
    where ec.event_id=v_event.id and ec.status='active'
      and ec.source='subscription_included'
  ) then
    raise exception 'included_event_certification_not_created' using errcode='55000';
  end if;

  return v_event;
exception when others then
  perform set_config('scrole.certify_event_on_create','false',true);
  raise;
end;
$function$;

revoke all on function public.create_certified_event_with_subscription(uuid,text,text,timestamptz,text,text,boolean,text,uuid,uuid,text,timestamptz,boolean,boolean,date) from public,anon;
grant execute on function public.create_certified_event_with_subscription(uuid,text,text,timestamptz,text,text,boolean,text,uuid,uuid,text,timestamptz,boolean,boolean,date) to authenticated;
revoke all on function public.scrole_certify_event_after_explicit_creation() from public,anon,authenticated;
