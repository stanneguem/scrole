create table if not exists public.community_salon_user_preferences (
  salon_id uuid not null references public.community_salons(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  notifications_enabled boolean not null default true,
  media_visibility_enabled boolean not null default true,
  updated_at timestamptz not null default now(),
  primary key (salon_id, user_id)
);

alter table public.community_salon_user_preferences enable row level security;
drop policy if exists "Users can read own salon preferences" on public.community_salon_user_preferences;
create policy "Users can read own salon preferences"
on public.community_salon_user_preferences for select to authenticated
using (user_id = (select auth.uid()));
drop policy if exists "Users can insert own salon preferences" on public.community_salon_user_preferences;
create policy "Users can insert own salon preferences"
on public.community_salon_user_preferences for insert to authenticated
with check (
  user_id = (select auth.uid())
  and exists (select 1 from public.community_salon_members m
    where m.salon_id = community_salon_user_preferences.salon_id
      and m.user_id = (select auth.uid()))
);
drop policy if exists "Users can update own salon preferences" on public.community_salon_user_preferences;
create policy "Users can update own salon preferences"
on public.community_salon_user_preferences for update to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

create or replace function public.update_community_chat_group_preferences(
  p_salon_id uuid,
  p_notifications_enabled boolean,
  p_media_visibility_enabled boolean
) returns void
language plpgsql security definer set search_path = public
as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'Authentification requise'; end if;
  if not exists (select 1 from public.community_salon_members
    where salon_id = p_salon_id and user_id = v_uid) then
    raise exception 'Vous ne faites pas partie de cette discussion';
  end if;
  insert into public.community_salon_user_preferences
    (salon_id,user_id,notifications_enabled,media_visibility_enabled,updated_at)
  values (p_salon_id,v_uid,p_notifications_enabled,p_media_visibility_enabled,now())
  on conflict (salon_id,user_id) do update set
    notifications_enabled = excluded.notifications_enabled,
    media_visibility_enabled = excluded.media_visibility_enabled,
    updated_at = now();
end;
$$;

revoke all on function public.update_community_chat_group_preferences(uuid,boolean,boolean) from public, anon;
grant execute on function public.update_community_chat_group_preferences(uuid,boolean,boolean) to authenticated;

create or replace function public.get_community_chat_group_settings(p_salon_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_salon public.community_salons;
  v_role text;
  v_members jsonb;
  v_preferences public.community_salon_user_preferences;
begin
  if v_uid is null then raise exception 'Authentification requise'; end if;
  select * into v_salon from public.community_salons where id = p_salon_id;
  if not found then raise exception 'Discussion introuvable'; end if;
  select m.role into v_role from public.community_salon_members m
    where m.salon_id = p_salon_id and m.user_id = v_uid;
  if v_role is null then raise exception 'Vous ne faites pas partie de cette discussion'; end if;
  select * into v_preferences from public.community_salon_user_preferences
    where salon_id = p_salon_id and user_id = v_uid;
  select coalesce(jsonb_agg(jsonb_build_object(
    'user_id',m.user_id,'role',m.role,'joined_at',m.joined_at,
    'display_name',coalesce(nullif(trim(concat_ws(' ',up.first_name,up.last_name)),''),up.username,'Membre'),
    'username',up.username,'photo_url',up.photo_url
  ) order by case m.role when 'owner' then 0 when 'moderator' then 1 else 2 end,m.joined_at),'[]'::jsonb)
  into v_members
  from public.community_salon_members m
  left join public.user_profiles up on up.user_id=m.user_id
  where m.salon_id=p_salon_id;
  return jsonb_build_object(
    'id',v_salon.id,'community_id',v_salon.community_id,'name',v_salon.name,
    'description',v_salon.description,'visibility',v_salon.visibility,
    'avatar_url',v_salon.avatar_url,'created_by',v_salon.created_by,
    'my_role',v_role,'is_salon_admin',v_role in ('owner','moderator'),
    'is_salon_owner',v_role='owner','member_count',jsonb_array_length(v_members),
    'notifications_enabled',coalesce(v_preferences.notifications_enabled,true),
    'media_visibility_enabled',coalesce(v_preferences.media_visibility_enabled,true),
    'members',v_members
  );
end;
$$;
revoke all on function public.get_community_chat_group_settings(uuid) from public, anon;
grant execute on function public.get_community_chat_group_settings(uuid) to authenticated;
