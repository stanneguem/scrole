ALTER TABLE public.community_salons ADD COLUMN IF NOT EXISTS avatar_url text;

CREATE OR REPLACE FUNCTION public.set_community_chat_group_avatar(
  p_salon_id uuid,
  p_avatar_url text
) RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_salon public.community_salons;
  v_expected_prefix text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Utilisateur non authentifié';
  END IF;

  SELECT * INTO v_salon
  FROM public.community_salons
  WHERE id = p_salon_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Discussion introuvable';
  END IF;

  IF v_salon.created_by <> v_uid
     AND NOT public.community_can(v_salon.community_id, 'can_create_salon') THEN
    RAISE EXCEPTION 'Action non autorisée';
  END IF;

  v_expected_prefix := '/salons/' || p_salon_id::text || '/avatar/';
  IF p_avatar_url IS NULL
     OR p_avatar_url !~ '^https://'
     OR position(v_expected_prefix in p_avatar_url) = 0
     OR p_avatar_url !~* '\.(jpg|jpeg|png|webp|avif|gif)(\?.*)?$' THEN
    RAISE EXCEPTION 'URL de couverture R2 invalide';
  END IF;

  UPDATE public.community_salons
  SET avatar_url = p_avatar_url, updated_at = now()
  WHERE id = p_salon_id;

  RETURN p_avatar_url;
END;
$$;

REVOKE ALL ON FUNCTION public.set_community_chat_group_avatar(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_community_chat_group_avatar(uuid, text) TO authenticated;

DROP FUNCTION IF EXISTS public.list_community_chat_groups_with_preview(uuid);
CREATE FUNCTION public.list_community_chat_groups_with_preview(p_community_id uuid)
RETURNS TABLE(
  id uuid,
  community_id uuid,
  name text,
  description text,
  visibility text,
  created_by uuid,
  created_at timestamptz,
  updated_at timestamptz,
  avatar_url text,
  last_message text,
  last_message_type text,
  last_message_at timestamptz,
  member_count bigint,
  my_status text,
  can_manage boolean
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL OR NOT public.is_community_member(p_community_id) THEN
    RAISE EXCEPTION 'Vous devez être membre de la communauté';
  END IF;

  RETURN QUERY
  SELECT
    s.id,
    s.community_id,
    s.name,
    s.description,
    s.visibility,
    s.created_by,
    s.created_at,
    s.updated_at,
    s.avatar_url,
    latest.content,
    latest.type,
    latest.sent_at,
    CASE
      WHEN s.visibility = 'public'
        OR s.created_by = v_uid
        OR EXISTS (
          SELECT 1 FROM public.community_salon_members m
          WHERE m.salon_id = s.id AND m.user_id = v_uid
        )
      THEN (
        SELECT count(*) FROM public.community_salon_members m
        WHERE m.salon_id = s.id
      )
      ELSE NULL
    END,
    CASE
      WHEN s.created_by = v_uid
        OR EXISTS (
          SELECT 1 FROM public.community_salon_members m
          WHERE m.salon_id = s.id AND m.user_id = v_uid
        )
      THEN 'member'
      ELSE COALESCE((
        SELECT r.status FROM public.community_salon_join_requests r
        WHERE r.salon_id = s.id AND r.user_id = v_uid
      ), 'none')
    END,
    public.community_can(p_community_id, 'can_create_salon')
  FROM public.community_salons s
  LEFT JOIN LATERAL (
    SELECT m.content, m.type, m.sent_at
    FROM public.community_salon_messages m
    WHERE m.salon_id = s.id AND NOT m.is_deleted
    ORDER BY m.sent_at DESC
    LIMIT 1
  ) latest ON true
  WHERE s.community_id = p_community_id
    AND (
      s.visibility = 'public'
      OR s.created_by = v_uid
      OR EXISTS (
        SELECT 1 FROM public.community_salon_members m
        WHERE m.salon_id = s.id AND m.user_id = v_uid
      )
      OR EXISTS (
        SELECT 1 FROM public.community_salon_join_requests r
        WHERE r.salon_id = s.id AND r.user_id = v_uid AND r.status = 'pending'
      )
    )
  ORDER BY COALESCE(latest.sent_at, s.updated_at) DESC, s.created_at DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.list_community_chat_groups_with_preview(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_community_chat_groups_with_preview(uuid) TO authenticated;