-- R2 community-post media compatibility and global mention expansion.
-- The live SQL function create_post was updated to accept R2 photo object keys
-- while retaining legacy Supabase Storage URLs for existing queued/offline posts.
-- New community uploads use R2 via r2-media-upload; private community objects
-- use private/communities/{communityId}/posts/... and signed reads.
create or replace function private.expand_global_mentions(
  p_actor uuid,
  p_community_id uuid,
  p_content text,
  p_requested uuid[] default '{}'::uuid[]
)
returns uuid[]
language plpgsql stable security definer set search_path = ''
as $function$
declare v_result uuid[] := coalesce(p_requested, '{}'::uuid[]);
begin
  if p_actor is null or coalesce(p_content, '') = '' then return v_result; end if;
  if p_community_id is not null and p_content ~* '(^|[[:space:][:punct:]])@(all|tous|everyone|everybody|todos|todas|tout|toute|tutti|alle)([[:space:][:punct:]]|$)' then
    select coalesce(array_agg(distinct cm.user_id), '{}'::uuid[]) into v_result
    from public.community_members cm join public.user_profiles up on up.user_id=cm.user_id
    where cm.community_id=p_community_id and cm.user_id<>p_actor
      and up.account_status='active' and up.deleted_at is null
      and not private.users_blocked(p_actor,cm.user_id);
    return v_result;
  end if;
  if p_community_id is null then
    if p_content ~* '(^|[[:space:][:punct:]])@(ami|amis|friend|friends)([[:space:][:punct:]]|$)' then
      select coalesce(array_agg(distinct x.user_id), '{}'::uuid[]) into v_result
      from (select case when f.user_a_id=p_actor then f.user_b_id else f.user_a_id end user_id from public.friendships f where f.user_a_id=p_actor or f.user_b_id=p_actor) x
      join public.user_profiles up on up.user_id=x.user_id
      where x.user_id<>p_actor and up.account_status='active' and up.deleted_at is null and not private.users_blocked(p_actor,x.user_id);
      return v_result;
    elsif p_content ~* '(^|[[:space:][:punct:]])@(follower|followers|abonne|abonnes|abonné|abonnés|seguidores|seguidor)([[:space:][:punct:]]|$)' then
      select coalesce(array_agg(distinct uf.follower_id), '{}'::uuid[]) into v_result
      from public.user_follows uf join public.user_profiles up on up.user_id=uf.follower_id
      where uf.followed_id=p_actor and uf.follower_id<>p_actor and up.account_status='active' and up.deleted_at is null and not private.users_blocked(p_actor,uf.follower_id);
      return v_result;
    elsif p_content ~* '(^|[[:space:][:punct:]])@(proche|proches|cercle|circle|closefriends|close-friends)([[:space:][:punct:]]|$)' then
      select coalesce(array_agg(distinct x.user_id), '{}'::uuid[]) into v_result
      from (
        select case when f.user_a_id=p_actor then f.user_b_id else f.user_a_id end user_id from public.friendships f where f.user_a_id=p_actor or f.user_b_id=p_actor
        union select uf.follower_id from public.user_follows uf where uf.followed_id=p_actor
      ) x join public.user_profiles up on up.user_id=x.user_id
      where x.user_id<>p_actor and up.account_status='active' and up.deleted_at is null and not private.users_blocked(p_actor,x.user_id);
      return v_result;
    end if;
  end if;
  return v_result;
end;
$function$;

-- Installed create_post validation is patched to call this helper, accept
-- R2-hosted photos, restrict community post mentions to that community's members,
-- and permit personal post mentions to friends and followers only.
