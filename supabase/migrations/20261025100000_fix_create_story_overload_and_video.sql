-- Fix the ambiguous create_story overload and support standalone video stories.
-- The 8-argument wrapper has required arguments to avoid competing with the
-- 7-argument canonical function when optional parameters are omitted.
do $canonical_story$
declare
  v_def text;
  v_updated text;
begin
  select pg_get_functiondef(
    'public.create_story(uuid,text,text,text,text,text,jsonb)'::regprocedure
  ) into v_def;
  v_updated := replace(v_def,
    'v_kind not in (''text'', ''image'')',
    'v_kind not in (''text'', ''image'', ''video'')');
  v_updated := replace(v_updated,
    'v_kind NOT IN (''text'', ''image'')',
    'v_kind NOT IN (''text'', ''image'', ''video'')');
  if v_updated <> v_def then
    execute v_updated;
  elsif position('''video''' in v_def) = 0 then
    raise exception 'Could not safely locate story-kind validation';
  end if;
end
$canonical_story$;

drop function public.create_story(uuid,text,text,text,text,text,jsonb,boolean);

create function public.create_story(
  p_id uuid,
  p_kind text,
  p_content text,
  p_image_url text,
  p_background text,
  p_audience text,
  p_poll jsonb,
  p_allow_reshare boolean
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_result jsonb;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  perform public.create_story(
    p_id, p_kind, p_content, p_image_url, p_background, p_audience, p_poll
  );
  update public.stories
     set allow_reshare = coalesce(p_allow_reshare, false)
   where id = p_id and author_id = v_uid;
  if not found then raise exception 'Story unavailable or not owned by caller'; end if;
  select to_jsonb(s) into v_result from public.stories s where s.id = p_id;
  return coalesce(v_result, jsonb_build_object('id', p_id, 'success', true));
end
$function$;

grant execute on function public.create_story(uuid,text,text,text,text,text,jsonb,boolean) to authenticated;
grant execute on function public.create_story(uuid,text,text,text,text,text,jsonb,boolean) to service_role;

alter table public.stories
  drop constraint if exists stories_kind_check;
alter table public.stories
  add constraint stories_kind_check
  check (kind = any (array['text'::text, 'image'::text, 'post'::text, 'video'::text]));

alter table public.stories
  drop constraint if exists stories_kind_content_check;
alter table public.stories
  add constraint stories_kind_content_check
  check (
    (kind = 'text'::text and nullif(btrim(content), ''::text) is not null
      and image_url is null and shared_post_id is null)
    or (kind = 'image'::text and image_url is not null and shared_post_id is null)
    or (kind = 'video'::text and image_url is not null and shared_post_id is null)
    or (kind = 'post'::text and shared_post_id is not null and image_url is null)
  );

notify pgrst, 'reload schema';