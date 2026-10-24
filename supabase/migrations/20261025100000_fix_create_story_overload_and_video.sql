-- Fix the ambiguous create_story overload and support video stories.
-- Safe to rerun; does not delete existing stories or media.
do $migration$
declare
  v_def text;
  v_updated text;
begin
  -- The seven-argument implementation is the canonical story creator.
  select pg_get_functiondef(
    'public.create_story(uuid,text,text,text,text,text,jsonb)'::regprocedure
  ) into v_def;

  v_updated := replace(
    v_def,
    'v_kind not in (''text'', ''image'')',
    'v_kind not in (''text'', ''image'', ''video'')'
  );
  v_updated := replace(
    v_updated,
    'v_kind NOT IN (''text'', ''image'')',
    'v_kind NOT IN (''text'', ''image'', ''video'')'
  );

  if v_updated <> v_def then
    execute v_updated;
  elsif position('''video''' in v_def) = 0 then
    raise exception 'Could not safely locate the story-kind validation in create_story(uuid,text,text,text,text,text,jsonb)';
  end if;

  -- The eight-argument wrapper must not have a default for p_allow_reshare.
  -- Otherwise its default makes its own internal seven-argument call ambiguous.
  select pg_get_functiondef(
    'public.create_story(uuid,text,text,text,text,text,jsonb,boolean)'::regprocedure
  ) into v_def;

  v_updated := replace(
    v_def,
    'p_allow_reshare boolean DEFAULT false',
    'p_allow_reshare boolean'
  );
  v_updated := replace(
    v_updated,
    'p_allow_reshare boolean default false',
    'p_allow_reshare boolean'
  );

  if v_updated <> v_def then
    execute v_updated;
  elsif position('p_allow_reshare boolean DEFAULT false' in v_def) > 0
     or position('p_allow_reshare boolean default false' in v_def) > 0 then
    raise exception 'Could not safely remove the default from the create_story wrapper';
  end if;
end
$migration$;

-- Ensure PostgREST refreshes the available RPC signatures.
notify pgrst, 'reload schema';
