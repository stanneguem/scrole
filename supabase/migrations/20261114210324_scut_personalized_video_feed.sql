-- Personalized Scut video recommendations and private watch-depth signals.
create table if not exists public.scut_watch_signals (
  user_id uuid not null references auth.users(id) on delete cascade,
  post_id uuid not null references public.community_posts(id) on delete cascade,
  max_percent numeric(5,2) not null default 0 check (max_percent between 0 and 100),
  total_watch_ms bigint not null default 0 check (total_watch_ms >= 0),
  watch_sessions integer not null default 0 check (watch_sessions >= 0),
  completed_count integer not null default 0 check (completed_count >= 0),
  last_watched_at timestamptz not null default now(),
  primary key (user_id, post_id)
);
create index if not exists scut_watch_signals_user_recent_idx
  on public.scut_watch_signals (user_id, last_watched_at desc);
create index if not exists scut_watch_signals_post_idx
  on public.scut_watch_signals (post_id);
alter table public.scut_watch_signals enable row level security;
revoke all on public.scut_watch_signals from anon, authenticated;

create or replace function public.record_scut_watch(
  p_post_id uuid, p_watched_ms integer, p_duration_ms integer, p_session_id uuid default null
) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_percent numeric(5,2);
  v_completed boolean;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  if p_watched_ms is null or p_duration_ms is null or p_duration_ms <= 0 or p_watched_ms < 0 then
    raise exception 'Invalid watch duration';
  end if;
  if not exists (
    select 1 from public.community_posts p
    where p.id = p_post_id and p.status = 'active' and p.deleted_at is null
      and (
        (p.community_id is null and (
          p.author_id = v_uid or p.audience = 'public'
          or (p.audience = 'friends' and exists (
            select 1 from public.friendships f
            where (f.user_a_id = v_uid and f.user_b_id = p.author_id)
               or (f.user_b_id = v_uid and f.user_a_id = p.author_id)
          ))
          or (p.audience = 'followers' and exists (
            select 1 from public.user_follows uf
            where uf.follower_id = v_uid and uf.followed_id = p.author_id
          ))
        ))
        or (p.community_id is not null and public.can_view_community(p.community_id))
      )
  ) then raise exception 'Video unavailable'; end if;

  v_percent := least(100, round((p_watched_ms::numeric / p_duration_ms::numeric) * 100, 2));
  v_completed := v_percent >= 90;
  insert into public.scut_watch_signals (
    user_id, post_id, max_percent, total_watch_ms, watch_sessions, completed_count, last_watched_at
  ) values (
    v_uid, p_post_id, v_percent, p_watched_ms, 1,
    case when v_completed then 1 else 0 end, now()
  )
  on conflict (user_id, post_id) do update set
    max_percent = greatest(public.scut_watch_signals.max_percent, excluded.max_percent),
    total_watch_ms = least(2147483647::bigint, public.scut_watch_signals.total_watch_ms + excluded.total_watch_ms),
    watch_sessions = least(1000000, public.scut_watch_signals.watch_sessions + 1),
    completed_count = least(1000000, public.scut_watch_signals.completed_count + excluded.completed_count),
    last_watched_at = now();
  return jsonb_build_object('recorded', true, 'percent', v_percent);
end;
$$;
revoke all on function public.record_scut_watch(uuid,integer,integer,uuid) from public, anon;
grant execute on function public.record_scut_watch(uuid,integer,integer,uuid) to authenticated;

create or replace function public.get_scuts_feed(
  p_limit integer default 10, p_exclude_ids uuid[] default '{}'::uuid[]
) returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_limit integer := greatest(1, least(coalesce(p_limit, 10), 30));
  v_items jsonb;
  v_has_more boolean;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;

  with my_interests as materialized (
    select interest_id from public.user_interests where user_id = v_uid
  ),
  my_follows as materialized (
    select followed_id from public.user_follows where follower_id = v_uid
  ),
  my_friends as materialized (
    select case when user_a_id = v_uid then user_b_id else user_a_id end user_id
    from public.friendships where user_a_id = v_uid or user_b_id = v_uid
  ),
  blocked as materialized (
    select case when b.bloqueur_id = v_uid then b.bloque_id else b.bloqueur_id end user_id
    from public.blocage_utilisateur b
    where b.statut and (b.bloqueur_id = v_uid or b.bloque_id = v_uid)
      and (b.bloque_jusquau is null or b.bloque_jusquau > now())
  ),
  video_posts as materialized (
    select p.*
    from public.community_posts p
    join public.user_profiles up on up.user_id = p.author_id
      and up.account_status = 'active' and up.deleted_at is null
    left join public.communities c on c.id = p.community_id
    where p.status = 'active' and p.deleted_at is null
      and p.created_at >= now() - interval '90 days'
      and p.id <> all(coalesce(p_exclude_ids, '{}'::uuid[]))
      and (
        (jsonb_typeof(p.media) = 'array' and exists (
          select 1 from jsonb_array_elements(
            case when jsonb_typeof(p.media) = 'array' then p.media else '[]'::jsonb end
          ) m
          where lower(coalesce(m->>'type','')) in ('video','reel')
            and nullif(m->>'url','') is not null
        ))
        or nullif(p.video_url,'') is not null
        or (jsonb_typeof(p.videos) = 'array' and jsonb_array_length(p.videos) > 0)
      )
      and not exists (select 1 from public.post_hides h where h.user_id = v_uid and h.post_id = p.id)
      and not exists (select 1 from blocked b where b.user_id = p.author_id)
      and (
        (p.community_id is null and (
          p.author_id = v_uid or p.audience = 'public'
          or (p.audience = 'friends' and exists (select 1 from my_friends f where f.user_id = p.author_id))
          or (p.audience = 'followers' and exists (select 1 from my_follows f where f.followed_id = p.author_id))
        ))
        or (p.community_id is not null and c.status = 'active'
          and public.can_view_community(p.community_id))
      )
  ),
  scored as (
    select p.*, up.username, up.first_name, up.last_name, up.photo_url,
      coalesce((select count(*) * 18 from public.user_interests ui
        join my_interests mi on mi.interest_id = ui.interest_id where ui.user_id = p.author_id),0)
      + coalesce((select sum(case when s.max_percent >= 90 then 34
          when s.max_percent >= 50 then 22 when s.max_percent >= 25 then 12 else -8 end)
        from public.scut_watch_signals s where s.user_id = v_uid and s.post_id = p.id),0)
      + case when exists(select 1 from my_follows f where f.followed_id = p.author_id) then 42 else 0 end
      + case when exists(select 1 from my_friends f where f.user_id = p.author_id) then 48 else 0 end
      + coalesce((select least(30, count(*) * 5)
        from public.community_post_hashtags ph
        join public.community_post_hashtags mine on mine.hashtag_id = ph.hashtag_id
        join public.scut_watch_signals ws on ws.post_id = mine.post_id and ws.user_id = v_uid
        where ph.post_id = p.id and ws.max_percent >= 25),0)
      + coalesce((select least(30, count(*) * 5)
        from public.community_post_reactions r where r.post_id = p.id and r.reaction = 'like'),0)
      + greatest(0, 35 - extract(epoch from (now() - p.created_at))/86400.0)
      - coalesce((select least(45, count(*) * 15)
        from public.post_hides h join public.community_posts hp on hp.id = h.post_id
        where h.user_id = v_uid and hp.author_id = p.author_id),0) as score
    from video_posts p join public.user_profiles up on up.user_id = p.author_id
  ),
  ranked as (
    select s.*, row_number() over (order by score desc, created_at desc, id desc) rn
    from scored s
  ),
  selected as (select * from ranked where rn <= v_limit + 1),
  payload as (
    select r.*,
      (select jsonb_agg(jsonb_build_object('id', h.id, 'name', h.name) order by h.name)
        from public.community_post_hashtags ph join public.hashtags h on h.id = ph.hashtag_id
        where ph.post_id = r.id) hashtags,
      (select count(*) from public.community_post_reactions x where x.post_id = r.id and x.reaction = 'like') likes_count,
      (select count(*) from public.community_post_reactions x where x.post_id = r.id and x.reaction = 'dislike') dislikes_count,
      (select count(*) from public.community_post_comments x where x.post_id = r.id) comments_count,
      (select x.reaction from public.community_post_reactions x where x.post_id = r.id and x.user_id = v_uid) viewer_reaction,
      (select jsonb_build_object('id', c.id, 'name', c.name, 'slug', c.slug,
        'photo_profile', c.photo_profile, 'visibility', c.visibility,
        'allow_post_sharing', coalesce(cs.allow_post_sharing,true))
       from public.communities c left join public.community_settings cs on cs.community_id=c.id
       where c.id = r.community_id) community_json
    from selected r
  )
  select
    coalesce((select jsonb_agg(
      jsonb_build_object(
        'type','post','id',p.id,'community_id',p.community_id,'author_id',p.author_id,
        'content',p.content,'photo',p.photo,'photos',p.photos,
        'media',case
          when jsonb_typeof(p.media)='array' and jsonb_array_length(p.media)>0 then p.media
          when nullif(p.video_url,'') is not null then jsonb_build_array(jsonb_build_object(
            'type','video','url',p.video_url,'thumbnail_url',p.video_thumbnail_url))
          else coalesce((select jsonb_agg(case when jsonb_typeof(v)='object' then v
            else jsonb_build_object('type','video','url',v #>> '{}') end)
            from jsonb_array_elements(coalesce(p.videos,'[]'::jsonb)) v),'[]'::jsonb)
        end,
        'created_at',p.created_at,'updated_at',p.updated_at,'status',p.status,
        'audience',p.audience,'comments_enabled',p.comments_enabled,
        'sharing_enabled',p.sharing_enabled,'reactions_enabled',p.reactions_enabled,
        'hashtags',coalesce(p.hashtags,'[]'::jsonb),
        'author',jsonb_build_object('user_id',p.author_id,'username',p.username,
          'first_name',p.first_name,'last_name',p.last_name,'photo_url',p.photo_url,
          'is_certified',exists(select 1 from public.user_certifications uc
            where uc.user_id=p.author_id and uc.status::text='active'
              and uc.issued_at<=now() and (uc.expires_at is null or uc.expires_at>=now()))),
        'community',p.community_json,
        'comments_count',p.comments_count,'likes_count',p.likes_count,
        'dislikes_count',p.dislikes_count,'viewer_reaction',p.viewer_reaction
      ) || private.post_extras(p.id,v_uid) order by p.rn
    ) from payload p where p.rn <= v_limit),'[]'::jsonb),
    exists(select 1 from ranked where rn > v_limit)
  into v_items,v_has_more;
  return jsonb_build_object('items',v_items,'has_more',coalesce(v_has_more,false));
end;
$$;
revoke all on function public.get_scuts_feed(integer,uuid[]) from public, anon;
grant execute on function public.get_scuts_feed(integer,uuid[]) to authenticated;
