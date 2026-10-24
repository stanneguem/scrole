-- Add safe user search for group invitations. Only active group owners/admins may search.
create or replace function public.search_users_for_group_invite(p_group_id uuid, p_query text)
returns table(user_id uuid, username text, display_name text, avatar_url text)
language plpgsql security definer set search_path = ''
as $$
declare v_uid uuid := auth.uid(); v_query text := btrim(coalesce(p_query,''));
begin
  if v_uid is null then raise exception 'authentication_required' using errcode='28000'; end if;
  if length(v_query) < 2 or length(v_query) > 80 then return; end if;
  if not exists (
    select 1 from public.group_conversation_members m
    where m.group_id=p_group_id and m.user_id=v_uid and m.status='active'
      and m.role in ('owner','administrator')
  ) then raise exception 'not_allowed_to_invite' using errcode='42501'; end if;
  return query
  select p.user_id,p.username,
    coalesce(nullif(btrim(concat_ws(' ',p.first_name,p.last_name)),''),p.username,''),
    p.photo_url
  from public.user_profiles p
  where p.user_id<>v_uid
    and coalesce(p.account_status,'active')='active'
    and p.deleted_at is null
    and (
      p.username ilike '%' || replace(replace(v_query,'%','\%'),'_','\_') || '%'
      or p.first_name ilike '%' || replace(replace(v_query,'%','\%'),'_','\_') || '%'
      or p.last_name ilike '%' || replace(replace(v_query,'%','\%'),'_','\_') || '%'
    )
    and not exists (
      select 1 from public.group_conversation_members m
      where m.group_id=p_group_id and m.user_id=p.user_id and m.status='active'
    )
    and not exists (
      select 1 from public.group_conversation_invitations i
      where i.group_id=p_group_id and i.invited_user_id=p.user_id and i.status='pending'
        and (i.expires_at is null or i.expires_at>now())
    )
  order by p.username
  limit 20;
end $$;
revoke all on function public.search_users_for_group_invite(uuid,text) from public, anon;
grant execute on function public.search_users_for_group_invite(uuid,text) to authenticated;
