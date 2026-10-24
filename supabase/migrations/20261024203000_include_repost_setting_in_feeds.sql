-- Return the effective community-wide repost setting in both feed APIs.
CREATE OR REPLACE FUNCTION public.get_home_feed(p_limit integer DEFAULT 20, p_cursor text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := auth.uid();
  v_limit int := greatest(1, least(coalesce(p_limit, 20), 50));
  v_win numeric; v_prom_days numeric; v_prom_min numeric; v_ratio numeric;
  c_score numeric; c_ts timestamptz; c_id uuid; s_score numeric; s_ts timestamptz; s_id uuid;
  v_part text; v_in_c text := ''; v_in_s text := ''; v_page int := 0;
  v_posts jsonb; v_last_c text; v_last_s text; v_has_more boolean; v_next text;
  v_n int; v_pos int; v_car jsonb := '[]'::jsonb; v_c1 jsonb; v_c2 jsonb; v_out jsonb;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;

  select value into v_win from public.feed_config where key = 'feed_window_days';
  select value into v_prom_days from public.feed_config where key = 'promotion_window_days';
  select value into v_prom_min from public.feed_config where key = 'promotion_min_interactions';
  select value into v_ratio from public.feed_config where key = 'suggested_max_ratio';
  v_win := coalesce(v_win, 30); v_prom_days := coalesce(v_prom_days, 7);
  v_prom_min := coalesce(v_prom_min, 10); v_ratio := coalesce(v_ratio, 0.25);

  if p_cursor is not null and length(trim(p_cursor)) > 0 then
    begin
      v_in_c := split_part(p_cursor, '~', 1); v_in_s := split_part(p_cursor, '~', 2);
      v_page := coalesce(nullif(split_part(p_cursor, '~', 3), '')::int, 0);
      if v_in_c <> '' then
        c_score := split_part(v_in_c, '|', 1)::numeric; c_ts := split_part(v_in_c, '|', 2)::timestamptz; c_id := split_part(v_in_c, '|', 3)::uuid;
      end if;
      if v_in_s <> '' then
        s_score := split_part(v_in_s, '|', 1)::numeric; s_ts := split_part(v_in_s, '|', 2)::timestamptz; s_id := split_part(v_in_s, '|', 3)::uuid;
      end if;
    exception when others then raise exception 'Invalid feed cursor'; end;
  end if;

  with
  base as (
    select p.id, p.community_id, p.author_id, p.content, p.photo, p.photos, p.media, p.created_at, p.updated_at,
           p.status, p.comments_enabled, p.sharing_enabled, p.reactions_enabled, p.audience, p.allow_promotion,
      case
        when p.author_id = v_uid then 'own'
        when p.community_id is not null and exists (select 1 from public.community_members m where m.community_id = p.community_id and m.user_id = v_uid) then 'community_member'
        when p.community_id is null and public.are_friends(v_uid, p.author_id) then 'friend'
        when p.community_id is null and exists (select 1 from public.user_follows uf where uf.follower_id = v_uid and uf.followed_id = p.author_id) then 'follow'
        when p.community_id is not null then 'promoted'
        else 'public_popular'
      end as src
    from public.community_posts p
    where p.status = 'active'
      and p.created_at >= now() - make_interval(days => v_win::int)
      and not exists (select 1 from public.post_hides h where h.user_id = v_uid and h.post_id = p.id)
      and public.can_view_post_row(p.community_id, p.author_id, p.audience)
      and not private.users_blocked(v_uid, p.author_id)
      and (p.community_id is null or exists (select 1 from public.communities c where c.id = p.community_id and c.status = 'active'))
  ),
  metrics as (
    select b.*,
      (select count(*) from public.community_post_comments c where c.post_id = b.id)::bigint as comments_count,
      (select count(*) from public.community_post_reactions r where r.post_id = b.id and r.reaction = 'like')::bigint as likes_count,
      (select count(*) from public.community_post_reactions r where r.post_id = b.id and r.reaction = 'dislike')::bigint as dislikes_count
    from base b
  ),
  scored as (
    select m.*, up.username, up.first_name, up.last_name, up.photo_url as global_photo_url,
      case when m.src in ('promoted', 'public_popular') then 's' else 'c' end as stream,
      exists (select 1 from public.user_certifications uc where uc.user_id = m.author_id and uc.status::text = 'active'
              and uc.issued_at <= now() and (uc.expires_at is null or uc.expires_at >= now())) as author_is_certified,
      (
        case when m.author_id = v_uid then 35
             when public.are_friends(v_uid, m.author_id) then 100
             when exists (select 1 from public.user_follows uf where uf.follower_id = v_uid and uf.followed_id = m.author_id) then 70
             else 0 end
        + case when m.src = 'community_member' then 50 else 0 end
        + case when m.src = 'promoted' then least(60, (
              select count(*) from public.community_interests ci
              join public.user_interests ui on ui.interest_id = ci.interest_id and ui.user_id = v_uid
              where ci.community_id = m.community_id) * 15) else 0 end
        + least(40, (select count(*) from public.community_members a join public.community_members b2
                     on b2.community_id = a.community_id and b2.user_id = m.author_id where a.user_id = v_uid) * 10)
        + least(40, (select count(*) from public.user_activity ua where ua.user_id = v_uid and ua.owner_id = m.author_id
                     and ua.created_at >= now() - interval '90 days') * 5)
        + least(40, floor(sqrt((m.likes_count * 2)::numeric + m.comments_count::numeric * 3 + m.dislikes_count::numeric + 1) * 8))
        + greatest(0, floor(35 * exp(-extract(epoch from (now() - m.created_at)) / 172800.0)))
      - case when exists (select 1 from public.post_views pv where pv.viewer_id = v_uid and pv.post_id = m.id) then 80 else 0 end
      )::numeric as feed_score
    from metrics m
    join public.user_profiles up on up.user_id = m.author_id and up.account_status = 'active' and up.deleted_at is null
    where m.src in ('own', 'community_member', 'friend', 'follow')
       or (m.src = 'promoted' and m.allow_promotion
           and coalesce((select cs.allow_post_promotion from public.community_settings cs where cs.community_id = m.community_id), true)
           and m.created_at >= now() - make_interval(days => v_prom_days::int)
           and (m.likes_count + 2 * m.comments_count) >= v_prom_min)
       or (m.src = 'public_popular' and m.audience = 'public'
           and m.created_at >= now() - make_interval(days => v_prom_days::int)
           and (m.likes_count + 2 * m.comments_count) >= v_prom_min)
  ),
  sel as (
    select s.*, row_number() over (partition by s.stream order by s.feed_score desc, s.created_at desc, s.id desc) as rn
    from scored s
    where (s.stream = 'c' and (c_score is null or (s.feed_score, s.created_at, s.id) < (c_score, c_ts, c_id)))
       or (s.stream = 's' and (s_score is null or (s.feed_score, s.created_at, s.id) < (s_score, s_ts, s_id)))
  ),
  sel2 as (select * from sel where rn <= v_limit + 1),
  cnt as (
    select count(*) filter (where stream = 'c')::int as c_avail, count(*) filter (where stream = 's')::int as s_avail from sel2
  ),
  tk as (
    select c_avail, s_avail,
           least(s_avail, greatest(floor(v_limit * v_ratio)::int, v_limit - c_avail))::int as s_take
    from cnt
  ),
  tk2 as (select c_avail, s_avail, s_take, least(c_avail, v_limit - s_take)::int as c_take from tk),
  chosen as (
    select s.*,
      case when s.stream = 'c' then s.rn::numeric else s.rn::numeric * (t.c_take + 1) / (t.s_take + 1) end as ord_key
    from sel2 s cross join tk2 t
    where (s.stream = 'c' and s.rn <= t.c_take) or (s.stream = 's' and s.rn <= t.s_take)
  )
  select
    coalesce(jsonb_agg(jsonb_build_object(
      'type', 'post', 'id', ch.id, 'community_id', ch.community_id, 'author_id', ch.author_id,
      'content', ch.content, 'photo', ch.photo, 'photos', ch.photos,
      'media', case when jsonb_typeof(ch.media) = 'array' and jsonb_array_length(ch.media) > 0 then ch.media
                    else coalesce((select jsonb_agg(jsonb_build_object('type', 'photo', 'url', x) order by ord)
                                   from unnest(coalesce(ch.photos, '{}'::text[])) with ordinality t(x, ord)), '[]'::jsonb) end,
      'created_at', ch.created_at, 'updated_at', ch.updated_at, 'status', ch.status,
      'audience', ch.audience, 'allow_promotion', ch.allow_promotion,
      'comments_enabled', ch.comments_enabled, 'sharing_enabled', ch.sharing_enabled, 'reactions_enabled', ch.reactions_enabled,
      'hashtags', coalesce((select jsonb_agg(jsonb_build_object('id', h.id, 'name', h.name) order by h.name)
                            from public.community_post_hashtags ph join public.hashtags h on h.id = ph.hashtag_id
                            where ph.post_id = ch.id), '[]'::jsonb),
      'mentions', coalesce((select jsonb_agg(jsonb_build_object('user_id', mu.user_id, 'username', mup.username,
                              'first_name', mup.first_name, 'last_name', mup.last_name, 'photo_url', mup.photo_url, 'is_certified', EXISTS (SELECT 1 FROM public.user_certifications uc WHERE uc.user_id = mup.user_id AND uc.status::text = 'active' AND uc.issued_at <= now() AND (uc.expires_at IS NULL OR uc.expires_at >= now()))) order by mu.created_at)
                            from public.community_post_mentions mu join public.user_profiles mup on mup.user_id = mu.user_id
                            where mu.post_id = ch.id), '[]'::jsonb),
      'poll', private.poll_state(ch.id, v_uid),
      'author', jsonb_build_object('user_id', ch.author_id, 'username', ch.username, 'first_name', ch.first_name,
                  'last_name', ch.last_name, 'photo_url', ch.global_photo_url, 'is_certified', ch.author_is_certified, 'pseudo', ch.username),
      'community', case when ch.community_id is null then null else
                    (select jsonb_build_object(
                      'id', c.id, 'name', c.name, 'slug', c.slug,
                      'photo_profile', c.photo_profile, 'visibility', c.visibility,
                      'allow_post_sharing', coalesce((select cs.allow_post_sharing from public.community_settings cs where cs.community_id = c.id), true)
                    ) from public.communities c where c.id = ch.community_id) end,
      'source', ch.src, 'is_suggested', (ch.stream = 's'),
      'comments_count', ch.comments_count, 'likes_count', ch.likes_count, 'dislikes_count', ch.dislikes_count,
      'viewer_reaction', (select r.reaction from public.community_post_reactions r where r.post_id = ch.id and r.user_id = v_uid)
    ) || private.post_extras(ch.id, v_uid) order by ch.ord_key, ch.feed_score desc), '[]'::jsonb),
    (select x.feed_score::text || '|' || x.created_at::text || '|' || x.id::text from chosen x where x.stream = 'c' order by x.rn desc limit 1),
    (select x.feed_score::text || '|' || x.created_at::text || '|' || x.id::text from chosen x where x.stream = 's' order by x.rn desc limit 1),
    (select (t.c_avail > t.c_take or t.s_avail > t.s_take) from tk2 t)
  into v_posts, v_last_c, v_last_s, v_has_more
  from chosen ch;

  v_n := jsonb_array_length(v_posts);

  -- carrousels : un par page (profils / événements en alternance), les deux pour un fil vide
  if v_n = 0 and v_page = 0 then
    v_c1 := private.home_profiles_carousel(); v_c2 := private.home_events_carousel();
    if v_c1 is not null then v_car := v_car || jsonb_build_array(v_c1 || jsonb_build_object('id', 'suggested_profiles_p0')); end if;
    if v_c2 is not null then v_car := v_car || jsonb_build_array(v_c2 || jsonb_build_object('id', 'suggested_events_p0')); end if;
  else
    if v_page % 2 = 0 then
      v_c1 := private.home_profiles_carousel();
      if v_c1 is not null then v_c1 := v_c1 || jsonb_build_object('id', 'suggested_profiles_p' || v_page);
      else v_c1 := private.home_events_carousel();
        if v_c1 is not null then v_c1 := v_c1 || jsonb_build_object('id', 'suggested_events_p' || v_page); end if;
      end if;
    else
      v_c1 := private.home_events_carousel();
      if v_c1 is not null then v_c1 := v_c1 || jsonb_build_object('id', 'suggested_events_p' || v_page);
      else v_c1 := private.home_profiles_carousel();
        if v_c1 is not null then v_c1 := v_c1 || jsonb_build_object('id', 'suggested_profiles_p' || v_page); end if;
      end if;
    end if;
    if v_c1 is not null then v_car := jsonb_build_array(v_c1); end if;
  end if;

  v_pos := least(5, v_n);
  v_out := coalesce((select jsonb_agg(e order by i) from jsonb_array_elements(v_posts) with ordinality t(e, i) where i <= v_pos), '[]'::jsonb)
        || v_car
        || coalesce((select jsonb_agg(e order by i) from jsonb_array_elements(v_posts) with ordinality t(e, i) where i > v_pos), '[]'::jsonb);

  v_has_more := coalesce(v_has_more, false);
  v_next := case when v_has_more
                 then coalesce(v_last_c, v_in_c) || '~' || coalesce(v_last_s, v_in_s) || '~' || (v_page + 1)::text end;
  return jsonb_build_object('items', v_out, 'next_cursor', v_next, 'has_more', v_has_more);
end $function$
;
CREATE OR REPLACE FUNCTION public.get_community_feed(p_community_id uuid, p_limit integer DEFAULT 20, p_cursor text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_user_id uuid:=auth.uid(); v_limit int:=greatest(1,least(coalesce(p_limit,20),50)); v_score numeric; v_created timestamptz; v_id uuid; v_items jsonb; v_next text;
begin
if v_user_id is null then raise exception 'Authentication required'; end if;
if not public.can_view_community(p_community_id) then raise exception 'Community is not accessible'; end if;
if p_cursor is not null and length(trim(p_cursor))>0 then begin v_score:=split_part(p_cursor,'|',1)::numeric; v_created:=split_part(p_cursor,'|',2)::timestamptz; v_id:=split_part(p_cursor,'|',3)::uuid; exception when others then raise exception 'Invalid feed cursor'; end; end if;
with pc as (
select p.*,coalesce((select count(*) from public.community_post_comments c where c.post_id=p.id),0)::bigint comments_count,
coalesce((select count(*) from public.community_post_reactions r where r.post_id=p.id and r.reaction='like'),0)::bigint likes_count,
coalesce((select count(*) from public.community_post_reactions r where r.post_id=p.id and r.reaction='dislike'),0)::bigint dislikes_count,
(select r.reaction from public.community_post_reactions r where r.post_id=p.id and r.user_id=v_user_id) viewer_reaction,
coalesce((select jsonb_agg(jsonb_build_object('id',h.id,'name',h.name) order by h.name) from public.community_post_hashtags ph join public.hashtags h on h.id=ph.hashtag_id where ph.post_id=p.id),'[]'::jsonb) hashtags,
coalesce((select jsonb_agg(jsonb_build_object('user_id',mu.user_id,'username',mup.username,'first_name',mup.first_name,'last_name',mup.last_name,'photo_url',mup.photo_url,'is_certified',exists(select 1 from public.user_certifications uc where uc.user_id=mup.user_id and uc.status::text='active' and uc.issued_at<=now() and (uc.expires_at is null or uc.expires_at>=now()))) order by mu.created_at) from public.community_post_mentions mu join public.user_profiles mup on mup.user_id=mu.user_id where mu.post_id=p.id),'[]'::jsonb) mentions,
private.poll_state(p.id,v_user_id) poll
from public.community_posts p where p.community_id=p_community_id and p.status='active'),
sc as (
select pc.*,up.username,up.first_name,up.last_name,up.photo_url global_photo_url,
exists(select 1 from public.user_certifications uc where uc.user_id=pc.author_id and uc.status::text='active' and uc.issued_at<=now() and (uc.expires_at is null or uc.expires_at>=now())) author_is_certified,
(case when pc.author_id=v_user_id then 35 when public.are_friends(v_user_id,pc.author_id) then 100 when exists(select 1 from public.user_follows uf where uf.follower_id=v_user_id and uf.followed_id=pc.author_id) then 70 else 0 end
+least(40,(select count(*) from public.community_members a join public.community_members b on b.community_id=a.community_id and b.user_id=pc.author_id where a.user_id=v_user_id)*10)
+least(40,(select count(*) from public.user_activity ua where ua.user_id=v_user_id and ua.owner_id=pc.author_id and ua.created_at>=now()-interval '90 days')*5)
+least(40,floor(sqrt((pc.likes_count*2)::numeric+pc.comments_count::numeric*3+pc.dislikes_count::numeric+1)*8))
+greatest(0,floor(35*exp(-extract(epoch from(now()-pc.created_at))/172800.0))))::numeric feed_score
from pc join public.user_profiles up on up.user_id=pc.author_id
where up.account_status = 'active' and up.deleted_at is null),
f as (
select * from sc where v_score is null or feed_score<v_score or(feed_score=v_score and created_at<v_created) or(feed_score=v_score and created_at=v_created and id<v_id)
order by feed_score desc,created_at desc,id desc limit v_limit+1),
pg as(select * from f order by feed_score desc,created_at desc,id desc limit v_limit)
select coalesce(jsonb_agg(jsonb_build_object(
'type','post','id',id,'community_id',community_id,'audience',audience,'allow_promotion',allow_promotion,
'community',(select jsonb_build_object(
'id',cm.id,'name',cm.name,'slug',cm.slug,'photo_profile',cm.photo_profile,'visibility',cm.visibility,
'allow_post_sharing',coalesce((select cs.allow_post_sharing from public.community_settings cs where cs.community_id=cm.id),true)
) from public.communities cm where cm.id=community_id),
'author_id',author_id,'content',content,'photo',photo,'photos',photos,
'media',case when jsonb_typeof(media)='array' and jsonb_array_length(media)>0 then media else
 coalesce((select jsonb_agg(jsonb_build_object('type','photo','url',x) order by ord) from unnest(coalesce(photos,'{}'::text[])) with ordinality t(x,ord)),'[]'::jsonb)
 || case when video_url is null then '[]'::jsonb else jsonb_build_array(jsonb_build_object('type','video','url',video_url,'thumbnail_url',video_thumbnail_url,'duration_ms',video_duration_ms,'size_bytes',video_size_bytes)) end end,
'created_at',created_at,'updated_at',updated_at,'status',status,'comments_enabled',comments_enabled,'sharing_enabled',sharing_enabled,'reactions_enabled',reactions_enabled,
'video',case when video_url is null then null else jsonb_build_object('url',video_url,'thumbnail_url',video_thumbnail_url,'duration_ms',video_duration_ms,'size_bytes',video_size_bytes) end,
'hashtags',hashtags,'mentions',mentions,'poll',poll,
'author',jsonb_build_object('user_id',author_id,'username',username,'first_name',first_name,'last_name',last_name,'photo_url',global_photo_url,'is_certified',author_is_certified,'pseudo',username,'bio',null),
'comments_count',comments_count,'likes_count',likes_count,'dislikes_count',dislikes_count,'viewer_reaction',viewer_reaction) || private.post_extras(id,v_user_id)
order by feed_score desc,created_at desc,id desc),'[]'::jsonb),
case when(select count(*) from f)>v_limit then(select p2.feed_score::text||'|'||p2.created_at::text||'|'||p2.id::text from pg p2 order by p2.feed_score desc,p2.created_at desc,p2.id desc offset v_limit-1 limit 1) end
into v_items,v_next from pg;
return jsonb_build_object('items',v_items,'next_cursor',v_next,'has_more',v_next is not null);
end $function$
;
