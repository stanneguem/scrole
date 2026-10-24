-- Return the authoritative member count for a community, including its creator.
create or replace function public.get_community_member_count(p_community_id uuid)
returns integer
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not public.can_view_community(p_community_id) then
    raise exception 'Community is not accessible';
  end if;

  select count(*)::integer
    into v_count
  from public.community_members cm
  join public.user_profiles up on up.user_id = cm.user_id
  where cm.community_id = p_community_id
    and lower(coalesce(up.account_status, '')) = 'active'
    and up.deleted_at is null;

  return coalesce(v_count, 0);
end;
$$;

revoke all on function public.get_community_member_count(uuid) from public, anon;
grant execute on function public.get_community_member_count(uuid) to authenticated;
