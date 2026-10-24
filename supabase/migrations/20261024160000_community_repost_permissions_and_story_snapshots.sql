-- Community-level repost permission and safe story snapshots.
ALTER TABLE public.community_settings
  ADD COLUMN IF NOT EXISTS allow_post_sharing boolean NOT NULL DEFAULT true;

ALTER TABLE public.stories
  ADD COLUMN IF NOT EXISTS shared_post_snapshot jsonb;

ALTER TABLE public.community_posts
  ADD COLUMN IF NOT EXISTS shared_post_snapshot jsonb;

CREATE OR REPLACE FUNCTION private.story_post_snapshot(p_post_id uuid, p_viewer uuid, p_depth integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_p public.community_posts;
  v_item jsonb;
  v_nested jsonb;
begin
  if p_depth > 8 then
    return jsonb_build_object('id', p_post_id, 'available', false, 'can_open_original', false);
  end if;
  select * into v_p from public.community_posts where id = p_post_id;
  if not found or v_p.status <> 'active'
     or not public.can_view_post_row(v_p.community_id, v_p.author_id, v_p.audience)
     or private.users_blocked(p_viewer, v_p.author_id) then
    return jsonb_build_object('id', p_post_id, 'available', false, 'can_open_original', false);
  end if;
  v_item := private.post_item(p_post_id, p_viewer);
  if v_p.shared_post_id is not null then
    if exists (
      select 1 from public.community_posts source
      where source.id = v_p.shared_post_id
        and source.community_id is not null
        and not (coalesce(public.is_admin_or_above(), false) or public.is_community_member(source.community_id))
    ) then
      v_nested := coalesce(
        v_p.shared_post_snapshot,
        jsonb_build_object('id', v_p.shared_post_id, 'available', false, 'can_open_original', false)
      );
    else
      v_nested := private.story_post_snapshot(v_p.shared_post_id, p_viewer, p_depth + 1);
    end if;
    v_item := jsonb_set(v_item, '{shared_post}', v_nested, true);
  end if;
  -- Snapshot de contenu et d'attribution uniquement : pas de communauté,
  -- réactions/commentaires source ni de navigation vers la publication.
  v_item := v_item - array[
    'community_id','community','likes_count','dislikes_count','comments_count',
    'viewer_reaction','views_count','viewers_count','shares_count',
    'viewer_has_shared','shared_comment_id','shared_comment','poll'
  ];
  v_item := v_item || jsonb_build_object(
    'author_id', null,
    'author', coalesce(v_item -> 'author', '{}'::jsonb) - 'user_id' - 'id',
    'available', true,
    'can_open_original', false,
    'shared_post_can_open_original', false,
    'likes_count', 0,
    'dislikes_count', 0,
    'comments_count', 0,
    'shares_count', 0,
    'views_count', 0,
    'viewer_reaction', null
  );
  return v_item;
end
$function$;

REVOKE ALL ON FUNCTION private.story_post_snapshot(uuid, uuid, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.story_post_snapshot(uuid, uuid, integer) TO authenticated;

CREATE OR REPLACE FUNCTION private.story_can_open_original(p_post_id uuid, p_viewer uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_p public.community_posts;
begin
  select * into v_p from public.community_posts where id = p_post_id;
  if not found or v_p.status <> 'active'
     or private.users_blocked(p_viewer, v_p.author_id)
     or not public.can_view_post_row(v_p.community_id, v_p.author_id, v_p.audience) then
    return false;
  end if;
  if v_p.community_id is not null
     and not (coalesce(public.is_admin_or_above(), false) or public.is_community_member(v_p.community_id)) then
    return false;
  end if;
  return true;
end
$function$;

REVOKE ALL ON FUNCTION private.story_can_open_original(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.story_can_open_original(uuid, uuid) TO authenticated;


CREATE OR REPLACE FUNCTION public.get_community_management_settings(p_community_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_community public.communities; v_access public.community_access_rules; v_settings public.community_settings;
begin
  if (select auth.uid()) is null then raise exception 'Utilisateur non authentifié'; end if;
  if not public.is_community_admin(p_community_id) then raise exception 'Action réservée aux administrateurs de la communauté'; end if;
  select * into v_community from public.communities c where c.id = p_community_id and c.status = 'active';
  if not found then raise exception 'Communauté introuvable'; end if;
  select * into v_access from public.community_access_rules r where r.community_id = p_community_id;
  select * into v_settings from public.community_settings s where s.community_id = p_community_id;
  return jsonb_build_object(
    'community', jsonb_build_object('id',v_community.id,'name',v_community.name,'slug',v_community.slug,'description',v_community.description,'slogan',v_community.slogan,'photo_profile',v_community.photo_profile,'photo_cover',v_community.photo_cover,'visibility',v_community.visibility,'require_manual_approval',v_community.require_manual_approval),
    'access_rules', jsonb_build_object('countries_enabled',coalesce(v_access.countries_enabled,false),'allowed_countries',coalesce(to_jsonb(v_access.allowed_countries),'[]'::jsonb),'cities_enabled',coalesce(v_access.cities_enabled,false),'allowed_cities',coalesce(to_jsonb(v_access.allowed_cities),'[]'::jsonb),'certification_required',coalesce(v_access.certification_required,false),'gender_restriction',v_access.gender_restriction,'age_min',v_access.age_min,'age_max',v_access.age_max),
    'settings', jsonb_build_object('members_list_visible',coalesce(v_settings.members_list_visible,true),'posts_require_approval',coalesce(v_settings.posts_require_approval,false),'post_permission',coalesce(v_settings.post_permission,'everyone'),'allow_reports',coalesce(v_settings.allow_reports,true),'allow_comments',coalesce(v_settings.allow_comments,true),'allow_reactions',coalesce(v_settings.allow_reactions,true),'allow_post_promotion',coalesce(v_settings.allow_post_promotion,true),'allow_post_sharing',coalesce(v_settings.allow_post_sharing,true))
  );
end; $function$;


CREATE OR REPLACE FUNCTION private.community_chain_sharing_allowed(p_post_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_current uuid := p_post_id;
  v_post public.community_posts;
  v_depth integer := 0;
begin
  while v_current is not null loop
    v_depth := v_depth + 1;
    if v_depth > 8 then return false; end if;
    select * into v_post from public.community_posts where id = v_current;
    if not found or v_post.status <> 'active' or not coalesce(v_post.sharing_enabled, false) then
      return false;
    end if;
    if v_post.community_id is not null then
      if not exists (
        select 1 from public.communities community
        where community.id = v_post.community_id
          and community.status = 'active'
          and (community.visibility = 'public' or public.is_community_member(community.id))
      ) then
        return false;
      end if;
      if exists (
        select 1 from public.community_settings cs
        where cs.community_id = v_post.community_id
          and not coalesce(cs.allow_post_sharing, true)
      ) then
        return false;
      end if;
    end if;
    v_current := v_post.shared_post_id;
  end loop;
  return true;
end
$function$;

REVOKE ALL ON FUNCTION private.community_chain_sharing_allowed(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.community_chain_sharing_allowed(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION private.post_extras(p_post_id uuid, p_viewer uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_shared uuid;
  v_scomment uuid;
  v_snapshot jsonb;
  v_card jsonb := null;
  v_ccard jsonb := null;
  v_orig public.community_posts;
begin
  select shared_post_id, shared_comment_id, shared_post_snapshot
    into v_shared, v_scomment, v_snapshot
  from public.community_posts where id = p_post_id;

  if v_shared is not null then
    select * into v_orig from public.community_posts where id = v_shared;
    if found and v_orig.status = 'active'
       and private.story_can_open_original(v_shared, p_viewer) then
      v_card := private.post_item(v_shared, p_viewer) || jsonb_build_object('available', true, 'can_open_original', true);
    elsif v_snapshot is not null then
      v_card := v_snapshot || jsonb_build_object('available', true, 'can_open_original', false);
    else
      v_card := jsonb_build_object('id', v_shared, 'available', false, 'can_open_original', false);
    end if;
  end if;

  if v_scomment is not null then
    v_ccard := private.comment_card(v_scomment, p_viewer);
  end if;

  return jsonb_build_object(
    'views_count', (select coalesce(sum(v.view_count), 0)::bigint from public.post_views v where v.post_id = p_post_id),
    'viewers_count', (select count(*) from public.post_views v where v.post_id = p_post_id),
    'shares_count', (select count(*) from public.community_posts s where s.shared_post_id = p_post_id and s.status = 'active'),
    'viewer_has_shared', exists (select 1 from public.community_posts s where s.shared_post_id = p_post_id and s.author_id = p_viewer),
    'shared_post_id', v_shared,
    'shared_post', v_card,
    'shared_post_can_open_original', coalesce((v_card ->> 'can_open_original')::boolean, false),
    'shared_comment_id', v_scomment,
    'shared_comment', v_ccard
  );
end
$function$;

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
  v_photos text[] := '{}'; v_video_url text; v_video_thumbnail_url text; v_clean uuid[] := '{}'; v_spam text[] := '{}'; v_status text := 'active';
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
    if v_orig.status <> 'active' or not public.can_view_post_row(v_orig.community_id, v_orig.author_id, v_orig.audience) then
      raise exception 'Publication indisponible';
    end if;
    if private.users_blocked(v_uid, v_orig.author_id) then raise exception 'Action impossible'; end if;
    if not private.community_chain_sharing_allowed(p_shared_post_id) then
      raise exception 'Le repartage est désactivé sur cette publication ou sa communauté source';
    end if;
    if v_orig.community_id is not null then
      if not exists (
        select 1 from public.communities c
        where c.id = v_orig.community_id and c.status = 'active'
          and (c.visibility = 'public' or public.is_community_member(c.id))
      ) then
        raise exception 'Vous devez être membre de cette communauté pour repartager ses publications';
      end if;
      if exists (
        select 1 from public.community_settings cs
        where cs.community_id = v_orig.community_id
          and not coalesce(cs.allow_post_sharing, true)
      ) then
        raise exception 'Le repartage est désactivé par les administrateurs de cette communauté';
      end if;
    elsif v_orig.audience <> 'public' then
      raise exception 'Ce post ne peut pas être partagé';
    end if;
    if p_community_id is not null and v_orig.community_id = p_community_id then
      raise exception 'Ce post est déjà dans cette communauté';
    end if;
    -- Garder l'identifiant du post choisi pour préserver toute la chaîne.
    v_shared := p_shared_post_id;
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
      v_video_url := v_url;
      v_video_thumbnail_url := coalesce(v_video_thumbnail_url, nullif(v_item->>'thumbnail_url', ''));
      if v_duration is null or v_duration <= 0 or v_duration > 30 then raise exception 'Une vidéo doit durer au maximum 30 secondes'; end if;
      if nullif(v_url, '') is null or v_url not like 'https://%' or position('..' in v_url) > 0 then raise exception 'URL de vidéo invalide'; end if;
      if p_community_id is not null then
        if not (
          v_object_key like 'communities/' || p_community_id::text || '/posts/%'
          or v_object_key like 'private/communities/' || p_community_id::text || '/posts/' || v_uid::text || '/%'
        ) then raise exception 'Clé de stockage vidéo invalide'; end if;
      else
        if v_object_key not like 'posts/' || v_uid::text || '/%' then raise exception 'Clé de stockage vidéo invalide'; end if;
      end if;
      if right(lower(v_object_key), 4) <> '.mp4' and right(lower(v_object_key), 4) <> '.mov' then
        raise exception 'Format vidéo non pris en charge';
      end if;
      continue;
    end if;
    if v_type <> 'photo' then raise exception 'Type de média non pris en charge'; end if;
    if lower(coalesce(v_item->>'storage', '')) = 'supabase' then
      if nullif(v_url, '') is null or v_url not like v_prefix or position('..' in v_url) > 0 then raise exception 'Photo Supabase invalide'; end if;
    elsif lower(coalesce(v_item->>'storage', '')) = 'r2' then
      v_object_key := coalesce(v_item->>'object_key', '');
      if v_object_key = '' or position('..' in v_object_key) > 0 or left(v_object_key,1) = '/' then raise exception 'Clé photo R2 invalide'; end if;
      if p_community_id is not null then
        if not (v_object_key like 'communities/' || p_community_id::text || '/posts/%' or v_object_key like 'private/communities/' || p_community_id::text || '/posts/%') then raise exception 'Clé R2 hors communauté'; end if;
      else
        if v_object_key not like 'posts/' || v_uid::text || '/%' then raise exception 'Clé R2 hors propriétaire'; end if;
      end if;
      if nullif(v_url, '') is null or position('..' in v_url) > 0 then raise exception 'URL photo R2 invalide'; end if;
    else
      raise exception 'Stockage photo non pris en charge';
    end if;
    v_photos := array_append(v_photos, v_url);
  end loop;
  if not v_is_share and v_media_count = 0 and nullif(btrim(p_content), '') is null then
    raise exception 'Un post doit contenir du texte ou au moins un média';
  end if;
  if char_length(coalesce(p_content, '')) > 5000 then raise exception 'Le contenu ne peut pas dépasser 5000 caractères'; end if;
  if cardinality(coalesce(p_hashtags, '{}')) > 10 then raise exception 'Maximum 10 hashtags'; end if;
  v_clean := private.expand_global_mentions(v_uid, p_community_id, p_content, coalesce(p_mentions, '{}'::uuid[]));
  if p_community_id is null then
    select coalesce(array_agg(distinct m), '{}'::uuid[]) into v_clean
    from unnest(v_clean) m
    join public.user_profiles up on up.user_id=m
    where up.account_status='active' and up.deleted_at is null
      and m <> v_uid
      and (public.are_friends(v_uid,m) or exists(select 1 from public.user_follows uf where uf.followed_id=v_uid and uf.follower_id=m))
      and not private.users_blocked(v_uid,m);
  else
    select coalesce(array_agg(distinct m), '{}'::uuid[]) into v_clean
    from unnest(v_clean) m
    where exists (select 1 from public.community_members cm join public.user_profiles up on up.user_id=cm.user_id where cm.community_id=p_community_id and cm.user_id=m and up.account_status='active' and up.deleted_at is null and not private.users_blocked(v_uid,m));
  end if;

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
          and p.created_at > now() - interval '10 minutes') >= 20 then
      raise exception 'Vous publiez trop vite : 20 publications maximum toutes les 10 minutes';
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
      id, community_id, author_id, content, photo, photos, video_url, video_thumbnail_url, videos, media, status,
      comments_enabled, sharing_enabled, reactions_enabled, audience, allow_promotion, shared_post_id, shared_comment_id)
    values (
      p_id, p_community_id, v_uid, nullif(btrim(p_content), ''),
      case when cardinality(v_photos) > 0 then v_photos[1] end, v_photos, v_video_url, v_video_thumbnail_url, coalesce(
        (select jsonb_agg(item) from jsonb_array_elements(coalesce(p_media, '[]'::jsonb)) item where item->>'type' = 'video'), '[]'::jsonb),
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
$function$;


REVOKE ALL ON FUNCTION public.create_post(uuid, text, uuid, text, jsonb, text[], uuid[], boolean, boolean, boolean, jsonb, boolean, uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_post(uuid, text, uuid, text, jsonb, text[], uuid[], boolean, boolean, boolean, jsonb, boolean, uuid, uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.share_post(
  p_id uuid,
  p_original_post_id uuid,
  p_community_id uuid DEFAULT NULL::uuid,
  p_audience text DEFAULT 'public'::text,
  p_comment text DEFAULT NULL::text
) RETURNS public.community_posts
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare
  v_uid uuid := auth.uid();
  v_source public.community_posts;
  v_shared public.community_posts;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  if p_original_post_id is null then raise exception 'Publication indisponible'; end if;

  select * into v_source from public.community_posts where id = p_original_post_id;
  if not found or v_source.status <> 'active'
     or not public.can_view_post_row(v_source.community_id, v_source.author_id, v_source.audience)
     or private.users_blocked(v_uid, v_source.author_id) then
    raise exception 'Publication indisponible';
  end if;
  if not private.community_chain_sharing_allowed(p_original_post_id) then
    raise exception 'Le repartage est désactivé sur cette publication ou sa communauté source';
  end if;
  if v_source.community_id is not null then
    if not exists (
      select 1 from public.communities c
      where c.id = v_source.community_id and c.status = 'active'
        and (c.visibility = 'public' or public.is_community_member(c.id))
    ) then raise exception 'Publication indisponible'; end if;
    if exists (
      select 1 from public.community_settings cs
      where cs.community_id = v_source.community_id
        and not coalesce(cs.allow_post_sharing, true)
    ) then raise exception 'Le repartage est désactivé par les administrateurs de cette communauté'; end if;
  elsif v_source.audience <> 'public' then
    raise exception 'Cette publication ne peut pas être repartagée';
  end if;

  v_shared := public.create_post(
    p_id, p_comment, p_community_id, p_audience, '[]'::jsonb, '{}'::text[], '{}'::uuid[],
    true, true, true, null, true, p_original_post_id, null
  );
  update public.community_posts
    set shared_post_snapshot = private.story_post_snapshot(p_original_post_id, v_uid, 0)
    where id = v_shared.id
    returning * into v_shared;
  return v_shared;
end
$function$;

REVOKE ALL ON FUNCTION public.share_post(uuid, uuid, uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.share_post(uuid, uuid, uuid, text, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.share_post_to_story(p_id uuid, p_original_post_id uuid, p_caption text DEFAULT NULL::text, p_background text DEFAULT NULL::text, p_audience text DEFAULT 'public'::text)
 RETURNS stories
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := auth.uid(); v_row public.stories; v_orig public.community_posts;
  v_audience text := lower(btrim(coalesce(p_audience, 'public')));
  v_caption text := nullif(btrim(p_caption), ''); v_bg text := nullif(btrim(p_background), '');
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  if p_id is null then raise exception 'L''identifiant de la story est obligatoire'; end if;
  select * into v_row from public.stories where id = p_id;
  if found then
    if v_row.author_id = v_uid then return v_row; end if;
    raise exception 'Identifiant de story déjà utilisé';
  end if;
  if not exists (select 1 from public.user_profiles up where up.user_id = v_uid and up.account_status = 'active' and up.deleted_at is null) then
    raise exception 'Compte indisponible';
  end if;
  if v_audience not in ('public', 'followers', 'friends') then raise exception 'Audience invalide'; end if;
  if char_length(coalesce(p_caption, '')) > 500 then raise exception 'Le texte ne peut pas dépasser 500 caractères'; end if;
  if v_bg is not null and v_bg !~ '^(#[0-9A-Fa-f]{6}|[a-z0-9_-]{1,30})$' then raise exception 'Fond invalide'; end if;

  if p_original_post_id is null then raise exception 'Publication indisponible'; end if;
  select * into v_orig from public.community_posts where id = p_original_post_id;
  if not found then raise exception 'Publication indisponible'; end if;
  -- Conserver exactement le post sélectionné : ne jamais aplatir la chaîne de republications.
  if v_orig.status <> 'active' or not public.can_view_post_row(v_orig.community_id, v_orig.author_id, v_orig.audience) then
    raise exception 'Publication indisponible';
  end if;
  if private.users_blocked(v_uid, v_orig.author_id) then raise exception 'Action impossible'; end if;
  if not private.community_chain_sharing_allowed(p_original_post_id) then raise exception 'Le repartage est désactivé sur cette publication ou sa communauté source'; end if;
  if v_orig.community_id is not null then
    if not exists (
      select 1 from public.communities c
      where c.id = v_orig.community_id and c.status = 'active'
        and (c.visibility = 'public' or public.is_community_member(c.id))
    ) then raise exception 'Ce post ne peut pas être partagé'; end if;
    if exists (
      select 1 from public.community_settings cs
      where cs.community_id = v_orig.community_id
        and not coalesce(cs.allow_post_sharing, true)
    ) then raise exception 'Le repartage est désactivé par les administrateurs de cette communauté'; end if;
  elsif v_orig.audience <> 'public' then
    raise exception 'Ce post ne peut pas être partagé';
  end if;

  if (select count(*) from public.stories s where s.author_id = v_uid and s.created_at > now() - interval '24 hours') >= 20 then
    raise exception 'Limite de stories atteinte : 20 stories par 24 heures';
  end if;

  begin
    insert into public.stories (id, author_id, kind, content, background, audience, shared_post_id, shared_post_snapshot, expires_at)
    values (p_id, v_uid, 'post', v_caption, v_bg, v_audience, v_orig.id,
      private.story_post_snapshot(v_orig.id, v_uid, 0), now() + interval '24 hours')
    returning * into v_row;
  exception when unique_violation then
    raise exception 'Vous avez déjà partagé ce post dans une story';
  end;

  if v_orig.author_id <> v_uid then
    perform private.notify_community_user(v_orig.author_id, 'post_shared_story', v_uid,
      jsonb_build_object('post_id', v_orig.id, 'story_id', p_id, 'community_id', v_orig.community_id, 'actor_id', v_uid),
      'Publication partagée en story', 'Quelqu''un a partagé votre publication dans sa story.');
  end if;
  return v_row;
end $function$;


CREATE OR REPLACE FUNCTION private.story_groups(p_scope text, p_limit integer, p_offset integer, p_author uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_uid uuid := auth.uid(); v_result jsonb;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  with vis as (
    select s.id, s.author_id, s.kind, s.content, s.image_url, s.background, s.shared_post_id, s.shared_post_snapshot, s.audience, s.created_at, s.expires_at,
           exists (select 1 from public.story_views sv where sv.story_id = s.id and sv.viewer_id = v_uid) as viewed
    from public.stories s
    where s.status = 'active' and s.expires_at > now()
      and public.can_view_story_row(s.author_id, s.audience)
      and case p_scope when 'own' then s.author_id = v_uid when 'user' then s.author_id = p_author else s.author_id <> v_uid end
  ),
  rel as (
    select a.author_id,
      case when a.author_id = v_uid then 'own'
           when public.are_friends(v_uid, a.author_id) then 'friend'
           when exists (select 1 from public.user_follows f where f.follower_id = v_uid and f.followed_id = a.author_id) then 'follow'
           else 'other' end as relation
    from (select distinct author_id from vis) a
  ),
  grp as (
    select v.author_id, r.relation, max(v.created_at) as latest_at, count(*)::int as stories_count,
           bool_or(not v.viewed) as has_unseen
    from vis v join rel r on r.author_id = v.author_id
    group by v.author_id, r.relation
  ),
  filtered as (
    select g.*,
      case when p_scope = 'suggested' then (
          least(50, (select count(*) from public.friendships f
                     where (f.user_a_id = g.author_id and public.are_friends(v_uid, f.user_b_id))
                        or (f.user_b_id = g.author_id and public.are_friends(v_uid, f.user_a_id))) * 10)
        + least(32, (select count(*) from public.community_members a join public.community_members b
                     on b.community_id = a.community_id and b.user_id = g.author_id where a.user_id = v_uid) * 8)
        + least(20, (select count(*) from public.user_interests a join public.user_interests b
                     on b.interest_id = a.interest_id and b.user_id = v_uid where a.user_id = v_uid) * 5)
        + least(30, round(5 * ln(1 + (select count(distinct sv.viewer_id) from public.story_views sv
                     join vis v2 on v2.id = sv.story_id where v2.author_id = g.author_id))))
        + floor(20 * exp(-extract(epoch from (now() - g.latest_at)) / 43200.0))
      )::numeric else 0::numeric end as score
    from grp g
    join public.user_profiles up on up.user_id = g.author_id and up.account_status = 'active' and up.deleted_at is null
    where case p_scope
            when 'following' then g.relation in ('friend', 'follow')
            when 'suggested' then g.relation = 'other' and g.has_unseen
            else true end
  ),
  ordered as (
    select f.*, row_number() over (
      order by case when p_scope = 'suggested' then -f.score else (case when f.has_unseen then 0 else 1 end)::numeric end,
               f.latest_at desc, f.author_id) as rn
    from filtered f
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'author', jsonb_build_object('user_id', up.user_id, 'username', up.username, 'pseudo', up.username, 'first_name', up.first_name,
                 'last_name', up.last_name, 'photo_url', up.photo_url,
                 'is_certified', exists (select 1 from public.user_certifications uc where uc.user_id = up.user_id
                                         and uc.status::text = 'active' and uc.issued_at <= now()
                                         and (uc.expires_at is null or uc.expires_at >= now()))),
      'relation', o.relation, 'has_unseen', o.has_unseen, 'latest_at', o.latest_at, 'stories_count', o.stories_count,
      'stories', (select jsonb_agg(jsonb_build_object(
                    'id', v.id, 'kind', v.kind, 'content', v.content, 'image_url', v.image_url, 'background', v.background,
                    'shared_post_id', v.shared_post_id,
                    'shared_post_can_open_original', case when v.shared_post_id is null then false else private.story_can_open_original(v.shared_post_id, v_uid) end,
                    'shared_post', case
                      when v.shared_post_id is null then null
                      when private.story_can_open_original(v.shared_post_id, v_uid) then private.story_post_card(v.shared_post_id, v_uid)
                      else coalesce(v.shared_post_snapshot, jsonb_build_object('id', v.shared_post_id, 'available', false, 'can_open_original', false))
                    end,
                    'audience', v.audience, 'created_at', v.created_at, 'expires_at', v.expires_at, 'viewed', v.viewed,
                    'viewers_count', case when v.author_id = v_uid then (select count(*) from public.story_views sv where sv.story_id = v.id) end,
                    'comments_count', (select count(*)::integer from public.story_comments c
                                       join public.user_profiles cup on cup.user_id = c.author_id
                                       where c.story_id = v.id and c.parent_comment_id is null
                                         and cup.account_status = 'active' and cup.deleted_at is null),
                    'viewer_has_liked', exists (select 1 from public.story_likes sl where sl.story_id = v.id and sl.user_id = v_uid),
                    'likes_count', case when v.author_id = v_uid then (select count(*) from public.story_likes sl where sl.story_id = v.id) end,
                    'poll', private.story_poll_state(v.id, v_uid)) order by v.created_at)
                  from vis v where v.author_id = o.author_id)
    ) order by o.rn), '[]'::jsonb)
  into v_result
  from ordered o join public.user_profiles up on up.user_id = o.author_id
  where o.rn > p_offset and o.rn <= p_offset + p_limit;
  return v_result;
end $function$;


CREATE OR REPLACE FUNCTION public.set_community_post_sharing_enabled(
  p_community_id uuid,
  p_enabled boolean
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
begin
  if auth.uid() is null then raise exception 'Utilisateur non authentifié'; end if;
  if not public.is_community_admin(p_community_id) then
    raise exception 'Action réservée aux administrateurs de la communauté';
  end if;
  if not exists (select 1 from public.communities c where c.id = p_community_id and c.status = 'active') then
    raise exception 'Communauté introuvable';
  end if;
  insert into public.community_settings (community_id, allow_post_sharing)
  values (p_community_id, p_enabled)
  on conflict (community_id) do update
    set allow_post_sharing = excluded.allow_post_sharing, updated_at = now();
  return jsonb_build_object('community_id', p_community_id, 'allow_post_sharing', p_enabled);
end
$function$;

REVOKE ALL ON FUNCTION public.set_community_post_sharing_enabled(uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_community_post_sharing_enabled(uuid, boolean) TO authenticated;
