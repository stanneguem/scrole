-- Allow Premium/Pro profile certifications to use included event certification
-- even when the account is not represented by a row in scrole_subscriptions.

create or replace function public.scrole_certify_event_after_explicit_creation()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_subscription public.scrole_subscriptions%rowtype;
  v_profile_cert_id uuid;
  v_profile_valid_until timestamptz;
  v_plan_code text;
  v_quota integer;
  v_used integer;
begin
  if current_setting('scrole.certify_event_on_create', true) is distinct from 'true' then
    return new;
  end if;

  select * into v_subscription
  from public.scrole_subscriptions
  where user_id = new.creator_id
    and status = 'active'
    and (ends_at is null or ends_at > now())
  order by ends_at desc nulls first
  limit 1
  for update;

  if found then
    v_plan_code := v_subscription.plan_code;
    select value into v_quota
    from public.scrole_quota_settings
    where quota_key = v_plan_code || '_included_certified_events';

    select count(*) into v_used
    from public.event_certifications
    where subscription_id = v_subscription.id
      and source = 'subscription_included'
      and status = 'active'
      and (valid_until is null or valid_until > now());

    if v_used >= coalesce(v_quota, 0) then
      raise exception 'included_event_certification_quota_exceeded' using errcode = '22023';
    end if;

    insert into public.event_certifications (
      event_id, source, status, subscription_id, valid_until
    ) values (
      new.id, 'subscription_included', 'active', v_subscription.id, v_subscription.ends_at
    );

    insert into public.scrole_certification_audit (
      actor_user_id, subscription_id, entity_type, entity_id, action, new_status, details
    ) values (
      new.creator_id, v_subscription.id, 'event', new.id,
      'included_event_certification_granted', 'active',
      jsonb_build_object('plan_code', v_plan_code, 'quota', v_quota, 'valid_until', v_subscription.ends_at)
    );
    return new;
  end if;

  -- The app can identify Premium/Pro through user_certifications rather than
  -- scrole_subscriptions; honor that same active profile entitlement here.
  select uc.id, uc.expires_at, lower(ct.code)
    into v_profile_cert_id, v_profile_valid_until, v_plan_code
  from public.user_certifications uc
  join public.certification_type ct on ct.id = uc.certification_type_id
  where uc.user_id = new.creator_id
    and uc.status::text = 'active'
    and uc.issued_at <= now()
    and (uc.expires_at is null or uc.expires_at > now())
    and lower(ct.code) in ('pro', 'premium')
  order by case lower(ct.code) when 'premium' then 2 else 1 end desc,
           uc.expires_at desc nulls first
  limit 1
  for update of uc;

  if v_profile_cert_id is null then
    raise exception 'active_subscription_required_for_included_event_certification' using errcode = '42501';
  end if;

  select value into v_quota
  from public.scrole_quota_settings
  where quota_key = v_plan_code || '_included_certified_events';

  select count(*) into v_used
  from public.event_certifications
  where profile_certification_id = v_profile_cert_id
    and source = 'profile_entitlement'
    and status = 'active'
    and (valid_until is null or valid_until > now());

  if v_used >= coalesce(v_quota, 0) then
    raise exception 'included_event_certification_quota_exceeded' using errcode = '22023';
  end if;

  insert into public.event_certifications (
    event_id, source, status, profile_certification_id, valid_until
  ) values (
    new.id, 'profile_entitlement', 'active', v_profile_cert_id, v_profile_valid_until
  );

  insert into public.scrole_certification_audit (
    actor_user_id, entity_type, entity_id, action, new_status, details
  ) values (
    new.creator_id, 'event', new.id,
    'profile_entitlement_event_certification_granted', 'active',
    jsonb_build_object('plan_code', v_plan_code, 'quota', v_quota, 'valid_until', v_profile_valid_until,
                       'profile_certification_id', v_profile_cert_id)
  );

  return new;
end;
$function$;

create or replace function public.create_certified_event_with_subscription(
  p_id uuid, p_name text, p_slug text, p_starts_at timestamp with time zone,
  p_description text default null, p_photo text default null,
  p_is_virtual boolean default false, p_virtual_link text default null,
  p_country_id uuid default null, p_city_id uuid default null, p_address text default null,
  p_ends_at timestamp with time zone default null, p_is_free boolean default false,
  p_is_public boolean default true, p_real_created_at date default null
)
returns public.events
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_event public.events%rowtype;
  v_user uuid := auth.uid();
  v_has_subscription boolean;
  v_has_profile_entitlement boolean;
begin
  if v_user is null then
    raise exception 'authentication_required' using errcode = '28000';
  end if;

  select exists (
    select 1 from public.scrole_subscriptions s
    where s.user_id = v_user and s.status = 'active'
      and (s.ends_at is null or s.ends_at > now())
  ) into v_has_subscription;

  select exists (
    select 1
    from public.user_certifications uc
    join public.certification_type ct on ct.id = uc.certification_type_id
    where uc.user_id = v_user and uc.status::text = 'active'
      and uc.issued_at <= now()
      and (uc.expires_at is null or uc.expires_at > now())
      and lower(ct.code) in ('pro', 'premium')
  ) into v_has_profile_entitlement;

  if not v_has_subscription and not v_has_profile_entitlement then
    raise exception 'active_subscription_required_for_included_event_certification' using errcode = '42501';
  end if;

  perform set_config('scrole.certify_event_on_create', 'true', true);
  v_event := public.create_event(
    p_id, p_name, p_slug, p_starts_at, p_description, p_photo, p_is_virtual,
    p_virtual_link, p_country_id, p_city_id, p_address, p_ends_at, p_is_free,
    p_is_public, p_real_created_at
  );
  perform set_config('scrole.certify_event_on_create', 'false', true);

  if not exists (
    select 1 from public.event_certifications ec
    where ec.event_id = v_event.id and ec.status = 'active'
      and ec.source in ('subscription_included', 'profile_entitlement')
  ) then
    raise exception 'included_event_certification_not_created' using errcode = '55000';
  end if;

  return v_event;
exception when others then
  perform set_config('scrole.certify_event_on_create', 'false', true);
  raise;
end;
$function$;
