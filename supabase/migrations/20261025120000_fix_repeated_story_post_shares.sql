-- Allow the same post to be shared into stories repeatedly by the same user.
-- Keep the 24-hour total-story limit, but do not impose a per-post uniqueness rule.
DO $migration$
DECLARE
  v record;
BEGIN
  FOR v IN
    SELECT ns.nspname AS schema_name, idx.relname AS index_name,
           con.conname AS constraint_name
    FROM pg_index i
    JOIN pg_class tbl ON tbl.oid = i.indrelid
    JOIN pg_namespace ns ON ns.oid = tbl.relnamespace
    JOIN pg_class idx ON idx.oid = i.indexrelid
    LEFT JOIN pg_constraint con ON con.conindid = i.indexrelid
    WHERE ns.nspname = 'public'
      AND tbl.relname = 'stories'
      AND i.indisunique
      AND NOT i.indisprimary
      AND pg_get_indexdef(i.indexrelid) ILIKE '%shared_post_id%'
      AND pg_get_indexdef(i.indexrelid) ILIKE '%author_id%'
  LOOP
    IF v.constraint_name IS NOT NULL THEN
      EXECUTE format('ALTER TABLE public.stories DROP CONSTRAINT %I', v.constraint_name);
    ELSE
      EXECUTE format('DROP INDEX %I.%I', v.schema_name, v.index_name);
    END IF;
  END LOOP;
END
$migration$;

CREATE OR REPLACE FUNCTION public.share_post_to_story(
  p_id uuid,
  p_original_post_id uuid,
  p_caption text DEFAULT NULL::text,
  p_background text DEFAULT NULL::text,
  p_audience text DEFAULT 'public'::text
)
RETURNS public.stories
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_row public.stories;
  v_orig public.community_posts;
  v_audience text := lower(btrim(coalesce(p_audience, 'public')));
  v_caption text := nullif(btrim(p_caption), '');
  v_bg text := nullif(btrim(p_background), '');
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF p_id IS NULL THEN RAISE EXCEPTION 'L''identifiant de la story est obligatoire'; END IF;

  SELECT * INTO v_row FROM public.stories WHERE id = p_id;
  IF FOUND THEN
    IF v_row.author_id = v_uid THEN RETURN v_row; END IF;
    RAISE EXCEPTION 'Identifiant de story déjà utilisé';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.user_profiles up
    WHERE up.user_id = v_uid AND up.account_status = 'active' AND up.deleted_at IS NULL
  ) THEN RAISE EXCEPTION 'Compte indisponible'; END IF;

  IF v_audience NOT IN ('public', 'followers', 'friends') THEN RAISE EXCEPTION 'Audience invalide'; END IF;
  IF char_length(coalesce(p_caption, '')) > 500 THEN RAISE EXCEPTION 'Le texte ne peut pas dépasser 500 caractères'; END IF;
  IF v_bg IS NOT NULL AND v_bg !~ '^(#[0-9A-Fa-f]{6}|[a-z0-9_-]{1,30})$' THEN RAISE EXCEPTION 'Fond invalide'; END IF;

  IF p_original_post_id IS NULL THEN RAISE EXCEPTION 'Publication indisponible'; END IF;
  SELECT * INTO v_orig FROM public.community_posts WHERE id = p_original_post_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Publication indisponible'; END IF;

  IF v_orig.status <> 'active'
     OR NOT public.can_view_post_row(v_orig.community_id, v_orig.author_id, v_orig.audience) THEN
    RAISE EXCEPTION 'Publication indisponible';
  END IF;
  IF private.users_blocked(v_uid, v_orig.author_id) THEN RAISE EXCEPTION 'Action impossible'; END IF;
  IF NOT private.community_chain_sharing_allowed(p_original_post_id) THEN
    RAISE EXCEPTION 'Le repartage est désactivé sur cette publication ou sa communauté source';
  END IF;

  IF v_orig.community_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.communities c
      WHERE c.id = v_orig.community_id AND c.status = 'active'
        AND (c.visibility = 'public' OR public.is_community_member(c.id))
    ) THEN RAISE EXCEPTION 'Ce post ne peut pas être partagé'; END IF;

    IF EXISTS (
      SELECT 1 FROM public.community_settings cs
      WHERE cs.community_id = v_orig.community_id
        AND NOT coalesce(cs.allow_post_sharing, true)
    ) THEN RAISE EXCEPTION 'Le repartage est désactivé par les administrateurs de cette communauté'; END IF;
  ELSIF v_orig.audience <> 'public' THEN
    RAISE EXCEPTION 'Ce post ne peut pas être partagé';
  END IF;

  IF (SELECT count(*) FROM public.stories s
      WHERE s.author_id = v_uid AND s.created_at > now() - interval '24 hours') >= 20 THEN
    RAISE EXCEPTION 'Limite de stories atteinte : 20 stories par 24 heures';
  END IF;

  -- A fresh p_id creates a fresh story even when this source post was shared before.
  INSERT INTO public.stories (
    id, author_id, kind, content, background, audience,
    shared_post_id, shared_post_snapshot, expires_at
  )
  VALUES (
    p_id, v_uid, 'post', v_caption, v_bg, v_audience, v_orig.id,
    private.redact_shared_snapshot(private.story_post_snapshot(v_orig.id, v_uid, 0)),
    now() + interval '24 hours'
  )
  RETURNING * INTO v_row;

  IF v_orig.author_id <> v_uid THEN
    PERFORM private.notify_community_user(
      v_orig.author_id, 'post_shared_story', v_uid,
      jsonb_build_object(
        'post_id', v_orig.id, 'story_id', p_id,
        'community_id', v_orig.community_id, 'actor_id', v_uid
      ),
      'Publication partagée en story',
      'Quelqu''un a partagé votre publication dans sa story.'
    );
  END IF;

  RETURN v_row;
END
$function$;

REVOKE ALL ON FUNCTION public.share_post_to_story(uuid, uuid, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.share_post_to_story(uuid, uuid, text, text, text) TO authenticated;
NOTIFY pgrst, 'reload schema';
