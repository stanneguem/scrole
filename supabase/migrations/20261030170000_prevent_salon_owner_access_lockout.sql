-- Prevent salon access rules from excluding the salon creator.
-- The same checks run inside the SECURITY DEFINER RPC, before any writes.
create or replace function public.update_community_chat_group_advanced_settings(
  p_salon_id uuid,
  p_audio_messages_allowed boolean,
  p_countries_enabled boolean,
  p_allowed_countries uuid[],
  p_cities_enabled boolean,
  p_allowed_cities uuid[],
  p_certification_required boolean,
  p_gender_restriction text,
  p_age_min integer,
  p_age_max integer
)
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_uid uuid := auth.uid();
  v_role text;
  v_salon public.community_salons;
  v_profile public.user_profiles;
  v_community_rules public.community_access_rules;
  v_gender genre_enum;
  v_owner_age integer;
begin
  if v_uid is null then raise exception 'Authentification requise'; end if;
  select * into v_salon from public.community_salons where id=p_salon_id;
  if not found then raise exception 'Salon introuvable'; end if;
  select role into v_role from public.community_salon_members where salon_id=p_salon_id and user_id=v_uid;
  if coalesce(v_role,'') not in ('owner','moderator') and v_salon.created_by<>v_uid then
    raise exception 'Action réservée aux administrateurs de cette discussion';
  end if;
  select * into v_profile from public.user_profiles where user_id=v_salon.created_by;
  if not found then raise exception 'Impossible de vérifier le profil du propriétaire : modification refusée'; end if;

  if p_age_min is not null and (p_age_min<13 or p_age_min>120) then raise exception 'Âge minimum invalide'; end if;
  if p_age_max is not null and (p_age_max<13 or p_age_max>120) then raise exception 'Âge maximum invalide'; end if;
  if p_age_min is not null and p_age_max is not null and p_age_min>p_age_max then raise exception 'La tranche d’âge est invalide'; end if;
  if p_gender_restriction is not null and p_gender_restriction not in ('homme','femme') then raise exception 'Restriction de genre invalide'; end if;
  v_gender:=p_gender_restriction::genre_enum;

  select * into v_community_rules from public.community_access_rules where community_id=v_salon.community_id;
  if not found then raise exception 'Règles de la communauté introuvables'; end if;
  if v_community_rules.certification_required and not p_certification_required then raise exception 'La certification est obligatoire dans cette communauté'; end if;
  if v_community_rules.countries_enabled and (not p_countries_enabled or not (coalesce(p_allowed_countries,'{}') <@ v_community_rules.allowed_countries)) then raise exception 'Les pays autorisés par le salon doivent respecter ceux de la communauté'; end if;
  if v_community_rules.cities_enabled and (not p_cities_enabled or not (coalesce(p_allowed_cities,'{}') <@ v_community_rules.allowed_cities)) then raise exception 'Les villes autorisées par le salon doivent respecter celles de la communauté'; end if;
  if v_community_rules.age_min is not null and (p_age_min is null or p_age_min<v_community_rules.age_min) then raise exception 'L’âge minimum du salon ne peut pas être inférieur à celui de la communauté'; end if;
  if v_community_rules.age_max is not null and (p_age_max is null or p_age_max>v_community_rules.age_max) then raise exception 'L’âge maximum du salon ne peut pas être supérieur à celui de la communauté'; end if;
  if v_community_rules.gender_restriction is not null and p_gender_restriction is distinct from v_community_rules.gender_restriction::text then raise exception 'La restriction de genre doit respecter celle de la communauté'; end if;

  if p_countries_enabled and not (v_profile.country_id=any(coalesce(p_allowed_countries,'{}'))) then
    raise exception 'Modification refusée : le propriétaire du salon ne réside pas dans les pays autorisés. Ajoutez son pays ou désactivez cette restriction.';
  end if;
  if p_cities_enabled and not (v_profile.city_id=any(coalesce(p_allowed_cities,'{}'))) then
    raise exception 'Modification refusée : le propriétaire du salon ne réside pas dans les villes autorisées. Ajoutez sa ville ou désactivez cette restriction.';
  end if;
  if p_certification_required and not coalesce(v_profile.is_verified,false) then
    raise exception 'Modification refusée : le propriétaire du salon ne possède pas la certification requise.';
  end if;
  if p_gender_restriction is not null and p_gender_restriction is distinct from v_profile.gender::text then
    raise exception 'Modification refusée : la restriction de genre exclurait le propriétaire du salon.';
  end if;
  if v_profile.birth_date is not null then
    v_owner_age:=date_part('year',age(current_date,v_profile.birth_date))::integer;
    if p_age_min is not null and v_owner_age<p_age_min then raise exception 'Modification refusée : l’âge minimum exclurait le propriétaire du salon.'; end if;
    if p_age_max is not null and v_owner_age>p_age_max then raise exception 'Modification refusée : l’âge maximum exclurait le propriétaire du salon.'; end if;
  elsif p_age_min is not null or p_age_max is not null then
    raise exception 'Modification refusée : la date de naissance du propriétaire ne permet pas de vérifier cette restriction.';
  end if;

  update public.community_salons set audio_messages_allowed=p_audio_messages_allowed,updated_at=now() where id=p_salon_id;
  insert into public.community_salon_access_rules(salon_id,countries_enabled,allowed_countries,cities_enabled,allowed_cities,certification_required,gender_restriction,age_min,age_max)
  values(p_salon_id,p_countries_enabled,coalesce(p_allowed_countries,'{}'),p_cities_enabled,coalesce(p_allowed_cities,'{}'),p_certification_required,v_gender,p_age_min,p_age_max)
  on conflict(salon_id) do update set countries_enabled=excluded.countries_enabled,allowed_countries=excluded.allowed_countries,cities_enabled=excluded.cities_enabled,allowed_cities=excluded.allowed_cities,certification_required=excluded.certification_required,gender_restriction=excluded.gender_restriction,age_min=excluded.age_min,age_max=excluded.age_max;
end;
$function$;
revoke all on function public.update_community_chat_group_advanced_settings(uuid,boolean,boolean,uuid[],boolean,uuid[],boolean,text,integer,integer) from public,anon;
grant execute on function public.update_community_chat_group_advanced_settings(uuid,boolean,boolean,uuid[],boolean,uuid[],boolean,text,integer,integer) to authenticated;

-- Restore the affected salon's city restriction to its owner's actual city (Yaoundé).
update public.community_salon_access_rules r
set cities_enabled=true, allowed_cities=array['74596b0a-4906-4399-9d2d-6432621c18d5'::uuid]
from public.community_salons s
where r.salon_id=s.id
  and s.id='306451f2-8936-49b9-ae28-556e92d23143'
  and s.created_by='572f9ff1-429e-4d29-b489-9726507dc9d3';