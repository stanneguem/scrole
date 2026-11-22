-- Harden MLS transport visibility. In particular, avoid recursive RLS
-- policies on e2ee_group_devices and never expose unclaimed KeyPackages via
-- table-wide SELECT. Claiming is performed only by the atomic SECURITY DEFINER RPC.

create or replace function private.e2ee_can_access_group(p_group_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select auth.uid() is not null
    and exists (
      select 1
      from public.e2ee_group_devices mine
      join public.e2ee_groups g on g.id = mine.group_id
      where mine.group_id = p_group_id
        and mine.user_id = auth.uid()
        and exists (
          select 1 from public.e2ee_devices d
          where d.id = mine.device_id
            and d.user_id = mine.user_id
            and d.revoked_at is null
        )
        and (
          (g.scope_type = 'direct' and exists (
            select 1 from public.direct_conversations dc
            where dc.id = g.scope_id
              and (dc.user_one_id = auth.uid() or dc.user_two_id = auth.uid())
          ))
          or
          (g.scope_type = 'community_salon' and exists (
            select 1 from public.community_salon_members sm
            where sm.salon_id = g.scope_id and sm.user_id = auth.uid()
          ))
        )
    );
$function$;

revoke all on function private.e2ee_can_access_group(uuid) from public, anon;
grant execute on function private.e2ee_can_access_group(uuid) to authenticated;

drop policy if exists e2ee_groups_read_member on public.e2ee_groups;
create policy e2ee_groups_read_member on public.e2ee_groups
for select to authenticated
using (private.e2ee_can_access_group(id));

drop policy if exists e2ee_group_devices_read_member on public.e2ee_group_devices;
create policy e2ee_group_devices_read_member on public.e2ee_group_devices
for select to authenticated
using (private.e2ee_can_access_group(group_id));

drop policy if exists e2ee_messages_read_member on public.e2ee_messages;
create policy e2ee_messages_read_member on public.e2ee_messages
for select to authenticated
using (private.e2ee_can_access_group(group_id));

-- Device public credentials can be looked up by authenticated users; private
-- identity material is never in this table. KeyPackages are different: expose
-- them only through the one-time claim function after authorization.
revoke select on public.e2ee_key_packages from authenticated;
drop policy if exists e2ee_key_packages_read_authenticated on public.e2ee_key_packages;

-- Remove direct table writes to the public device registry. Registration and
-- revocation are explicit RPCs so clients cannot forge timestamps or revive
-- revoked devices through direct UPDATE/INSERT requests.
revoke insert, update on public.e2ee_devices from authenticated;
drop policy if exists e2ee_devices_insert_self on public.e2ee_devices;
drop policy if exists e2ee_devices_update_self on public.e2ee_devices;

create or replace function public.e2ee_register_device(
  p_installation_id text,
  p_platform text,
  p_device_label text,
  p_public_credential bytea,
  p_credential_fingerprint bytea
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_installation_id is null or char_length(p_installation_id) not between 16 and 128
     or p_platform not in ('android', 'ios')
     or p_public_credential is null or octet_length(p_public_credential) not between 1 and 8192
     or p_credential_fingerprint is null or octet_length(p_credential_fingerprint) <> 32 then
    raise exception 'Invalid E2EE device registration' using errcode = '22023';
  end if;

  insert into public.e2ee_devices(
    user_id, installation_id, platform, device_label,
    public_credential, credential_fingerprint
  )
  values (
    auth.uid(), p_installation_id, p_platform,
    left(coalesce(p_device_label, ''), 120),
    p_public_credential, p_credential_fingerprint
  )
  on conflict (user_id, installation_id) do update
    set last_seen_at = now()
  where public.e2ee_devices.revoked_at is null
  returning id into v_id;

  if v_id is null then
    raise exception 'This installation was revoked and cannot be silently reactivated'
      using errcode = '55000';
  end if;
  return v_id;
end;
$function$;

create or replace function public.e2ee_revoke_device(p_device_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_count integer;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  update public.e2ee_devices
  set revoked_at = coalesce(revoked_at, now())
  where id = p_device_id and user_id = auth.uid() and revoked_at is null;

  get diagnostics v_count = row_count;
  return v_count = 1;
end;
$function$;

revoke all on function public.e2ee_register_device(text, text, text, bytea, bytea) from public, anon;
revoke all on function public.e2ee_revoke_device(uuid) from public, anon;
grant execute on function public.e2ee_register_device(text, text, text, bytea, bytea) to authenticated;
grant execute on function public.e2ee_revoke_device(uuid) to authenticated;

create or replace function public.e2ee_mark_group_rekey_required()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_salon_id uuid;
begin
  if tg_op = 'DELETE' then
    v_salon_id := old.salon_id;
  else
    v_salon_id := new.salon_id;
  end if;

  update public.e2ee_groups
  set status = 'rekey_required', updated_at = now()
  where scope_type = 'community_salon'
    and scope_id = v_salon_id
    and status in ('active', 'pending');

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$function$;
