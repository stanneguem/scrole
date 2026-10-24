-- Le tab Publications d'un profil ne montre que les publications créées dans le fil personnel.
-- Les publications créées dans une communauté restent accessibles depuis le fil de cette communauté.
-- On conserve les contrôles d'accès, de blocage, de visibilité et de suppression existants.
CREATE OR REPLACE FUNCTION public.get_external_profile_tab(p_user_id uuid, p_tab text, p_limit integer DEFAULT 24, p_offset integer DEFAULT 0)
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
  v_limit integer := greatest(1, least(coalesce(p_limit, 24), 60));
  v_offset integer := greatest(0, coalesce(p_offset, 0));
  v_tab text := lower(trim(coalesce(p_tab, '')));
BEGIN
  IF v_me IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF p_user_id IS NULL THEN RAISE EXCEPTION 'invalid_profile_user'; END IF;

  SELECT lower(coalesce(up.account_status, 'active')), up.deleted_at
    INTO v_account_status, v_deleted_at
  FROM public.user_profiles up
  WHERE up.user_id = p_user_id;

  IF NOT FOUND THEN RAISE EXCEPTION 'profile_not_found'; END IF;
  IF v_deleted_at IS NOT NULL OR v_account_status = 'deleted' THEN RAISE EXCEPTION 'profile_deleted'; END IF;
  IF v_account_status = 'suspended' THEN RAISE EXCEPTION 'profile_suspended'; END IF;
  IF v_account_status IN ('banned', 'ban', 'banni', 'bannie') THEN RAISE EXCEPTION 'profile_banned'; END IF;
  IF v_account_status <> 'active' THEN RAISE EXCEPTION 'profile_unavailable'; END IF;

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
    SELECT 1
    FROM public.friendships f
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

  IF v_tab IN ('posts', 'publications') THEN
    SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC, x.id DESC), '[]'::jsonb)
      INTO v_items
    FROM (
      SELECT
        p.id, p.author_id, p.content, p.photo, p.photos, p.media, p.videos,
        p.video_url, p.video_thumbnail_url, p.created_at, p.community_id, p.audience,
        p.comments_enabled, p.sharing_enabled, p.reactions_enabled,
        (SELECT count(*)::int
           FROM public.community_post_reactions r
          WHERE r.post_id = p.id AND r.reaction = 'like') AS likes_count,
        (SELECT count(*)::int
           FROM public.community_post_reactions r
          WHERE r.post_id = p.id AND r.reaction = 'dislike') AS dislikes_count,
        (SELECT count(*)::int
           FROM public.community_post_comments c
          WHERE c.post_id = p.id) AS comments_count,
        (SELECT coalesce(sum(v.view_count), 0)::int
           FROM public.post_views v
          WHERE v.post_id = p.id) AS views_count,
        (SELECT count(*)::int
           FROM public.community_posts sp
          WHERE sp.shared_post_id = p.id AND sp.deleted_at IS NULL) AS shares_count,
        (SELECT r.reaction
           FROM public.community_post_reactions r
          WHERE r.post_id = p.id AND r.user_id = v_me
          LIMIT 1) AS viewer_reaction,
        EXISTS (
          SELECT 1 FROM public.community_posts sp
          WHERE sp.shared_post_id = p.id AND sp.author_id = v_me AND sp.deleted_at IS NULL
        ) AS viewer_has_shared
      FROM public.community_posts p
      JOIN public.user_profiles author ON author.user_id = p.author_id
      WHERE p.author_id = p_user_id
        AND p.community_id IS NULL
        AND p.status = 'active' AND p.deleted_at IS NULL
        AND author.account_status = 'active' AND author.deleted_at IS NULL
        AND public.can_view_post(p.id)
        AND NOT EXISTS (
          SELECT 1 FROM public.post_hides h
          WHERE h.post_id = p.id AND h.user_id = v_me
        )
      ORDER BY p.created_at DESC, p.id DESC
      LIMIT v_limit OFFSET v_offset
    ) x;

  ELSIF v_tab IN ('liked', 'likes', 'liked_posts', 'j_aime_recents') THEN
    SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.liked_at DESC, x.id DESC), '[]'::jsonb)
      INTO v_items
    FROM (
      SELECT
        p.id, p.author_id, p.content, p.photo, p.photos, p.media, p.videos,
        p.video_url, p.video_thumbnail_url, p.created_at, p.community_id, p.audience,
        p.comments_enabled, p.sharing_enabled, p.reactions_enabled,
        r.created_at AS liked_at,
        (SELECT count(*)::int
           FROM public.community_post_reactions r2
          WHERE r2.post_id = p.id AND r2.reaction = 'like') AS likes_count,
        (SELECT count(*)::int
           FROM public.community_post_reactions r2
          WHERE r2.post_id = p.id AND r2.reaction = 'dislike') AS dislikes_count,
        (SELECT count(*)::int
           FROM public.community_post_comments c
          WHERE c.post_id = p.id) AS comments_count,
        (SELECT coalesce(sum(v.view_count), 0)::int
           FROM public.post_views v
          WHERE v.post_id = p.id) AS views_count,
        (SELECT count(*)::int
           FROM public.community_posts sp
          WHERE sp.shared_post_id = p.id AND sp.deleted_at IS NULL) AS shares_count,
        (SELECT r2.reaction
           FROM public.community_post_reactions r2
          WHERE r2.post_id = p.id AND r2.user_id = v_me
          LIMIT 1) AS viewer_reaction,
        EXISTS (
          SELECT 1 FROM public.community_posts sp
          WHERE sp.shared_post_id = p.id AND sp.author_id = v_me AND sp.deleted_at IS NULL
        ) AS viewer_has_shared
      FROM public.community_post_reactions r
      JOIN public.community_posts p ON p.id = r.post_id
      JOIN public.user_profiles author ON author.user_id = p.author_id
      WHERE r.user_id = p_user_id AND r.reaction = 'like'
        AND p.status = 'active' AND p.deleted_at IS NULL
        AND author.account_status = 'active' AND author.deleted_at IS NULL
        AND public.can_view_post(p.id)
        AND NOT EXISTS (
          SELECT 1 FROM public.post_hides h
          WHERE h.post_id = p.id AND h.user_id = v_me
        )
      ORDER BY r.created_at DESC, p.id DESC
      LIMIT v_limit OFFSET v_offset
    ) x;

  ELSIF v_tab IN ('events', 'evenements', 'événements') THEN
    SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.starts_at DESC NULLS LAST, x.created_at DESC, x.id DESC), '[]'::jsonb)
      INTO v_items
    FROM (
      SELECT
        e.id, e.creator_id, e.name, e.slug, e.description, e.photo,
        e.starts_at, e.ends_at, e.address, e.is_virtual, e.is_public,
        e.status, e.created_at, c.nom AS city, co.nom AS country,
        CASE
          WHEN e.creator_id = p_user_id THEN 'organisateur'
          WHEN EXISTS (
            SELECT 1 FROM public.event_co_creators cc
            WHERE cc.event_id = e.id AND cc.user_id = p_user_id AND cc.status = 'acceptee'
          ) THEN 'co_organisateur'
          WHEN EXISTS (
            SELECT 1 FROM public.event_staff es
            WHERE es.event_id = e.id AND es.user_id = p_user_id AND es.status = 'acceptee'
          ) THEN 'staff'
          ELSE 'participant'
        END AS role
      FROM public.events e
      LEFT JOIN public.cities c ON c.id = e.city_id
      LEFT JOIN public.countries co ON co.id = e.country_id
      WHERE e.status = 'active'
        AND (
          e.creator_id = p_user_id
          OR EXISTS (
            SELECT 1 FROM public.event_co_creators cc
            WHERE cc.event_id = e.id AND cc.user_id = p_user_id AND cc.status = 'acceptee'
          )
          OR EXISTS (
            SELECT 1 FROM public.event_staff es
            WHERE es.event_id = e.id AND es.user_id = p_user_id AND es.status = 'acceptee'
          )
          OR EXISTS (
            SELECT 1 FROM public.event_calendar ec
            WHERE ec.event_id = e.id AND ec.user_id = p_user_id
          )
          OR EXISTS (
            SELECT 1 FROM public.event_checkins ci
            WHERE ci.event_id = e.id AND ci.user_id = p_user_id AND ci.status = 'valid'
          )
          OR EXISTS (
            SELECT 1 FROM public.event_guest_invitations gi
            WHERE gi.event_id = e.id AND gi.user_id = p_user_id AND gi.status = 'acceptee'
          )
        )
        AND public.can_view_event(e.id)
      ORDER BY e.starts_at DESC NULLS LAST, e.created_at DESC, e.id DESC
      LIMIT v_limit OFFSET v_offset
    ) x;
  ELSE
    RAISE EXCEPTION 'invalid_profile_tab';
  END IF;

  RETURN v_items;
END;
$function$
;
