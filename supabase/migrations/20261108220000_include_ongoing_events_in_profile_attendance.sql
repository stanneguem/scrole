-- Keep the Profile / External Profile Events tab based on validated
-- event-entry check-ins, regardless of whether the event is ongoing or completed.
-- Applied to Supabase project djvmxrwfchnqdtzayhwf.

CREATE OR REPLACE FUNCTION public.get_profile_attended_event_series(p_user_id uuid, p_limit integer DEFAULT 60, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_me uuid := auth.uid();
  v_visibility text;
  v_account_status text;
  v_deleted_at timestamptz;
  v_blocked boolean := false;
  v_connected boolean := false;
  v_following boolean := false;
  v_items jsonb := '[]'::jsonb;
  v_limit integer := greatest(1, least(coalesce(p_limit, 60), 60));
  v_offset integer := greatest(0, coalesce(p_offset, 0));
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
    SELECT 1
    FROM public.blocage_utilisateur b
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

  -- Only a validated event-entry check-in qualifies as attendance.
  -- No event-status filter: ongoing and completed events remain visible.
  WITH attended AS (
    SELECT
      e.id,
      coalesce(e.series_id, e.id) AS group_id,
      e.edition_number,
      e.creator_id,
      e.name,
      e.slug,
      e.description,
      e.photo,
      e.starts_at,
      e.ends_at,
      e.address,
      e.is_virtual,
      e.is_public,
      e.status,
      e.created_at,
      c.nom AS city,
      co.nom AS country,
      CASE WHEN e.creator_id = p_user_id THEN 'organisateur' ELSE 'participant' END AS role
    FROM public.events e
    LEFT JOIN public.cities c ON c.id = e.city_id
    LEFT JOIN public.countries co ON co.id = e.country_id
    WHERE EXISTS (
      SELECT 1
      FROM public.event_checkins ci
      WHERE ci.event_id = e.id
        AND ci.user_id = p_user_id
        AND ci.status = 'valid'
        AND ci.activity_id IS NULL
    )
  ),
  ranked AS (
    SELECT
      a.*,
      row_number() OVER (
        PARTITION BY group_id
        ORDER BY edition_number DESC, starts_at DESC, created_at DESC
      ) AS edition_rank
    FROM attended a
  ),
  page AS (
    SELECT *
    FROM ranked
    WHERE edition_rank = 1
    ORDER BY starts_at DESC NULLS LAST, created_at DESC, group_id
    LIMIT v_limit OFFSET v_offset
  ),
  grouped AS (
    SELECT
      group_id,
      count(*)::integer AS edition_count,
      jsonb_agg(
        jsonb_build_object(
          'id', id,
          'edition_number', edition_number,
          'name', name,
          'photo', photo,
          'description', description,
          'starts_at', starts_at,
          'ends_at', ends_at,
          'status', status,
          'city', city,
          'country', country
        )
        ORDER BY edition_number
      ) AS editions
    FROM attended
    GROUP BY group_id
  )
  SELECT coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', p.group_id,
        'series_id', p.group_id,
        'name', p.name,
        'slug', p.slug,
        'description', p.description,
        'photo', p.photo,
        'starts_at', p.starts_at,
        'ends_at', p.ends_at,
        'address', p.address,
        'is_virtual', p.is_virtual,
        'is_public', p.is_public,
        'status', p.status,
        'created_at', p.created_at,
        'city', p.city,
        'country', p.country,
        'role', p.role,
        'edition_count', g.edition_count,
        'editions', g.editions
      )
      ORDER BY p.starts_at DESC NULLS LAST, p.created_at DESC, p.group_id
    ),
    '[]'::jsonb
  )
  INTO v_items
  FROM page p
  JOIN grouped g ON g.group_id = p.group_id;

  RETURN v_items;
END;
$function$;
