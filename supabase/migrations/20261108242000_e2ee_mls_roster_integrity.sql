-- Enforce complete MLS device rosters and scope-limited KeyPackage claims.
-- A participant cannot silently omit another active device from a commit roster,
-- and KeyPackages cannot be claimed by unrelated authenticated users.

create or replace function private.e2ee_claim_key_package_for_scope(
  p_scope_type text,
  p_scope_id uuid,
  p_target_device_id uuid,
  p_claiming_device_id uuid
)
returns table (
  package_id uuid,
  ciphersuite text,
  key_package bytea,
  package_hash bytea,
  source_device_id uuid
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_target_user_id uuid;
  v_claiming_user_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if p_scope_type not in ('direct', 'community_salon') or p_scope_id is null then
    raise exception 'Invalid E2EE scope' using errcode = '22023';
  end if;

  select d.user_id into v_target_user_id
  from public.e2ee_devices d
  where d.id = p_target_device_id and d.revoked_at is null;

  select d.user_id into v_claiming_user_id
  from public.e2ee_devices d
  where d.id = p_claiming_device_id
    and d.user_id = auth.uid()
    and d.revoked_at is null;

  if v_target_user_id is null or v_claiming_user_id is null then
    raise exception 'Active target and claiming devices are required' using errcode = '42501';
  end if;

  if p_scope_type = 'direct' and not exists (
    select 1 from public.direct_conversations dc
    where dc.id = p_scope_id
      and auth.uid() in (dc.user_one_id, dc.user_two_id)
      and v_target_user_id in (dc.user_one_id, dc.user_two_id)
  ) then
    raise exception 'Target device is outside this direct conversation' using errcode = '42501';
  end if;

  if p_scope_type = 'community_salon' and (
    not exists (
      select 1 from public.community_salon_members sm
      where sm.salon_id = p_scope_id and sm.user_id = auth.uid()
    )
    or not exists (
      select 1 from public.community_salon_members sm
      where sm.salon_id = p_scope_id and sm.user_id = v_target_user_id
    )
  ) then
    raise exception 'Target device is outside this community salon' using errcode = '42501';
  end if;

  return query
  select *
  from private.e2ee_claim_key_package(p_target_device_id, p_claiming_device_id);
end;
$function$;

revoke all on function private.e2ee_claim_key_package_for_scope(text, uuid, uuid, uuid)
  from public, anon;
grant execute on function private.e2ee_claim_key_package_for_scope(text, uuid, uuid, uuid)
  to authenticated;

create or replace function public.e2ee_claim_key_package_for_scope(
  p_scope_type text,
  p_scope_id uuid,
  p_target_device_id uuid,
  p_claiming_device_id uuid
)
returns table (
  package_id uuid,
  ciphersuite text,
  key_package bytea,
  package_hash bytea,
  source_device_id uuid
)
language sql
security invoker
set search_path = public, pg_temp
as $function$
  select *
  from private.e2ee_claim_key_package_for_scope(
    p_scope_type, p_scope_id, p_target_device_id, p_claiming_device_id
  );
$function$;

revoke all on function public.e2ee_claim_key_package(uuid, uuid) from public, anon, authenticated;
revoke all on function public.e2ee_claim_key_package_for_scope(text, uuid, uuid, uuid)
  from public, anon;
grant execute on function public.e2ee_claim_key_package_for_scope(text, uuid, uuid, uuid)
  to authenticated;

create or replace function public.e2ee_apply_group_commit(
  p_group_id uuid,
  p_expected_epoch bigint,
  p_commit_ciphertext bytea,
  p_active_device_ids uuid[]
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_group public.e2ee_groups%rowtype;
  v_new_epoch bigint;
  v_device_count integer;
  v_valid_count integer;
  v_expected_count integer;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select * into v_group
  from public.e2ee_groups
  where id = p_group_id
  for update;

  if not found or v_group.status = 'suspended' then
    raise exception 'E2EE group unavailable' using errcode = '55000';
  end if;

  if v_group.epoch <> p_expected_epoch then
    raise exception 'E2EE epoch conflict' using errcode = '40001';
  end if;

  if not exists (
    select 1 from public.e2ee_group_devices gd
    join public.e2ee_devices d on d.id = gd.device_id
    where gd.group_id = p_group_id
      and gd.user_id = auth.uid()
      and d.revoked_at is null
  ) then
    raise exception 'Active group device required' using errcode = '42501';
  end if;

  if v_group.scope_type = 'direct' and not exists (
    select 1 from public.direct_conversations dc
    where dc.id = v_group.scope_id
      and auth.uid() in (dc.user_one_id, dc.user_two_id)
  ) then
    raise exception 'Not a direct conversation participant' using errcode = '42501';
  elsif v_group.scope_type = 'community_salon' and not exists (
    select 1 from public.community_salon_members sm
    where sm.salon_id = v_group.scope_id and sm.user_id = auth.uid()
  ) then
    raise exception 'Not a current community salon member' using errcode = '42501';
  end if;

  if p_commit_ciphertext is null
     or octet_length(p_commit_ciphertext) not between 1 and 1048576
     or p_active_device_ids is null
     or cardinality(p_active_device_ids) not between 1 and 512 then
    raise exception 'Invalid MLS commit or member device list' using errcode = '22023';
  end if;

  select count(distinct x), count(*)
  into v_valid_count, v_device_count
  from unnest(p_active_device_ids) as x;

  if v_valid_count <> v_device_count then
    raise exception 'Duplicate E2EE device in group roster' using errcode = '22023';
  end if;

  -- Existing MLS devices plus devices that have published at least one
  -- KeyPackage for this scope. Merely registering an unused installation must
  -- not let it freeze every conversation the account belongs to.
  if v_group.scope_type = 'direct' then
    select count(*) into v_expected_count
    from public.e2ee_devices d
    join public.direct_conversations dc
      on d.user_id in (dc.user_one_id, dc.user_two_id)
    where dc.id = v_group.scope_id
      and d.revoked_at is null
      and (
        exists (
          select 1 from public.e2ee_group_devices current_member
          where current_member.group_id = p_group_id
            and current_member.device_id = d.id
        )
        or exists (
          select 1 from public.e2ee_key_packages kp
          where kp.device_id = d.id
        )
      );
  else
    select count(*) into v_expected_count
    from public.e2ee_devices d
    join public.community_salon_members sm on sm.user_id = d.user_id
    where sm.salon_id = v_group.scope_id
      and d.revoked_at is null
      and (
        exists (
          select 1 from public.e2ee_group_devices current_member
          where current_member.group_id = p_group_id
            and current_member.device_id = d.id
        )
        or exists (
          select 1 from public.e2ee_key_packages kp
          where kp.device_id = d.id
        )
      );
  end if;

  if v_expected_count <> v_device_count then
    raise exception 'MLS roster must include every active device in the conversation'
      using errcode = '42501';
  end if;

  if v_group.scope_type = 'direct' then
    select count(*) into v_valid_count
    from public.e2ee_devices d
    join public.direct_conversations dc
      on d.user_id in (dc.user_one_id, dc.user_two_id)
    where dc.id = v_group.scope_id
      and d.revoked_at is null
      and d.id = any(p_active_device_ids)
      and (
        exists (
          select 1 from public.e2ee_group_devices current_member
          where current_member.group_id = p_group_id
            and current_member.device_id = d.id
        )
        or exists (
          select 1 from public.e2ee_key_packages kp
          where kp.device_id = d.id
        )
      );
  else
    select count(*) into v_valid_count
    from public.e2ee_devices d
    join public.community_salon_members sm on sm.user_id = d.user_id
    where sm.salon_id = v_group.scope_id
      and d.revoked_at is null
      and d.id = any(p_active_device_ids)
      and (
        exists (
          select 1 from public.e2ee_group_devices current_member
          where current_member.group_id = p_group_id
            and current_member.device_id = d.id
        )
        or exists (
          select 1 from public.e2ee_key_packages kp
          where kp.device_id = d.id
        )
      );
  end if;

  if v_valid_count <> v_expected_count then
    raise exception 'MLS roster does not match the complete active device set'
      using errcode = '42501';
  end if;

  v_new_epoch := v_group.epoch + 1;

  insert into public.e2ee_messages(
    group_id, sender_user_id, sender_device_id, epoch, message_kind, ciphertext
  )
  select p_group_id, gd.user_id, gd.device_id, v_group.epoch, 1, p_commit_ciphertext
  from public.e2ee_group_devices gd
  join public.e2ee_devices d on d.id = gd.device_id
  where gd.group_id = p_group_id
    and gd.user_id = auth.uid()
    and d.revoked_at is null
  order by gd.device_id
  limit 1;

  delete from public.e2ee_group_devices where group_id = p_group_id;

  insert into public.e2ee_group_devices(group_id, user_id, device_id, joined_epoch)
  select p_group_id, d.user_id, d.id, v_new_epoch
  from public.e2ee_devices d
  where d.id = any(p_active_device_ids)
    and d.revoked_at is null;

  update public.e2ee_groups
  set epoch = v_new_epoch, status = 'active', updated_at = now()
  where id = p_group_id;

  return v_new_epoch;
end;
$function$;

revoke all on function public.e2ee_apply_group_commit(uuid, bigint, bytea, uuid[])
  from public, anon;
grant execute on function public.e2ee_apply_group_commit(uuid, bigint, bytea, uuid[])
  to authenticated;

-- Publishing a KeyPackage is the point at which a new device becomes eligible
-- for MLS membership. Existing groups must rekey before continuing to send.
create or replace function public.e2ee_mark_groups_rekey_on_key_package()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid;
begin
  select user_id into v_user_id
  from public.e2ee_devices
  where id = new.device_id and revoked_at is null;

  if v_user_id is not null then
    update public.e2ee_groups g
    set status = 'rekey_required', updated_at = now()
    where g.status in ('active', 'pending')
      and (
        (g.scope_type = 'direct' and exists (
          select 1 from public.direct_conversations dc
          where dc.id = g.scope_id and v_user_id in (dc.user_one_id, dc.user_two_id)
        ))
        or
        (g.scope_type = 'community_salon' and exists (
          select 1 from public.community_salon_members sm
          where sm.salon_id = g.scope_id and sm.user_id = v_user_id
        ))
      );
  end if;
  return new;
end;
$function$;

drop trigger if exists e2ee_key_package_rekey on public.e2ee_key_packages;
create trigger e2ee_key_package_rekey
after insert on public.e2ee_key_packages
for each row execute function public.e2ee_mark_groups_rekey_on_key_package();

revoke all on function public.e2ee_mark_groups_rekey_on_key_package() from public, anon, authenticated;

comment on function public.e2ee_apply_group_commit(uuid, bigint, bytea, uuid[]) is
  'Applies an MLS commit only when its next roster includes every active device of every current scope member.';
comment on function public.e2ee_claim_key_package_for_scope(text, uuid, uuid, uuid) is
  'Atomically claims a one-time KeyPackage only when the target device belongs to the same authorized conversation or salon.';
