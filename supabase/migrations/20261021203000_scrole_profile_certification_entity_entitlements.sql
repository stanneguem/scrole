-- Admin-issued active Pro/Premium profile certifications also grant included
-- event/community quotas, without fabricating a paid subscription.
alter table public.event_certifications
  add column if not exists profile_certification_id uuid references public.user_certifications(id) on delete restrict;
alter table public.community_certifications
  add column if not exists profile_certification_id uuid references public.user_certifications(id) on delete restrict;

alter table public.event_certifications drop constraint if exists event_certifications_source_check;
alter table public.event_certifications add constraint event_certifications_source_check
  check (source in ('subscription_included','profile_entitlement','purchased','admin_grant'));
alter table public.community_certifications drop constraint if exists community_certifications_source_check;
alter table public.community_certifications add constraint community_certifications_source_check
  check (source in ('subscription_included','profile_entitlement','purchased','admin_grant'));

create or replace function public.scrole_get_my_subscription_entitlements()
returns jsonb language plpgsql stable security definer set search_path=''
as $function$
declare
  v_user uuid:=auth.uid(); v_sub public.scrole_subscriptions%rowtype;
  v_cert_id uuid; v_valid_until timestamptz; v_plan text; v_basis text;
  v_quotas jsonb; v_event_used integer:=0; v_community_used integer:=0;
  v_event_quota integer:=0; v_community_quota integer:=0;
begin
  if v_user is null then raise exception 'authentication_required' using errcode='28000'; end if;
  select * into v_sub from public.scrole_subscriptions s where s.user_id=v_user and s.status='active'
    and (s.ends_at is null or s.ends_at>now()) order by s.ends_at desc nulls first limit 1;
  if found then
    v_plan:=v_sub.plan_code; v_basis:='subscription'; v_quotas:=public.scrole_subscription_quotas(v_plan);
    v_event_quota:=coalesce((select value from public.scrole_quota_settings where quota_key=v_plan||'_included_certified_events'),(v_quotas->>'events')::integer);
    v_community_quota:=coalesce((select value from public.scrole_quota_settings where quota_key=v_plan||'_included_certified_communities'),(v_quotas->>'communities')::integer);
    select count(*) into v_event_used from public.event_certifications where subscription_id=v_sub.id and source='subscription_included' and status='active' and (valid_until is null or valid_until>now());
    select count(*) into v_community_used from public.community_certifications where subscription_id=v_sub.id and source='subscription_included' and status='active' and (valid_until is null or valid_until>now());
    return jsonb_build_object('active',true,'plan_code',v_plan,'entitlement_basis',v_basis,'subscription_id',v_sub.id,'ends_at',v_sub.ends_at,
      'event_quota',v_event_quota,'event_used',v_event_used,'event_remaining',greatest(0,v_event_quota-v_event_used),
      'community_quota',v_community_quota,'community_used',v_community_used,'community_remaining',greatest(0,v_community_quota-v_community_used));
  end if;
  select uc.id,uc.expires_at,lower(ct.code) into v_cert_id,v_valid_until,v_plan
  from public.user_certifications uc join public.certification_type ct on ct.id=uc.certification_type_id
  where uc.user_id=v_user and uc.status::text='active' and uc.issued_at<=now()
    and (uc.expires_at is null or uc.expires_at>now()) and lower(ct.code) in ('pro','premium')
  order by case lower(ct.code) when 'premium' then 2 when 'pro' then 1 else 0 end desc,uc.expires_at desc nulls first limit 1;
  if v_cert_id is null then return jsonb_build_object('active',false,'plan_code',null,'entitlement_basis',null,
    'event_quota',0,'event_used',0,'event_remaining',0,'community_quota',0,'community_used',0,'community_remaining',0); end if;
  v_basis:='profile_certification';
  v_event_quota:=coalesce((select value from public.scrole_quota_settings where quota_key=v_plan||'_included_certified_events'),0);
  v_community_quota:=coalesce((select value from public.scrole_quota_settings where quota_key=v_plan||'_included_certified_communities'),0);
  select count(*) into v_event_used from public.event_certifications where profile_certification_id=v_cert_id and source='profile_entitlement' and status='active' and (valid_until is null or valid_until>now());
  select count(*) into v_community_used from public.community_certifications where profile_certification_id=v_cert_id and source='profile_entitlement' and status='active' and (valid_until is null or valid_until>now());
  return jsonb_build_object('active',true,'plan_code',v_plan,'entitlement_basis',v_basis,'profile_certification_id',v_cert_id,'ends_at',v_valid_until,
    'event_quota',v_event_quota,'event_used',v_event_used,'event_remaining',greatest(0,v_event_quota-v_event_used),
    'community_quota',v_community_quota,'community_used',v_community_used,'community_remaining',greatest(0,v_community_quota-v_community_used));
end;
$function$;

create or replace function public.scrole_certify_owned_entity_with_subscription(p_entity_type text,p_entity_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare
  v_user uuid:=auth.uid(); v_owner uuid; v_sub public.scrole_subscriptions%rowtype;
  v_cert_id uuid; v_valid_until timestamptz; v_plan text; v_quota integer; v_used integer; v_existing_id uuid;
begin
  if v_user is null then raise exception 'authentication_required' using errcode='28000'; end if;
  if p_entity_type not in ('event','community') or p_entity_id is null then raise exception 'invalid_certification_target' using errcode='22023'; end if;
  if p_entity_type='event' then select creator_id into v_owner from public.events where id=p_entity_id and lower(status)='active';
  else select creator_id into v_owner from public.communities where id=p_entity_id and lower(status)='active'; end if;
  if not found then raise exception 'active_certification_target_required' using errcode='P0002'; end if;
  if v_owner is distinct from v_user then raise exception 'entity_not_owned_by_current_user' using errcode='42501'; end if;
  select * into v_sub from public.scrole_subscriptions where user_id=v_user and status='active'
    and (ends_at is null or ends_at>now()) order by ends_at desc nulls first limit 1 for update;
  if found then return public.scrole_grant_included_certification(v_sub.id,p_entity_type,p_entity_id); end if;

  select uc.id,uc.expires_at,lower(ct.code) into v_cert_id,v_valid_until,v_plan
  from public.user_certifications uc join public.certification_type ct on ct.id=uc.certification_type_id
  where uc.user_id=v_user and uc.status::text='active' and uc.issued_at<=now()
    and (uc.expires_at is null or uc.expires_at>now()) and lower(ct.code) in ('pro','premium')
  order by case lower(ct.code) when 'premium' then 2 when 'pro' then 1 else 0 end desc,uc.expires_at desc nulls first limit 1 for update of uc;
  if v_cert_id is null then raise exception 'active_pro_or_premium_profile_certification_required' using errcode='42501'; end if;

  if p_entity_type='event' then
    v_quota:=coalesce((select value from public.scrole_quota_settings where quota_key=v_plan||'_included_certified_events'),0);
    select count(*) into v_used from public.event_certifications where profile_certification_id=v_cert_id and source='profile_entitlement' and status='active' and (valid_until is null or valid_until>now()) and event_id<>p_entity_id;
    select id into v_existing_id from public.event_certifications where event_id=p_entity_id and profile_certification_id=v_cert_id and source='profile_entitlement' order by created_at desc limit 1 for update;
    if exists(select 1 from public.event_certifications where event_id=p_entity_id and profile_certification_id=v_cert_id and source='profile_entitlement' and status='active' and (valid_until is null or valid_until>now())) then
      return jsonb_build_object('entity_type',p_entity_type,'entity_id',p_entity_id,'status','active','already_active',true,'source','profile_entitlement'); end if;
    if v_used>=v_quota then raise exception 'included_event_certification_quota_exceeded' using errcode='22023'; end if;
    if v_existing_id is null then insert into public.event_certifications(event_id,source,status,profile_certification_id,valid_until) values(p_entity_id,'profile_entitlement','active',v_cert_id,v_valid_until) returning id into v_existing_id;
    else update public.event_certifications set status='active',valid_until=v_valid_until,suspended_at=null,updated_at=now() where id=v_existing_id; end if;
  else
    v_quota:=coalesce((select value from public.scrole_quota_settings where quota_key=v_plan||'_included_certified_communities'),0);
    select count(*) into v_used from public.community_certifications where profile_certification_id=v_cert_id and source='profile_entitlement' and status='active' and (valid_until is null or valid_until>now()) and community_id<>p_entity_id;
    select id into v_existing_id from public.community_certifications where community_id=p_entity_id and profile_certification_id=v_cert_id and source='profile_entitlement' order by created_at desc limit 1 for update;
    if exists(select 1 from public.community_certifications where community_id=p_entity_id and profile_certification_id=v_cert_id and source='profile_entitlement' and status='active' and (valid_until is null or valid_until>now())) then
      return jsonb_build_object('entity_type',p_entity_type,'entity_id',p_entity_id,'status','active','already_active',true,'source','profile_entitlement'); end if;
    if v_used>=v_quota then raise exception 'included_community_certification_quota_exceeded' using errcode='22023'; end if;
    if v_existing_id is null then insert into public.community_certifications(community_id,source,status,profile_certification_id,valid_until) values(p_entity_id,'profile_entitlement','active',v_cert_id,v_valid_until) returning id into v_existing_id;
    else update public.community_certifications set status='active',valid_until=v_valid_until,suspended_at=null,updated_at=now() where id=v_existing_id; end if;
  end if;
  insert into public.scrole_certification_audit(actor_user_id,entity_type,entity_id,action,new_status,details)
  values(v_user,p_entity_type,p_entity_id,'profile_certification_entitlement_granted','active',jsonb_build_object('profile_certification_id',v_cert_id,'plan_code',v_plan,'quota',v_quota,'valid_until',v_valid_until));
  return jsonb_build_object('entity_type',p_entity_type,'entity_id',p_entity_id,'status','active','certification_id',v_existing_id,'source','profile_entitlement','profile_certification_id',v_cert_id,'valid_until',v_valid_until);
end;
$function$;

revoke all on function public.scrole_get_my_subscription_entitlements() from public,anon;
grant execute on function public.scrole_get_my_subscription_entitlements() to authenticated;
revoke all on function public.scrole_certify_owned_entity_with_subscription(text,uuid) from public,anon;
grant execute on function public.scrole_certify_owned_entity_with_subscription(text,uuid) to authenticated;
