-- Preserve the provenance of subscription-included profile certifications.
-- Existing certification requests and records are retained. The nullable request_id
-- is permitted only for rows explicitly linked to a subscription.

alter table public.user_certifications
  add column if not exists source text not null default 'request';

alter table public.user_certifications
  add column if not exists subscription_id uuid
  references public.scrole_subscriptions(id) on delete restrict;

alter table public.user_certifications
  alter column request_id drop not null;

do $function$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid='public.user_certifications'::regclass
      and conname='user_certifications_source_subscription_check'
  ) then
    alter table public.user_certifications
      add constraint user_certifications_source_subscription_check
      check (
        (source = 'subscription_included' and request_id is null and subscription_id is not null)
        or
        (source in ('request','admin_grant') and request_id is not null and subscription_id is null)
      );
  end if;
end;
$function$;

create index if not exists user_certifications_subscription_source_idx
  on public.user_certifications(subscription_id,source)
  where subscription_id is not null;

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

  select pce.id,pce.user_certification_id
  into v_entitlement_id,v_cert_id
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
      and uc.source <> 'subscription_included'
    order by uc.issued_at desc limit 1;
    if v_cert_id is not null then
      return jsonb_build_object('status','already_certified_independently','user_certification_id',v_cert_id);
    end if;

    insert into public.user_certifications(
      user_id,certification_type_id,request_id,status,issued_at,expires_at,source,subscription_id
    ) values (
      v_sub.user_id,v_type_id,null,'active'::public.status_certification,now(),v_sub.ends_at,
      'subscription_included',p_subscription_id
    ) returning id into v_cert_id;

    insert into public.profile_certification_entitlements(
      user_certification_id,subscription_id,status,valid_until
    ) values(v_cert_id,p_subscription_id,'active',v_sub.ends_at)
    returning id into v_entitlement_id;
  else
    update public.user_certifications
    set certification_type_id=v_type_id,status='active'::public.status_certification,
        source='subscription_included',subscription_id=p_subscription_id,
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
          source='subscription_included',subscription_id=new.id,
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

revoke all on function public.scrole_grant_included_profile_certification(uuid) from public,anon,authenticated;
grant execute on function public.scrole_grant_included_profile_certification(uuid) to service_role;
revoke all on function public.scrole_sync_included_profile_certification() from public,anon,authenticated;
