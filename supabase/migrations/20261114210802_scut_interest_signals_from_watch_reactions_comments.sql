-- Personalize video themes from watch depth, likes, dislikes and comments.
do $$
declare v_def text;
begin
 v_def := pg_get_functiondef('public.get_scuts_feed(integer,uuid[])'::regprocedure);
 v_def := replace(v_def,
   E'  video_posts as materialized (',
   E'  my_content_signals as materialized (\n' ||
   E'    select s.post_id, (case when s.max_percent >= 90 then 12 when s.max_percent >= 50 then 8 else 4 end\n' ||
   E'      + least(8, greatest(s.watch_sessions - 1, 0) * 2))::numeric weight\n' ||
   E'    from public.scut_watch_signals s where s.user_id = v_uid and s.max_percent >= 25\n' ||
   E'    union all\n' ||
   E'    select r.post_id, case when r.reaction = ''like'' then 10::numeric else -14::numeric end\n' ||
   E'    from public.community_post_reactions r where r.user_id = v_uid and r.reaction in (''like'',''dislike'')\n' ||
   E'    union all\n' ||
   E'    select c.post_id, 10::numeric from public.community_post_comments c where c.author_id = v_uid\n' ||
   E'  ),\n' ||
   E'  my_tag_affinity as materialized (\n' ||
   E'    select ph.hashtag_id, sum(sig.weight) weight\n' ||
   E'    from my_content_signals sig join public.community_post_hashtags ph on ph.post_id = sig.post_id\n' ||
   E'    group by ph.hashtag_id\n' ||
   E'  ),\n' ||
   E'  video_posts as materialized (');
 v_def := replace(v_def,
   E'      + coalesce((\n' ||
   E'        select least(45, coalesce(sum(case when ws.max_percent >= 90 then 12 when ws.max_percent >= 50 then 8 else 4 end),0))\n' ||
   E'        from public.community_post_hashtags ph\n' ||
   E'        join public.community_post_hashtags mine on mine.hashtag_id = ph.hashtag_id\n' ||
   E'        join public.scut_watch_signals ws on ws.post_id = mine.post_id and ws.user_id = v_uid\n' ||
   E'        where ph.post_id = p.id and ws.max_percent >= 25\n' ||
   E'      ),0)',
   E'      + coalesce((select least(60, sum(a.weight))\n' ||
   E'        from public.community_post_hashtags ph\n' ||
   E'        join my_tag_affinity a on a.hashtag_id = ph.hashtag_id\n' ||
   E'        where ph.post_id = p.id),0)');
 execute v_def;
end $$;