-- Allow community administrators to moderate every chat salon in their community.
-- Salon owners retain their existing ability to delete their own salon.

create or replace function public.list_community_admin_salons(p_community_id uuid)
returns table (
  id uuid,
  name text,
  description text,
  visibility text,
  avatar_url text,
  created_at timestamptz,
  member_count bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  if (select auth.uid()) is null
     or not public.is_community_admin(p_community_id) then
    raise exception 'Accès réservé aux administrateurs de la communauté';
  end if;

  return query
  select s.id, s.name, s.description, s.visibility, s.avatar_url,
         s.created_at,
         (select count(*) from public.community_salon_members m where m.salon_id = s.id)
  from public.community_salons s
  where s.community_id = p_community_id
  order by s.created_at desc;
end;
$function$;

revoke all on function public.list_community_admin_salons(uuid) from public, anon;
grant execute on function public.list_community_admin_salons(uuid) to authenticated;

create or replace function public.delete_community_chat_group(p_salon_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_community_id uuid;
  v_owner uuid;
begin
  if v_uid is null then
    raise exception 'Authentification requise';
  end if;

  select s.community_id, s.created_by
    into v_community_id, v_owner
  from public.community_salons s
  where s.id = p_salon_id
  for update;

  if v_community_id is null then
    raise exception 'Discussion introuvable';
  end if;

  if not public.is_community_admin(v_community_id)
     and not (
       v_owner = v_uid
       and exists (
         select 1
         from public.community_salon_members m
         where m.salon_id = p_salon_id
           and m.user_id = v_uid
           and m.role = 'owner'
       )
     ) then
    raise exception 'Seul le propriétaire de cette discussion ou un administrateur de la communauté peut la supprimer';
  end if;

  delete from public.community_salons where id = p_salon_id;
end;
$function$;

revoke all on function public.delete_community_chat_group(uuid) from public, anon;
grant execute on function public.delete_community_chat_group(uuid) to authenticated;
