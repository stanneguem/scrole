-- Keep the external agenda ordered by event start and creation date.
-- created_at must be selected in the derived table before it can be used by jsonb_agg.
CREATE OR REPLACE FUNCTION public.get_external_user_agenda(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_me uuid := auth.uid();
  v_visibility text;
  v_blocked boolean := false;
  v_connected boolean := false;
  v_following boolean := false;
  v_items jsonb := '[]'::jsonb;
  v_account_status text;
  v_deleted_at timestamptz;
BEGIN
  IF v_me IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF p_user_id IS NULL THEN RAISE EXCEPTION 'invalid_profile_user'; END IF;

  SELECT lower(coalesce(up.account_status, 'active')), up.deleted_at
    INTO v_account_status, v_deleted_at
  FROM public.user_profiles up
  WHERE up.user_id = p_user_id;
  IF NOT FOUND OR v_deleted_at IS NOT NULL OR v_account_status <> 'active' THEN
    RAISE EXCEPTION 'profile_unavailable';
  END IF;

  SELECT lower(coalesce(upv.profile_visibility, 'public'))
    INTO v_visibility
  FROM public.user_privacy upv
  WHERE upv.user_id = p_user_id;
  v_visibility := coalesce(v_visibility, 'public');

  SELECT EXISTS (
    SELECT 1 FROM public.blocage_utilisateur b
    WHERE b.statut
      AND ((b.bloqueur_id = v_me AND b.bloque_id = p_user_id)
        OR (b.bloqueur_id = p_user_id AND b.bloque_id = v_me))
      AND (b.bloque_jusquau IS NULL OR b.bloque_jusquau > now())
  ) INTO v_blocked;
  IF v_blocked THEN RAISE EXCEPTION 'profile_blocked'; END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.friendships f
    WHERE f.user_a_id = least(v_me, p_user_id)
      AND f.user_b_id = greatest(v_me, p_user_id)
  ) INTO v_connected;

  SELECT EXISTS (
    SELECT 1 FROM public.user_follows f
    WHERE f.follower_id = v_me AND f.followed_id = p_user_id
  ) INTO v_following;

  IF v_visibility IN ('private', 'prive', 'privé')
    AND v_me <> p_user_id AND NOT v_connected AND NOT v_following THEN
    RAISE EXCEPTION 'profile_private';
  END IF;

  SELECT coalesce(
    jsonb_agg(to_jsonb(x) ORDER BY x.starts_at DESC NULLS LAST, x.created_at DESC, x.id DESC),
    '[]'::jsonb
  )
    INTO v_items
  FROM (
    SELECT e.id, e.name, e.photo, e.description, e.starts_at, e.ends_at,
           e.address, c.nom AS city, co.nom AS country, e.created_at
    FROM public.event_calendar ec
    JOIN public.events e ON e.id = ec.event_id
    LEFT JOIN public.cities c ON c.id = e.city_id
    LEFT JOIN public.countries co ON co.id = e.country_id
    WHERE ec.user_id = p_user_id
      AND e.status = 'active'
      AND public.can_view_event(e.id)
  ) x;

  RETURN v_items;
END;
$function$;

-- The function checks auth.uid() and enforces profile visibility itself.
-- It is only intended to be called by authenticated app users.
REVOKE ALL ON FUNCTION public.get_external_user_agenda(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_external_user_agenda(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_external_user_agenda(uuid) TO authenticated;
