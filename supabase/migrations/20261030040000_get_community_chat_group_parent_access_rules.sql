-- Expose the parent community's geographic and profile access limits
-- to salon administrators without requiring community-admin permissions.
create or replace function public.get_community_chat_group_parent_access_rules(p_salon_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_community_id uuid;
  v_role text;
  v_rules public.community_access_rules;
begin
  if v_uid is null then
    raise exception 'Authentification requise';
  end if;

  select s.community_id
    into v_community_id
  from public.community_salons s
  where s.id = p_salon_id;

  if v_community_id is null then
    raise exception 'Discussion introuvable';
  end if;

  select m.role
    into v_role
  from public.community_salon_members m
  where m.salon_id = p_salon_id
    and m.user_id = v_uid;

  if coalesce(v_role, '') not in ('owner', 'moderator') then
    raise exception 'Action réservée aux administrateurs de cette discussion';
  end if;

  select r.*
    into v_rules
  from public.community_access_rules r
  where r.community_id = v_community_id;

  return jsonb_build_object(
    'community_id', v_community_id,
    'countries_enabled', coalesce(v_rules.countries_enabled, false),
    'allowed_countries', coalesce(to_jsonb(v_rules.allowed_countries), '[]'::jsonb),
    'cities_enabled', coalesce(v_rules.cities_enabled, false),
    'allowed_cities', coalesce(to_jsonb(v_rules.allowed_cities), '[]'::jsonb),
    'certification_required', coalesce(v_rules.certification_required, false),
    'gender_restriction', v_rules.gender_restriction,
    'age_min', v_rules.age_min,
    'age_max', v_rules.age_max
  );
end;
$function$;

revoke all on function public.get_community_chat_group_parent_access_rules(uuid) from public;
revoke all on function public.get_community_chat_group_parent_access_rules(uuid) from anon;
grant execute on function public.get_community_chat_group_parent_access_rules(uuid) to authenticated;
