-- Restrict one-time MLS KeyPackage consumption to an authenticated,
-- self-owned claiming device. Clients must never update consumption fields.
-- The private worker is SECURITY DEFINER with a fixed empty search_path;
-- the exposed wrapper remains SECURITY INVOKER and checks auth.uid().

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to authenticated;

create or replace function private.e2ee_claim_key_package(
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
begin
  if auth.uid() is null or not exists (
    select 1
    from public.e2ee_devices d
    where d.id = p_claiming_device_id
      and d.user_id = auth.uid()
      and d.revoked_at is null
  ) then
    raise exception 'E2EE claiming device is not owned by the authenticated user'
      using errcode = '42501';
  end if;

  return query
  with candidate as (
    select kp.id
    from public.e2ee_key_packages kp
    join public.e2ee_devices source_device on source_device.id = kp.device_id
    where kp.device_id = p_target_device_id
      and source_device.revoked_at is null
      and kp.consumed_at is null
      and kp.expires_at > now()
    order by kp.created_at asc
    for update of kp skip locked
    limit 1
  )
  update public.e2ee_key_packages kp
  set consumed_at = now(),
      consumed_by_device_id = p_claiming_device_id
  from candidate
  where kp.id = candidate.id
  returning kp.id, kp.ciphersuite, kp.key_package, kp.package_hash, kp.device_id;
end;
$function$;

revoke all on function private.e2ee_claim_key_package(uuid, uuid) from public, anon;
grant execute on function private.e2ee_claim_key_package(uuid, uuid) to authenticated;

revoke update on public.e2ee_key_packages from authenticated;
drop policy if exists e2ee_key_packages_claim_once on public.e2ee_key_packages;

create or replace function public.e2ee_claim_key_package(
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
  from private.e2ee_claim_key_package(
    p_target_device_id,
    p_claiming_device_id
  );
$function$;

revoke all on function public.e2ee_claim_key_package(uuid, uuid) from public, anon;
grant execute on function public.e2ee_claim_key_package(uuid, uuid) to authenticated;
