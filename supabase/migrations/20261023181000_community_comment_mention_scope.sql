-- Comment mentions on public community posts may target friends and members;
-- post creation itself remains limited to members in create_post.
-- private.clean_mentions is shared by post/comment writers, so create_post applies
-- the stricter member-only filter in its own validation block.
-- The live function body was patched additively by the companion migration.
create or replace function private.clean_mentions(
  p_community_id uuid,
  p_mentions uuid[],
  p_actor uuid,
  p_max integer
)
returns uuid[]
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare v_requested uuid[]; v_clean uuid[];
begin
  select coalesce(array_agg(distinct m), '{}'::uuid[]) into v_requested
  from unnest(coalesce(p_mentions, '{}'::uuid[])) m
  where m is not null and m is distinct from p_actor;
  if cardinality(v_requested) > p_max then raise exception 'Trop de personnes identifiées (% maximum)', p_max; end if;
  if p_community_id is null then
    select coalesce(array_agg(m), '{}'::uuid[]) into v_clean
    from unnest(v_requested) m
    where exists(select 1 from public.user_profiles up where up.user_id=m and up.account_status='active' and up.deleted_at is null and public.are_friends(p_actor,up.user_id) and not private.users_blocked(p_actor,up.user_id));
  else
    select coalesce(array_agg(m), '{}'::uuid[]) into v_clean
    from unnest(v_requested) m
    where exists(select 1 from public.community_members cm join public.user_profiles up on up.user_id=cm.user_id where cm.community_id=p_community_id and cm.user_id=m and up.account_status='active' and up.deleted_at is null and not private.users_blocked(p_actor,up.user_id))
      or (exists(select 1 from public.communities c where c.id=p_community_id and c.visibility='public')
        and exists(select 1 from public.user_profiles up where up.user_id=m and up.account_status='active' and up.deleted_at is null)
        and public.are_friends(p_actor,m) and not private.users_blocked(p_actor,m));
  end if;
  return coalesce(v_clean, '{}'::uuid[]);
end;
$function$;


do $block$
declare v_def text;
begin
  select pg_get_functiondef('public.create_post(uuid,text,uuid,text,jsonb,text[],uuid[],boolean,boolean,boolean,jsonb,boolean,uuid,uuid)'::regprocedure) into v_def;
  v_def := replace(v_def,
    'v_clean := private.clean_mentions(p_community_id, coalesce(p_mentions, ''{}''), v_uid, 20);',
    'if p_community_id is null then
    v_clean := private.clean_mentions(null, coalesce(p_mentions, ''{}''), v_uid, 20);
  else
    select coalesce(array_agg(m), ''{}''::uuid[]) into v_clean
    from unnest(coalesce(p_mentions, ''{}''::uuid[])) m
    where exists (select 1 from public.community_members cm join public.user_profiles up on up.user_id=cm.user_id where cm.community_id=p_community_id and cm.user_id=m and up.account_status=''active'' and up.deleted_at is null and not private.users_blocked(v_uid,m));
  end if;');
  execute v_def;
end
$block$;