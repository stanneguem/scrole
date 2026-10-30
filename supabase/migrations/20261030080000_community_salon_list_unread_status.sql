DROP FUNCTION IF EXISTS public.list_community_chat_groups_with_preview(uuid);
CREATE FUNCTION public.list_community_chat_groups_with_preview(p_community_id uuid)
RETURNS TABLE(
 id uuid,community_id uuid,name text,description text,visibility text,created_by uuid,
 created_at timestamptz,updated_at timestamptz,avatar_url text,
 last_message text,last_message_type text,last_message_at timestamptz,
 last_message_sender_id uuid,last_message_sender_name text,
 unread_count bigint,last_message_all_read boolean,
 member_count bigint,my_status text,can_manage boolean
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$
DECLARE v_uid uuid:=auth.uid();
BEGIN
 IF v_uid IS NULL OR NOT public.is_community_member(p_community_id) THEN
   RAISE EXCEPTION 'Vous devez être membre de la communauté';
 END IF;
 RETURN QUERY
 SELECT s.id,s.community_id,s.name,s.description,s.visibility,s.created_by,s.created_at,s.updated_at,s.avatar_url,
   latest.content,latest.type,latest.sent_at,latest.sender_id,
   CASE WHEN latest.sender_id=v_uid THEN 'Vous' ELSE COALESCE(NULLIF(trim(concat_ws(' ',up.first_name,up.last_name)),''),up.username,'Membre') END,
   CASE WHEN latest.id IS NULL THEN 0::bigint ELSE (
     SELECT count(*) FROM public.community_salon_messages um
     LEFT JOIN public.community_salon_message_receipts ur ON ur.message_id=um.id AND ur.user_id=v_uid
     WHERE um.salon_id=s.id AND NOT um.is_deleted AND um.sender_id<>v_uid
       AND um.sent_at>COALESCE((
         SELECT max(rr.read_at) FROM public.community_salon_message_receipts rr
         JOIN public.community_salon_messages rm ON rm.id=rr.message_id
         WHERE rr.user_id=v_uid AND rm.salon_id=s.id
       ),'epoch'::timestamptz)
   ) END,
   CASE WHEN latest.id IS NULL OR latest.sender_id<>v_uid THEN false ELSE
     (SELECT count(*)>0 AND count(*)=count(*) FILTER (WHERE lr.read_at IS NOT NULL)
      FROM public.community_salon_members lm
      LEFT JOIN public.community_salon_message_receipts lr ON lr.message_id=latest.id AND lr.user_id=lm.user_id
      WHERE lm.salon_id=s.id AND lm.user_id<>v_uid)
   END,
   CASE WHEN s.visibility='public' OR s.created_by=v_uid OR EXISTS(SELECT 1 FROM public.community_salon_members m WHERE m.salon_id=s.id AND m.user_id=v_uid)
     THEN (SELECT count(*) FROM public.community_salon_members m WHERE m.salon_id=s.id) ELSE NULL END,
   CASE WHEN s.created_by=v_uid OR EXISTS(SELECT 1 FROM public.community_salon_members m WHERE m.salon_id=s.id AND m.user_id=v_uid)
     THEN 'member' ELSE COALESCE((SELECT r.status FROM public.community_salon_join_requests r WHERE r.salon_id=s.id AND r.user_id=v_uid),'none') END,
   public.community_can(p_community_id,'can_create_salon')
 FROM public.community_salons s
 LEFT JOIN LATERAL (
   SELECT m.id,m.content,m.type,m.sent_at,m.sender_id FROM public.community_salon_messages m
   WHERE m.salon_id=s.id AND NOT m.is_deleted ORDER BY m.sent_at DESC LIMIT 1
 ) latest ON true
 LEFT JOIN public.user_profiles up ON up.user_id=latest.sender_id
 WHERE s.community_id=p_community_id AND (
   s.visibility='public' OR s.created_by=v_uid
   OR EXISTS(SELECT 1 FROM public.community_salon_members m WHERE m.salon_id=s.id AND m.user_id=v_uid)
   OR EXISTS(SELECT 1 FROM public.community_salon_join_requests r WHERE r.salon_id=s.id AND r.user_id=v_uid AND r.status='pending')
 )
 ORDER BY COALESCE(latest.sent_at,s.updated_at) DESC,s.created_at DESC;
END; $$;
REVOKE ALL ON FUNCTION public.list_community_chat_groups_with_preview(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.list_community_chat_groups_with_preview(uuid) TO authenticated;