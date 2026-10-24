-- R2 story keys and global mention expansion for Scrole.
-- Additive/repeatable: no existing rows or objects are deleted.
create or replace function private.expand_global_mentions(
  p_actor uuid,
  p_community_id uuid,
  p_content text,
  p_requested uuid[] default '{}'::uuid[]
)
returns uuid[]
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_result uuid[] := coalesce(p_requested, '{}'::uuid[]);
begin
  if p_actor is null or coalesce(p_content, '') = '' then return v_result; end if;
  if p_community_id is not null
     and p_content ~* '(^|[[:space:][:punct:]])@(all|tous|everyone|everybody|todos|todas|tout|toute|tutti|alle)([[:space:][:punct:]]|$)' then
    select coalesce(array_agg(distinct cm.user_id), '{}'::uuid[]) into v_result
    from public.community_members cm
    join public.user_profiles up on up.user_id = cm.user_id
    where cm.community_id = p_community_id and cm.user_id <> p_actor
      and up.account_status = 'active' and up.deleted_at is null
      and not private.users_blocked(p_actor, cm.user_id);
    return v_result;
  end if;
  if p_community_id is null then
    if p_content ~* '(^|[[:space:][:punct:]])@(ami|amis|friend|friends)([[:space:][:punct:]]|$)' then
      select coalesce(array_agg(distinct x.user_id), '{}'::uuid[]) into v_result
      from (
        select case when f.user_a_id = p_actor then f.user_b_id else f.user_a_id end user_id
        from public.friendships f where f.user_a_id = p_actor or f.user_b_id = p_actor
      ) x join public.user_profiles up on up.user_id = x.user_id
      where x.user_id <> p_actor and up.account_status = 'active' and up.deleted_at is null
        and not private.users_blocked(p_actor, x.user_id);
      return v_result;
    elsif p_content ~* '(^|[[:space:][:punct:]])@(follower|followers|abonne|abonnes|abonné|abonnés|seguidores|seguidor)([[:space:][:punct:]]|$)' then
      select coalesce(array_agg(distinct uf.follower_id), '{}'::uuid[]) into v_result
      from public.user_follows uf join public.user_profiles up on up.user_id = uf.follower_id
      where uf.followed_id = p_actor and uf.follower_id <> p_actor
        and up.account_status = 'active' and up.deleted_at is null
        and not private.users_blocked(p_actor, uf.follower_id);
      return v_result;
    elsif p_content ~* '(^|[[:space:][:punct:]])@(proche|proches|cercle|circle|closefriends|close-friends)([[:space:][:punct:]]|$)' then
      select coalesce(array_agg(distinct x.user_id), '{}'::uuid[]) into v_result
      from (
        select case when f.user_a_id = p_actor then f.user_b_id else f.user_a_id end user_id
        from public.friendships f where f.user_a_id = p_actor or f.user_b_id = p_actor
        union select uf.follower_id from public.user_follows uf where uf.followed_id = p_actor
      ) x join public.user_profiles up on up.user_id = x.user_id
      where x.user_id <> p_actor and up.account_status = 'active' and up.deleted_at is null
        and not private.users_blocked(p_actor, x.user_id);
      return v_result;
    end if;
  end if;
  return v_result;
end;
$function$;

-- Keep the existing create_story signature for compatibility while accepting
-- new private R2 keys. The 8-argument overload sets allow_reshare after insert.
do $block$
declare v_def text; v_old text; v_new text;
begin
  select pg_get_functiondef('public.create_story(uuid,text,text,text,text,text,jsonb)'::regprocedure) into v_def;
  v_old := 'if v_image not like (''%/storage/v1/object/public/community-media/users/'' || v_uid::text || ''/stories/%'')
       or position(''..'' in v_image) > 0 then
      raise exception ''Image invalide'';
    end if;';
  v_new := 'if position(''..'' in v_image) > 0 or position(chr(92) in v_image) > 0 or left(v_image,1) = ''/'' then raise exception ''Image invalide''; end if;
    if v_image like ''%/storage/v1/object/public/community-media/users/'' || v_uid::text || ''/stories/%'' then null;
    elsif v_image like ''stories/'' || v_uid::text || ''/%'' then null;
    else raise exception ''Image invalide''; end if;';
  if position(v_old in v_def) > 0 then execute replace(v_def, v_old, v_new); end if;
end
$block$;
