-- Restricted previews must not advertise a repost action that cannot be authorized.
CREATE OR REPLACE FUNCTION private.redact_shared_snapshot(p_snapshot jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
DECLARE
  v_result jsonb;
  v_key text;
  v_value jsonb;
BEGIN
  IF p_snapshot IS NULL OR jsonb_typeof(p_snapshot) <> 'object' THEN
    RETURN p_snapshot;
  END IF;
  v_result := '{}'::jsonb;
  FOR v_key, v_value IN SELECT key, value FROM jsonb_each(p_snapshot)
  LOOP
    IF v_key = ANY (ARRAY[
      'id','user_id','author_id','community_id','community','shared_post_id',
      'shared_comment_id','shared_comment','poll','likes_count','dislikes_count',
      'comments_count','shares_count','views_count','viewers_count','viewer_reaction',
      'viewer_has_shared','community_slug'
    ]) THEN
      CONTINUE;
    ELSIF v_key = 'author' AND jsonb_typeof(v_value) = 'object' THEN
      v_result := v_result || jsonb_build_object(
        v_key, private.redact_shared_snapshot(v_value)
      );
    ELSIF v_key = 'shared_post' AND jsonb_typeof(v_value) = 'object' THEN
      v_result := v_result || jsonb_build_object(
        v_key, private.redact_shared_snapshot(v_value)
      );
    ELSIF v_key = 'media' AND jsonb_typeof(v_value) = 'array' THEN
      v_result := v_result || jsonb_build_object(v_key, v_value);
    ELSE
      v_result := v_result || jsonb_build_object(v_key, v_value);
    END IF;
  END LOOP;
  RETURN v_result || jsonb_build_object(
    'available', true,
    'can_open_original', false,
    'shared_post_can_open_original', false,
    'sharing_enabled', false,
    'author_id', null,
    'likes_count', 0,
    'dislikes_count', 0,
    'comments_count', 0,
    'shares_count', 0,
    'views_count', 0,
    'viewer_reaction', null
  );
END
$function$
;
REVOKE ALL ON FUNCTION private.redact_shared_snapshot(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.redact_shared_snapshot(jsonb) TO authenticated;
