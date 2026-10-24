-- Scrole Reputation V2 engine: event ledger, weighted public score, and admin RPCs.
-- Review and test before applying. This migration does not rewrite legacy user_statistics.

alter table public.reputation_ledger
  add column if not exists dimension text not null default 'quality';

alter table public.reputation_scoring_rules
  add column if not exists sort_order integer not null default 100;

create table if not exists public.user_reputation_scores (
  user_id uuid primary key references auth.users(id) on delete cascade,
  score numeric(4,2) not null default 0 check (score >= 0 and score <= 5),
  dimension_scores jsonb not null default '{}'::jsonb,
  last_meaningful_activity_at timestamptz,
  calculated_at timestamptz not null default now()
);

alter table public.user_community_reputation
  add column if not exists score numeric(4,2) not null default 0;
alter table public.user_community_reputation
  add column if not exists dimension_scores jsonb not null default '{}'::jsonb;
alter table public.user_community_reputation
  add constraint user_community_reputation_score_range check (score >= 0 and score <= 5);

alter table public.user_reputation_scores enable row level security;
drop policy if exists "Users can read own reputation score" on public.user_reputation_scores;
create policy "Users can read own reputation score"
  on public.user_reputation_scores for select to authenticated using (user_id = auth.uid());

insert into public.reputation_scoring_rules(rule_key,label,points,daily_cap,enabled,config,sort_order)
values
 ('meaningful_post','Publication originale pertinente',2,6,true,'{"max_awards_per_day":3,"requires_non_spam":true,"dimension":"quality","dimension_weight":0.30,"saturation_k":24}',10),
 ('constructive_comment','Commentaire constructif',1,5,true,'{"max_awards_per_day":5,"minimum_characters":20,"dimension":"quality","dimension_weight":0.30,"saturation_k":30}',20),
 ('post_positive_reaction_received','Réaction positive reçue sur une publication',1,5,true,'{"distinct_reactors_only":true,"exclude_author":true,"dimension":"recognition","dimension_weight":0.25,"saturation_k":40}',30),
 ('comment_positive_reaction_received','Réaction positive reçue sur un commentaire',1,5,true,'{"distinct_reactors_only":true,"exclude_author":true,"dimension":"recognition","dimension_weight":0.25,"saturation_k":35}',40),
 ('meaningful_activity_day','Journée de participation significative',1,1,true,'{"distinct_active_day":true,"dimension":"consistency","dimension_weight":0.20,"saturation_k":45}',50),
 ('community_contribution','Contribution à une communauté',1,4,true,'{"dimension":"communities","dimension_weight":0.15,"saturation_k":24}',60),
 ('confirmed_spam_penalty','Abus confirmé par modération',-3,null,true,'{"moderation_required":true,"dimension":"trust","dimension_weight":0.10}',70),
 ('weekly_inactivity_decay','Décroissance hebdomadaire après inactivité',0,null,true,'{"grace_days":30,"rate_percent":1,"period":"week","minimum_score":0}',80)
on conflict(rule_key) do nothing;

create or replace function public.admin_get_reputation_rules()
returns table(rule_key text,label text,points integer,daily_cap integer,enabled boolean,config jsonb,sort_order integer,updated_at timestamptz)
language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_admin_or_above() then raise exception 'Action réservée aux administrateurs' using errcode='42501'; end if;
  return query select r.rule_key,r.label,r.points,r.daily_cap,r.enabled,r.config,r.sort_order,r.updated_at
    from public.reputation_scoring_rules r order by r.sort_order,r.rule_key;
end $$;

create or replace function public.admin_update_reputation_rule(
  p_rule_key text,
  p_points integer,
  p_daily_cap integer,
  p_enabled boolean,
  p_config jsonb
) returns public.reputation_scoring_rules
language plpgsql security definer set search_path = ''
as $$
declare v_row public.reputation_scoring_rules;
begin
  if not public.is_admin_or_above() then raise exception 'Action réservée aux administrateurs' using errcode='42501'; end if;
  if p_rule_key is null or length(trim(p_rule_key))=0 then raise exception 'Règle invalide'; end if;
  if p_daily_cap is not null and p_daily_cap < 0 then raise exception 'Le plafond quotidien doit être positif ou nul'; end if;
  if p_points < -20 or p_points > 20 then raise exception 'Les points doivent être compris entre -20 et 20'; end if;
  if p_config is null or jsonb_typeof(p_config) <> 'object' then raise exception 'Configuration invalide'; end if;
  if coalesce((p_config->>'dimension_weight')::numeric,0) < 0 or coalesce((p_config->>'dimension_weight')::numeric,0) > 1 then
    raise exception 'La pondération doit être comprise entre 0 et 1';
  end if;
  if coalesce((p_config->>'saturation_k')::numeric,1) <= 0 then raise exception 'La saturation doit être positive'; end if;
  update public.reputation_scoring_rules r
    set points=p_points,daily_cap=p_daily_cap,enabled=p_enabled,config=p_config,updated_at=now()
    where r.rule_key=p_rule_key returning * into v_row;
  if not found then raise exception 'Règle introuvable'; end if;
  return v_row;
end $$;

create or replace function public.reputation_award_event(
  p_user_id uuid,p_scope_type text,p_scope_id uuid,p_event_key text,
  p_source_type text,p_source_id text,p_points_delta integer,p_dimension text,
  p_metadata jsonb default '{}'::jsonb
) returns void
language plpgsql security definer set search_path = ''
as $$
declare v_rule public.reputation_scoring_rules; v_today_count integer; v_delta integer;
begin
  if p_user_id is null or p_points_delta=0 then return; end if;
  select * into v_rule from public.reputation_scoring_rules where rule_key=p_event_key and enabled;
  if not found then return; end if;
  if p_points_delta > 0 then
    v_delta := v_rule.points;
    if v_delta <= 0 then return; end if;
  elsif p_event_key = 'confirmed_spam_penalty' then
    v_delta := p_points_delta;
  else
    select -coalesce(sum(l.points_delta),0)::integer into v_delta
      from public.reputation_ledger l
      where l.user_id=p_user_id and l.scope_type=p_scope_type
        and coalesce(l.scope_id,'00000000-0000-0000-0000-000000000000'::uuid)=coalesce(p_scope_id,'00000000-0000-0000-0000-000000000000'::uuid)
        and l.event_key=p_event_key and l.source_id=p_source_id and l.points_delta>0;
    if v_delta >= 0 then return; end if;
  end if;
  if v_delta > 0 and v_rule.daily_cap is not null then
    perform pg_advisory_xact_lock(hashtextextended(p_user_id::text||':'||p_scope_type||':'||coalesce(p_scope_id::text,'global')||':'||p_event_key,0));
    select coalesce(sum(l.points_delta),0)::integer into v_today_count
      from public.reputation_ledger l
      where l.user_id=p_user_id and l.scope_type=p_scope_type
        and coalesce(l.scope_id,'00000000-0000-0000-0000-000000000000'::uuid)=coalesce(p_scope_id,'00000000-0000-0000-0000-000000000000'::uuid)
        and l.event_key=p_event_key and l.created_at >= date_trunc('day',now());
    if v_today_count + v_delta > v_rule.daily_cap then return; end if;
  end if;
  insert into public.reputation_ledger(user_id,scope_type,scope_id,event_key,source_type,source_id,points_delta,dimension,metadata)
  values(p_user_id,p_scope_type,p_scope_id,p_event_key,p_source_type,p_source_id,v_delta,p_dimension,coalesce(p_metadata,'{}'::jsonb))
  on conflict do nothing;
end $$;

create or replace function public.reputation_on_post_insert()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if new.status='active' and new.deleted_at is null and new.shared_post_id is null
     and length(trim(coalesce(new.content,''))) >= 20 then
    perform public.reputation_award_event(new.author_id,'global',null,'meaningful_post','community_post',new.id::text,2,'quality',
      jsonb_build_object('community_id',new.community_id));
    perform public.reputation_award_event(new.author_id,'community',new.community_id,'meaningful_post','community_post',new.id::text,2,'quality','{}'::jsonb);
    perform public.reputation_award_event(new.author_id,'global',null,'community_contribution','community_post',new.id::text,1,'communities',
      jsonb_build_object('community_id',new.community_id));
    perform public.reputation_award_event(new.author_id,'community',new.community_id,'community_contribution','community_post',new.id::text,1,'communities','{}'::jsonb);
    perform public.reputation_award_event(new.author_id,'global',null,'meaningful_activity_day','active_day',to_char(now() at time zone 'utc','YYYY-MM-DD'),1,'consistency','{}'::jsonb);
    perform public.reputation_award_event(new.author_id,'community',new.community_id,'meaningful_activity_day','active_day',to_char(now() at time zone 'utc','YYYY-MM-DD'),1,'consistency','{}'::jsonb);
  end if;
  return new;
end $$;

create or replace function public.reputation_on_comment_insert()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare v_community_id uuid;
begin
  select p.community_id into v_community_id from public.community_posts p
    where p.id=new.post_id and p.status='active' and p.deleted_at is null;
  if v_community_id is not null and length(trim(coalesce(new.content,''))) >= 20 then
    perform public.reputation_award_event(new.author_id,'global',null,'constructive_comment','community_comment',new.id::text,1,'quality',
      jsonb_build_object('community_id',v_community_id));
    perform public.reputation_award_event(new.author_id,'community',v_community_id,'constructive_comment','community_comment',new.id::text,1,'quality','{}'::jsonb);
    perform public.reputation_award_event(new.author_id,'global',null,'community_contribution','community_comment',new.id::text,1,'communities',
      jsonb_build_object('community_id',v_community_id));
    perform public.reputation_award_event(new.author_id,'community',v_community_id,'community_contribution','community_comment',new.id::text,1,'communities','{}'::jsonb);
    perform public.reputation_award_event(new.author_id,'global',null,'meaningful_activity_day','active_day',to_char(now() at time zone 'utc','YYYY-MM-DD'),1,'consistency','{}'::jsonb);
    perform public.reputation_award_event(new.author_id,'community',v_community_id,'meaningful_activity_day','active_day',to_char(now() at time zone 'utc','YYYY-MM-DD'),1,'consistency','{}'::jsonb);
  end if;
  return new;
end $$;

create or replace function public.reputation_on_post_reaction()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare v_post public.community_posts;
begin
  if tg_op='DELETE' then
    select * into v_post from public.community_posts where id=old.post_id;
    if found and old.reaction='like' and v_post.author_id<>old.user_id then
      perform public.reputation_award_event(v_post.author_id,'global',null,'post_positive_reaction_received','post_reaction_reversal',old.post_id::text||':'||old.user_id::text,-1,'recognition','{"reason":"reaction_removed"}'::jsonb);
      perform public.reputation_award_event(v_post.author_id,'community',v_post.community_id,'post_positive_reaction_received','post_reaction',old.post_id::text||':'||old.user_id::text,-1,'recognition','{"reason":"reaction_removed"}'::jsonb);
    end if;
    return old;
  end if;
  select * into v_post from public.community_posts where id=new.post_id;
  if not found or v_post.author_id=new.user_id then return new; end if;
  if new.reaction='like' and (tg_op='INSERT' or old.reaction is distinct from new.reaction) then
    perform public.reputation_award_event(v_post.author_id,'global',null,'post_positive_reaction_received','post_reaction',new.post_id::text||':'||new.user_id::text,1,'recognition',
      jsonb_build_object('reactor_id',new.user_id,'community_id',v_post.community_id));
    perform public.reputation_award_event(v_post.author_id,'community',v_post.community_id,'post_positive_reaction_received','post_reaction',new.post_id::text||':'||new.user_id::text,1,'recognition',
      jsonb_build_object('reactor_id',new.user_id));
  elsif tg_op='UPDATE' and old.reaction='like' and new.reaction is distinct from 'like' then
    perform public.reputation_award_event(v_post.author_id,'global',null,'post_positive_reaction_received','post_reaction_reversal',new.post_id::text||':'||new.user_id::text,-1,'recognition','{"reason":"reaction_changed"}'::jsonb);
    perform public.reputation_award_event(v_post.author_id,'community',v_post.community_id,'post_positive_reaction_received','post_reaction',new.post_id::text||':'||new.user_id::text,-1,'recognition','{"reason":"reaction_changed"}'::jsonb);
  end if;
  return new;
end $$;

create or replace function public.reputation_on_comment_reaction()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare v_comment public.community_post_comments; v_community_id uuid;
begin
  if tg_op='DELETE' then
    select c.* into v_comment from public.community_post_comments c where c.id=old.comment_id;
    if found and old.reaction='like' and v_comment.author_id<>old.user_id then
      select p.community_id into v_community_id from public.community_posts p where p.id=v_comment.post_id;
      perform public.reputation_award_event(v_comment.author_id,'global',null,'comment_positive_reaction_received','comment_reaction_reversal',old.comment_id::text||':'||old.user_id::text,-1,'recognition','{"reason":"reaction_removed"}'::jsonb);
      if v_community_id is not null then perform public.reputation_award_event(v_comment.author_id,'community',v_community_id,'comment_positive_reaction_received','comment_reaction',old.comment_id::text||':'||old.user_id::text,-1,'recognition','{"reason":"reaction_removed"}'::jsonb); end if;
    end if;
    return old;
  end if;
  select c.* into v_comment from public.community_post_comments c where c.id=new.comment_id;
  if not found or v_comment.author_id=new.user_id then return new; end if;
  select p.community_id into v_community_id from public.community_posts p where p.id=v_comment.post_id;
  if new.reaction='like' and (tg_op='INSERT' or old.reaction is distinct from new.reaction) then
    perform public.reputation_award_event(v_comment.author_id,'global',null,'comment_positive_reaction_received','comment_reaction',new.comment_id::text||':'||new.user_id::text,1,'recognition',
      jsonb_build_object('reactor_id',new.user_id,'community_id',v_community_id));
    if v_community_id is not null then perform public.reputation_award_event(v_comment.author_id,'community',v_community_id,'comment_positive_reaction_received','comment_reaction',new.comment_id::text||':'||new.user_id::text,1,'recognition','{}'::jsonb); end if;
  elsif tg_op='UPDATE' and old.reaction='like' and new.reaction is distinct from 'like' then
    perform public.reputation_award_event(v_comment.author_id,'global',null,'comment_positive_reaction_received','comment_reaction_reversal',new.comment_id::text||':'||new.user_id::text,-1,'recognition','{"reason":"reaction_changed"}'::jsonb);
    if v_community_id is not null then perform public.reputation_award_event(v_comment.author_id,'community',v_community_id,'comment_positive_reaction_received','comment_reaction',new.comment_id::text||':'||new.user_id::text,-1,'recognition','{"reason":"reaction_changed"}'::jsonb); end if;
  end if;
  return new;
end $$;

drop trigger if exists reputation_post_insert on public.community_posts;
create trigger reputation_post_insert after insert on public.community_posts
for each row execute function public.reputation_on_post_insert();
drop trigger if exists reputation_comment_insert on public.community_post_comments;
create trigger reputation_comment_insert after insert on public.community_post_comments
for each row execute function public.reputation_on_comment_insert();
drop trigger if exists reputation_post_reaction on public.community_post_reactions;
create trigger reputation_post_reaction after insert or update or delete on public.community_post_reactions
for each row execute function public.reputation_on_post_reaction();
drop trigger if exists reputation_comment_reaction on public.community_comment_reactions;
create trigger reputation_comment_reaction after insert or update or delete on public.community_comment_reactions
for each row execute function public.reputation_on_comment_reaction();

create or replace function public.get_user_reputation(p_user_id uuid default null,p_community_id uuid default null)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_me uuid := auth.uid(); v_target uuid; v_weights jsonb := '{}'::jsonb; v_decay jsonb := '{}'::jsonb;
  v_quality numeric:=0; v_recognition numeric:=0; v_consistency numeric:=0; v_communities numeric:=0; v_trust numeric:=0;
  v_quality_k numeric:=30; v_recognition_k numeric:=40; v_consistency_k numeric:=45; v_communities_k numeric:=24;
  v_weight_quality numeric:=0.30; v_weight_recognition numeric:=0.25; v_weight_consistency numeric:=0.20; v_weight_communities numeric:=0.15; v_weight_trust numeric:=0.10;
  v_q numeric:=0; v_r numeric:=0; v_c numeric:=0; v_n numeric:=0; v_f numeric:=0; v_total numeric:=0;
  v_last timestamptz; v_grace integer:=30; v_decay_rate numeric:=1; v_inactive_weeks numeric:=0; v_factor numeric:=1;
  v_blocked boolean:=false; v_visibility text:='public'; v_connected boolean:=false; v_following boolean:=false;
  v_status text; v_deleted timestamptz; v_result jsonb;
begin
  if v_me is null then raise exception 'not_authenticated' using errcode='28000'; end if;
  v_target:=coalesce(p_user_id,v_me);
  select lower(coalesce(up.account_status,'active')),up.deleted_at into v_status,v_deleted
    from public.user_profiles up where up.user_id=v_target;
  if not found or v_deleted is not null or v_status <> 'active' then raise exception 'profile_unavailable' using errcode='42501'; end if;
  if v_target<>v_me then
    select lower(coalesce(upv.profile_visibility,'public')) into v_visibility from public.user_privacy upv where upv.user_id=v_target;
    select exists(select 1 from public.blocage_utilisateur b where b.statut and
      ((b.bloqueur_id=v_me and b.bloque_id=v_target) or (b.bloqueur_id=v_target and b.bloque_id=v_me))
      and (b.bloque_jusquau is null or b.bloque_jusquau>now())) into v_blocked;
    if v_blocked then raise exception 'profile_blocked' using errcode='42501'; end if;
    select exists(select 1 from public.friendships f where f.user_a_id=least(v_me,v_target) and f.user_b_id=greatest(v_me,v_target)) into v_connected;
    select exists(select 1 from public.user_follows f where f.follower_id=v_me and f.followed_id=v_target) into v_following;
    if p_community_id is null and coalesce(v_visibility,'public') in ('private','prive','privé') and not v_connected and not v_following then
      raise exception 'profile_private' using errcode='42501';
    end if;
  end if;
  if p_community_id is not null and not exists(select 1 from public.community_members cm where cm.community_id=p_community_id and cm.user_id=v_target) then
    -- Community reputation is visible to community members only.
    if not exists(select 1 from public.community_members cm where cm.community_id=p_community_id and cm.user_id=v_me) then
      raise exception 'community_reputation_private' using errcode='42501';
    end if;
  end if;

  select config into v_decay from public.reputation_scoring_rules where rule_key='weekly_inactivity_decay';
  v_grace:=greatest(0,coalesce((v_decay->>'grace_days')::integer,30));
  v_decay_rate:=greatest(0,least(20,coalesce((v_decay->>'rate_percent')::numeric,1)));
  select
    coalesce(sum(l.points_delta) filter(where l.dimension='quality'),0),
    coalesce(sum(l.points_delta) filter(where l.dimension='recognition'),0),
    coalesce(sum(l.points_delta) filter(where l.dimension='consistency'),0),
    coalesce(sum(l.points_delta) filter(where l.dimension='communities'),0),
    max(l.created_at) filter (where l.points_delta > 0 and l.event_key in ('meaningful_post','constructive_comment','meaningful_activity_day','community_contribution'))
  into v_q,v_r,v_c,v_n,v_last
  from public.reputation_ledger l
  where l.user_id=v_target
    and ((p_community_id is null and l.scope_type='global') or (p_community_id is not null and l.scope_type='community' and l.scope_id=p_community_id));

  select
    coalesce(max((r.config->>'dimension_weight')::numeric) filter(where r.config->>'dimension'='quality'),0.30),
    coalesce(max((r.config->>'dimension_weight')::numeric) filter(where r.config->>'dimension'='recognition'),0.25),
    coalesce(max((r.config->>'dimension_weight')::numeric) filter(where r.config->>'dimension'='consistency'),0.20),
    coalesce(max((r.config->>'dimension_weight')::numeric) filter(where r.config->>'dimension'='communities'),0.15),
    coalesce(max((r.config->>'dimension_weight')::numeric) filter(where r.config->>'dimension'='trust'),0.10),
    coalesce(max((r.config->>'saturation_k')::numeric) filter(where r.config->>'dimension'='quality'),30),
    coalesce(max((r.config->>'saturation_k')::numeric) filter(where r.config->>'dimension'='recognition'),40),
    coalesce(max((r.config->>'saturation_k')::numeric) filter(where r.config->>'dimension'='consistency'),45),
    coalesce(max((r.config->>'saturation_k')::numeric) filter(where r.config->>'dimension'='communities'),24)
  into v_weight_quality,v_weight_recognition,v_weight_consistency,v_weight_communities,v_weight_trust,v_quality_k,v_recognition_k,v_consistency_k,v_communities_k
  from public.reputation_scoring_rules r where r.enabled;

  -- Saturation: more activity keeps helping, but each additional action has less impact.
  v_quality:=5*(1-exp(-greatest(0,v_q)/greatest(1,v_quality_k)));
  v_recognition:=5*(1-exp(-greatest(0,v_r)/greatest(1,v_recognition_k)));
  v_consistency:=5*(1-exp(-greatest(0,v_c)/greatest(1,v_consistency_k)));
  v_communities:=5*(1-exp(-greatest(0,v_n)/greatest(1,v_communities_k)));
  -- Trust is neutral only after a meaningful history exists; new accounts do not start with a high score.
  select coalesce(sum(abs(l.points_delta)),0) into v_f
    from public.reputation_ledger l
    where l.user_id=v_target and l.dimension='trust' and l.points_delta<0
      and ((p_community_id is null and l.scope_type='global') or (p_community_id is not null and l.scope_type='community' and l.scope_id=p_community_id));
  v_trust:=greatest(
    0,
    5*(1-exp(-(greatest(0,v_q)+greatest(0,v_r)+greatest(0,v_c)+greatest(0,v_n))/60.0))
      - least(5,v_f)
  );
  if v_last is null then v_factor:=0;
  elsif now()-v_last > make_interval(days=>v_grace) then
    v_inactive_weeks:=extract(epoch from (now()-v_last-make_interval(days=>v_grace)))/604800.0;
    v_factor:=greatest(0.50,exp(-ln(1.0+v_decay_rate/100.0)*v_inactive_weeks));
  end if;
  v_total:=greatest(0,least(5,(
      (v_quality*v_weight_quality+v_recognition*v_weight_recognition+
      v_consistency*v_weight_consistency+v_communities*v_weight_communities+v_trust*v_weight_trust)
      / greatest(0.01,v_weight_quality+v_weight_recognition+v_weight_consistency+v_weight_communities+v_weight_trust)
    )*v_factor));
  v_result:=jsonb_build_object('user_id',v_target,'community_id',p_community_id,
    'score',round(v_total::numeric,2),'max_score',5.00,'last_meaningful_activity_at',v_last,
    'dimensions',jsonb_build_object('quality',round(v_quality::numeric,2),'recognition',round(v_recognition::numeric,2),
      'consistency',round(v_consistency::numeric,2),'communities',round(v_communities::numeric,2),'trust',round(v_trust::numeric,2)),
    'weights',jsonb_build_object('quality',v_weight_quality,'recognition',v_weight_recognition,'consistency',v_weight_consistency,'communities',v_weight_communities,'trust',v_weight_trust),
    'inactivity_factor',round(v_factor::numeric,4));
  if p_community_id is null then
    insert into public.user_reputation_scores(user_id,score,dimension_scores,last_meaningful_activity_at,calculated_at)
    values(v_target,round(v_total::numeric,2),v_result->'dimensions',v_last,now())
    on conflict(user_id) do update set score=excluded.score,dimension_scores=excluded.dimension_scores,last_meaningful_activity_at=excluded.last_meaningful_activity_at,calculated_at=now();
  else
    insert into public.user_community_reputation(user_id,community_id,points,level,score,dimension_scores,last_meaningful_activity_at,updated_at)
    values(v_target,p_community_id,round(v_total*100)::integer,greatest(1,ceil(v_total)::integer),round(v_total::numeric,2),v_result->'dimensions',v_last,now())
    on conflict(user_id,community_id) do update set points=excluded.points,level=excluded.level,score=excluded.score,dimension_scores=excluded.dimension_scores,last_meaningful_activity_at=excluded.last_meaningful_activity_at,updated_at=now();
  end if;
  return v_result;
end $$;

revoke all on function public.admin_get_reputation_rules() from public, anon, authenticated;
revoke all on function public.admin_update_reputation_rule(text,integer,integer,boolean,jsonb) from public, anon, authenticated;
grant execute on function public.admin_get_reputation_rules() to authenticated;
grant execute on function public.admin_update_reputation_rule(text,integer,integer,boolean,jsonb) to authenticated;
revoke all on function public.reputation_award_event(uuid,text,uuid,text,text,text,integer,text,jsonb) from public, anon, authenticated;
revoke all on function public.reputation_on_post_insert() from public, anon, authenticated;
revoke all on function public.reputation_on_comment_insert() from public, anon, authenticated;
revoke all on function public.reputation_on_post_reaction() from public, anon, authenticated;
revoke all on function public.reputation_on_comment_reaction() from public, anon, authenticated;
revoke all on function public.get_user_reputation(uuid,uuid) from public, anon;
grant execute on function public.get_user_reputation(uuid,uuid) to authenticated;


create or replace function public.admin_apply_reputation_penalty(
  p_user_id uuid,p_scope_type text,p_scope_id uuid,p_source_type text,p_source_id text,p_reason text,p_points integer default 1
) returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_admin_or_above() then raise exception 'Action réservée aux administrateurs' using errcode='42501'; end if;
  if p_points < 1 or p_points > 5 then raise exception 'La pénalité doit être comprise entre 1 et 5'; end if;
  if p_scope_type not in ('global','community') then raise exception 'Portée invalide'; end if;
  if p_scope_type='community' and p_scope_id is null then raise exception 'La communauté est obligatoire'; end if;
  if p_source_id is null or length(trim(p_source_id))=0 or p_reason is null or length(trim(p_reason))<8 then
    raise exception 'La source et un motif explicite sont obligatoires';
  end if;
  perform public.reputation_award_event(p_user_id,p_scope_type,p_scope_id,'confirmed_spam_penalty',
    'moderation:'||p_source_type,p_source_id,-p_points,'trust',
    jsonb_build_object('reason',p_reason,'moderator_id',auth.uid(),'moderation_source',p_source_type));
end $$;

revoke all on function public.admin_apply_reputation_penalty(uuid,text,uuid,text,text,text,integer) from public,anon;
grant execute on function public.admin_apply_reputation_penalty(uuid,text,uuid,text,text,text,integer) to authenticated;


create or replace function public.get_community_member_reputations(p_community_id uuid,p_user_ids uuid[])
returns table(user_id uuid,score numeric)
language plpgsql security definer set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode='28000'; end if;
  if not exists(select 1 from public.community_members cm where cm.community_id=p_community_id and cm.user_id=auth.uid()) then
    raise exception 'community_membership_required' using errcode='42501';
  end if;
  return query
    select requested.user_id,
      coalesce((public.get_user_reputation(requested.user_id,p_community_id)->>'score')::numeric,0)::numeric
    from (select distinct unnest(coalesce(p_user_ids,'{}'::uuid[])) as user_id) requested
    join public.community_members cm on cm.community_id=p_community_id and cm.user_id=requested.user_id;
end $$;
revoke all on function public.get_community_member_reputations(uuid,uuid[]) from public,anon;
grant execute on function public.get_community_member_reputations(uuid,uuid[]) to authenticated;


create or replace function public.reputation_on_post_status_change()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if (new.deleted_at is not null or new.status <> 'active') and old.deleted_at is null and old.status='active' then
    perform public.reputation_award_event(old.author_id,'global',null,'meaningful_post','content_reversal',old.id::text,-2,'quality',
      jsonb_build_object('reason','post_deleted_or_inactive','community_id',old.community_id));
    perform public.reputation_award_event(old.author_id,'community',old.community_id,'meaningful_post','content_reversal',old.id::text,-2,'quality',
      jsonb_build_object('reason','post_deleted_or_inactive'));
    perform public.reputation_award_event(old.author_id,'global',null,'community_contribution','content_reversal',old.id::text,-1,'communities','{"reason":"post_deleted_or_inactive"}'::jsonb);
    perform public.reputation_award_event(old.author_id,'community',old.community_id,'community_contribution','content_reversal',old.id::text,-1,'communities','{"reason":"post_deleted_or_inactive"}'::jsonb);
  end if;
  return new;
end $$;

drop trigger if exists reputation_post_status_change on public.community_posts;
create trigger reputation_post_status_change after update of status,deleted_at on public.community_posts
for each row execute function public.reputation_on_post_status_change();

create or replace function public.reputation_on_comment_delete()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare v_community_id uuid;
begin
  select p.community_id into v_community_id from public.community_posts p where p.id=old.post_id;
  if length(trim(coalesce(old.content,''))) >= 20 then
    perform public.reputation_award_event(old.author_id,'global',null,'constructive_comment','content_reversal',old.id::text,-1,'quality',
      jsonb_build_object('reason','comment_deleted','community_id',v_community_id));
    perform public.reputation_award_event(old.author_id,'global',null,'community_contribution','comment_reversal',old.id::text,-1,'communities','{"reason":"comment_deleted"}'::jsonb);
    if v_community_id is not null then
      perform public.reputation_award_event(old.author_id,'community',v_community_id,'constructive_comment','content_reversal',old.id::text,-1,'quality','{"reason":"comment_deleted"}'::jsonb);
      perform public.reputation_award_event(old.author_id,'community',v_community_id,'community_contribution','comment_reversal',old.id::text,-1,'communities','{"reason":"comment_deleted"}'::jsonb);
    end if;
  end if;
  return old;
end $$;

drop trigger if exists reputation_comment_delete on public.community_post_comments;
create trigger reputation_comment_delete after delete on public.community_post_comments
for each row execute function public.reputation_on_comment_delete();

revoke all on function public.reputation_on_post_status_change() from public,anon,authenticated;
revoke all on function public.reputation_on_comment_delete() from public,anon,authenticated;
