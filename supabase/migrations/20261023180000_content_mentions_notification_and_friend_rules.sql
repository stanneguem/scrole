begin;

-- Personal-feed post mentions are limited to mutual friends. Community post
-- mentions are limited to active members of that community.
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
declare
  v_requested uuid[];
  v_clean uuid[];
begin
  select coalesce(array_agg(distinct m), '{}'::uuid[])
    into v_requested
  from unnest(coalesce(p_mentions, '{}'::uuid[])) as m
  where m is not null and m is distinct from p_actor;

  if cardinality(v_requested) > p_max then
    raise exception 'Trop de personnes identifiées (% maximum)', p_max;
  end if;

  if p_community_id is null then
    select coalesce(array_agg(m), '{}'::uuid[])
      into v_clean
    from unnest(v_requested) as m
    where exists (
      select 1
      from public.user_profiles up
      where up.user_id = m
        and up.account_status = 'active'
        and up.deleted_at is null
        and public.are_friends(p_actor, up.user_id)
        and not private.users_blocked(p_actor, up.user_id)
    );
  else
    select coalesce(array_agg(m), '{}'::uuid[])
      into v_clean
    from unnest(v_requested) as m
    join public.community_members cm
      on cm.user_id = m and cm.community_id = p_community_id
    join public.user_profiles up on up.user_id = cm.user_id
    where up.account_status = 'active'
      and up.deleted_at is null
      and not private.users_blocked(p_actor, up.user_id);
  end if;

  return coalesce(v_clean, '{}'::uuid[]);
end;
$function$;

-- Persisted @mentions create notifications, but private-community recipients
-- must still be members at the moment the notification is generated.
create or replace function public.notify_user_for_content_mention()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid;
  v_post_id uuid;
  v_community_id uuid;
  v_post_status text;
  v_title text := 'Vous avez été mentionné';
  v_body text;
  v_data jsonb;
begin
  if tg_table_name = 'community_post_mentions' then
    select p.id, p.author_id, p.community_id, p.status
      into v_post_id, v_actor, v_community_id, v_post_status
    from public.community_posts p
    where p.id = new.post_id;
    if not found or v_post_status <> 'active' then return new; end if;
    if v_community_id is not null and not exists (
      select 1 from public.community_members cm
      where cm.community_id = v_community_id and cm.user_id = new.user_id
    ) then return new; end if;
    if v_community_id is null and not public.are_friends(v_actor, new.user_id) then return new; end if;
    v_body := 'Vous avez été mentionné dans une publication.';
    v_data := jsonb_build_object('post_id', v_post_id, 'source_type', 'post', 'source_id', v_post_id, 'actor_id', v_actor);
    if v_community_id is not null then v_data := v_data || jsonb_build_object('community_id', v_community_id); end if;
    insert into public.notifications(user_id, type, title, body, actor_id, data)
    values(new.user_id, 'community_post_mention', v_title, v_body, v_actor, v_data);
  elsif tg_table_name = 'community_comment_mentions' then
    select c.author_id, c.post_id, p.community_id, p.status
      into v_actor, v_post_id, v_community_id, v_post_status
    from public.community_post_comments c
    join public.community_posts p on p.id = c.post_id
    where c.id = new.comment_id;
    if not found or v_post_status <> 'active' then return new; end if;
    if v_community_id is not null and not exists (
      select 1 from public.community_members cm
      where cm.community_id = v_community_id and cm.user_id = new.user_id
    ) then return new; end if;
    if v_community_id is null and not public.are_friends(v_actor, new.user_id) then return new; end if;
    v_body := 'Vous avez été mentionné dans un commentaire.';
    v_data := jsonb_build_object('post_id', v_post_id, 'comment_id', new.comment_id, 'source_type', 'comment', 'source_id', new.comment_id, 'actor_id', v_actor);
    if v_community_id is not null then v_data := v_data || jsonb_build_object('community_id', v_community_id); end if;
    insert into public.notifications(user_id, type, title, body, actor_id, data)
    values(new.user_id, 'community_comment_mention', v_title, v_body, v_actor, v_data);
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_notify_user_for_post_mention on public.community_post_mentions;
create trigger trg_notify_user_for_post_mention
after insert on public.community_post_mentions
for each row execute function public.notify_user_for_content_mention();

drop trigger if exists trg_notify_user_for_comment_mention on public.community_comment_mentions;
create trigger trg_notify_user_for_comment_mention
after insert on public.community_comment_mentions
for each row execute function public.notify_user_for_content_mention();

revoke all on function public.notify_user_for_content_mention() from public, anon, authenticated;

commit;
