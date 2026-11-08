-- Scrole E2EE foundation: public MLS device credentials and one-time key packages.
-- This migration is intentionally additive. It does NOT enable encrypted messages
-- or alter legacy plaintext message RPCs. E2EE activation is blocked until the
-- audited native MLS engine is integrated into Flutter.

create table if not exists public.e2ee_devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  installation_id text not null check (char_length(installation_id) between 16 and 128),
  platform text not null check (platform in ('android', 'ios')),
  device_label text,
  protocol_version smallint not null default 1 check (protocol_version = 1),
  public_credential bytea not null check (octet_length(public_credential) between 1 and 8192),
  credential_fingerprint bytea not null check (octet_length(credential_fingerprint) = 32),
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  revoked_at timestamptz,
  unique (user_id, installation_id),
  unique (id, user_id)
);

create index if not exists e2ee_devices_active_user_idx
  on public.e2ee_devices (user_id, last_seen_at desc)
  where revoked_at is null;

create table if not exists public.e2ee_key_packages (
  id uuid primary key default gen_random_uuid(),
  device_id uuid not null references public.e2ee_devices(id) on delete cascade,
  ciphersuite text not null check (char_length(ciphersuite) between 1 and 128),
  key_package bytea not null check (octet_length(key_package) between 1 and 65536),
  package_hash bytea not null unique check (octet_length(package_hash) = 32),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  consumed_at timestamptz,
  consumed_by_device_id uuid references public.e2ee_devices(id) on delete set null,
  constraint e2ee_key_package_expiry_check check (expires_at > created_at),
  constraint e2ee_key_package_consumption_check check (
    (consumed_at is null and consumed_by_device_id is null)
    or (consumed_at is not null and consumed_by_device_id is not null)
  )
);

create index if not exists e2ee_key_packages_available_idx
  on public.e2ee_key_packages (device_id, created_at)
  where consumed_at is null;

alter table public.e2ee_devices enable row level security;
alter table public.e2ee_key_packages enable row level security;

revoke all on public.e2ee_devices from anon, public;
revoke all on public.e2ee_key_packages from anon, public;
grant select, insert on public.e2ee_devices to authenticated;
grant update (last_seen_at, revoked_at) on public.e2ee_devices to authenticated;
grant select, insert on public.e2ee_key_packages to authenticated;
grant update (consumed_at, consumed_by_device_id) on public.e2ee_key_packages to authenticated;

drop policy if exists e2ee_devices_read_authenticated on public.e2ee_devices;
create policy e2ee_devices_read_authenticated
  on public.e2ee_devices for select to authenticated
  using (revoked_at is null);

drop policy if exists e2ee_devices_insert_self on public.e2ee_devices;
create policy e2ee_devices_insert_self
  on public.e2ee_devices for insert to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists e2ee_devices_update_self on public.e2ee_devices;
create policy e2ee_devices_update_self
  on public.e2ee_devices for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

drop policy if exists e2ee_key_packages_read_authenticated on public.e2ee_key_packages;
create policy e2ee_key_packages_read_authenticated
  on public.e2ee_key_packages for select to authenticated
  using (expires_at > now());

drop policy if exists e2ee_key_packages_insert_own_device on public.e2ee_key_packages;
create policy e2ee_key_packages_insert_own_device
  on public.e2ee_key_packages for insert to authenticated
  with check (
    exists (
      select 1 from public.e2ee_devices d
      where d.id = device_id
        and d.user_id = (select auth.uid())
        and d.revoked_at is null
    )
  );

drop policy if exists e2ee_key_packages_claim_once on public.e2ee_key_packages;
create policy e2ee_key_packages_claim_once
  on public.e2ee_key_packages for update to authenticated
  using (consumed_at is null and expires_at > now())
  with check (
    consumed_at is not null
    and exists (
      select 1 from public.e2ee_devices d
      where d.id = consumed_by_device_id
        and d.user_id = (select auth.uid())
        and d.revoked_at is null
    )
  );

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
language plpgsql
security invoker
set search_path = public, pg_temp
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

revoke all on function public.e2ee_claim_key_package(uuid, uuid) from public, anon;
grant execute on function public.e2ee_claim_key_package(uuid, uuid) to authenticated;

comment on table public.e2ee_devices is
  'Public MLS device credentials only. Private identity keys and MLS state must remain on user devices.';
comment on table public.e2ee_key_packages is
  'Public, single-use MLS KeyPackages. Private keys are never stored in Supabase.';
comment on function public.e2ee_claim_key_package(uuid, uuid) is
  'Atomically consumes one available MLS KeyPackage for an authenticated user device.';
