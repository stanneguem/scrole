-- Make hashtag indexing reliable even when a client omits p_hashtags.
-- Additive by design: explicitly attached hashtag links are never removed.
create or replace function public.index_content_hashtags()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_tag text;
  v_normalized text;
begin
  if new.content is null or new.content = '' then
    return new;
  end if;

  for v_tag in
    select picked.tag
    from (
      select distinct on (lower(m.parts[1]))
        m.parts[1] as tag
      from regexp_matches(new.content, '#([[:alnum:]_]{1,64})', 'g') as m(parts)
      where nullif(m.parts[1], '') is not null
      order by lower(m.parts[1]), m.parts[1]
    ) as picked
    order by lower(picked.tag)
    limit 10
  loop
    v_normalized := lower(btrim(v_tag));
    if v_normalized = '' then continue; end if;

    insert into public.hashtags (name, normalized_name)
    values (btrim(v_tag), v_normalized)
    on conflict (normalized_name) do nothing;

    insert into public.community_post_hashtags (post_id, hashtag_id)
    select new.id, h.id
    from public.hashtags h
    where h.normalized_name = v_normalized
    on conflict (post_id, hashtag_id) do nothing;
  end loop;

  return new;
end
$function$;

revoke all on function public.index_content_hashtags() from public, anon, authenticated;
drop trigger if exists trg_index_content_hashtags on public.community_posts;
create trigger trg_index_content_hashtags
after insert or update of content on public.community_posts
for each row execute function public.index_content_hashtags();

-- Backfill posts already containing hashtags; preserve existing manually attached tags.
do $backfill$
declare
  r record;
  v_tag text;
  v_normalized text;
begin
  for r in
    select p.id, p.content from public.community_posts p
    where p.content is not null and p.content ~ '#[[:alnum:]_]{1,64}'
  loop
    for v_tag in
      select picked.tag
      from (
        select distinct on (lower(m.parts[1])) m.parts[1] as tag
        from regexp_matches(r.content, '#([[:alnum:]_]{1,64})', 'g') as m(parts)
        where nullif(m.parts[1], '') is not null
        order by lower(m.parts[1]), m.parts[1]
      ) as picked
      order by lower(picked.tag)
      limit 10
    loop
      v_normalized := lower(btrim(v_tag));
      insert into public.hashtags (name, normalized_name)
      values (btrim(v_tag), v_normalized)
      on conflict (normalized_name) do nothing;

      insert into public.community_post_hashtags (post_id, hashtag_id)
      select r.id, h.id from public.hashtags h
      where h.normalized_name = v_normalized
      on conflict (post_id, hashtag_id) do nothing;
    end loop;
  end loop;
end
$backfill$;

-- Trend score blends the recent 30-minute velocity with 24-hour volume.
create or replace function public.get_trending_hashtags(p_limit integer default 20)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_limit integer := greatest(1, least(coalesce(p_limit, 20), 50));
  v_result jsonb;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;

  with tag_counts as (
    select h.id, h.name, h.normalized_name,
      count(distinct p.id) filter (where p.created_at >= now() - interval '30 minutes')::integer as posts_30m,
      count(distinct p.id)::integer as posts_24h
    from public.hashtags h
    join public.community_post_hashtags ph on ph.hashtag_id = h.id
    join public.community_posts p on p.id = ph.post_id
    join public.user_profiles up on up.user_id = p.author_id
    where p.created_at >= now() - interval '24 hours'
      and p.status = 'active' and p.deleted_at is null
      and up.account_status = 'active' and up.deleted_at is null
      and public.can_view_post_row(p.community_id, p.author_id, p.audience)
      and not private.users_blocked(v_uid, p.author_id)
      and not exists (select 1 from public.post_hides hidden where hidden.user_id = v_uid and hidden.post_id = p.id)
      and (p.community_id is null or exists (select 1 from public.communities c where c.id = p.community_id and c.status = 'active'))
    group by h.id, h.name, h.normalized_name
  ),
  ranked as (
    select *, (posts_30m * 3 + posts_24h)::integer as trend_score
    from tag_counts where posts_24h > 0
    order by trend_score desc, posts_30m desc, posts_24h desc, normalized_name asc
    limit v_limit
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id, 'name', name, 'normalized_name', normalized_name,
    'posts_30m', posts_30m, 'posts_24h', posts_24h, 'trend_score', trend_score
  ) order by trend_score desc, posts_30m desc, posts_24h desc, normalized_name asc), '[]'::jsonb)
  into v_result from ranked;

  return v_result;
end
$function$;

revoke all on function public.get_trending_hashtags(integer) from public, anon;
grant execute on function public.get_trending_hashtags(integer) to authenticated;
