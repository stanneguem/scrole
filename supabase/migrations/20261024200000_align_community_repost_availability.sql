-- Expose the effective community repost setting to feed cards and align the
-- availability RPC with the enforcement used by the actual share RPCs.
CREATE OR REPLACE FUNCTION private.post_item(p_post_id uuid, p_viewer uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select jsonb_build_object(
    'type', 'post', 'id', p.id, 'community_id', p.community_id, 'author_id', p.author_id,
    'content', p.content, 'photo', p.photo, 'photos', p.photos,
    'media', case when jsonb_typeof(p.media) = 'array' and jsonb_array_length(p.media) > 0 then p.media
                  else coalesce((select jsonb_agg(jsonb_build_object('type', 'photo', 'url', x) order by ord)
                                 from unnest(coalesce(p.photos, '{}'::text[])) with ordinality t(x, ord)), '[]'::jsonb) end,
    'created_at', p.created_at, 'updated_at', p.updated_at, 'status', p.status,
    'audience', p.audience, 'allow_promotion', p.allow_promotion,
    'comments_enabled', p.comments_enabled, 'sharing_enabled', p.sharing_enabled, 'reactions_enabled', p.reactions_enabled,
    'hashtags', coalesce((select jsonb_agg(jsonb_build_object('id', h.id, 'name', h.name) order by h.name)
                          from public.community_post_hashtags ph join public.hashtags h on h.id = ph.hashtag_id
                          where ph.post_id = p.id), '[]'::jsonb),
    'mentions', coalesce((select jsonb_agg(jsonb_build_object('user_id', mu.user_id, 'username', mup.username,
                            'first_name', mup.first_name, 'last_name', mup.last_name, 'photo_url', mup.photo_url) order by mu.created_at)
                          from public.community_post_mentions mu join public.user_profiles mup on mup.user_id = mu.user_id
                          where mu.post_id = p.id), '[]'::jsonb),
    'poll', private.poll_state(p.id, p_viewer),
    'author', jsonb_build_object('user_id', p.author_id, 'username', up.username, 'first_name', up.first_name,
                'last_name', up.last_name, 'photo_url', up.photo_url, 'pseudo', up.username,
                'is_certified', exists (select 1 from public.user_certifications uc where uc.user_id = p.author_id
                                        and uc.status::text = 'active' and uc.issued_at <= now()
                                        and (uc.expires_at is null or uc.expires_at >= now()))),
    'community', case when p.community_id is null then null else
                  (select jsonb_build_object(
                    'id', c.id, 'name', c.name, 'slug', c.slug,
                    'photo_profile', c.photo_profile, 'visibility', c.visibility,
                    'allow_post_sharing', coalesce((select cs.allow_post_sharing from public.community_settings cs where cs.community_id = c.id), true)
                  ) from public.communities c where c.id = p.community_id) end,
    'comments_count', (select count(*) from public.community_post_comments c where c.post_id = p.id),
    'likes_count', (select count(*) from public.community_post_reactions r where r.post_id = p.id and r.reaction = 'like'),
    'dislikes_count', (select count(*) from public.community_post_reactions r where r.post_id = p.id and r.reaction = 'dislike'),
    'viewer_reaction', (select r.reaction from public.community_post_reactions r where r.post_id = p.id and r.user_id = p_viewer)
  ) || private.post_extras(p.id, p_viewer)
  from public.community_posts p
  join public.user_profiles up on up.user_id = p.author_id
  where p.id = p_post_id;
$function$
;
CREATE OR REPLACE FUNCTION public.can_repost_community_post(p_post_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(exists (
    select 1
    from public.community_posts p
    where p.id = p_post_id
      and p.status = 'active'
      and public.can_view_post_row(p.community_id, p.author_id, p.audience)
      and private.community_chain_sharing_allowed(p.id)
      and not private.users_blocked(auth.uid(), p.author_id)
      and (p.community_id is null or public.is_community_member(p.community_id))
  ), false);
$function$;
REVOKE ALL ON FUNCTION public.can_repost_community_post(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_repost_community_post(uuid) TO authenticated;
