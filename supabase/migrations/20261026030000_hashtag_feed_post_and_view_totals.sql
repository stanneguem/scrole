create or replace function public.get_posts_by_hashtag(
  p_hashtag text,
  p_limit integer default 20,
  p_cursor text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_tag text := lower(regexp_replace(btrim(coalesce(p_hashtag, '')), '^#+', '', 'g'));
  v_limit integer := greatest(1, least(coalesce(p_limit, 20), 50));
  v_created timestamptz;
  v_id uuid;
  v_items jsonb := '[]'::jsonb;
  v_next text;
  v_count integer := 0;
  v_total_posts integer := 0;
  v_total_views bigint := 0;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  if v_tag = '' then raise exception 'Hashtag is required'; end if;

  if p_cursor is not null and length(btrim(p_cursor)) > 0 then
    begin
      v_created := split_part(p_cursor, '|', 1)::timestamptz;
      v_id := split_part(p_cursor, '|', 2)::uuid;
    exception when others then
      raise exception 'Invalid hashtag feed cursor';
    end;
  end if;

  with all_matched as (
    select p.id, p.created_at, coalesce(p.views_count, 0)::bigint as views_count
    from public.community_posts p
    join public.community_post_hashtags ph on ph.post_id = p.id
    join public.hashtags h on h.id = ph.hashtag_id
    join public.user_profiles up on up.user_id = p.author_id
    where (h.normalized_name = v_tag or lower(h.name) = v_tag)
      and p.status = 'active' and p.deleted_at is null
      and up.account_status = 'active' and up.deleted_at is null
      and public.can_view_post_row(p.community_id, p.author_id, p.audience)
      and not private.users_blocked(v_uid, p.author_id)
      and not exists (select 1 from public.post_hides hidden where hidden.user_id = v_uid and hidden.post_id = p.id)
      and (p.community_id is null or exists (select 1 from public.communities c where c.id = p.community_id and c.status = 'active'))
  ),
  stats as (
    select count(*)::integer as total_posts, coalesce(sum(views_count), 0)::bigint as total_views
    from all_matched
  ),
  matched as (
    select id, created_at
    from all_matched
    where v_created is null or (created_at, id) < (v_created, v_id)
    order by created_at desc, id desc
    limit v_limit + 1
  ),
  page as (
    select id, created_at from matched order by created_at desc, id desc limit v_limit
  )
  select
    coalesce((select jsonb_agg(
      private.post_item(page.id, v_uid)
      || jsonb_build_object('source', 'hashtag', 'is_suggested', false)
      order by page.created_at desc, page.id desc
    ) from page), '[]'::jsonb),
    case when (select count(*) from matched) > v_limit then (
      select page.created_at::text || '|' || page.id::text
      from page order by page.created_at asc, page.id asc limit 1
    ) end,
    (select count(*)::integer from matched),
    stats.total_posts,
    stats.total_views
  into v_items, v_next, v_count, v_total_posts, v_total_views
  from stats;

  return jsonb_build_object(
    'items', v_items,
    'next_cursor', v_next,
    'has_more', v_count > v_limit,
    'total_posts', v_total_posts,
    'total_views', v_total_views
  );
end
$function$;

revoke all on function public.get_posts_by_hashtag(text, integer, text) from public, anon;
grant execute on function public.get_posts_by_hashtag(text, integer, text) to authenticated;