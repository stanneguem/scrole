-- Avoid replaying videos already watched meaningfully and spread creators through the queue.
do $$
declare v_def text;
begin
 v_def := pg_get_functiondef('public.get_scuts_feed(integer,uuid[])'::regprocedure);
 v_def := replace(v_def,
   'and p.id <> all(coalesce(p_exclude_ids, ''{}''::uuid[]))',
   'and p.id <> all(coalesce(p_exclude_ids, ''{}''::uuid[]))' || E'\n      and not exists (select 1 from public.scut_watch_signals seen where seen.user_id = v_uid and seen.post_id = p.id and seen.max_percent >= 25)');
 v_def := replace(v_def,
   E'      + coalesce((\n        select sum(case when s.max_percent >= 90 then 34\n                        when s.max_percent >= 50 then 22\n                        when s.max_percent >= 25 then 12\n                        else -8 end)\n        from public.scut_watch_signals s\n        where s.user_id = v_uid and s.post_id = p.id\n      ),0)\n',
   '');
 v_def := replace(v_def,
   'select least(30, count(*) * 5)' || E'\\n        from public.community_post_hashtags ph',
   'select least(45, coalesce(sum(case when ws.max_percent >= 90 then 12 when ws.max_percent >= 50 then 8 else 4 end),0))' || E'\\n        from public.community_post_hashtags ph');
 v_def := replace(v_def,
   E'  ranked as (\n    select s.*, row_number() over (\n      order by score desc, created_at desc, id desc\n    ) rn\n    from scored s\n  ),',
   E'  author_ordered as (\n    select s.*, row_number() over (partition by author_id order by score desc, created_at desc, id desc) author_position\n    from scored s\n  ),\n  ranked as (\n    select s.*, row_number() over (\n      order by (score - ((author_position - 1) * 30)) desc, score desc, created_at desc, id desc\n    ) rn\n    from author_ordered s\n  ),');
 execute v_def;
end $$;