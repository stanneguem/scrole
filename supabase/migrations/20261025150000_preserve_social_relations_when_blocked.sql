-- Keep stored social relations visible even when either user has blocked the other.
-- Blocking still restricts interactions; it must not alter friendship/follow counts or lists.

CREATE OR REPLACE FUNCTION public.get_follow_stats(p_user_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_me uuid := auth.uid();
  v_t uuid;
  v_followers_count integer;
  v_following_count integer;
  v_friends_count integer;
BEGIN
  IF v_me IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  v_t := coalesce(p_user_id, v_me);

  SELECT count(*)::integer
  INTO v_followers_count
  FROM public.user_follows f
  JOIN public.user_profiles up
    ON up.user_id = f.follower_id
   AND up.account_status = 'active'
   AND up.deleted_at IS NULL
  WHERE f.followed_id = v_t;

  SELECT count(*)::integer
  INTO v_following_count
  FROM public.user_follows f
  JOIN public.user_profiles up
    ON up.user_id = f.followed_id
   AND up.account_status = 'active'
   AND up.deleted_at IS NULL
  WHERE f.follower_id = v_t;

  SELECT count(*)::integer
  INTO v_friends_count
  FROM public.friendships fr
  JOIN public.user_profiles up
    ON up.user_id = CASE
      WHEN fr.user_a_id = v_t THEN fr.user_b_id
      ELSE fr.user_a_id
    END
   AND up.account_status = 'active'
   AND up.deleted_at IS NULL
  WHERE (fr.user_a_id = v_t OR fr.user_b_id = v_t);

  RETURN jsonb_build_object(
    'user_id', v_t,
    'followers_count', v_followers_count,
    'following_count', v_following_count,
    'friends_count', v_friends_count
  );
END
$function$;

CREATE OR REPLACE FUNCTION private.follow_list(p_kind text, p_user_id uuid, p_limit integer, p_offset integer, p_query text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_me uuid := auth.uid(); v_t uuid := coalesce(p_user_id, auth.uid());
  v_limit int := greatest(1, least(coalesce(p_limit, 30), 100)); v_offset int := greatest(0, coalesce(p_offset, 0));
  v_q text := nullif(btrim(p_query), ''); v_items jsonb; v_total int;
begin
  if v_me is null then raise exception 'Authentication required'; end if;
  if v_t <> v_me then
    if private.is_private_profile(v_t) and not coalesce(public.is_admin_or_above(), false)
       and not exists (select 1 from public.user_follows f where f.follower_id = v_me and f.followed_id = v_t) then
      raise exception 'Cette liste est réservée aux abonnés de ce profil';
    end if;
  end if;

  with rows as (
    select f.follower_id as other_id, f.created_at as at from public.user_follows f where p_kind = 'followers' and f.followed_id = v_t
    union all
    select f.followed_id, f.created_at from public.user_follows f where p_kind = 'following' and f.follower_id = v_t
    union all
    select case when fr.user_a_id = v_t then fr.user_b_id else fr.user_a_id end, fr.created_at
    from public.friendships fr where p_kind = 'friends' and (fr.user_a_id = v_t or fr.user_b_id = v_t)
  ), filtered as (
    select r.other_id, r.at, up.bio from rows r
    join public.user_profiles up on up.user_id = r.other_id and up.account_status = 'active' and up.deleted_at is null
    where (v_q is null or up.username ilike '%' || v_q || '%' or concat_ws(' ', up.first_name, up.last_name) ilike '%' || v_q || '%')
  ), page as (
    select * from filtered order by at desc, other_id limit v_limit offset v_offset
  )
  select coalesce(jsonb_agg(private.user_badge(p.other_id) || jsonb_build_object(
           'bio', p.bio, 'followed_at', p.at,
           'i_follow', exists (select 1 from public.user_follows x where x.follower_id = v_me and x.followed_id = p.other_id),
           'follows_me', exists (select 1 from public.user_follows x where x.follower_id = p.other_id and x.followed_id = v_me),
           'is_friend', public.are_friends(v_me, p.other_id),
           'request_sent', exists (select 1 from public.follow_requests r where r.requester_id = v_me and r.target_id = p.other_id and r.status = 'pending'))
         order by p.at desc, p.other_id), '[]'::jsonb),
         (select count(*) from filtered)
  into v_items, v_total from page p;
  return jsonb_build_object('items', v_items, 'total', v_total, 'has_more', v_total > v_offset + v_limit);
end
$function$;
