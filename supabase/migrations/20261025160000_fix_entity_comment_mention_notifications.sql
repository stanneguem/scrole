-- Fix entity mention matching and retain the exact source post/comment in notifications.
CREATE OR REPLACE FUNCTION public.save_content_entity_mentions(
  p_source_type text,
  p_source_id uuid,
  p_community_ids uuid[] DEFAULT '{}'::uuid[],
  p_event_ids uuid[] DEFAULT '{}'::uuid[]
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_actor uuid := auth.uid();
  v_community_id uuid;
  v_event_id uuid;
  v_source_community_id uuid;
  v_post_id uuid;
  v_content text;
  v_saved integer := 0;
  v_context text;
  v_title text;
  v_body text;
  v_recipient uuid;
  v_is_organizer boolean;
BEGIN
  IF v_actor IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF p_source_type NOT IN ('post','comment') THEN RAISE EXCEPTION 'Source invalide'; END IF;

  IF p_source_type = 'post' THEN
    SELECT p.id, p.community_id, p.content
      INTO v_post_id, v_source_community_id, v_content
    FROM public.community_posts p
    WHERE p.id = p_source_id AND p.author_id = v_actor AND p.status = 'active';
    IF NOT FOUND THEN RAISE EXCEPTION 'Publication introuvable ou non autorisée'; END IF;
  ELSE
    SELECT p.id, p.community_id, c.content
      INTO v_post_id, v_source_community_id, v_content
    FROM public.community_post_comments c
    JOIN public.community_posts p ON p.id = c.post_id
    WHERE c.id = p_source_id AND c.author_id = v_actor AND p.status = 'active';
    IF NOT FOUND THEN RAISE EXCEPTION 'Commentaire introuvable ou non autorisé'; END IF;
  END IF;

  v_context := CASE WHEN p_source_type = 'post' THEN 'publication' ELSE 'commentaire' END;

  FOREACH v_community_id IN ARRAY coalesce(p_community_ids, '{}'::uuid[]) LOOP
    -- The UI inserts community mentions as ~{Community name}.
    IF EXISTS (
      SELECT 1 FROM public.communities c
      WHERE c.id = v_community_id
        AND c.status = 'active'
        AND position('~{' || c.name || '}' IN coalesce(v_content,'')) > 0
    ) AND NOT EXISTS (
      SELECT 1 FROM public.community_content_entity_mentions m
      WHERE m.source_type=p_source_type AND m.source_id=p_source_id
        AND m.entity_type='community' AND m.entity_id=v_community_id
    ) THEN
      INSERT INTO public.community_content_entity_mentions(source_type,source_id,entity_type,entity_id,actor_id)
      VALUES(p_source_type,p_source_id,'community',v_community_id,v_actor)
      ON CONFLICT DO NOTHING;
      IF FOUND THEN
        v_saved := v_saved + 1;
        v_title := 'Votre communauté a été mentionnée';
        v_body := 'Votre communauté a été mentionnée dans un ' || v_context || '.';

        FOR v_recipient IN
          SELECT cm.user_id
          FROM public.community_members cm
          JOIN public.user_profiles up ON up.user_id=cm.user_id
          WHERE cm.community_id=v_community_id
            AND up.account_status='active' AND up.deleted_at IS NULL
          UNION
          SELECT c.creator_id FROM public.communities c WHERE c.id=v_community_id
        LOOP
          PERFORM private.notify_community_user(
            v_recipient,
            CASE WHEN p_source_type='post' THEN 'community_mentioned_in_post' ELSE 'community_mentioned_in_comment' END,
            v_actor,
            jsonb_build_object(
              'mentioned_community_id',v_community_id,
              'source_community_id',v_source_community_id,
              'community_id',v_source_community_id,
              'source_type',p_source_type,'source_id',p_source_id,
              'post_id',v_post_id,
              'comment_id',CASE WHEN p_source_type='comment' THEN p_source_id ELSE NULL END,
              'actor_id',v_actor
            ),
            v_title,v_body
          );
        END LOOP;
      END IF;
    END IF;
  END LOOP;

  FOREACH v_event_id IN ARRAY coalesce(p_event_ids, '{}'::uuid[]) LOOP
    -- The UI inserts event mentions as *{Event name}.
    IF EXISTS (
      SELECT 1 FROM public.events e
      WHERE e.id=v_event_id
        AND coalesce(e.status,'active') NOT IN ('deleted','cancelled','archived')
        AND position('*{' || e.name || '}' IN coalesce(v_content,'')) > 0
    ) AND NOT EXISTS (
      SELECT 1 FROM public.community_content_entity_mentions m
      WHERE m.source_type=p_source_type AND m.source_id=p_source_id
        AND m.entity_type='event' AND m.entity_id=v_event_id
    ) THEN
      INSERT INTO public.community_content_entity_mentions(source_type,source_id,entity_type,entity_id,actor_id)
      VALUES(p_source_type,p_source_id,'event',v_event_id,v_actor)
      ON CONFLICT DO NOTHING;
      IF FOUND THEN
        v_saved := v_saved + 1;
        FOR v_recipient IN
          SELECT ec.user_id FROM public.event_calendar ec WHERE ec.event_id=v_event_id
          UNION
          SELECT e.creator_id FROM public.events e WHERE e.id=v_event_id
          UNION
          SELECT cc.user_id FROM public.event_co_creators cc
          WHERE cc.event_id=v_event_id AND coalesce(cc.status,'accepted') IN ('accepted','active')
          UNION
          SELECT es.user_id FROM public.event_staff es
          WHERE es.event_id=v_event_id AND coalesce(es.status,'accepted') IN ('accepted','active')
        LOOP
          SELECT
            EXISTS(SELECT 1 FROM public.events e WHERE e.id=v_event_id AND e.creator_id=v_recipient)
            OR EXISTS(SELECT 1 FROM public.event_co_creators cc WHERE cc.event_id=v_event_id AND cc.user_id=v_recipient AND coalesce(cc.status,'accepted') IN ('accepted','active'))
            OR EXISTS(SELECT 1 FROM public.event_staff es WHERE es.event_id=v_event_id AND es.user_id=v_recipient AND coalesce(es.status,'accepted') IN ('accepted','active'))
          INTO v_is_organizer;

          IF v_is_organizer THEN
            v_title := 'Votre événement a été mentionné';
            v_body := 'Votre événement a été mentionné dans un ' || v_context || '.';
          ELSE
            v_title := 'Un événement de votre calendrier a été mentionné';
            v_body := 'Un événement auquel vous souhaitez participer a été mentionné dans un ' || v_context || '.';
          END IF;

          PERFORM private.notify_community_user(
            v_recipient,
            CASE WHEN v_is_organizer THEN
              CASE WHEN p_source_type='post' THEN 'event_organizer_mentioned_in_post' ELSE 'event_organizer_mentioned_in_comment' END
            ELSE
              CASE WHEN p_source_type='post' THEN 'event_mentioned_in_post' ELSE 'event_mentioned_in_comment' END
            END,
            v_actor,
            jsonb_build_object(
              'event_id',v_event_id,
              'source_community_id',v_source_community_id,
              'community_id',v_source_community_id,
              'source_type',p_source_type,'source_id',p_source_id,
              'post_id',v_post_id,
              'comment_id',CASE WHEN p_source_type='comment' THEN p_source_id ELSE NULL END,
              'actor_id',v_actor,
              'recipient_role',CASE WHEN v_is_organizer THEN 'organizer' ELSE 'calendar' END
            ),
            v_title,v_body
          );
        END LOOP;
      END IF;
    END IF;
  END LOOP;

  RETURN jsonb_build_object('success',true,'saved',v_saved);
END;
$function$;

REVOKE ALL ON FUNCTION public.save_content_entity_mentions(text,uuid,uuid[],uuid[]) FROM public;
GRANT EXECUTE ON FUNCTION public.save_content_entity_mentions(text,uuid,uuid[],uuid[]) TO authenticated;
