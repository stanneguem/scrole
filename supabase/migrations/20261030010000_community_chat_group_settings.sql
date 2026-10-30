-- Salon settings and administration are scoped strictly to community_salon_members.role.
-- A community administrator is not automatically a salon administrator.

create or replace function public.get_community_chat_group_settings(p_salon_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_salon public.community_salons;
  v_role text;
  v_members jsonb;
begin
  if v_uid is null then raise exception 'Authentification requise'; end if;

  select * into v_salon
  from public.community_salons
  where id = p_salon_id;

  if not found then raise exception 'Discussion introuvable'; end if;

  select m.role into v_role
  from public.community_salon_members m
  where m.salon_id = p_salon_id and m.user_id = v_uid;

  if v_role is null then raise exception 'Vous ne faites pas partie de cette discussion'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'user_id', m.user_id,
    'role', m.role,
    'joined_at', m.joined_at,
    'display_name', coalesce(nullif(trim(concat_ws(' ', up.first_name, up.last_name)), ''), up.username, 'Membre'),
    'username', up.username,
    'photo_url', up.photo_url
  ) order by case m.role when 'owner' then 0 when 'moderator' then 1 else 2 end, m.joined_at), '[]'::jsonb)
  into v_members
  from public.community_salon_members m
  left join public.user_profiles up on up.user_id = m.user_id
  where m.salon_id = p_salon_id;

  return jsonb_build_object(
    'id', v_salon.id,
    'community_id', v_salon.community_id,
    'name', v_salon.name,
    'description', v_salon.description,
    'visibility', v_salon.visibility,
    'avatar_url', v_salon.avatar_url,
    'created_by', v_salon.created_by,
    'my_role', v_role,
    'is_salon_admin', v_role in ('owner', 'moderator'),
    'is_salon_owner', v_role = 'owner',
    'member_count', jsonb_array_length(v_members),
    'members', v_members
  );
end;
$$;

create or replace function public.update_community_chat_group_settings(
  p_salon_id uuid,
  p_name text,
  p_description text,
  p_visibility text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_role text;
begin
  if v_uid is null then raise exception 'Authentification requise'; end if;
  select role into v_role from public.community_salon_members
  where salon_id = p_salon_id and user_id = v_uid;
  if v_role not in ('owner', 'moderator') then raise exception 'Action réservée aux administrateurs de cette discussion'; end if;
  if p_name is null or length(trim(p_name)) < 2 or length(trim(p_name)) > 80 then raise exception 'Nom du groupe invalide'; end if;
  if p_visibility not in ('public', 'private') then raise exception 'Visibilité invalide'; end if;
  update public.community_salons
  set name = trim(p_name), description = coalesce(trim(p_description), ''),
      visibility = p_visibility, updated_at = now()
  where id = p_salon_id;
  if not found then raise exception 'Discussion introuvable'; end if;
end;
$$;

create or replace function public.set_community_chat_group_member_role(
  p_salon_id uuid, p_user_id uuid, p_role text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_actor_role text;
begin
  if v_uid is null then raise exception 'Authentification requise'; end if;
  select role into v_actor_role from public.community_salon_members
  where salon_id = p_salon_id and user_id = v_uid;
  if v_actor_role <> 'owner' then raise exception 'Seul le propriétaire de la discussion peut gérer les rôles administrateurs'; end if;
  if p_role not in ('moderator', 'member') then raise exception 'Rôle invalide'; end if;
  if p_user_id = v_uid then raise exception 'Vous ne pouvez pas modifier votre propre rôle'; end if;
  update public.community_salon_members
  set role = p_role
  where salon_id = p_salon_id and user_id = p_user_id and role <> 'owner';
  if not found then raise exception 'Membre introuvable ou rôle non modifiable'; end if;
end;
$$;

create or replace function public.remove_community_chat_group_member(
  p_salon_id uuid, p_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_actor_role text;
  v_target_role text;
begin
  if v_uid is null then raise exception 'Authentification requise'; end if;
  select role into v_actor_role from public.community_salon_members
  where salon_id = p_salon_id and user_id = v_uid;
  select role into v_target_role from public.community_salon_members
  where salon_id = p_salon_id and user_id = p_user_id;
  if v_actor_role not in ('owner', 'moderator') then raise exception 'Action réservée aux administrateurs de cette discussion'; end if;
  if v_target_role is null then raise exception 'Membre introuvable'; end if;
  if v_target_role = 'owner' then raise exception 'Le propriétaire ne peut pas être retiré'; end if;
  if v_actor_role = 'moderator' and v_target_role <> 'member' then raise exception 'Un modérateur ne peut retirer qu’un membre'; end if;
  if p_user_id = v_uid then raise exception 'Utilisez Quitter la discussion pour vous retirer'; end if;
  delete from public.community_salon_members where salon_id = p_salon_id and user_id = p_user_id;
end;
$$;

create or replace function public.leave_community_chat_group(p_salon_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_role text;
begin
  if v_uid is null then raise exception 'Authentification requise'; end if;
  select role into v_role from public.community_salon_members
  where salon_id = p_salon_id and user_id = v_uid;
  if v_role is null then raise exception 'Vous ne faites pas partie de cette discussion'; end if;
  if v_role = 'owner' then raise exception 'Transférez la propriété de la discussion avant de la quitter'; end if;
  delete from public.community_salon_members where salon_id = p_salon_id and user_id = v_uid;
  update public.community_salon_join_requests
  set status = 'rejected', reviewed_at = now(), reviewed_by = v_uid
  where salon_id = p_salon_id and user_id = v_uid and status = 'pending';
end;
$$;

create or replace function public.delete_community_chat_group(p_salon_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_owner uuid;
begin
  if v_uid is null then raise exception 'Authentification requise'; end if;
  select created_by into v_owner from public.community_salons where id = p_salon_id for update;
  if v_owner is null then raise exception 'Discussion introuvable'; end if;
  if v_owner <> v_uid or not exists (
    select 1 from public.community_salon_members
    where salon_id = p_salon_id and user_id = v_uid and role = 'owner'
  ) then raise exception 'Seul le propriétaire de cette discussion peut la supprimer'; end if;
  delete from public.community_salons where id = p_salon_id;
end;
$$;

-- The existing avatar RPC must use salon-scoped roles too; community admins alone
-- must not gain control over a salon's avatar.
create or replace function public.set_community_chat_group_avatar(
  p_salon_id uuid, p_avatar_url text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_role text;
  v_expected_prefix text;
begin
  if v_uid is null then raise exception 'Utilisateur non authentifié'; end if;
  select role into v_role from public.community_salon_members
  where salon_id = p_salon_id and user_id = v_uid;
  if v_role not in ('owner', 'moderator') then
    raise exception 'Action réservée aux administrateurs de cette discussion';
  end if;
  v_expected_prefix := '/salons/' || p_salon_id::text || '/avatar/';
  if p_avatar_url is null or p_avatar_url !~ '^https://'
     or position(v_expected_prefix in p_avatar_url) = 0
     or p_avatar_url !~* '\.(jpg|jpeg|png|webp|avif|gif)(\?.*)?$' then
    raise exception 'URL de couverture R2 invalide';
  end if;
  update public.community_salons
  set avatar_url = p_avatar_url, updated_at = now()
  where id = p_salon_id;
  if not found then raise exception 'Discussion introuvable'; end if;
  return p_avatar_url;
end;
$$;

revoke all on function public.get_community_chat_group_settings(uuid) from public, anon;
revoke all on function public.update_community_chat_group_settings(uuid,text,text,text) from public, anon;
revoke all on function public.set_community_chat_group_member_role(uuid,uuid,text) from public, anon;
revoke all on function public.remove_community_chat_group_member(uuid,uuid) from public, anon;
revoke all on function public.leave_community_chat_group(uuid) from public, anon;
revoke all on function public.delete_community_chat_group(uuid) from public, anon;
revoke all on function public.set_community_chat_group_avatar(uuid,text) from public, anon;

grant execute on function public.get_community_chat_group_settings(uuid) to authenticated;
grant execute on function public.update_community_chat_group_settings(uuid,text,text,text) to authenticated;
grant execute on function public.set_community_chat_group_member_role(uuid,uuid,text) to authenticated;
grant execute on function public.remove_community_chat_group_member(uuid,uuid) to authenticated;
grant execute on function public.leave_community_chat_group(uuid) to authenticated;
grant execute on function public.delete_community_chat_group(uuid) to authenticated;
grant execute on function public.set_community_chat_group_avatar(uuid,text) to authenticated;
