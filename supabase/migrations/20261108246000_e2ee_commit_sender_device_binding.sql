-- Bind an MLS Commit to the exact registered device that produced it.
-- The previous RPC selected an arbitrary enrolled device owned by auth.uid(),
-- which was insufficient for accurate multi-device sender attribution.
drop function if exists public.e2ee_apply_group_commit(uuid, bigint, bytea, uuid[]);

create or replace function public.e2ee_apply_group_commit(
  p_group_id uuid,
  p_expected_epoch bigint,
  p_sender_device_id uuid,
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
      and gd.device_id = p_sender_device_id
      and gd.user_id = auth.uid()
      and d.revoked_at is null
  ) then
    raise exception 'Active sender device required' using errcode = '42501';
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
    and gd.device_id = p_sender_device_id
    and gd.user_id = auth.uid()
    and d.revoked_at is null;

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

-- Publishing a KeyPackage is the point at which a new device becomes eligible
-- for MLS membership. Existing groups must rekey before continuing to send.

revoke all on function public.e2ee_apply_group_commit(uuid, bigint, uuid, bytea, uuid[])
  from public, anon;
grant execute on function public.e2ee_apply_group_commit(uuid, bigint, uuid, bytea, uuid[])
  to authenticated;
