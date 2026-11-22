-- Report both 24-hour hashtag activity and lifetime visible-post totals.
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
      count(distinct p.id) filter (where p.created_at >= now() - interval '24 hours')::integer as posts_24h,
      count(distinct p.id)::integer as posts_total
    from public.hashtags h
    join public.community_post_hashtags ph on ph.hashtag_id = h.id
    join public.community_posts p on p.id = ph.post_id
    join public.user_profiles up on up.user_id = p.author_id
    where p.status = 'active' and p.deleted_at is null
      and up.account_status = 'active' and up.deleted_at is null
      and public.can_view_post_row(p.community_id, p.author_id, p.audience)
      and not private.users_blocked(v_uid, p.author_id)
      and not exists (select 1 from public.post_hides hidden where hidden.user_id = v_uid and hidden.post_id = p.id)
      and (p.community_id is null or exists (select 1 from public.communities c where c.id = p.community_id and c.status = 'active'))
    group by h.id, h.name, h.normalized_name
  ),
  ranked as (
    select *, (posts_30m * 3 + posts_24h)::integer as trend_score
    from tag_counts
    where posts_24h > 0
    order by trend_score desc, posts_30m desc, posts_24h desc, normalized_name asc
    limit v_limit
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id, 'name', name, 'normalized_name', normalized_name,
    'posts_30m', posts_30m, 'posts_24h', posts_24h,
    'posts_total', posts_total, 'trend_score', trend_score
  ) order by trend_score desc, posts_30m desc, posts_24h desc, normalized_name asc), '[]'::jsonb)
  into v_result from ranked;

  return v_result;
end
$function$;

revoke all on function public.get_trending_hashtags(integer) from public, anon;
grant execute on function public.get_trending_hashtags(integer) to authenticated;