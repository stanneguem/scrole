-- Story comment reactions (like/dislike) and reaction counters.
-- The table is intentionally not exposed for direct client writes; mutations go through the RPC.

create table if not exists public.story_comment_reactions (
  comment_id uuid not null references public.story_comments(id) on delete cascade,
  user_id uuid not null references public.user_profiles(user_id) on delete cascade,
  reaction text not null check (reaction in ('like', 'dislike')),
  created_at timestamptz not null default now(),
  constraint story_comment_reactions_pkey primary key (comment_id, user_id)
);

create index if not exists story_comment_reactions_comment_reaction_idx
  on public.story_comment_reactions (comment_id, reaction);

alter table public.story_comment_reactions enable row level security;
revoke all on table public.story_comment_reactions from anon, authenticated;

create or replace function public.set_story_comment_reaction(
  p_comment_id uuid,
  p_reaction text
) returns text
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_comment public.story_comments;
  v_story public.stories;
  v_reaction text := lower(nullif(btrim(coalesce(p_reaction, '')), ''));
begin
  if v_uid is null then
    raise exception 'Authentication required';
  end if;

  if v_reaction is not null and v_reaction not in ('like', 'dislike', 'none') then
    raise exception 'Réaction invalide';
  end if;

  select * into v_comment
  from public.story_comments c
  where c.id = p_comment_id;

  if not found then
    raise exception 'Commentaire introuvable';
  end if;

  select * into v_story
  from public.stories s
  where s.id = v_comment.story_id
    and s.status = 'active'
    and s.expires_at > now();

  if not found or not public.can_view_story_row(v_story.author_id, v_story.audience) then
    raise exception 'Story introuvable ou non accessible';
  end if;

  if private.users_blocked(v_uid, v_story.author_id)
     or private.users_blocked(v_uid, v_comment.author_id) then
    raise exception 'Action impossible';
  end if;

  if v_reaction is null or v_reaction = 'none' then
    delete from public.story_comment_reactions
    where comment_id = p_comment_id and user_id = v_uid;
    return null;
  end if;

  insert into public.story_comment_reactions (comment_id, user_id, reaction)
  values (p_comment_id, v_uid, v_reaction)
  on conflict (comment_id, user_id)
  do update set reaction = excluded.reaction, created_at = now();

  if v_reaction = 'like'
     and v_comment.author_id <> v_uid
     and not exists (
       select 1 from public.notifications n
       where n.user_id = v_comment.author_id
         and n.type = 'story_comment_like'
         and n.actor_id = v_uid
         and n.data ->> 'comment_id' = p_comment_id::text
     ) then
    perform private.notify_community_user(
      v_comment.author_id,
      'story_comment_like',
      v_uid,
      jsonb_build_object(
        'story_id', v_comment.story_id,
        'comment_id', p_comment_id,
        'actor_id', v_uid
      ),
      'Nouveau like sur votre commentaire',
      'Quelqu’un a aimé votre commentaire sur une story.'
    );
  end if;

  return v_reaction;
end
$function$;

revoke all on function public.set_story_comment_reaction(uuid, text) from public, anon;
grant execute on function public.set_story_comment_reaction(uuid, text) to authenticated;

create or replace function public.get_story_comments(
  p_story_id uuid,
  p_limit integer default 30,
  p_offset integer default 0
) returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_story public.stories;
  v_limit integer := greatest(1, least(coalesce(p_limit, 30), 50));
  v_offset integer := greatest(0, coalesce(p_offset, 0));
  v_total integer;
  v_items jsonb;
begin
  if v_uid is null then
    raise exception 'Authentication required';
  end if;

  select * into v_story
  from public.stories s
  where s.id = p_story_id
    and s.status = 'active'
    and s.expires_at > now();

  if not found or not public.can_view_story_row(v_story.author_id, v_story.audience) then
    raise exception 'Story introuvable ou non accessible';
  end if;

  select count(*)::integer into v_total
  from public.story_comments c
  join public.user_profiles up on up.user_id = c.author_id
  where c.story_id = p_story_id
    and c.parent_comment_id is null
    and up.account_status = 'active'
    and up.deleted_at is null;

  select coalesce(jsonb_agg(item order by created_at, id), '[]'::jsonb)
  into v_items
  from (
    select c.created_at, c.id,
      jsonb_build_object(
        'id', c.id,
        'story_id', c.story_id,
        'author_id', c.author_id,
        'content', c.content,
        'created_at', c.created_at,
        'updated_at', c.updated_at,
        'likes_count', (
          select count(*)::integer from public.story_comment_reactions scr
          where scr.comment_id = c.id and scr.reaction = 'like'
        ),
        'dislikes_count', (
          select count(*)::integer from public.story_comment_reactions scr
          where scr.comment_id = c.id and scr.reaction = 'dislike'
        ),
        'user_reaction', (
          select scr.reaction from public.story_comment_reactions scr
          where scr.comment_id = c.id and scr.user_id = v_uid
          limit 1
        ),
        'author', jsonb_build_object(
          'user_id', up.user_id,
          'username', up.username,
          'first_name', up.first_name,
          'last_name', up.last_name,
          'photo_url', up.photo_url,
          'is_certified', exists (
            select 1
            from public.user_certifications uc
            where uc.user_id = up.user_id
              and uc.status::text = 'active'
              and uc.issued_at <= now()
              and (uc.expires_at is null or uc.expires_at >= now())
          )
        ),
        'replies', coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', r.id,
            'story_id', r.story_id,
            'author_id', r.author_id,
            'parent_comment_id', r.parent_comment_id,
            'content', r.content,
            'created_at', r.created_at,
            'updated_at', r.updated_at,
            'likes_count', (
              select count(*)::integer from public.story_comment_reactions rsr
              where rsr.comment_id = r.id and rsr.reaction = 'like'
            ),
            'dislikes_count', (
              select count(*)::integer from public.story_comment_reactions rsr
              where rsr.comment_id = r.id and rsr.reaction = 'dislike'
            ),
            'user_reaction', (
              select rsr.reaction from public.story_comment_reactions rsr
              where rsr.comment_id = r.id and rsr.user_id = v_uid
              limit 1
            ),
            'author', jsonb_build_object(
              'user_id', rup.user_id,
              'username', rup.username,
              'first_name', rup.first_name,
              'last_name', rup.last_name,
              'photo_url', rup.photo_url,
              'is_certified', exists (
                select 1
                from public.user_certifications ruc
                where ruc.user_id = rup.user_id
                  and ruc.status::text = 'active'
                  and ruc.issued_at <= now()
                  and (ruc.expires_at is null or ruc.expires_at >= now())
              )
            )
          ) order by r.created_at, r.id)
          from public.story_comments r
          join public.user_profiles rup on rup.user_id = r.author_id
          where r.parent_comment_id = c.id
            and r.story_id = p_story_id
            and rup.account_status = 'active'
            and rup.deleted_at is null
        ), '[]'::jsonb)
      ) as item
    from public.story_comments c
    join public.user_profiles up on up.user_id = c.author_id
    where c.story_id = p_story_id
      and c.parent_comment_id is null
      and up.account_status = 'active'
      and up.deleted_at is null
    order by c.created_at, c.id
    limit v_limit offset v_offset
  ) page;

  return jsonb_build_object(
    'story_id', p_story_id,
    'items', v_items,
    'total', v_total,
    'limit', v_limit,
    'offset', v_offset,
    'has_more', v_total > v_offset + v_limit
  );
end
$function$;

revoke all on function public.get_story_comments(uuid, integer, integer) from public, anon;
grant execute on function public.get_story_comments(uuid, integer, integer) to authenticated;
