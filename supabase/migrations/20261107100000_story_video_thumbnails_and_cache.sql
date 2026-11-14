-- Persist dedicated video story thumbnails and expose them in story tray JSON.
alter table public.stories
  add column if not exists thumbnail_url text;

-- Keep the existing eight-argument create_story overload untouched for older clients.
create or replace function public.create_story(
  p_id uuid,
  p_kind text,
  p_content text,
  p_image_url text,
  p_background text,
  p_audience text,
  p_poll jsonb,
  p_allow_reshare boolean,
  p_thumbnail_url text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_thumbnail text := nullif(btrim(p_thumbnail_url), '');
  v_result jsonb;
begin
  if v_uid is null then
    raise exception 'Authentication required';
  end if;

  if v_thumbnail is not null and (
    position('..' in v_thumbnail) > 0
    or position(chr(92) in v_thumbnail) > 0
    or left(v_thumbnail, 1) = '/'
    or v_thumbnail not like 'stories/' || v_uid::text || '/%'
  ) then
    raise exception 'Miniature de story invalide';
  end if;

  perform public.create_story(
    p_id, p_kind, p_content, p_image_url, p_background,
    p_audience, p_poll, p_allow_reshare
  );

  update public.stories
     set thumbnail_url = v_thumbnail
   where id = p_id
     and author_id = v_uid
     and kind = 'video';

  if not found and v_thumbnail is not null then
    raise exception 'Story vidéo indisponible ou non autorisée';
  end if;

  select to_jsonb(s) into v_result
    from public.stories s
   where s.id = p_id and s.author_id = v_uid;

  return coalesce(v_result, jsonb_build_object('id', p_id, 'success', true));
end
$function$;

revoke all on function public.create_story(uuid,text,text,text,text,text,jsonb,boolean,text)
  from public, anon;
grant execute on function public.create_story(uuid,text,text,text,text,text,jsonb,boolean,text)
  to authenticated;

-- Extend the existing private story grouping function without duplicating its
-- access-control and audience-visibility rules.
do $$
declare
  v_def text := pg_get_functiondef(
    'private.story_groups(text,integer,integer,uuid)'::regprocedure
  );
begin
  v_def := replace(
    v_def,
    's.image_url, s.background',
    's.image_url, s.thumbnail_url, s.background'
  );
  v_def := replace(
    v_def,
    '''image_url'', v.image_url, ''background''',
    '''image_url'', v.image_url, ''thumbnail_url'', v.thumbnail_url, ''background'''
  );
  if position('thumbnail_url' in v_def) = 0 then
    raise exception 'Unable to extend story_groups JSON with thumbnail_url';
  end if;
  execute v_def;
end
$$;

-- Queue original video/image and thumbnail objects for R2 deletion when a
-- story is removed or expires. The cleanup worker validates keys again.
create or replace function private.enqueue_story_media_for_cleanup()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_key text;
begin
  foreach v_key in array array[old.image_url, old.thumbnail_url]
  loop
    if v_key is null then
      continue;
    end if;
    v_key := btrim(v_key);
    if v_key ~ ('^stories/' || old.author_id::text || '/[A-Za-z0-9_-]+\.(jpg|jpeg|png|webp|avif|gif|mp4|mov)$') then
      insert into public.story_media_cleanup_queue(object_key)
      values (v_key)
      on conflict (object_key) do nothing;
    end if;
  end loop;
  return old;
end;
$function$;
