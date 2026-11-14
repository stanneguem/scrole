-- Enable video as a first-class story media kind.
-- Additive migration: no stories or media objects are deleted.
do $migration$
declare
  fn record;
  v_def text;
  v_updated text;
  v_old text;
  v_new text;
  c record;
  v_constraint text;
begin
  -- Preserve all existing create_story overloads and security settings while
  -- widening the existing kind validation, when it uses a recognised form.
  for fn in
    select p.oid
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'create_story'
  loop
    v_def := pg_get_functiondef(fn.oid);
    v_updated := v_def;

    v_updated := replace(v_updated, 'p_kind not in (''text'', ''image'')',
                                      'p_kind not in (''text'', ''image'', ''video'')');
    v_updated := replace(v_updated, 'p_kind NOT IN (''text'', ''image'')',
                                      'p_kind NOT IN (''text'', ''image'', ''video'')');
    v_updated := replace(v_updated, 'v_kind not in (''text'', ''image'')',
                                      'v_kind not in (''text'', ''image'', ''video'')');
    v_updated := replace(v_updated, 'v_kind NOT IN (''text'', ''image'')',
                                      'v_kind NOT IN (''text'', ''image'', ''video'')');
    v_updated := replace(v_updated, 'p_kind not in (''image'', ''text'')',
                                      'p_kind not in (''image'', ''text'', ''video'')');
    v_updated := replace(v_updated, 'v_kind not in (''image'', ''text'')',
                                      'v_kind not in (''image'', ''text'', ''video'')');
    -- Handle formatting variants commonly emitted by PL/pgSQL migrations.
    v_updated := replace(v_updated, 'p_kind not in (''text'',''image'')',
                                      'p_kind not in (''text'',''image'',''video'')');
    v_updated := replace(v_updated, 'p_kind NOT IN (''text'',''image'')',
                                      'p_kind NOT IN (''text'',''image'',''video'')');
    v_updated := replace(v_updated, 'v_kind not in (''text'',''image'')',
                                      'v_kind not in (''text'',''image'',''video'')');
    v_updated := replace(v_updated, 'v_kind NOT IN (''text'',''image'')',
                                      'v_kind NOT IN (''text'',''image'',''video'')');
    v_updated := replace(v_updated, 'p_kind not in (''image'',''text'')',
                                      'p_kind not in (''image'',''text'',''video'')');
    v_updated := replace(v_updated, 'v_kind not in (''image'',''text'')',
                                      'v_kind not in (''image'',''text'',''video'')');

    if v_updated <> v_def then
      execute v_updated;
    end if;
  end loop;

  -- Some deployments express the allowed values as a table CHECK constraint.
  -- Widen only a recognisable text/image constraint; leave unknown expressions
  -- untouched rather than risk changing unrelated validation.
  for c in
    select con.conname, pg_get_constraintdef(con.oid) as definition
    from pg_constraint con
    join pg_class rel on rel.oid = con.conrelid
    join pg_namespace ns on ns.oid = rel.relnamespace
    where ns.nspname = 'public'
      and rel.relname = 'stories'
      and con.contype = 'c'
      and pg_get_constraintdef(con.oid) ilike '%kind%'
      and pg_get_constraintdef(con.oid) ilike '%image%'
      and pg_get_constraintdef(con.oid) not ilike '%video%'
  loop
    v_constraint := c.definition;
    v_constraint := replace(v_constraint,
      'ARRAY[''text''::text, ''image''::text]',
      'ARRAY[''text''::text, ''image''::text, ''video''::text]');
    v_constraint := replace(v_constraint,
      'ARRAY[''image''::text, ''text''::text]',
      'ARRAY[''image''::text, ''text''::text, ''video''::text]');
    v_constraint := replace(v_constraint,
      'ANY (ARRAY[''text''::text, ''image''::text])',
      'ANY (ARRAY[''text''::text, ''image''::text, ''video''::text])');
    v_constraint := replace(v_constraint,
      'ANY (ARRAY[''image''::text, ''text''::text])',
      'ANY (ARRAY[''image''::text, ''text''::text, ''video''::text])');

    if v_constraint <> c.definition then
      execute format('alter table public.stories drop constraint %I', c.conname);
      execute format('alter table public.stories add constraint %I %s',
                     c.conname, v_constraint);
    end if;
  end loop;
end
$migration$;

-- Resolve PostgREST ambiguity between the 7-argument RPC and the 8-argument
-- allow_reshare wrapper. The wrapper's final boolean must be explicit so a
-- call without p_allow_reshare can only resolve to the 7-argument function.
do $fix_overload$
declare
  v_def text;
  v_updated text;
begin
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

  if v_updated = v_def and position('p_allow_reshare boolean DEFAULT false' in v_def) = 0
     and position('p_allow_reshare boolean default false' in v_def) = 0 then
    raise notice 'create_story 8-argument wrapper already has no default for p_allow_reshare';
  elsif v_updated <> v_def then
    execute v_updated;
  end if;
end
$fix_overload$;

-- Refresh PostgREST's function metadata after the migration is applied.
notify pgrst, 'reload schema';
