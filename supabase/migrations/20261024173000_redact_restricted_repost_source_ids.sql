-- Remove all source identifiers and community metadata from a shared preview that
-- is intentionally visible without access to its source.
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
    'author_id', null,
    'likes_count', 0,
    'dislikes_count', 0,
    'comments_count', 0,
    'shares_count', 0,
    'views_count', 0,
    'viewer_reaction', null
  );
END
$function$;

REVOKE ALL ON FUNCTION private.redact_shared_snapshot(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.redact_shared_snapshot(jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION private.post_extras(p_post_id uuid, p_viewer uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_shared uuid;
  v_scomment uuid;
  v_snapshot jsonb;
  v_card jsonb := null;
  v_ccard jsonb := null;
  v_orig public.community_posts;
begin
  select shared_post_id, shared_comment_id, shared_post_snapshot
    into v_shared, v_scomment, v_snapshot
  from public.community_posts where id = p_post_id;

  if v_shared is not null then
    select * into v_orig from public.community_posts where id = v_shared;
    if found and v_orig.status = 'active'
       and private.story_can_open_original(v_shared, p_viewer) then
      v_card := private.post_item(v_shared, p_viewer) || jsonb_build_object('available', true, 'can_open_original', true);
    elsif v_snapshot is not null then
      v_card := private.redact_shared_snapshot(v_snapshot) || jsonb_build_object('available', true, 'can_open_original', false);
    else
      v_card := jsonb_build_object('id', v_shared, 'available', false, 'can_open_original', false);
    end if;
  end if;

  if v_scomment is not null then
    v_ccard := private.comment_card(v_scomment, p_viewer);
  end if;

  return jsonb_build_object(
    'views_count', (select coalesce(sum(v.view_count), 0)::bigint from public.post_views v where v.post_id = p_post_id),
    'viewers_count', (select count(*) from public.post_views v where v.post_id = p_post_id),
    'shares_count', (select count(*) from public.community_posts s where s.shared_post_id = p_post_id and s.status = 'active'),
    'viewer_has_shared', exists (select 1 from public.community_posts s where s.shared_post_id = p_post_id and s.author_id = p_viewer),
    'shared_post_id', case when v_card is not null and coalesce((v_card ->> 'can_open_original')::boolean, false) then v_shared else null end,
    'shared_post', v_card,
    'shared_post_can_open_original', coalesce((v_card ->> 'can_open_original')::boolean, false),
    'shared_comment_id', v_scomment,
    'shared_comment', v_ccard
  );
end
$function$
;

CREATE OR REPLACE FUNCTION private.story_groups(p_scope text, p_limit integer, p_offset integer, p_author uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_uid uuid := auth.uid(); v_result jsonb;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  with vis as (
    select s.id, s.author_id, s.kind, s.content, s.image_url, s.background, s.shared_post_id, s.shared_post_snapshot, s.audience, s.created_at, s.expires_at,
           exists (select 1 from public.story_views sv where sv.story_id = s.id and sv.viewer_id = v_uid) as viewed
    from public.stories s
    where s.status = 'active' and s.expires_at > now()
      and public.can_view_story_row(s.author_id, s.audience)
      and case p_scope when 'own' then s.author_id = v_uid when 'user' then s.author_id = p_author else s.author_id <> v_uid end
  ),
  rel as (
    select a.author_id,
      case when a.author_id = v_uid then 'own'
           when public.are_friends(v_uid, a.author_id) then 'friend'
           when exists (select 1 from public.user_follows f where f.follower_id = v_uid and f.followed_id = a.author_id) then 'follow'
           else 'other' end as relation
    from (select distinct author_id from vis) a
  ),
  grp as (
    select v.author_id, r.relation, max(v.created_at) as latest_at, count(*)::int as stories_count,
           bool_or(not v.viewed) as has_unseen
    from vis v join rel r on r.author_id = v.author_id
    group by v.author_id, r.relation
  ),
  filtered as (
    select g.*,
      case when p_scope = 'suggested' then (
          least(50, (select count(*) from public.friendships f
                     where (f.user_a_id = g.author_id and public.are_friends(v_uid, f.user_b_id))
                        or (f.user_b_id = g.author_id and public.are_friends(v_uid, f.user_a_id))) * 10)
        + least(32, (select count(*) from public.community_members a join public.community_members b
                     on b.community_id = a.community_id and b.user_id = g.author_id where a.user_id = v_uid) * 8)
        + least(20, (select count(*) from public.user_interests a join public.user_interests b
                     on b.interest_id = a.interest_id and b.user_id = v_uid where a.user_id = v_uid) * 5)
        + least(30, round(5 * ln(1 + (select count(distinct sv.viewer_id) from public.story_views sv
                     join vis v2 on v2.id = sv.story_id where v2.author_id = g.author_id))))
        + floor(20 * exp(-extract(epoch from (now() - g.latest_at)) / 43200.0))
      )::numeric else 0::numeric end as score
    from grp g
    join public.user_profiles up on up.user_id = g.author_id and up.account_status = 'active' and up.deleted_at is null
    where case p_scope
            when 'following' then g.relation in ('friend', 'follow')
            when 'suggested' then g.relation = 'other' and g.has_unseen
            else true end
  ),
  ordered as (
    select f.*, row_number() over (
      order by case when p_scope = 'suggested' then -f.score else (case when f.has_unseen then 0 else 1 end)::numeric end,
               f.latest_at desc, f.author_id) as rn
    from filtered f
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'author', jsonb_build_object('user_id', up.user_id, 'username', up.username, 'pseudo', up.username, 'first_name', up.first_name,
                 'last_name', up.last_name, 'photo_url', up.photo_url,
                 'is_certified', exists (select 1 from public.user_certifications uc where uc.user_id = up.user_id
                                         and uc.status::text = 'active' and uc.issued_at <= now()
                                         and (uc.expires_at is null or uc.expires_at >= now()))),
      'relation', o.relation, 'has_unseen', o.has_unseen, 'latest_at', o.latest_at, 'stories_count', o.stories_count,
      'stories', (select jsonb_agg(jsonb_build_object(
                    'id', v.id, 'kind', v.kind, 'content', v.content, 'image_url', v.image_url, 'background', v.background,
                    'shared_post_id', case when v.shared_post_id is not null and private.story_can_open_original(v.shared_post_id, v_uid) then v.shared_post_id else null end,
                    'shared_post_can_open_original', case when v.shared_post_id is null then false else private.story_can_open_original(v.shared_post_id, v_uid) end,
                    'shared_post', case
                      when v.shared_post_id is null then null
                      when private.story_can_open_original(v.shared_post_id, v_uid) then private.story_post_card(v.shared_post_id, v_uid)
                      else coalesce(private.redact_shared_snapshot(v.shared_post_snapshot), jsonb_build_object('available', false, 'can_open_original', false))
                    end,
                    'audience', v.audience, 'created_at', v.created_at, 'expires_at', v.expires_at, 'viewed', v.viewed,
                    'viewers_count', case when v.author_id = v_uid then (select count(*) from public.story_views sv where sv.story_id = v.id) end,
                    'comments_count', (select count(*)::integer from public.story_comments c
                                       join public.user_profiles cup on cup.user_id = c.author_id
                                       where c.story_id = v.id and c.parent_comment_id is null
                                         and cup.account_status = 'active' and cup.deleted_at is null),
                    'viewer_has_liked', exists (select 1 from public.story_likes sl where sl.story_id = v.id and sl.user_id = v_uid),
                    'likes_count', case when v.author_id = v_uid then (select count(*) from public.story_likes sl where sl.story_id = v.id) end,
                    'poll', private.story_poll_state(v.id, v_uid)) order by v.created_at)
                  from vis v where v.author_id = o.author_id)
    ) order by o.rn), '[]'::jsonb)
  into v_result
  from ordered o join public.user_profiles up on up.user_id = o.author_id
  where o.rn > p_offset and o.rn <= p_offset + p_limit;
  return v_result;
end $function$
;
