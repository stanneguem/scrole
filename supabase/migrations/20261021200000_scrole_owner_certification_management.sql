-- User-facing certification actions: ownership, validated profile certification,
-- subscription entitlement and active certification status are checked server-side.
create or replace function public.scrole_get_entity_certification_status(
  p_entity_type text,
  p_entity_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_user uuid := auth.uid();
  v_entity_owner uuid;
  v_entity_active boolean := false;
  v_entity_certified boolean := false;
  v_community_certified boolean := false;
  v_source text;
  v_valid_until timestamptz;
begin
  if v_user is null then raise exception 'authentication_required' using errcode = '28000'; end if;
  if p_entity_type not in ('event','community') or p_entity_id is null then
    raise exception 'invalid_certification_target' using errcode = '22023';
  end if;

  if p_entity_type = 'event' then
    select e.creator_id, coalesce(lower(e.status) = 'active', false)
      into v_entity_owner, v_entity_active
    from public.events e where e.id = p_entity_id;
    if not found then raise exception 'event_not_found' using errcode = 'P0002'; end if;
    select ec.source, ec.valid_until into v_source, v_valid_until
    from public.event_certifications ec
    where ec.event_id = p_entity_id and ec.status = 'active'
      and (ec.valid_until is null or ec.valid_until > now())
    order by ec.created_at desc limit 1;
    v_entity_certified := found;
    select exists (
      select 1 from public.events e
      join public.communities c on c.id = e.community_id and c.status = 'active'
      join public.community_certifications cc on cc.community_id = c.id
      where e.id = p_entity_id and cc.status = 'active'
        and (cc.valid_until is null or cc.valid_until > now())
    ) into v_community_certified;
  else
    select c.creator_id, coalesce(lower(c.status) = 'active', false)
      into v_entity_owner, v_entity_active
    from public.communities c where c.id = p_entity_id;
    if not found then raise exception 'community_not_found' using errcode = 'P0002'; end if;
    select cc.source, cc.valid_until into v_source, v_valid_until
    from public.community_certifications cc
    where cc.community_id = p_entity_id and cc.status = 'active'
      and (cc.valid_until is null or cc.valid_until > now())
    order by cc.created_at desc limit 1;
    v_entity_certified := found;
  end if;

  return jsonb_build_object(
    'entity_type', p_entity_type, 'entity_id', p_entity_id,
    'is_owner', v_entity_owner = v_user, 'entity_active', v_entity_active,
    'entity_certified', v_entity_certified, 'community_certified', v_community_certified,
    'ticketing_allowed', v_entity_certified or v_community_certified,
    'source', v_source, 'valid_until', v_valid_until
  );
end;
$function$;

create or replace function public.scrole_certify_owned_entity_with_subscription(
  p_entity_type text,
  p_entity_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user uuid := auth.uid();
  v_owner uuid;
  v_has_profile_certification boolean := false;
  v_subscription public.scrole_subscriptions%rowtype;
begin
  if v_user is null then raise exception 'authentication_required' using errcode = '28000'; end if;
  if p_entity_type not in ('event','community') or p_entity_id is null then
    raise exception 'invalid_certification_target' using errcode = '22023';
  end if;

  if p_entity_type = 'event' then
    select e.creator_id into v_owner from public.events e
    where e.id = p_entity_id and lower(e.status) = 'active';
  else
    select c.creator_id into v_owner from public.communities c
    where c.id = p_entity_id and lower(c.status) = 'active';
  end if;
  if not found then raise exception 'active_certification_target_required' using errcode = 'P0002'; end if;
  if v_owner is distinct from v_user then
    raise exception 'entity_not_owned_by_current_user' using errcode = '42501';
  end if;

  select exists (
    select 1 from public.user_certifications uc
    where uc.user_id = v_user and uc.status::text = 'active'
      and uc.issued_at <= now() and (uc.expires_at is null or uc.expires_at > now())
  ) into v_has_profile_certification;
  if not v_has_profile_certification then
    raise exception 'active_profile_certification_required' using errcode = '42501';
  end if;

  select * into v_subscription from public.scrole_subscriptions s
  where s.user_id = v_user and s.status = 'active'
    and (s.ends_at is null or s.ends_at > now())
  order by s.ends_at desc nulls first limit 1 for update;
  if not found then
    raise exception 'active_pro_or_premium_subscription_required_for_included_certification'
      using errcode = '42501';
  end if;

  return public.scrole_grant_included_certification(v_subscription.id, p_entity_type, p_entity_id);
end;
$function$;

revoke all on function public.scrole_get_entity_certification_status(text,uuid) from public, anon;
grant execute on function public.scrole_get_entity_certification_status(text,uuid) to authenticated;
revoke all on function public.scrole_certify_owned_entity_with_subscription(text,uuid) from public, anon;
grant execute on function public.scrole_certify_owned_entity_with_subscription(text,uuid) to authenticated;
