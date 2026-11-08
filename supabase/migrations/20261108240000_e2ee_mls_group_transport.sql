-- MLS group transport for direct conversations and community salons.
-- Stores opaque MLS ciphertext only. Legacy plaintext message tables remain
-- unchanged until clients are fully migrated and explicitly enable E2EE.

create table if not exists public.e2ee_groups (
  id uuid primary key default gen_random_uuid(),
  scope_type text not null check (scope_type in ('direct', 'community_salon')),
  scope_id uuid not null,
  mls_group_id bytea not null check (octet_length(mls_group_id) between 1 and 255),
  created_by uuid not null references auth.users(id) on delete restrict,
  epoch bigint not null default 0 check (epoch >= 0),
  status text not null default 'pending'
    check (status in ('pending', 'active', 'rekey_required', 'suspended')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (scope_type, scope_id),
  unique (mls_group_id)
);

create table if not exists public.e2ee_group_devices (
  group_id uuid not null references public.e2ee_groups(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  device_id uuid not null,
  joined_epoch bigint not null default 0 check (joined_epoch >= 0),
  added_at timestamptz not null default now(),
  primary key (group_id, device_id),
  foreign key (device_id, user_id)
    references public.e2ee_devices(id, user_id) on delete cascade
);

create index if not exists e2ee_group_devices_user_idx
  on public.e2ee_group_devices (user_id, group_id);

create table if not exists public.e2ee_messages (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.e2ee_groups(id) on delete cascade,
  sender_user_id uuid not null references auth.users(id) on delete restrict,
  sender_device_id uuid not null,
  epoch bigint not null check (epoch >= 0),
  message_kind smallint not null check (message_kind in (1, 2)),
  ciphertext bytea not null check (octet_length(ciphertext) between 1 and 1048576),
  created_at timestamptz not null default now(),
  foreign key (group_id, sender_device_id)
    references public.e2ee_group_devices(group_id, device_id) on delete restrict
);

create index if not exists e2ee_messages_group_cursor_idx
  on public.e2ee_messages (group_id, created_at, id);

alter table public.e2ee_groups enable row level security;
alter table public.e2ee_group_devices enable row level security;
alter table public.e2ee_messages enable row level security;

revoke all on public.e2ee_groups from anon, public, authenticated;
revoke all on public.e2ee_group_devices from anon, public, authenticated;
revoke all on public.e2ee_messages from anon, public, authenticated;
grant select on public.e2ee_groups, public.e2ee_group_devices, public.e2ee_messages to authenticated;

drop policy if exists e2ee_groups_read_member on public.e2ee_groups;
create policy e2ee_groups_read_member on public.e2ee_groups
for select to authenticated using (
  exists (
    select 1
    from public.e2ee_group_devices gd
    where gd.group_id = id and gd.user_id = (select auth.uid())
  )
  and (
    (scope_type = 'direct' and exists (
      select 1 from public.direct_conversations dc
      where dc.id = scope_id
        and (dc.user_one_id = (select auth.uid()) or dc.user_two_id = (select auth.uid()))
    ))
    or
    (scope_type = 'community_salon' and exists (
      select 1 from public.community_salon_members sm
      where sm.salon_id = scope_id and sm.user_id = (select auth.uid())
    ))
  )
);

drop policy if exists e2ee_group_devices_read_member on public.e2ee_group_devices;
create policy e2ee_group_devices_read_member on public.e2ee_group_devices
for select to authenticated using (
  exists (
    select 1 from public.e2ee_group_devices mine
    join public.e2ee_groups g on g.id = mine.group_id
    where mine.group_id = e2ee_group_devices.group_id
      and mine.user_id = (select auth.uid())
      and (
        (g.scope_type = 'direct' and exists (
          select 1 from public.direct_conversations dc
          where dc.id = g.scope_id
            and (dc.user_one_id = (select auth.uid()) or dc.user_two_id = (select auth.uid()))
        ))
        or
        (g.scope_type = 'community_salon' and exists (
          select 1 from public.community_salon_members sm
          where sm.salon_id = g.scope_id and sm.user_id = (select auth.uid())
        ))
      )
  )
);

drop policy if exists e2ee_messages_read_member on public.e2ee_messages;
create policy e2ee_messages_read_member on public.e2ee_messages
for select to authenticated using (
  exists (
    select 1
    from public.e2ee_group_devices gd
    join public.e2ee_groups g on g.id = gd.group_id
    where gd.group_id = e2ee_messages.group_id
      and gd.user_id = (select auth.uid())
      and (
        (g.scope_type = 'direct' and exists (
          select 1 from public.direct_conversations dc
          where dc.id = g.scope_id
            and (dc.user_one_id = (select auth.uid()) or dc.user_two_id = (select auth.uid()))
        ))
        or
        (g.scope_type = 'community_salon' and exists (
          select 1 from public.community_salon_members sm
          where sm.salon_id = g.scope_id and sm.user_id = (select auth.uid())
        ))
      )
  )
);

create or replace function public.e2ee_create_group(
  p_scope_type text,
  p_scope_id uuid,
  p_mls_group_id bytea,
  p_creator_device_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_group_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if p_scope_type not in ('direct', 'community_salon')
     or p_mls_group_id is null
     or octet_length(p_mls_group_id) not between 1 and 255 then
    raise exception 'Invalid E2EE group parameters' using errcode = '22023';
  end if;

  if not exists (
    select 1 from public.e2ee_devices d
    where d.id = p_creator_device_id
      and d.user_id = auth.uid()
      and d.revoked_at is null
  ) then
    raise exception 'Active owned E2EE device required' using errcode = '42501';
  end if;

  if p_scope_type = 'direct' and not exists (
    select 1 from public.direct_conversations dc
    where dc.id = p_scope_id
      and (dc.user_one_id = auth.uid() or dc.user_two_id = auth.uid())
  ) then
    raise exception 'Not a direct conversation participant' using errcode = '42501';
  end if;

  if p_scope_type = 'community_salon' and not exists (
    select 1 from public.community_salon_members sm
    where sm.salon_id = p_scope_id and sm.user_id = auth.uid()
  ) then
    raise exception 'Not a community salon member' using errcode = '42501';
  end if;

  insert into public.e2ee_groups(scope_type, scope_id, mls_group_id, created_by)
  values (p_scope_type, p_scope_id, p_mls_group_id, auth.uid())
  returning id into v_group_id;

  insert into public.e2ee_group_devices(group_id, user_id, device_id, joined_epoch)
  values (v_group_id, auth.uid(), p_creator_device_id, 0);

  return v_group_id;
end;
$function$;

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
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select * into v_group
  from public.e2ee_groups
  where id = p_group_id
  for update;

  if not found then
    raise exception 'E2EE group not found' using errcode = 'P0002';
  end if;

  if v_group.status = 'suspended' then
    raise exception 'E2EE group is suspended' using errcode = '55000';
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
      and (dc.user_one_id = auth.uid() or dc.user_two_id = auth.uid())
  ) then
    raise exception 'Not a direct conversation participant' using errcode = '42501';
  end if;

  if v_group.scope_type = 'community_salon' and not exists (
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

  select count(*)
  into v_valid_count
  from public.e2ee_devices d
  where d.id = any(p_active_device_ids)
    and d.revoked_at is null
    and (
      (v_group.scope_type = 'direct' and exists (
        select 1 from public.direct_conversations dc
        where dc.id = v_group.scope_id
          and d.user_id in (dc.user_one_id, dc.user_two_id)
      ))
      or
      (v_group.scope_type = 'community_salon' and exists (
        select 1 from public.community_salon_members sm
        where sm.salon_id = v_group.scope_id and sm.user_id = d.user_id
      ))
    );

  if v_valid_count <> v_device_count then
    raise exception 'Group roster contains an unavailable or out-of-scope device'
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
  set epoch = v_new_epoch,
      status = 'active',
      updated_at = now()
  where id = p_group_id;

  return v_new_epoch;
end;
$function$;

create or replace function public.e2ee_send_group_message(
  p_group_id uuid,
  p_epoch bigint,
  p_sender_device_id uuid,
  p_ciphertext bytea
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_group public.e2ee_groups%rowtype;
  v_message_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select * into v_group
  from public.e2ee_groups
  where id = p_group_id;

  if not found or v_group.status <> 'active' then
    raise exception 'E2EE group is not active' using errcode = '55000';
  end if;

  if p_epoch <> v_group.epoch then
    raise exception 'E2EE epoch conflict' using errcode = '40001';
  end if;

  if p_ciphertext is null or octet_length(p_ciphertext) not between 1 and 1048576 then
    raise exception 'Invalid MLS ciphertext' using errcode = '22023';
  end if;

  if not exists (
    select 1 from public.e2ee_group_devices gd
    join public.e2ee_devices d on d.id = gd.device_id
    where gd.group_id = p_group_id
      and gd.device_id = p_sender_device_id
      and gd.user_id = auth.uid()
      and d.revoked_at is null
  ) then
    raise exception 'Sender device is not an active group member' using errcode = '42501';
  end if;

  if v_group.scope_type = 'direct' and not exists (
    select 1 from public.direct_conversations dc
    where dc.id = v_group.scope_id
      and (dc.user_one_id = auth.uid() or dc.user_two_id = auth.uid())
  ) then
    raise exception 'Not a direct conversation participant' using errcode = '42501';
  end if;

  if v_group.scope_type = 'community_salon' and not exists (
    select 1 from public.community_salon_members sm
    where sm.salon_id = v_group.scope_id and sm.user_id = auth.uid()
  ) then
    raise exception 'Not a current community salon member' using errcode = '42501';
  end if;

  insert into public.e2ee_messages(
    group_id, sender_user_id, sender_device_id, epoch, message_kind, ciphertext
  ) values (
    p_group_id, auth.uid(), p_sender_device_id, p_epoch, 2, p_ciphertext
  ) returning id into v_message_id;

  return v_message_id;
end;
$function$;

create or replace function public.e2ee_mark_group_rekey_required()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_salon_id uuid;
begin
  v_salon_id := coalesce(new.salon_id, old.salon_id);
  update public.e2ee_groups
  set status = 'rekey_required', updated_at = now()
  where scope_type = 'community_salon'
    and scope_id = v_salon_id
    and status in ('active', 'pending');
  return coalesce(new, old);
end;
$function$;

drop trigger if exists e2ee_salon_membership_rekey on public.community_salon_members;
create trigger e2ee_salon_membership_rekey
after insert or delete on public.community_salon_members
for each row execute function public.e2ee_mark_group_rekey_required();

create or replace function public.e2ee_mark_device_groups_rekey_required()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if old.revoked_at is null and new.revoked_at is not null then
    update public.e2ee_groups g
    set status = 'rekey_required', updated_at = now()
    where g.id in (
      select gd.group_id from public.e2ee_group_devices gd
      where gd.device_id = new.id
    )
    and g.status = 'active';
  end if;
  return new;
end;
$function$;

drop trigger if exists e2ee_device_revocation_rekey on public.e2ee_devices;
create trigger e2ee_device_revocation_rekey
after update of revoked_at on public.e2ee_devices
for each row execute function public.e2ee_mark_device_groups_rekey_required();

revoke all on function public.e2ee_create_group(text, uuid, bytea, uuid) from public, anon;
revoke all on function public.e2ee_apply_group_commit(uuid, bigint, bytea, uuid[]) from public, anon;
revoke all on function public.e2ee_send_group_message(uuid, bigint, uuid, bytea) from public, anon;
grant execute on function public.e2ee_create_group(text, uuid, bytea, uuid) to authenticated;
grant execute on function public.e2ee_apply_group_commit(uuid, bigint, bytea, uuid[]) to authenticated;
grant execute on function public.e2ee_send_group_message(uuid, bigint, uuid, bytea) to authenticated;

comment on table public.e2ee_groups is
  'Opaque MLS group mapping. No plaintext conversation content or private MLS secrets are stored.';
comment on table public.e2ee_messages is
  'Opaque MLS commit/application ciphertext only. Message previews and plaintext are intentionally absent.';
comment on function public.e2ee_apply_group_commit(uuid, bigint, bytea, uuid[]) is
  'Atomically stores an MLS commit and replaces the server-side active device roster for the next epoch.';
