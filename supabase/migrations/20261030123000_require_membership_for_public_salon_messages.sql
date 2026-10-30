-- A public salon is discoverable, but message access is restricted to members.
-- Keep the same authorization function in the repository migration history.
create or replace function public.can_access_salon(p_salon_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $function$
declare
  v_salon public.community_salons;
  v_uid uuid := auth.uid();
begin
  if v_uid is null then return false; end if;
  select * into v_salon from public.community_salons where id = p_salon_id;
  if not found then return false; end if;
  if not public.is_community_member(v_salon.community_id)
     or not public.check_salon_eligibility(p_salon_id, v_uid) then
    return false;
  end if;
  return v_salon.created_by = v_uid
    or exists (
      select 1 from public.community_salon_members m
      where m.salon_id = p_salon_id and m.user_id = v_uid
    );
end;
$function$;

revoke all on function public.can_access_salon(uuid) from public, anon;
grant execute on function public.can_access_salon(uuid) to authenticated;
