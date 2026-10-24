-- Trusted payment integration point for creating Pro/Premium subscriptions.
-- Payment verification must happen before service_role calls this RPC.

create or replace function public.scrole_activate_subscription(
  p_user_id uuid,
  p_plan_code text,
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_provider text,
  p_provider_subscription_id text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_subscription public.scrole_subscriptions%rowtype;
  v_existing public.scrole_subscriptions%rowtype;
  v_profile_entitlement jsonb;
begin
  if p_user_id is null or p_plan_code not in ('pro','premium') then
    raise exception 'invalid_subscription_user_or_plan' using errcode='22023';
  end if;
  if p_starts_at is null or p_ends_at is null or p_ends_at <= p_starts_at or p_ends_at <= now() then
    raise exception 'invalid_subscription_dates' using errcode='22023';
  end if;
  if nullif(trim(coalesce(p_provider,'')),'') is null
     or nullif(trim(coalesce(p_provider_subscription_id,'')),'') is null then
    raise exception 'payment_provider_reference_required' using errcode='22023';
  end if;
  if not exists (select 1 from auth.users u where u.id=p_user_id) then
    raise exception 'subscription_user_not_found' using errcode='22023';
  end if;

  select * into v_existing from public.scrole_subscriptions
  where provider=p_provider and provider_subscription_id=p_provider_subscription_id
  for update;

  if found then
    if v_existing.user_id <> p_user_id or v_existing.plan_code <> p_plan_code then
      raise exception 'provider_subscription_reference_conflict' using errcode='23505';
    end if;
    if v_existing.status <> 'active' then
      raise exception 'existing_subscription_requires_renewal_flow' using errcode='22023';
    end if;
    v_subscription := v_existing;
  else
    if exists (
      select 1 from public.scrole_subscriptions s
      where s.user_id=p_user_id and s.status='active'
      for update
    ) then
      raise exception 'user_already_has_active_subscription' using errcode='23505';
    end if;

    insert into public.scrole_subscriptions(
      user_id,plan_code,status,starts_at,ends_at,provider,provider_subscription_id
    ) values (
      p_user_id,p_plan_code,'active',p_starts_at,p_ends_at,p_provider,p_provider_subscription_id
    ) returning * into v_subscription;
  end if;

  v_profile_entitlement := public.scrole_grant_included_profile_certification(v_subscription.id);

  insert into public.scrole_certification_audit(
    actor_user_id,subscription_id,entity_type,entity_id,action,new_status,details
  ) values (
    p_user_id,v_subscription.id,'subscription',v_subscription.id,'subscription_activated','active',
    jsonb_build_object('plan_code',v_subscription.plan_code,'starts_at',v_subscription.starts_at,
      'ends_at',v_subscription.ends_at,'provider',p_provider,'provider_subscription_id',p_provider_subscription_id)
  );

  return jsonb_build_object(
    'subscription_id',v_subscription.id,
    'user_id',v_subscription.user_id,
    'plan_code',v_subscription.plan_code,
    'status',v_subscription.status,
    'starts_at',v_subscription.starts_at,
    'ends_at',v_subscription.ends_at,
    'profile_certification',v_profile_entitlement
  );
end;
$function$;

revoke all on function public.scrole_activate_subscription(uuid,text,timestamptz,timestamptz,text,text) from public,anon,authenticated;
grant execute on function public.scrole_activate_subscription(uuid,text,timestamptz,timestamptz,text,text) to service_role;
