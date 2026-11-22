-- Ensure platform administrators receive every report about a post,
-- including reports created from a community post that has not been escalated.
CREATE OR REPLACE FUNCTION public.get_platform_reports(
  p_status text DEFAULT 'open'::text,
  p_limit integer DEFAULT 20,
  p_offset integer DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 50);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_statuses text[];
  v_items jsonb;
  v_profile_items jsonb;
  v_has_more boolean;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Utilisateur non authentifié';
  END IF;
  IF NOT coalesce(public.is_admin_or_above(), false) THEN
    RAISE EXCEPTION 'Action réservée aux administrateurs de la plateforme';
  END IF;

  v_statuses := CASE p_status
    WHEN 'handled' THEN ARRAY['resolu', 'rejete']
    WHEN 'all' THEN ARRAY['en_attente', 'en_cours', 'resolu', 'rejete']
    ELSE ARRAY['en_attente', 'en_cours']
  END;

  WITH rows AS (
    SELECT s.*
    FROM public.signalement s
    WHERE s.status::text = ANY(v_statuses)
      AND s.target_type::text IN ('post', 'comment', 'story', 'user')
      AND (
        s.target_type::text = 'post'
        OR s.community_id IS NULL
        OR s.escalated_at IS NOT NULL
      )
    ORDER BY s.created_at DESC, s.id DESC
    OFFSET v_offset LIMIT v_limit + 1
  ), numbered AS (
    SELECT r.*, row_number() OVER (ORDER BY r.created_at DESC, r.id DESC) AS rn
    FROM rows r
  )
  SELECT
    coalesce(jsonb_agg(jsonb_build_object(
      'id', n.id,
      'source', 'signalement',
      'target_type', n.target_type::text,
      'target_id', n.target_id,
      'status', n.status::text,
      'created_at', n.created_at,
      'description', n.description,
      'escalated', n.escalated_at IS NOT NULL,
      'from_community', n.community_id IS NOT NULL,
      'community_id', n.community_id,
      'community', (SELECT jsonb_build_object('id', c.id, 'name', c.name)
                    FROM public.communities c WHERE c.id = n.community_id),
      'reason', (SELECT jsonb_build_object('id', r.id, 'code', r.code, 'nom', r.nom)
                 FROM public.signalement_raison r WHERE r.id = n.reason_id),
      'reporter', (SELECT jsonb_build_object('user_id', up.user_id, 'username', up.username,
                      'first_name', up.first_name, 'last_name', up.last_name, 'photo_url', up.photo_url)
                   FROM public.user_profiles up WHERE up.user_id = n.reporter_id),
      'reports_count', (SELECT count(*) FROM public.signalement s2
                        WHERE s2.target_type = n.target_type AND s2.target_id = n.target_id
                          AND s2.community_id IS NOT DISTINCT FROM n.community_id
                          AND s2.status IN ('en_attente', 'en_cours')),
      'target', CASE n.target_type::text
        WHEN 'post' THEN (SELECT jsonb_build_object('id', cp.id, 'content', left(cp.content, 300),
                            'status', cp.status, 'community_id', cp.community_id,
                            'photos_count', coalesce(cardinality(cp.photos), 0),
                            'author', jsonb_build_object('user_id', a.user_id, 'username', a.username,
                                'photo_url', a.photo_url))
                          FROM public.community_posts cp
                          LEFT JOIN public.user_profiles a ON a.user_id = cp.author_id
                          WHERE cp.id = n.target_id)
        WHEN 'comment' THEN (SELECT jsonb_build_object('id', c.id, 'post_id', c.post_id,
                            'content', left(c.content, 300),
                            'author', jsonb_build_object('user_id', a.user_id, 'username', a.username,
                                'photo_url', a.photo_url))
                          FROM public.community_post_comments c
                          LEFT JOIN public.user_profiles a ON a.user_id = c.author_id
                          WHERE c.id = n.target_id)
        WHEN 'story' THEN (SELECT jsonb_build_object('id', st.id, 'kind', st.kind,
                            'content', left(st.content, 300), 'image_url', st.image_url,
                            'expires_at', st.expires_at,
                            'author', jsonb_build_object('user_id', a.user_id, 'username', a.username,
                                'photo_url', a.photo_url))
                          FROM public.stories st
                          LEFT JOIN public.user_profiles a ON a.user_id = st.author_id
                          WHERE st.id = n.target_id)
        WHEN 'user' THEN (SELECT jsonb_build_object('user_id', up.user_id, 'username', up.username,
                            'first_name', up.first_name, 'last_name', up.last_name,
                            'photo_url', up.photo_url, 'account_status', up.account_status)
                          FROM public.user_profiles up WHERE up.user_id = n.target_id)
      END
    ) ORDER BY n.created_at DESC, n.id DESC) FILTER (WHERE n.rn <= v_limit), '[]'::jsonb),
    count(*) > v_limit
  INTO v_items, v_has_more
  FROM numbered n;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id', upr.id,
    'source', 'external_profile',
    'target_type', 'user',
    'target_id', upr.reported_user_id,
    'status', CASE upr.status WHEN 'pending' THEN 'en_attente'
                              WHEN 'reviewing' THEN 'en_cours'
                              WHEN 'resolved' THEN 'resolu'
                              WHEN 'dismissed' THEN 'rejete'
                              ELSE upr.status END,
    'created_at', upr.created_at,
    'description', upr.details,
    'escalated', false,
    'from_community', false,
    'community_id', null,
    'community', null,
    'reason', jsonb_build_object('code', upr.reason, 'nom', replace(upr.reason, '_', ' ')),
    'reporter', (SELECT jsonb_build_object('user_id', up.user_id, 'username', up.username,
                    'first_name', up.first_name, 'last_name', up.last_name, 'photo_url', up.photo_url)
                 FROM public.user_profiles up WHERE up.user_id = upr.reporter_user_id),
    'reports_count', (SELECT count(*) FROM public.user_profile_reports upr2
                      WHERE upr2.reported_user_id = upr.reported_user_id
                        AND upr2.status IN ('pending', 'reviewing')),
    'target', (SELECT jsonb_build_object('user_id', up.user_id, 'username', up.username,
                    'first_name', up.first_name, 'last_name', up.last_name,
                    'photo_url', up.photo_url, 'account_status', up.account_status)
               FROM public.user_profiles up WHERE up.user_id = upr.reported_user_id)
  ) ORDER BY upr.created_at DESC), '[]'::jsonb)
  INTO v_profile_items
  FROM public.user_profile_reports upr
  WHERE CASE p_status
    WHEN 'handled' THEN upr.status IN ('resolved', 'dismissed')
    WHEN 'all' THEN upr.status IN ('pending', 'reviewing', 'resolved', 'dismissed')
    ELSE upr.status IN ('pending', 'reviewing')
  END;

  RETURN jsonb_build_object(
    'items', v_items,
    'profile_items', v_profile_items,
    'has_more', coalesce(v_has_more, false)
  );
END;
$function$;
