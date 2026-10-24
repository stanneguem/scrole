-- Public wrapper is required because anon must not receive USAGE on the private schema.
CREATE OR REPLACE FUNCTION public.can_open_shared_post_source(p_post_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT private.story_can_open_original(p_post_id, auth.uid());
$function$;

REVOKE ALL ON FUNCTION public.can_open_shared_post_source(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.can_open_shared_post_source(uuid) TO anon, authenticated;

DROP POLICY IF EXISTS community_posts_select ON public.community_posts;
CREATE POLICY community_posts_select ON public.community_posts
  FOR SELECT TO anon, authenticated
  USING (
    status = 'active'
    AND public.can_view_post_row(community_id, author_id, audience)
    AND (shared_post_id IS NULL OR public.can_open_shared_post_source(shared_post_id))
  );

DROP POLICY IF EXISTS stories_select ON public.stories;
CREATE POLICY stories_select ON public.stories
  FOR SELECT TO authenticated
  USING (
    status = 'active'
    AND expires_at > now()
    AND public.can_view_story_row(author_id, audience)
    AND (shared_post_id IS NULL OR public.can_open_shared_post_source(shared_post_id))
  );
