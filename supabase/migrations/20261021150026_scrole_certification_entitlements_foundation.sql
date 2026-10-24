-- Scrole certification refactor: additive foundation only.
-- Applied to the active Supabase project; retained as the versioned source of truth.
-- It intentionally does not alter existing profile-certification tables or RPC signatures.

create table if not exists public.scrole_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete restrict,
  plan_code text not null check (plan_code in ('pro', 'premium')),
  status text not null default 'pending'
    check (status in ('pending', 'active', 'expired', 'cancelled', 'past_due')),
  starts_at timestamptz,
  ends_at timestamptz,
  provider text,
  provider_subscription_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint scrole_subscriptions_dates_valid
    check (ends_at is null or starts_at is null or ends_at > starts_at),
  constraint scrole_subscriptions_provider_ref_unique
    unique (provider, provider_subscription_id)
);

create index if not exists scrole_subscriptions_user_status_idx
  on public.scrole_subscriptions (user_id, status, ends_at desc);

create table if not exists public.event_certifications (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete restrict,
  source text not null check (source in ('subscription_included', 'purchased', 'admin_grant')),
  status text not null default 'active' check (status in ('active', 'suspended', 'expired')),
  subscription_id uuid references public.scrole_subscriptions(id) on delete restrict,
  valid_until timestamptz,
  suspended_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint event_certifications_source_subscription_check
    check ((source = 'subscription_included' and subscription_id is not null)
        or (source <> 'subscription_included' and subscription_id is null))
);

create index if not exists event_certifications_event_status_idx
  on public.event_certifications (event_id, status);
create index if not exists event_certifications_subscription_status_idx
  on public.event_certifications (subscription_id, status)
  where subscription_id is not null;

create table if not exists public.community_certifications (
  id uuid primary key default gen_random_uuid(),
  community_id uuid not null references public.communities(id) on delete restrict,
  source text not null check (source in ('subscription_included', 'purchased', 'admin_grant')),
  status text not null default 'active' check (status in ('active', 'suspended', 'expired')),
  subscription_id uuid references public.scrole_subscriptions(id) on delete restrict,
  valid_until timestamptz,
  suspended_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint community_certifications_source_subscription_check
    check ((source = 'subscription_included' and subscription_id is not null)
        or (source <> 'subscription_included' and subscription_id is null))
);

create index if not exists community_certifications_community_status_idx
  on public.community_certifications (community_id, status);
create index if not exists community_certifications_subscription_status_idx
  on public.community_certifications (subscription_id, status)
  where subscription_id is not null;

-- One active entitlement per entity and provenance. Historical rows remain available.
create unique index if not exists event_certifications_one_active_source_idx
  on public.event_certifications (event_id, coalesce(subscription_id, '00000000-0000-0000-0000-000000000000'::uuid), source)
  where status = 'active';
create unique index if not exists community_certifications_one_active_source_idx
  on public.community_certifications (community_id, coalesce(subscription_id, '00000000-0000-0000-0000-000000000000'::uuid), source)
  where status = 'active';

create table if not exists public.scrole_certification_audit (
  id bigint generated always as identity primary key,
  actor_user_id uuid references auth.users(id) on delete set null,
  subscription_id uuid references public.scrole_subscriptions(id) on delete set null,
  entity_type text check (entity_type in ('profile', 'event', 'community', 'subscription')),
  entity_id uuid,
  action text not null,
  previous_status text,
  new_status text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists scrole_certification_audit_entity_idx
  on public.scrole_certification_audit (entity_type, entity_id, created_at desc);
create index if not exists scrole_certification_audit_subscription_idx
  on public.scrole_certification_audit (subscription_id, created_at desc);

alter table public.scrole_subscriptions enable row level security;
alter table public.event_certifications enable row level security;
alter table public.community_certifications enable row level security;
alter table public.scrole_certification_audit enable row level security;

-- Reads are owner-scoped. Writes happen through SECURITY DEFINER RPCs only.
revoke all on public.scrole_subscriptions from anon, authenticated;
revoke all on public.event_certifications from anon, authenticated;
revoke all on public.community_certifications from anon, authenticated;
revoke all on public.scrole_certification_audit from anon, authenticated;
grant select on public.scrole_subscriptions to authenticated;
grant select on public.event_certifications to authenticated;
grant select on public.community_certifications to authenticated;

drop policy if exists scrole_subscriptions_select_own on public.scrole_subscriptions;
create policy scrole_subscriptions_select_own on public.scrole_subscriptions
  for select to authenticated using (user_id = (select auth.uid()));

drop policy if exists event_certifications_select_owner on public.event_certifications;
create policy event_certifications_select_owner on public.event_certifications
  for select to authenticated using (
    exists (select 1 from public.events e where e.id = event_id and e.creator_id = (select auth.uid()))
  );

drop policy if exists community_certifications_select_owner on public.community_certifications;
create policy community_certifications_select_owner on public.community_certifications
  for select to authenticated using (
    exists (select 1 from public.communities c where c.id = community_id and c.creator_id = (select auth.uid()))
  );

-- Returns the effective included quota. Kept private to authenticated server calls.
create or replace function public.scrole_subscription_quotas(p_plan_code text)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
begin
  if p_plan_code = 'pro' then
    return jsonb_build_object('events', 1, 'communities', 1);
  elsif p_plan_code = 'premium' then
    return jsonb_build_object('events', 4, 'communities', 4);
  end if;
  raise exception 'invalid_subscription_plan' using errcode = '22023';
end;
$$;

revoke all on function public.scrole_subscription_quotas(text) from public, anon;
grant execute on function public.scrole_subscription_quotas(text) to authenticated;

-- Atomically changes an owned subscription plan and explicitly applies the user's
-- choices for included event/community certifications. Pass NULL when no included
-- certification of that entity type should remain active. Purchased certifications
-- are not counted or modified.
create or replace function public.scrole_change_subscription_plan(
  p_subscription_id uuid,
  p_new_plan text,
  p_keep_event_id uuid default null,
  p_keep_community_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_sub public.scrole_subscriptions%rowtype;
  v_event_count integer;
  v_community_count integer;
  v_event_cert_id uuid;
  v_community_cert_id uuid;
begin
  if v_user is null then
    raise exception 'authentication_required' using errcode = '28000';
  end if;
  if p_new_plan is null or p_new_plan not in ('pro', 'premium') then
    raise exception 'invalid_subscription_plan' using errcode = '22023';
  end if;

  select * into v_sub
  from public.scrole_subscriptions
  where id = p_subscription_id and user_id = v_user
  for update;

  if not found then
    raise exception 'subscription_not_found_or_not_owned' using errcode = '42501';
  end if;
  if v_sub.status <> 'active' then
    raise exception 'subscription_not_active' using errcode = '22023';
  end if;
  if v_sub.plan_code <> 'premium' or p_new_plan <> 'pro' then
    raise exception 'only_premium_to_pro_downgrade_supported' using errcode = '22023';
  end if;

  select count(*) into v_event_count
  from public.event_certifications ec
  join public.events e on e.id = ec.event_id
  where ec.subscription_id = p_subscription_id
    and ec.source = 'subscription_included'
    and ec.status in ('active', 'suspended')
    and e.creator_id = v_user;

  select count(*) into v_community_count
  from public.community_certifications cc
  join public.communities c on c.id = cc.community_id
  where cc.subscription_id = p_subscription_id
    and cc.source = 'subscription_included'
    and cc.status in ('active', 'suspended')
    and c.creator_id = v_user;

  if p_new_plan = 'pro' then
    if p_keep_event_id is not null and not exists (
      select 1 from public.event_certifications ec
      join public.events e on e.id = ec.event_id
      where ec.event_id = p_keep_event_id and e.creator_id = v_user
        and ec.subscription_id = p_subscription_id
        and ec.source = 'subscription_included'
        and ec.status in ('active', 'suspended')
    ) then
      raise exception 'selected_event_certification_not_eligible' using errcode = '22023';
    end if;
    if p_keep_community_id is not null and not exists (
      select 1 from public.community_certifications cc
      join public.communities c on c.id = cc.community_id
      where cc.community_id = p_keep_community_id and c.creator_id = v_user
        and cc.subscription_id = p_subscription_id
        and cc.source = 'subscription_included'
        and cc.status in ('active', 'suspended')
    ) then
      raise exception 'selected_community_certification_not_eligible' using errcode = '22023';
    end if;
  end if;

  -- Keep exactly the user-selected included certification when moving to Pro.
  -- All other included certifications are suspended, never deleted.
  if p_new_plan = 'pro' then
    update public.event_certifications ec
    set status = case when ec.event_id = p_keep_event_id then 'active' else 'suspended' end,
        suspended_at = case when ec.event_id = p_keep_event_id then null else coalesce(ec.suspended_at, now()) end,
        updated_at = now()
    from public.events e
    where e.id = ec.event_id and e.creator_id = v_user
      and ec.subscription_id = p_subscription_id
      and ec.source = 'subscription_included'
      and ec.status in ('active', 'suspended');

    update public.community_certifications cc
    set status = case when cc.community_id = p_keep_community_id then 'active' else 'suspended' end,
        suspended_at = case when cc.community_id = p_keep_community_id then null else coalesce(cc.suspended_at, now()) end,
        updated_at = now()
    from public.communities c
    where c.id = cc.community_id and c.creator_id = v_user
      and cc.subscription_id = p_subscription_id
      and cc.source = 'subscription_included'
      and cc.status in ('active', 'suspended');
  end if;

  update public.scrole_subscriptions
  set plan_code = p_new_plan, updated_at = now()
  where id = p_subscription_id;

  insert into public.scrole_certification_audit(
    actor_user_id, subscription_id, entity_type, entity_id, action,
    previous_status, new_status, details
  ) values (
    v_user, p_subscription_id, 'subscription', p_subscription_id,
    'plan_changed', v_sub.plan_code, p_new_plan,
    jsonb_build_object(
      'kept_event_id', p_keep_event_id,
      'kept_community_id', p_keep_community_id,
      'prior_included_event_count', v_event_count,
      'prior_included_community_count', v_community_count
    )
  );

  return jsonb_build_object(
    'subscription_id', p_subscription_id,
    'previous_plan', v_sub.plan_code,
    'new_plan', p_new_plan,
    'kept_event_id', p_keep_event_id,
    'kept_community_id', p_keep_community_id,
    'suspended_other_included_certifications', p_new_plan = 'pro'
  );
end;
$$;

revoke all on function public.scrole_change_subscription_plan(uuid, text, uuid, uuid) from public, anon;
grant execute on function public.scrole_change_subscription_plan(uuid, text, uuid, uuid) to authenticated;

-- Server-only lifecycle transition: expiration suspends subscription-included
-- entity certifications but leaves purchased/admin-granted certifications untouched.
-- Designed for a trusted scheduler/backend; authenticated clients cannot execute it.
create or replace function public.scrole_suspend_expired_subscription_certifications()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_changed integer := 0;
begin
  with expired_subscriptions as (
    update public.scrole_subscriptions
    set status = 'expired', updated_at = now()
    where status = 'active' and ends_at is not null and ends_at <= now()
    returning id
  ), suspended_events as (
    update public.event_certifications ec
    set status = 'suspended', suspended_at = coalesce(ec.suspended_at, now()), updated_at = now()
    where ec.source = 'subscription_included'
      and ec.status = 'active'
      and ec.subscription_id in (select id from expired_subscriptions)
    returning ec.id
  ), suspended_communities as (
    update public.community_certifications cc
    set status = 'suspended', suspended_at = coalesce(cc.suspended_at, now()), updated_at = now()
    where cc.source = 'subscription_included'
      and cc.status = 'active'
      and cc.subscription_id in (select id from expired_subscriptions)
    returning cc.id
  )
  select (select count(*) from suspended_events) + (select count(*) from suspended_communities)
  into v_changed;

  return v_changed;
end;
$$;

revoke all on function public.scrole_suspend_expired_subscription_certifications() from public, anon, authenticated;
grant execute on function public.scrole_suspend_expired_subscription_certifications() to service_role;
