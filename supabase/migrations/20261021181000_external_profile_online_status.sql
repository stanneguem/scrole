-- Respect both online-status and last-seen preferences in external profile RPC results.
CREATE OR REPLACE FUNCTION public.get_external_profile_legacy(p_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_me uuid := auth.uid();
  v_profile public.user_profiles%rowtype;
  v_priv public.user_privacy%rowtype;
  v_connected boolean := false;
  v_pending_out boolean := false;
  v_pending_in boolean := false;
  v_blocked boolean := false;
  v_following boolean := false;
  v_certified boolean := false;
  v_certification_code text;
  v_can_message boolean := false;
  v_friend_count integer := 0;
  v_country text;
  v_city text;
  v_last_seen_at timestamptz;
  v_interests jsonb := '[]'::jsonb;
  v_role text;
  v_role_label text;
BEGIN
  IF v_me IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF p_user_id IS NULL OR p_user_id = v_me THEN RAISE EXCEPTION 'invalid_profile_user'; END IF;

  SELECT * INTO v_profile
  FROM public.user_profiles
  WHERE user_id = p_user_id AND deleted_at IS NULL;

  IF NOT FOUND THEN RAISE EXCEPTION 'profile_not_found'; END IF;

  SELECT * INTO v_priv FROM public.user_privacy WHERE user_id = p_user_id;

  IF NOT FOUND THEN
    v_priv.profile_visibility := 'public';
    v_priv.allow_messages_from := 'everyone';
    v_priv.afficher_pays := true;
    v_priv.afficher_ville := true;
    v_priv.afficher_derniere_connexion := true;
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.blocage_utilisateur b
    WHERE b.statut
      AND ((b.bloqueur_id = v_me AND b.bloque_id = p_user_id)
        OR (b.bloqueur_id = p_user_id AND b.bloque_id = v_me))
      AND (b.bloque_jusquau IS NULL OR b.bloque_jusquau > now())
  ) INTO v_blocked;

  IF v_blocked THEN
    RETURN jsonb_build_object(
      'user_id', p_user_id,
      'is_blocked', true,
      'is_private', true
    );
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.friendships f
    WHERE (f.user_a_id = LEAST(v_me, p_user_id) AND f.user_b_id = GREATEST(v_me, p_user_id))
  ) INTO v_connected;

  SELECT EXISTS (
    SELECT 1 FROM public.follow_requests r
    WHERE r.status = 'pending'
      AND r.requester_id = v_me
      AND r.target_id = p_user_id
  ) INTO v_pending_out;

  SELECT EXISTS (
    SELECT 1 FROM public.follow_requests r
    WHERE r.status = 'pending'
      AND r.requester_id = p_user_id
      AND r.target_id = v_me
  ) INTO v_pending_in;

  SELECT EXISTS (
    SELECT 1 FROM public.user_follows f
    WHERE f.follower_id = v_me AND f.followed_id = p_user_id
  ) INTO v_following;

  SELECT coalesce(v_profile.is_verified, false) OR EXISTS (
    SELECT 1 FROM public.user_certifications c
    WHERE c.user_id = p_user_id
      AND c.status::text = 'active'
      AND c.issued_at <= now()
      AND (c.expires_at IS NULL OR c.expires_at >= now())
  ) INTO v_certified;

  SELECT c.certification_code INTO v_certification_code
  FROM public.user_certifications c
  WHERE c.user_id = p_user_id
    AND c.status::text = 'active'
    AND c.issued_at <= now()
    AND (c.expires_at IS NULL OR c.expires_at >= now())
  ORDER BY c.expires_at DESC NULLS FIRST
  LIMIT 1;

  SELECT count(*)::integer
  INTO v_friend_count
  FROM public.friendships f
  WHERE f.user_a_id = p_user_id OR f.user_b_id = p_user_id;

  SELECT c.nom INTO v_country FROM public.countries c WHERE c.id = v_profile.country_id;
  SELECT c.nom INTO v_city FROM public.cities c WHERE c.id = v_profile.city_id;

  SELECT max(d.last_seen_at)
    INTO v_last_seen_at
  FROM public.user_devices d
  WHERE d.user_id = p_user_id;

  SELECT ur.role,
         CASE WHEN ur.role = 'autre' THEN coalesce(ur.custom_label, r.label) ELSE r.label END
  INTO v_role, v_role_label
  FROM public.user_roles ur JOIN public.roles r ON r.code = ur.role
  WHERE ur.user_id = p_user_id;
  v_role := coalesce(v_role, 'membre');
  v_role_label := coalesce(v_role_label, 'Membre');

  SELECT coalesce(
    jsonb_agg(x.interest ORDER BY x.name),
    '[]'::jsonb
  )
  INTO v_interests
  FROM (
    SELECT DISTINCT i.name,
      jsonb_build_object(
        'id', i.id,
        'name', i.name,
        'category', i.category,
        'icon_url', i.icon_url,
        'is_selected', true
      ) AS interest
    FROM public.user_interests ui
    JOIN public.interests i ON i.id = ui.interest_id
    WHERE ui.user_id = p_user_id
  ) x;

  v_can_message := (
    lower(coalesce(v_priv.allow_messages_from, 'everyone'))
    IN ('everyone', 'tous', 'tout_le_monde')
    OR (lower(coalesce(v_priv.allow_messages_from, 'everyone')) = 'friends' AND v_connected)
  );

  IF lower(coalesce(v_priv.profile_visibility, 'public')) IN ('private', 'prive', 'privé')
     AND NOT v_connected AND NOT v_following THEN
    RETURN jsonb_build_object(
      'user_id', p_user_id,
      'username', v_profile.username,
      'first_name', v_profile.first_name,
      'last_name', v_profile.last_name,
      'photo_url', v_profile.photo_url,
      'cover_url', v_profile.cover_url,
      'is_private', true,
      'is_connected', false,
      'connection_request_sent', v_pending_out,
      'incoming_connection_request', v_pending_in,
      'is_following', v_following,
      'follows_me', exists (select 1 from public.user_follows f2 where f2.follower_id = p_user_id and f2.followed_id = v_me),
      'followers_count', (select count(*) from public.user_follows f3 where f3.followed_id = p_user_id),
      'following_count', (select count(*) from public.user_follows f4 where f4.follower_id = p_user_id),
      'relationship', public.get_relationship(p_user_id),
      'is_certified', v_certified,
      'certification_code', v_certification_code,
      'can_message', v_can_message,
      'friend_count', v_friend_count,
      'interests', '[]'::jsonb
    );
  END IF;

  RETURN jsonb_build_object(
    'user_id', p_user_id,
    'username', v_profile.username,
    'first_name', v_profile.first_name,
    'last_name', v_profile.last_name,
    'birth_date', v_profile.birth_date,
    'bio', v_profile.bio,
    'slogan', v_profile.slogan,
    'photo_url', v_profile.photo_url,
    'cover_url', v_profile.cover_url,
    'country', CASE WHEN v_priv.afficher_pays THEN v_country ELSE NULL END,
    'city', CASE WHEN v_priv.afficher_ville THEN v_city ELSE NULL END,
    'last_seen_at', CASE WHEN coalesce(v_priv.afficher_derniere_connexion, false) THEN v_last_seen_at ELSE NULL END,
    'is_online', CASE WHEN coalesce(v_priv.show_online_status, true) AND v_last_seen_at >= now() - interval '5 minutes' THEN true ELSE false END,
    'role', v_role,
    'role_label', v_role_label,
    'is_private', false,
    'is_connected', v_connected,
    'connection_request_sent', v_pending_out,
    'incoming_connection_request', v_pending_in,
    'is_following', v_following,
      'follows_me', exists (select 1 from public.user_follows f2 where f2.follower_id = p_user_id and f2.followed_id = v_me),
      'followers_count', (select count(*) from public.user_follows f3 where f3.followed_id = p_user_id),
      'following_count', (select count(*) from public.user_follows f4 where f4.follower_id = p_user_id),
      'relationship', public.get_relationship(p_user_id),
    'is_certified', v_certified,
    'certification_code', v_certification_code,
    'can_message', v_can_message,
    'friend_count', v_friend_count,
    'interests', v_interests
  );
END;
$function$

