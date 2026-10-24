-- Keep member reports consistent with the community-wide reporting toggle.
-- Members can still report community posts/comments through report_content; this
-- adds the same enforcement to the dedicated member-report RPC.
CREATE OR REPLACE FUNCTION public.report_community_member(p_community_id uuid, p_user_id uuid, p_reason_id uuid, p_description text DEFAULT NULL::text)
 RETURNS signalement
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := auth.uid();
  v_row public.signalement;
  v_desc text := nullif(btrim(p_description), '');
begin
  if v_uid is null then raise exception 'Utilisateur non authentifié'; end if;
  if p_community_id is null or p_user_id is null then raise exception 'Communauté et utilisateur requis'; end if;
  if p_user_id = v_uid then raise exception 'Vous ne pouvez pas signaler votre propre compte'; end if;
  if not public.is_community_member(p_community_id) then raise exception 'Réservé aux membres de la communauté'; end if;
  if exists (
    select 1 from public.community_settings cs
    where cs.community_id = p_community_id and cs.allow_reports = false
  ) then
    raise exception 'Les signalements sont désactivés dans cette communauté';
  end if;
  if not exists (
    select 1 from public.community_members cm
    join public.user_profiles up on up.user_id = cm.user_id
    where cm.community_id = p_community_id
      and cm.user_id = p_user_id
      and lower(coalesce(up.account_status, '')) = 'active'
      and up.deleted_at is null
  ) then raise exception 'Membre introuvable dans cette communauté'; end if;
  if not exists (select 1 from public.signalement_raison r where r.id = p_reason_id and r.est_actif) then
    raise exception 'Motif de signalement invalide';
  end if;
  if char_length(coalesce(v_desc, '')) > 1000 then raise exception 'Description trop longue (1000 caractères maximum)'; end if;
  if (select count(*) from public.signalement s where s.reporter_id = v_uid and s.created_at > now() - interval '1 hour') >= 20 then
    raise exception 'Trop de signalements envoyés, réessayez plus tard';
  end if;
  select * into v_row from public.signalement s
  where s.reporter_id = v_uid
    and s.target_type = 'user'::public.user_activity_target_type
    and s.target_id = p_user_id
    and s.community_id = p_community_id
    and s.status in ('en_attente'::public.signalement_status, 'en_cours'::public.signalement_status)
  limit 1;
  if found then return v_row; end if;

  insert into public.signalement
    (reporter_id, target_type, target_id, reason_id, description, community_id)
  values
    (v_uid, 'user'::public.user_activity_target_type, p_user_id, p_reason_id, v_desc, p_community_id)
  returning * into v_row;
  return v_row;
end;
$function$
;
REVOKE ALL ON FUNCTION public.report_community_member(uuid, uuid, uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.report_community_member(uuid, uuid, uuid, text) TO authenticated;
