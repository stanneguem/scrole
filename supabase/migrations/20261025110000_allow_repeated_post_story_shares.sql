-- A publication may be shared to the same author's story repeatedly.
-- Remove only unique indexes/constraints on stories that include shared_post_id;
-- they incorrectly turned a valid repeated share into a uniqueness violation.
do $migration$
declare
  v record;
  v_def text;
  v_updated text;
  v_old text := E'  exception when unique_violation then\n    raise exception ''Vous avez déjà partagé ce post dans une story'';';
begin
  for v in
    select
      ns.nspname as schema_name,
      tbl.relname as table_name,
      idx.relname as index_name,
      con.conname as constraint_name,
      con.contype as constraint_type,
      pg_get_indexdef(i.indexrelid) as index_definition
    from pg_index i
    join pg_class tbl on tbl.oid = i.indrelid
    join pg_namespace ns on ns.oid = tbl.relnamespace
    join pg_class idx on idx.oid = i.indexrelid
    left join pg_constraint con on con.conindid = i.indexrelid
    where ns.nspname = 'public'
      and tbl.relname = 'stories'
      and i.indisunique
      and not i.indisprimary
      and pg_get_indexdef(i.indexrelid) ilike '%shared_post_id%'
      and pg_get_indexdef(i.indexrelid) ilike '%author_id%'
  loop
    if v.constraint_name is not null then
      execute format('alter table %I.%I drop constraint %I',
        v.schema_name, v.table_name, v.constraint_name);
    else
      execute format('drop index %I.%I', v.schema_name, v.index_name);
    end if;
  end loop;

  -- Do not misreport every unique_violation as "already shared". Repeated
  -- shares are valid; a real duplicate story ID should remain a separate error.
  select pg_get_functiondef(
    'public.share_post_to_story(uuid,uuid,text,text,text)'::regprocedure
  ) into v_def;

  v_updated := replace(v_def, v_old, '');
  if v_updated = v_def then
    raise notice 'share_post_to_story already has no duplicate-share rejection handler';
  else
    execute v_updated;
  end if;
end
$migration$;

notify pgrst, 'reload schema';
