-- Refreshing a KeyPackage for an already-enrolled device must not
-- invalidate active groups. Only newly provisioned devices require rekeying.
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
      and not exists (
        select 1 from public.e2ee_group_devices enrolled
        where enrolled.group_id = g.id and enrolled.device_id = new.device_id
      )
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

revoke all on function public.e2ee_mark_groups_rekey_on_key_package()
  from public, anon, authenticated;
