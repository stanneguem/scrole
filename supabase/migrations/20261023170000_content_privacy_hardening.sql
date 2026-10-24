-- Scrole content privacy hardening.
-- Additive migration: preserves existing rows and media. Review and apply after
-- confirming private media is served through authenticated/signed URLs; public
-- object URLs cannot be made private retroactively by changing SQL alone.

begin;

alter table public.stories
  add column if not exists allow_reshare boolean not null default false;

-- Stories must be limited to the author's friends/followers (plus the author
-- and platform admins). A stored legacy "public" audience is intentionally not
-- treated as public access by this helper.
create or replace function public.can_view_story_row(p_author uuid, p_audience text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select coalesce(
    (select auth.uid()) is not null
    and (
      p_author = (select auth.uid())
      or coalesce(public.is_admin_or_above(), false)
      or (
        not private.users_blocked((select auth.uid()), p_author)
        and (
          public.are_friends((select auth.uid()), p_author)
          or exists (
            select 1
            from public.user_follows f
            where f.follower_id = (select auth.uid())
              and f.followed_id = p_author
          )
        )
      )
    ),
    false
  );
$function$;

-- Revoke broad execution and expose the predicate only to authenticated callers.
revoke all on function public.can_view_story_row(uuid, text) from public, anon;
grant execute on function public.can_view_story_row(uuid, text) to authenticated;

-- A non-member may not receive mention records from a private community.
-- Public communities remain mentionable by any authenticated user.
create or replace function public.can_receive_community_post_mention(
  p_post_id uuid,
  p_recipient_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select coalesce(
    exists (
      select 1
      from public.community_posts p
      join public.communities c on c.id = p.community_id
      where p.id = p_post_id
        and p.status = 'active'
        and (
          c.visibility = 'public'
          or (
            c.visibility = 'private'
            and exists (
              select 1
              from public.community_members cm
              where cm.community_id = c.id
                and cm.user_id = p_recipient_id
            )
          )
        )
    ),
    false
  );
$function$;

revoke all on function public.can_receive_community_post_mention(uuid, uuid) from public, anon;
grant execute on function public.can_receive_community_post_mention(uuid, uuid) to authenticated;

-- Server-side validation for repost creation. Callers must be the actor, must
-- have access to the source, and source community policy must permit promotion.
create or replace function public.can_repost_community_post(p_post_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select coalesce(
    exists (
      select 1
      from public.community_posts p
      where p.id = p_post_id
        and p.status = 'active'
        and public.can_view_post_row(p.community_id, p.author_id, p.audience)
        and p.sharing_enabled
        and (
          p.community_id is null
          or exists (
            select 1
            from public.communities c
            where c.id = p.community_id
              and (
                c.visibility = 'public'
                or (
                  c.visibility = 'private'
                  and coalesce((
                    select cs.allow_post_promotion
                    from public.community_settings cs
                    where cs.community_id = c.id
                  ), false)
                )
              )
          )
        )
    ),
    false
  );
$function$;

revoke all on function public.can_repost_community_post(uuid) from public, anon;
grant execute on function public.can_repost_community_post(uuid) to authenticated;

-- Harden the direct stories table policy as well as the shared helper. RLS
-- remains the source of truth for direct PostgREST requests.
drop policy if exists stories_select on public.stories;
create policy stories_select
on public.stories
for select
to authenticated
using (
  status = 'active'
  and expires_at > now()
  and public.can_view_story_row(author_id, audience)
);

commit;


-- Replace the existing post writer with the same validation plus the private-community repost gate.
CREATE OR REPLACE FUNCTION public.create_post(p_id uuid, p_content text, p_community_id uuid DEFAULT NULL::uuid, p_audience text DEFAULT 'public'::text, p_media jsonb DEFAULT '[]'::jsonb, p_hashtags text[] DEFAULT '{}'::text[], p_mentions uuid[] DEFAULT '{}'::uuid[], p_comments_enabled boolean DEFAULT true, p_sharing_enabled boolean DEFAULT true, p_reactions_enabled boolean DEFAULT true, p_poll jsonb DEFAULT NULL::jsonb, p_allow_promotion boolean DEFAULT true, p_shared_post_id uuid DEFAULT NULL::uuid, p_shared_comment_id uuid DEFAULT NULL::uuid)
 RETURNS community_posts
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := auth.uid();
  v_row public.community_posts; v_orig public.community_posts; v_shared uuid;
  v_ocomment public.community_post_comments; v_cpost public.community_posts; v_shared_comment uuid; v_is_share boolean;
  v_item jsonb; v_type text; v_url text; v_prefix text; v_audience text;
  v_photos text[] := '{}'; v_clean uuid[] := '{}'; v_spam text[] := '{}'; v_status text := 'active';
  v_perm text; v_approval boolean; v_kind text; v_opts jsonb; v_i int := 0; v_end timestamptz; v_media_count int := 0; v_object_key text; v_duration numeric;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  if p_id is null then raise exception 'L''identifiant de la publication est obligatoire'; end if;

  select * into v_row from public.community_posts where id = p_id;
  if found then
    if v_row.author_id = v_uid then return v_row; end if;
    raise exception 'Identifiant de publication déjà utilisé';
  end if;

  if not exists (select 1 from public.user_profiles up
                 where up.user_id = v_uid and up.account_status = 'active' and up.deleted_at is null) then
    raise exception 'Compte indisponible';
  end if;

  if p_community_id is not null then
    v_audience := 'community';
    if not exists (select 1 from public.communities where id = p_community_id and status = 'active') then
      raise exception 'Communauté introuvable ou indisponible';
    end if;
    if not public.is_community_member(p_community_id) then
      raise exception 'Réservé aux membres de la communauté';
    end if;
    v_prefix := '%/storage/v1/object/public/community-media/communities/' || p_community_id::text || '/posts/%';
  else
    v_audience := lower(btrim(coalesce(p_audience, 'public')));
    if v_audience not in ('public', 'followers', 'friends') then raise exception 'Audience invalide'; end if;
    v_prefix := '%/storage/v1/object/public/community-media/users/' || v_uid::text || '/posts/%';
  end if;

  if p_shared_post_id is not null and p_shared_comment_id is not null then
    raise exception 'Un partage porte soit sur une publication, soit sur un commentaire';
  end if;
  if (p_shared_post_id is not null or p_shared_comment_id is not null)
     and (jsonb_array_length(coalesce(p_media, '[]'::jsonb)) > 0 or p_poll is not null) then
    raise exception 'Un partage ne peut contenir que du texte';
  end if;

  if p_shared_post_id is not null then
    select * into v_orig from public.community_posts where id = p_shared_post_id;
    if not found then raise exception 'Publication indisponible'; end if;
    if v_orig.shared_post_id is not null then
      select * into v_orig from public.community_posts where id = v_orig.shared_post_id;
      if not found then raise exception 'Publication indisponible'; end if;
    end if;
    if v_orig.status <> 'active' or not public.can_view_post_row(v_orig.community_id, v_orig.author_id, v_orig.audience) then
      raise exception 'Publication indisponible';
    end if;
    if private.users_blocked(v_uid, v_orig.author_id) then raise exception 'Action impossible'; end if;
    if not v_orig.sharing_enabled then raise exception 'Le partage est désactivé sur ce post'; end if;
    if v_orig.community_id is not null then
      if not exists (
        select 1 from public.communities c
        where c.id = v_orig.community_id and c.status = 'active'
          and (
            c.visibility = 'public'
            or (c.visibility = 'private' and coalesce((
              select cs.allow_post_promotion from public.community_settings cs
              where cs.community_id = c.id
            ), false))
          )
      ) then
        raise exception 'Le partage de cette communauté est désactivé';
      end if;
    elsif v_orig.audience <> 'public' then
      raise exception 'Ce post ne peut pas être partagé';
    end if;
    if p_community_id is not null and v_orig.community_id = p_community_id then
      raise exception 'Ce post est déjà dans cette communauté';
    end if;
    v_shared := v_orig.id;
  end if;

  if p_shared_comment_id is not null then
    select * into v_ocomment from public.community_post_comments where id = p_shared_comment_id;
    if not found then raise exception 'Commentaire introuvable'; end if;
    select * into v_cpost from public.community_posts where id = v_ocomment.post_id;
    if not found or v_cpost.status <> 'active'
       or not public.can_view_post_row(v_cpost.community_id, v_cpost.author_id, v_cpost.audience) then
      raise exception 'Publication indisponible';
    end if;
    if private.users_blocked(v_uid, v_ocomment.author_id) or private.users_blocked(v_uid, v_cpost.author_id) then
      raise exception 'Action impossible';
    end if;
    if not v_cpost.sharing_enabled then raise exception 'Le partage est désactivé sur ce post'; end if;
    if v_cpost.community_id is not null then
      if not exists (
        select 1 from public.communities c
        where c.id = v_cpost.community_id and c.status = 'active'
          and (
            c.visibility = 'public'
            or (c.visibility = 'private' and coalesce((
              select cs.allow_post_promotion from public.community_settings cs
              where cs.community_id = c.id
            ), false))
          )
      ) then
        raise exception 'Le partage de ce commentaire est désactivé';
      end if;
    elsif v_cpost.audience <> 'public' then
      raise exception 'Ce commentaire ne peut pas être partagé';
    end if;
    if p_community_id is not null and v_cpost.community_id = p_community_id then
      raise exception 'Ce commentaire est déjà dans cette communauté';
    end if;
    v_shared_comment := v_ocomment.id;
  end if;
  v_is_share := v_shared is not null or v_shared_comment is not null;

  if jsonb_typeof(coalesce(p_media, '[]'::jsonb)) <> 'array' then raise exception 'media doit être un tableau'; end if;
  for v_item in select value from jsonb_array_elements(coalesce(p_media, '[]'::jsonb)) loop
    v_media_count := v_media_count + 1;
    if v_media_count > 20 then raise exception 'Une publication peut contenir au maximum 20 médias'; end if;
    v_type := lower(coalesce(v_item->>'type', ''));
    v_url := v_item->>'url';
    if v_type = 'video' then
      if lower(coalesce(v_item->>'storage', '')) <> 'r2' then raise exception 'Vidéo invalide: storage doit être r2'; end if;
      v_object_key := coalesce(v_item->>'object_key', '');
      v_duration := nullif(v_item->>'duration_seconds', '')::numeric;
      if v_duration is null or v_duration <= 0 or v_duration > 30 then raise exception 'Une vidéo doit durer au maximum 30 secondes'; end if;
      if nullif(v_url, '') is null or v_url not like 'https://%' or position('..' in v_url) > 0 then raise exception 'URL de vidéo invalide'; end if;
      if p_community_id is not null then
        if v_object_key not like 'communities/' || p_community_id::text || '/posts/videos/%' then raise exception 'Clé de stockage vidéo invalide'; end if;
      else
        if v_object_key not like 'users/' || v_uid::text || '/posts/videos/%' then raise exception 'Clé de stockage vidéo invalide'; end if;
      end if;
      if v_object_key !~ '\.(mp4|mov)$' then raise exception 'Format vidéo non pris en charge'; end if;
      continue;
    end if;
    if v_type <> 'photo' then raise exception 'Type de média non pris en charge'; end if;
    if lower(coalesce(v_item->>'storage', '')) <> 'supabase' then raise exception 'Photo invalide: storage doit être supabase'; end if;
    if nullif(v_url, '') is null or v_url not like v_prefix or position('..' in v_url) > 0 then raise exception 'Photo invalide'; end if;
    v_photos := array_append(v_photos, v_url);
  end loop;
  if not v_is_share and v_media_count = 0 and nullif(btrim(p_content), '') is null then
    raise exception 'Un post doit contenir du texte ou au moins un média';
  end if;
  if char_length(coalesce(p_content, '')) > 5000 then raise exception 'Le contenu ne peut pas dépasser 5000 caractères'; end if;
  if cardinality(coalesce(p_hashtags, '{}')) > 10 then raise exception 'Maximum 10 hashtags'; end if;
  v_clean := private.clean_mentions(p_community_id, coalesce(p_mentions, '{}'), v_uid, 20);

  if p_community_id is not null then
    select post_permission, posts_require_approval into v_perm, v_approval
    from public.community_settings where community_id = p_community_id;
    v_perm := coalesce(v_perm, 'everyone'); v_approval := coalesce(v_approval, false);
    if v_perm = 'nobody' then raise exception 'Les publications sont désactivées dans cette communauté'; end if;
    if v_perm = 'admins_and_moderators' and not public.is_community_staff(p_community_id) then
      raise exception 'Seuls les administrateurs et modérateurs peuvent publier';
    end if;
    if not v_is_share or nullif(btrim(p_content), '') is not null then
      v_spam := private.detect_post_spam(p_community_id, v_uid, p_content);
    end if;
    if cardinality(v_spam) > 0 then v_status := 'spam_suspect';
    elsif v_approval and not public.is_community_staff(p_community_id) then v_status := 'en_attente'; end if;
  else
    if (select count(*) from public.community_posts p
        where p.author_id = v_uid and p.community_id is null
          and p.created_at > now() - interval '10 minutes') >= 5 then
      raise exception 'Vous publiez trop vite : 5 publications maximum toutes les 10 minutes';
    end if;
  end if;

  if p_poll is not null then
    if jsonb_typeof(p_poll) <> 'object' then raise exception 'Sondage invalide'; end if;
    v_kind := p_poll->>'kind';
    if v_kind is null or v_kind not in ('single', 'multiple', 'quiz', 'this_or_that') then
      raise exception 'Type de sondage invalide';
    end if;
    v_opts := p_poll->'options';
    if jsonb_typeof(v_opts) <> 'array' or jsonb_array_length(v_opts) < 2 or jsonb_array_length(v_opts) > 6 then
      raise exception 'Un sondage doit contenir entre 2 et 6 options';
    end if;
    if nullif(p_poll->>'duration_hours', '') is not null then
      if (p_poll->>'duration_hours')::numeric < 1 or (p_poll->>'duration_hours')::numeric > 168 then
        raise exception 'Durée de sondage invalide';
      end if;
      v_end := now() + ((p_poll->>'duration_hours')::numeric * interval '1 hour');
    end if;
    if v_end is null and v_kind <> 'quiz' then raise exception 'La durée du sondage est obligatoire'; end if;
  end if;

  begin
    insert into public.community_posts (
      id, community_id, author_id, content, photo, photos, videos, media, status,
      comments_enabled, sharing_enabled, reactions_enabled, audience, allow_promotion, shared_post_id, shared_comment_id)
    values (
      p_id, p_community_id, v_uid, nullif(btrim(p_content), ''),
      case when cardinality(v_photos) > 0 then v_photos[1] end, v_photos, '[]'::jsonb,
      coalesce(p_media, '[]'::jsonb), v_status,
      coalesce(p_comments_enabled, true), coalesce(p_sharing_enabled, true), coalesce(p_reactions_enabled, true),
      v_audience, coalesce(p_allow_promotion, true), v_shared, v_shared_comment)
    returning * into v_row;
  exception when unique_violation then
    if v_shared is not null then raise exception 'Vous avez déjà partagé ce post ici'; end if;
    if v_shared_comment is not null then raise exception 'Vous avez déjà partagé ce commentaire ici'; end if;
    raise;
  end;

  if cardinality(coalesce(p_hashtags, '{}')) > 0 then
    insert into public.hashtags (name, normalized_name)
    select trim(x), lower(trim(x)) from unnest(p_hashtags) x where nullif(trim(x), '') is not null
    on conflict (normalized_name) do nothing;
    insert into public.community_post_hashtags (post_id, hashtag_id)
    select p_id, h.id from public.hashtags h
    where h.normalized_name = any (select lower(trim(x)) from unnest(p_hashtags) x where nullif(trim(x), '') is not null)
    on conflict do nothing;
  end if;
  if cardinality(v_clean) > 0 then
    insert into public.community_post_mentions (post_id, user_id)
    select p_id, x from unnest(v_clean) x on conflict do nothing;
  end if;
  if p_poll is not null then
    insert into public.community_polls (post_id, kind, ends_at, explanation)
    values (p_id, v_kind, v_end, nullif(p_poll->>'explanation', ''));
    for v_item in select value from jsonb_array_elements(v_opts) loop
      v_i := v_i + 1;
      insert into public.community_poll_options (post_id, sort_order, label, is_correct)
      values (p_id, v_i, trim(v_item->>'label'), coalesce((v_item->>'is_correct')::boolean, false));
    end loop;
  end if;
  if p_community_id is not null and cardinality(v_spam) > 0 then
    insert into public.community_spam_flags (community_id, post_id, author_id, reasons, score)
    values (p_community_id, p_id, v_uid, v_spam, cardinality(v_spam)) on conflict (post_id) do nothing;
  end if;
  if cardinality(v_clean) > 0 then perform private.notify_post_mentions(p_id); end if;

  if v_shared is not null and v_orig.author_id <> v_uid then
    perform private.notify_community_user(v_orig.author_id, 'post_shared', v_uid,
      jsonb_build_object('post_id', v_orig.id, 'share_id', p_id, 'community_id', v_orig.community_id,
                         'target_community_id', p_community_id, 'actor_id', v_uid),
      'Publication partagée', 'Quelqu''un a partagé votre publication.');
  end if;
  if v_shared_comment is not null and v_ocomment.author_id <> v_uid then
    perform private.notify_community_user(v_ocomment.author_id, 'comment_shared', v_uid,
      jsonb_build_object('comment_id', v_ocomment.id, 'post_id', v_ocomment.post_id, 'share_id', p_id,
                         'target_community_id', p_community_id, 'actor_id', v_uid),
      'Commentaire partagé', 'Quelqu''un a partagé votre commentaire.');
  end if;
  return v_row;
end
$function$
;


-- Backward-compatible overload: persist the author's explicit story reshare choice.
create or replace function public.create_story(
  p_id uuid,
  p_kind text,
  p_content text default null,
  p_image_url text default null,
  p_background text default null,
  p_audience text default 'public',
  p_poll jsonb default null,
  p_allow_reshare boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_result jsonb;
begin
  if v_uid is null then
    raise exception 'Authentication required';
  end if;

  perform public.create_story(
    p_id, p_kind, p_content, p_image_url, p_background, p_audience, p_poll
  );

  update public.stories
     set allow_reshare = coalesce(p_allow_reshare, false)
   where id = p_id
     and author_id = v_uid;

  if not found then
    raise exception 'Story unavailable or not owned by caller';
  end if;

  select to_jsonb(s) into v_result
    from public.stories s
   where s.id = p_id;

  return coalesce(v_result, jsonb_build_object('id', p_id, 'success', true));
end
$function$;

revoke all on function public.create_story(uuid, text, text, text, text, text, jsonb, boolean) from public, anon;
grant execute on function public.create_story(uuid, text, text, text, text, text, jsonb, boolean) to authenticated;
