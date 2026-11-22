-- Public MLS credentials should be discoverable only by the owner and
-- users sharing a direct conversation or community salon with that device.
create or replace function private.e2ee_can_discover_device(p_device_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select auth.uid() is not null
    and exists (
      select 1
      from public.e2ee_devices target
      where target.id = p_device_id
        and target.revoked_at is null
        and (
          target.user_id = auth.uid()
          or exists (
            select 1
            from public.direct_conversations dc
            where auth.uid() in (dc.user_one_id, dc.user_two_id)
              and target.user_id in (dc.user_one_id, dc.user_two_id)
          )
          or exists (
            select 1
            from public.community_salon_members mine
            join public.community_salon_members target_member
              on target_member.salon_id = mine.salon_id
            where mine.user_id = auth.uid()
              and target_member.user_id = target.user_id
          )
        )
    );
$function$;

revoke all on function private.e2ee_can_discover_device(uuid) from public, anon;
grant execute on function private.e2ee_can_discover_device(uuid) to authenticated;

drop policy if exists e2ee_devices_read_authenticated on public.e2ee_devices;
create policy e2ee_devices_read_scoped
on public.e2ee_devices
for select to authenticated
using (private.e2ee_can_discover_device(id));
