-- Complete community salon management settings and salon-scoped administration.
-- Community-level administrators are deliberately not treated as salon administrators.

create or replace function public.get_community_chat_group_settings(p_salon_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare
  v_uid uuid:=auth.uid();
  v_salon public.community_salons;
  v_role text;
  v_members jsonb;
  v_preferences public.community_salon_user_preferences;
  v_rules public.community_salon_access_rules;
begin
  if v_uid is null then raise exception 'Authentification requise'; end if;
  select * into v_salon from public.community_salons where id=p_salon_id;
  if not found then raise exception 'Discussion introuvable'; end if;
  select role into v_role from public.community_salon_members where salon_id=p_salon_id and user_id=v_uid;
  if v_role is null then raise exception 'Vous ne faites pas partie de cette discussion'; end if;
  select * into v_preferences from public.community_salon_user_preferences where salon_id=p_salon_id and user_id=v_uid;
  select * into v_rules from public.community_salon_access_rules where salon_id=p_salon_id;
  select coalesce(jsonb_agg(jsonb_build_object(
    'user_id',m.user_id,'role',m.role,'joined_at',m.joined_at,
    'display_name',coalesce(nullif(trim(concat_ws(' ',up.first_name,up.last_name)),''),up.username,'Membre'),
    'username',up.username,'photo_url',up.photo_url
  ) order by case m.role when 'owner' then 0 when 'moderator' then 1 else 2 end,m.joined_at),'[]'::jsonb)
  into v_members from public.community_salon_members m
  left join public.user_profiles up on up.user_id=m.user_id where m.salon_id=p_salon_id;
  return jsonb_build_object(
    'id',v_salon.id,'community_id',v_salon.community_id,'name',v_salon.name,
    'description',v_salon.description,'visibility',v_salon.visibility,
    'avatar_url',v_salon.avatar_url,'created_by',v_salon.created_by,
    'audio_messages_allowed',v_salon.audio_messages_allowed,
    'my_role',v_role,'is_salon_admin',v_role in ('owner','moderator'),
    'is_salon_owner',v_role='owner','member_count',jsonb_array_length(v_members),
    'notifications_enabled',coalesce(v_preferences.notifications_enabled,true),
    'media_visibility_enabled',coalesce(v_preferences.media_visibility_enabled,true),
    'access_rules',jsonb_build_object(
      'countries_enabled',coalesce(v_rules.countries_enabled,false),
      'allowed_countries',coalesce(to_jsonb(v_rules.allowed_countries),'[]'::jsonb),
      'cities_enabled',coalesce(v_rules.cities_enabled,false),
      'allowed_cities',coalesce(to_jsonb(v_rules.allowed_cities),'[]'::jsonb),
      'certification_required',coalesce(v_rules.certification_required,false),
      'gender_restriction',v_rules.gender_restriction,
      'age_min',v_rules.age_min,'age_max',v_rules.age_max
    ),
    'members',v_members
  );
end $$;

create or replace function public.update_community_chat_group_advanced_settings(
  p_salon_id uuid,p_audio_messages_allowed boolean,p_countries_enabled boolean,
  p_allowed_countries uuid[],p_cities_enabled boolean,p_allowed_cities uuid[],
  p_certification_required boolean,p_gender_restriction text,p_age_min integer,p_age_max integer
) returns void language plpgsql security definer set search_path=public as $$
declare
  v_uid uuid:=auth.uid(); v_role text; v_community_rules public.community_access_rules; v_gender genre_enum;
begin
  if v_uid is null then raise exception 'Authentification requise'; end if;
  select role into v_role from public.community_salon_members where salon_id=p_salon_id and user_id=v_uid;
  if v_role not in ('owner','moderator') then raise exception 'Action réservée aux administrateurs de cette discussion'; end if;
  if p_age_min is not null and (p_age_min<13 or p_age_min>120) then raise exception 'Âge minimum invalide'; end if;
  if p_age_max is not null and (p_age_max<13 or p_age_max>120) then raise exception 'Âge maximum invalide'; end if;
  if p_age_min is not null and p_age_max is not null and p_age_min>p_age_max then raise exception 'La tranche d’âge est invalide'; end if;
  if p_gender_restriction is not null and p_gender_restriction not in ('homme','femme') then raise exception 'Restriction de genre invalide'; end if;
  v_gender:=p_gender_restriction::genre_enum;
  select * into v_community_rules from public.community_access_rules
  where community_id=(select community_id from public.community_salons where id=p_salon_id);
  if not found then raise exception 'Règles de la communauté introuvables'; end if;
  if v_community_rules.certification_required and not p_certification_required then raise exception 'La certification est obligatoire dans cette communauté'; end if;
  if v_community_rules.countries_enabled and (not p_countries_enabled or not (coalesce(p_allowed_countries,'{}') <@ v_community_rules.allowed_countries)) then raise exception 'Les restrictions de pays du salon doivent respecter celles de la communauté'; end if;
  if v_community_rules.cities_enabled and (not p_cities_enabled or not (coalesce(p_allowed_cities,'{}') <@ v_community_rules.allowed_cities)) then raise exception 'Les restrictions de ville du salon doivent respecter celles de la communauté'; end if;
  if v_community_rules.age_min is not null and (p_age_min is null or p_age_min<v_community_rules.age_min) then raise exception 'L’âge minimum du salon ne peut pas être inférieur à celui de la communauté'; end if;
  if v_community_rules.age_max is not null and (p_age_max is null or p_age_max>v_community_rules.age_max) then raise exception 'L’âge maximum du salon ne peut pas être supérieur à celui de la communauté'; end if;
  update public.community_salons set audio_messages_allowed=p_audio_messages_allowed,updated_at=now() where id=p_salon_id;
  insert into public.community_salon_access_rules(salon_id,countries_enabled,allowed_countries,cities_enabled,allowed_cities,certification_required,gender_restriction,age_min,age_max)
  values(p_salon_id,p_countries_enabled,coalesce(p_allowed_countries,'{}'),p_cities_enabled,coalesce(p_allowed_cities,'{}'),p_certification_required,v_gender,p_age_min,p_age_max)
  on conflict(salon_id) do update set countries_enabled=excluded.countries_enabled,allowed_countries=excluded.allowed_countries,
    cities_enabled=excluded.cities_enabled,allowed_cities=excluded.allowed_cities,
    certification_required=excluded.certification_required,gender_restriction=excluded.gender_restriction,
    age_min=excluded.age_min,age_max=excluded.age_max;
end $$;

create or replace function public.get_community_chat_group_requests(p_salon_id uuid)
returns table(request_id uuid,user_id uuid,username text,photo_url text,requested_at timestamptz,status text)
language plpgsql stable security definer set search_path=public as $$
declare v_role text;
begin
  if auth.uid() is null then raise exception 'Authentification requise'; end if;
  select role into v_role from public.community_salon_members where salon_id=p_salon_id and user_id=auth.uid();
  if v_role not in ('owner','moderator') then raise exception 'Action réservée aux administrateurs de cette discussion'; end if;
  return query select r.id,r.user_id,p.username,p.photo_url,r.requested_at,r.status
    from public.community_salon_join_requests r left join public.user_profiles p on p.user_id=r.user_id
    where r.salon_id=p_salon_id and r.status='pending' order by r.requested_at asc;
end $$;

create or replace function public.review_community_chat_group_request(p_request_id uuid,p_decision text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_request public.community_salon_join_requests; v_salon public.community_salons; v_role text;
begin
  if auth.uid() is null or p_decision not in ('accepted','rejected') then raise exception 'Requête invalide'; end if;
  select * into v_request from public.community_salon_join_requests where id=p_request_id for update;
  if not found then raise exception 'Demande introuvable'; end if;
  select role into v_role from public.community_salon_members where salon_id=v_request.salon_id and user_id=auth.uid();
  if v_role not in ('owner','moderator') then raise exception 'Action réservée aux administrateurs de cette discussion'; end if;
  select * into v_salon from public.community_salons where id=v_request.salon_id;
  if v_request.status<>'pending' then raise exception 'Cette demande a déjà été traitée'; end if;
  if p_decision='accepted' then
    if not exists(select 1 from public.community_members cm where cm.community_id=v_salon.community_id and cm.user_id=v_request.user_id)
      or not public.check_salon_eligibility(v_salon.id,v_request.user_id) then raise exception 'Le demandeur ne remplit plus les conditions d’accès'; end if;
    insert into public.community_salon_members(salon_id,user_id,role) values(v_salon.id,v_request.user_id,'member') on conflict do nothing;
  end if;
  update public.community_salon_join_requests set status=p_decision,reviewed_at=now(),reviewed_by=auth.uid() where id=p_request_id;
  return jsonb_build_object('status',p_decision,'request_id',p_request_id);
end $$;

revoke all on function public.get_community_chat_group_settings(uuid) from public,anon;
grant execute on function public.get_community_chat_group_settings(uuid) to authenticated;
revoke all on function public.update_community_chat_group_advanced_settings(uuid,boolean,boolean,uuid[],boolean,uuid[],boolean,text,integer,integer) from public,anon;
grant execute on function public.update_community_chat_group_advanced_settings(uuid,boolean,boolean,uuid[],boolean,uuid[],boolean,text,integer,integer) to authenticated;
revoke all on function public.get_community_chat_group_requests(uuid) from public,anon;
grant execute on function public.get_community_chat_group_requests(uuid) to authenticated;
revoke all on function public.review_community_chat_group_request(uuid,text) from public,anon;
grant execute on function public.review_community_chat_group_request(uuid,text) to authenticated;
