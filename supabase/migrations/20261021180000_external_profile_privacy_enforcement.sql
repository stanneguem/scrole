-- Enforce profile privacy and direct-message permissions on the server.
-- This migration mirrors the changes already applied to the Scrole Supabase project.

CREATE OR REPLACE FUNCTION public.can_send_direct_message_to(p_sender_id uuid, p_recipient_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_allowed boolean := true;
  v_connected boolean := false;
BEGIN
  IF auth.uid() IS NULL OR p_sender_id IS DISTINCT FROM auth.uid()
     OR p_recipient_id IS NULL OR p_sender_id = p_recipient_id THEN
    RETURN false;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.blocage_utilisateur b
    WHERE b.statut
      AND ((b.bloqueur_id = p_sender_id AND b.bloque_id = p_recipient_id)
        OR (b.bloqueur_id = p_recipient_id AND b.bloque_id = p_sender_id))
      AND (b.bloque_jusquau IS NULL OR b.bloque_jusquau > now())
  ) THEN
    RETURN false;
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.friendships f
    WHERE f.user_a_id = LEAST(p_sender_id, p_recipient_id)
      AND f.user_b_id = GREATEST(p_sender_id, p_recipient_id)
  ) INTO v_connected;

  SELECT LOWER(COALESCE(up.allow_messages_from, 'everyone'))
      IN ('everyone', 'tous', 'tout_le_monde')
    INTO v_allowed
  FROM public.user_privacy up
  WHERE up.user_id = p_recipient_id;

  v_allowed := COALESCE(v_allowed, true);
  RETURN v_connected OR v_allowed;
END;
$function$


REVOKE ALL ON FUNCTION public.can_send_direct_message_to(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.can_send_direct_message_to(uuid, uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_or_create_direct_conversation(p_other_user_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_me uuid := auth.uid();
  v_one uuid;
  v_two uuid;
  v_id uuid;
  v_connected boolean := false;
  v_allowed boolean := true;
BEGIN
  IF v_me IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF p_other_user_id IS NULL OR p_other_user_id = v_me THEN RAISE EXCEPTION 'invalid_other_user'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.user_profiles
    WHERE user_id = p_other_user_id AND deleted_at IS NULL
      AND lower(coalesce(account_status::text, 'active')) = 'active'
  ) THEN RAISE EXCEPTION 'profile_not_found'; END IF;

  v_one := least(v_me, p_other_user_id);
  v_two := greatest(v_me, p_other_user_id);

  SELECT EXISTS (
    SELECT 1 FROM public.friendships f
    WHERE f.user_a_id = v_one AND f.user_b_id = v_two
  ) INTO v_connected;

  IF EXISTS (
    SELECT 1 FROM public.blocage_utilisateur b
    WHERE b.statut
      AND ((b.bloqueur_id = v_me AND b.bloque_id = p_other_user_id)
        OR (b.bloqueur_id = p_other_user_id AND b.bloque_id = v_me))
      AND (b.bloque_jusquau IS NULL OR b.bloque_jusquau > now())
  ) THEN RAISE EXCEPTION 'users_blocked'; END IF;

  SELECT lower(coalesce(up.allow_messages_from, 'everyone'))
      IN ('everyone', 'tous', 'tout_le_monde')
    INTO v_allowed
  FROM public.user_privacy up
  WHERE up.user_id = p_other_user_id;

  v_allowed := coalesce(v_allowed, true);
  IF NOT v_connected AND NOT v_allowed THEN
    RAISE EXCEPTION 'users_not_allowed_to_message';
  END IF;

  SELECT id INTO v_id FROM public.direct_conversations
  WHERE user_one_id = v_one AND user_two_id = v_two;

  IF v_id IS NULL THEN
    INSERT INTO public.direct_conversations(user_one_id, user_two_id)
    VALUES (v_one, v_two) RETURNING id INTO v_id;
  END IF;

  INSERT INTO public.direct_conversation_members(conversation_id, user_id)
  VALUES (v_id, v_one) ON CONFLICT DO NOTHING;
  INSERT INTO public.direct_conversation_members(conversation_id, user_id)
  VALUES (v_id, v_two) ON CONFLICT DO NOTHING;

  UPDATE public.direct_conversation_members
  SET is_deleted = false, deleted_at = null
  WHERE conversation_id = v_id AND user_id = v_me;

  RETURN v_id;
END;
$function$


CREATE OR REPLACE FUNCTION public.send_direct_message(p_conversation_id uuid, p_text text DEFAULT NULL::text, p_type text DEFAULT 'text'::text, p_audio_url text DEFAULT NULL::text, p_media_urls text[] DEFAULT '{}'::text[], p_replied_to_id uuid DEFAULT NULL::uuid)
 RETURNS direct_messages
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_message public.direct_messages;
  v_me uuid := auth.uid();
  v_other uuid;
  v_allowed boolean := true;
  v_connected boolean := false;
BEGIN
  IF v_me IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING errcode = '42501'; END IF;
  IF NOT public.direct_conversation_is_member(p_conversation_id) THEN
    RAISE EXCEPTION 'not_conversation_member' USING errcode = '42501';
  END IF;

  SELECT CASE WHEN dc.user_one_id = v_me THEN dc.user_two_id ELSE dc.user_one_id END
  INTO v_other
  FROM public.direct_conversations dc
  WHERE dc.id = p_conversation_id AND v_me IN (dc.user_one_id, dc.user_two_id);

  IF v_other IS NULL THEN RAISE EXCEPTION 'not_conversation_member' USING errcode = '42501'; END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.friendships f
    WHERE f.user_a_id = least(v_me, v_other) AND f.user_b_id = greatest(v_me, v_other)
  ) INTO v_connected;

  SELECT lower(coalesce(up.allow_messages_from, 'everyone'))
      IN ('everyone', 'tous', 'tout_le_monde')
    INTO v_allowed
  FROM public.user_privacy up WHERE up.user_id = v_other;
  v_allowed := coalesce(v_allowed, true);

  IF NOT v_connected AND NOT v_allowed THEN
    RAISE EXCEPTION 'users_not_allowed_to_message' USING errcode = '42501';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.blocage_utilisateur b
    WHERE b.statut
      AND ((b.bloqueur_id = v_me AND b.bloque_id = v_other)
        OR (b.bloqueur_id = v_other AND b.bloque_id = v_me))
      AND (b.bloque_jusquau IS NULL OR b.bloque_jusquau > now())
  ) THEN RAISE EXCEPTION 'users_blocked' USING errcode = '42501'; END IF;

  INSERT INTO public.direct_messages (
    conversation_id, sender_id, text, type, audio_url, media_urls, replied_to_id
  ) VALUES (
    p_conversation_id, v_me, nullif(trim(p_text), ''), p_type, p_audio_url,
    coalesce(p_media_urls, '{}'), p_replied_to_id
  ) RETURNING * INTO v_message;

  UPDATE public.direct_conversations
  SET last_message_at = v_message.created_at, updated_at = now()
  WHERE id = p_conversation_id;
  RETURN v_message;
END;
$function$


CREATE OR REPLACE FUNCTION public.insert_direct_message(p_message_id uuid, p_conversation_id uuid, p_text text DEFAULT NULL::text, p_type text DEFAULT 'text'::text, p_audio_url text DEFAULT NULL::text, p_media_urls text[] DEFAULT '{}'::text[], p_replied_to_id uuid DEFAULT NULL::uuid)
 RETURNS direct_messages
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_message public.direct_messages;
  v_me uuid := auth.uid();
  v_other uuid;
  v_allowed boolean := true;
  v_connected boolean := false;
BEGIN
  IF v_me IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING errcode='42501'; END IF;
  IF NOT public.direct_conversation_is_member(p_conversation_id) THEN
    RAISE EXCEPTION 'not_conversation_member' USING errcode='42501';
  END IF;

  SELECT CASE WHEN dc.user_one_id = v_me THEN dc.user_two_id ELSE dc.user_one_id END
  INTO v_other FROM public.direct_conversations dc
  WHERE dc.id = p_conversation_id AND v_me IN (dc.user_one_id, dc.user_two_id);
  IF v_other IS NULL THEN RAISE EXCEPTION 'not_conversation_member' USING errcode='42501'; END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.friendships f
    WHERE f.user_a_id = least(v_me, v_other) AND f.user_b_id = greatest(v_me, v_other)
  ) INTO v_connected;
  SELECT lower(coalesce(up.allow_messages_from, 'everyone'))
      IN ('everyone', 'tous', 'tout_le_monde')
    INTO v_allowed FROM public.user_privacy up WHERE up.user_id = v_other;
  v_allowed := coalesce(v_allowed, true);

  IF NOT v_connected AND NOT v_allowed THEN
    RAISE EXCEPTION 'users_not_allowed_to_message' USING errcode='42501';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.blocage_utilisateur b
    WHERE b.statut
      AND ((b.bloqueur_id = v_me AND b.bloque_id = v_other)
        OR (b.bloqueur_id = v_other AND b.bloque_id = v_me))
      AND (b.bloque_jusquau IS NULL OR b.bloque_jusquau > now())
  ) THEN RAISE EXCEPTION 'users_blocked' USING errcode='42501'; END IF;

  INSERT INTO public.direct_messages(id, conversation_id, sender_id, text, type, audio_url, media_urls, replied_to_id)
  VALUES (p_message_id, p_conversation_id, v_me, nullif(trim(p_text), ''), p_type, p_audio_url, coalesce(p_media_urls, '{}'), p_replied_to_id)
  ON CONFLICT(id) DO UPDATE SET id = public.direct_messages.id
  RETURNING * INTO v_message;

  UPDATE public.direct_conversations
  SET last_message_at = greatest(coalesce(last_message_at, v_message.created_at), v_message.created_at),
      updated_at = now()
  WHERE id = p_conversation_id;
  RETURN v_message;
END;
$function$


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


DROP POLICY IF EXISTS direct_messages_insert_sender_member ON public.direct_messages;
CREATE POLICY direct_messages_insert_sender_member
ON public.direct_messages
FOR INSERT
TO authenticated
WITH CHECK (
  sender_id = auth.uid()
  AND public.direct_conversation_is_member(conversation_id)
  AND EXISTS (
    SELECT 1
    FROM public.direct_conversations dc
    WHERE dc.id = conversation_id
      AND auth.uid() IN (dc.user_one_id, dc.user_two_id)
      AND public.can_send_direct_message_to(
        auth.uid(),
        CASE WHEN dc.user_one_id = auth.uid() THEN dc.user_two_id ELSE dc.user_one_id END
      )
  )
);
