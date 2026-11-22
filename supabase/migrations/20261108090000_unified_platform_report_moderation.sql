-- Unified platform moderation for post, profile, community, story and comment reports.
-- Reserve explicit lifecycle states for platform-level moderation.
alter table public.community_posts drop constraint if exists community_posts_status_check;
alter table public.community_posts add constraint community_posts_status_check
  check (status = any (array['en_attente'::text,'active'::text,'rejected'::text,'deleted'::text,'spam_suspect'::text,'shadowbanned'::text]));
alter table public.communities drop constraint if exists communities_status_check;
alter table public.communities add constraint communities_status_check
  check (status = any (array['active'::text,'pending_deletion'::text,'deleted'::text,'suspended'::text]));

-- A reporter immediately hides their own reported post; moderation actions are audited.
create table if not exists public.admin_content_moderation_actions (
  id uuid primary key default gen_random_uuid(),
  target_type text not null check (target_type in ('post','comment','story','user','profile','community')),
  target_id uuid not null,
  author_id uuid references auth.users(id) on delete set null,
  admin_id uuid references public.administrateur_profil(id) on delete set null,
  action text not null check (action in ('delete','shadowban','suspend_user','suspend_community')),
  reason text,
  created_at timestamptz not null default now()
);
create index if not exists idx_admin_content_moderation_target
  on public.admin_content_moderation_actions(target_type,target_id,created_at desc);
alter table public.admin_content_moderation_actions enable row level security;
revoke all on public.admin_content_moderation_actions from public, anon, authenticated;

-- A report of a post also hides it for the reporting user, in the same transaction.
create or replace function public.report_content(
  p_target_type text,
  p_target_id uuid,
  p_reason_id uuid,
  p_description text default null
)
returns public.signalement
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_type public.user_activity_target_type;
  v_community_id uuid;
  v_owner uuid;
  v_allow boolean;
  v_visible boolean := false;
  v_post_author uuid;
  v_audience text;
  v_pstatus text;
  v_row public.signalement;
  v_desc text := nullif(btrim(p_description), '');
  v_story public.stories;
  v_report_community_id uuid;
begin
  if v_uid is null then raise exception 'Utilisateur non authentifié'; end if;
  if p_target_type is null or p_target_type not in ('post','comment','story','community') then
    raise exception 'Type de signalement invalide';
  end if;
  v_type := p_target_type::public.user_activity_target_type;
  if not exists(select 1 from public.signalement_raison r where r.id=p_reason_id and r.est_actif) then
    raise exception 'Motif de signalement invalide';
  end if;
  if char_length(coalesce(v_desc,'')) > 1000 then raise exception 'Description trop longue (1000 caractères maximum)'; end if;
  if (select count(*) from public.signalement s where s.reporter_id=v_uid and s.created_at>now()-interval '1 hour') >= 20 then
    raise exception 'Trop de signalements envoyés, réessayez plus tard';
  end if;

  if p_target_type='post' then
    select cp.community_id,cp.author_id,cp.audience,cp.status
      into v_community_id,v_owner,v_audience,v_pstatus
    from public.community_posts cp where cp.id=p_target_id;
    if found and v_pstatus='active' then
      v_visible:=public.can_view_post_row(v_community_id,v_owner,v_audience)
        and not private.users_blocked(v_uid,v_owner);
    end if;
  elsif p_target_type='comment' then
    select cp.community_id,c.author_id,cp.audience,cp.status,cp.author_id
      into v_community_id,v_owner,v_audience,v_pstatus,v_post_author
    from public.community_post_comments c
    join public.community_posts cp on cp.id=c.post_id
    where c.id=p_target_id;
    if found and v_pstatus='active' then
      v_visible:=public.can_view_post_row(v_community_id,v_post_author,v_audience)
        and not private.users_blocked(v_uid,v_owner);
    end if;
  elsif p_target_type='story' then
    select * into v_story from public.stories s
    where s.id=p_target_id and s.status='active' and s.expires_at>now();
    if found then
      v_owner:=v_story.author_id;
      v_visible:=public.can_view_story_row(v_story.author_id,v_story.audience)
        and not private.users_blocked(v_uid,v_story.author_id);
    end if;
  else
    select c.id,c.creator_id into v_community_id,v_owner
    from public.communities c where c.id=p_target_id and c.status='active';
    if found then v_visible:=public.can_view_community(v_community_id); end if;
  end if;

  if not coalesce(v_visible,false) then raise exception 'Contenu introuvable'; end if;
  if v_owner=v_uid then raise exception 'Vous ne pouvez pas signaler votre propre contenu'; end if;

  if p_target_type in ('post','comment') then
    v_report_community_id:=v_community_id;
    if v_community_id is not null then
      select s.allow_reports into v_allow from public.community_settings s where s.community_id=v_community_id;
      if coalesce(v_allow,true)=false then raise exception 'Les signalements sont désactivés dans cette communauté'; end if;
    end if;
  else
    v_report_community_id:=null;
  end if;

  select * into v_row from public.signalement s
  where s.reporter_id=v_uid and s.target_type=v_type and s.target_id=p_target_id
    and s.community_id is not distinct from v_report_community_id
    and s.status in ('en_attente','en_cours')
  order by s.created_at desc limit 1;

  if found then
    if p_target_type='post' then
      insert into public.post_hides(user_id,post_id) values(v_uid,p_target_id) on conflict do nothing;
    end if;
    return v_row;
  end if;

  insert into public.signalement(reporter_id,target_type,target_id,reason_id,description,community_id)
  values(v_uid,v_type,p_target_id,p_reason_id,v_desc,v_report_community_id)
  returning * into v_row;

  if p_target_type='post' then
    insert into public.post_hides(user_id,post_id) values(v_uid,p_target_id) on conflict do nothing;
  end if;
  return v_row;
end;
$function$;

-- Platform queue: complete review payloads for posts, profiles and communities.
create or replace function public.get_platform_reports(
  p_status text default 'open',
  p_limit integer default 20,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_limit integer:=least(greatest(coalesce(p_limit,20),1),50);
  v_offset integer:=greatest(coalesce(p_offset,0),0);
  v_statuses text[];
  v_items jsonb;
  v_profile_items jsonb;
  v_has_more boolean;
begin
  if auth.uid() is null then raise exception 'Utilisateur non authentifié'; end if;
  if not coalesce(public.is_admin_or_above(),false) then
    raise exception 'Action réservée aux administrateurs de la plateforme';
  end if;

  v_statuses:=case p_status
    when 'handled' then array['resolu','rejete']
    when 'all' then array['en_attente','en_cours','resolu','rejete']
    else array['en_attente','en_cours'] end;

  with rows as (
    select s.* from public.signalement s
    where s.status::text=any(v_statuses)
      and s.target_type::text in ('post','comment','story','user','profile','community')
      and (s.target_type::text in ('post','community','profile')
           or s.community_id is null or s.escalated_at is not null)
    order by s.created_at desc,s.id desc
    offset v_offset limit v_limit+1
  ), numbered as (
    select r.*,row_number() over(order by r.created_at desc,r.id desc) rn from rows r
  )
  select
    coalesce(jsonb_agg(jsonb_build_object(
      'id',n.id,'source','signalement','target_type',n.target_type::text,
      'target_id',n.target_id,'status',n.status::text,'created_at',n.created_at,
      'description',n.description,'escalated',n.escalated_at is not null,
      'from_community',n.community_id is not null,'community_id',n.community_id,
      'community',(select jsonb_build_object('id',c.id,'name',c.name) from public.communities c where c.id=n.community_id),
      'reason',(select jsonb_build_object('id',r.id,'code',r.code,'nom',r.nom) from public.signalement_raison r where r.id=n.reason_id),
      'reporter',(select jsonb_build_object('user_id',up.user_id,'username',up.username,'first_name',up.first_name,
                   'last_name',up.last_name,'photo_url',up.photo_url)
                  from public.user_profiles up where up.user_id=n.reporter_id),
      'reports_count',(select count(*) from public.signalement s2
                       where s2.target_type=n.target_type and s2.target_id=n.target_id
                         and s2.community_id is not distinct from n.community_id
                         and s2.status in ('en_attente','en_cours')),
      'target',case n.target_type::text
        when 'post' then (
          select jsonb_build_object(
            'id',cp.id,'content',cp.content,'status',cp.status,'community_id',cp.community_id,
            'created_at',cp.created_at,'updated_at',cp.updated_at,'moderation_reason',cp.moderation_reason,
            'photo',cp.photo,'photos',to_jsonb(cp.photos),'media',cp.media,'videos',cp.videos,
            'video_url',cp.video_url,'video_thumbnail_url',cp.video_thumbnail_url,
            'shared_post_snapshot',cp.shared_post_snapshot,
            'author',jsonb_build_object('user_id',a.user_id,'username',a.username,'first_name',a.first_name,
              'last_name',a.last_name,'photo_url',a.photo_url,'bio',a.bio,'account_status',a.account_status))
          from public.community_posts cp
          left join public.user_profiles a on a.user_id=cp.author_id
          where cp.id=n.target_id)
        when 'comment' then (
          select jsonb_build_object('id',c.id,'post_id',c.post_id,'content',c.content,'created_at',c.created_at,
            'author',jsonb_build_object('user_id',a.user_id,'username',a.username,'first_name',a.first_name,
              'last_name',a.last_name,'photo_url',a.photo_url),
            'post',jsonb_build_object('id',cp.id,'content',cp.content,'community_id',cp.community_id))
          from public.community_post_comments c
          join public.community_posts cp on cp.id=c.post_id
          left join public.user_profiles a on a.user_id=c.author_id
          where c.id=n.target_id)
        when 'story' then (
          select jsonb_build_object('id',st.id,'kind',st.kind,'content',st.content,'image_url',st.image_url,
            'thumbnail_url',st.thumbnail_url,'created_at',st.created_at,'expires_at',st.expires_at,
            'author',jsonb_build_object('user_id',a.user_id,'username',a.username,'first_name',a.first_name,
              'last_name',a.last_name,'photo_url',a.photo_url))
          from public.stories st
          left join public.user_profiles a on a.user_id=st.author_id
          where st.id=n.target_id)
        when 'user' then (
          select jsonb_build_object('user_id',up.user_id,'username',up.username,'first_name',up.first_name,
            'last_name',up.last_name,'photo_url',up.photo_url,'cover_url',up.cover_url,'bio',up.bio,
            'account_status',up.account_status,'created_at',up.created_at,
            'reputation_score',(select urs.score from public.user_reputation_scores urs where urs.user_id=up.user_id))
          from public.user_profiles up where up.user_id=n.target_id)
        when 'profile' then (
          select jsonb_build_object('user_id',up.user_id,'username',up.username,'first_name',up.first_name,
            'last_name',up.last_name,'photo_url',up.photo_url,'cover_url',up.cover_url,'bio',up.bio,
            'account_status',up.account_status,'created_at',up.created_at,
            'reputation_score',(select urs.score from public.user_reputation_scores urs where urs.user_id=up.user_id))
          from public.user_profiles up where up.user_id=n.target_id)
        when 'community' then (
          select jsonb_build_object('id',cm.id,'name',cm.name,'slug',cm.slug,'description',cm.description,
            'slogan',cm.slogan,'photo_profile',cm.photo_profile,'photo_cover',cm.photo_cover,
            'visibility',cm.visibility,'status',cm.status,'created_at',cm.created_at,
            'creator',jsonb_build_object('user_id',up.user_id,'username',up.username,
              'first_name',up.first_name,'last_name',up.last_name,'photo_url',up.photo_url))
          from public.communities cm
          left join public.user_profiles up on up.user_id=cm.creator_id
          where cm.id=n.target_id)
      end
    ) order by n.created_at desc,n.id desc) filter(where n.rn<=v_limit),'[]'::jsonb),
    count(*)>v_limit
  into v_items,v_has_more from numbered n;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',upr.id,'source','external_profile','target_type','user','target_id',upr.reported_user_id,
    'status',case upr.status when 'pending' then 'en_attente' when 'reviewing' then 'en_cours'
      when 'resolved' then 'resolu' when 'dismissed' then 'rejete' else upr.status end,
    'created_at',upr.created_at,'description',upr.details,'escalated',false,
    'from_community',false,'community_id',null,'community',null,
    'reason',jsonb_build_object('code',upr.reason,'nom',replace(upr.reason,'_',' ')),
    'reporter',(select jsonb_build_object('user_id',up.user_id,'username',up.username,'first_name',up.first_name,
      'last_name',up.last_name,'photo_url',up.photo_url) from public.user_profiles up where up.user_id=upr.reporter_user_id),
    'reports_count',(select count(*) from public.user_profile_reports upr2
      where upr2.reported_user_id=upr.reported_user_id and upr2.status in ('pending','reviewing')),
    'target',(select jsonb_build_object('user_id',up.user_id,'username',up.username,'first_name',up.first_name,
      'last_name',up.last_name,'photo_url',up.photo_url,'cover_url',up.cover_url,'bio',up.bio,
      'account_status',up.account_status,'created_at',up.created_at,
      'reputation_score',(select urs.score from public.user_reputation_scores urs where urs.user_id=up.user_id))
      from public.user_profiles up where up.user_id=upr.reported_user_id)
  ) order by upr.created_at desc),'[]'::jsonb)
  into v_profile_items
  from public.user_profile_reports upr
  where case p_status
    when 'handled' then upr.status in ('resolved','dismissed')
    when 'all' then upr.status in ('pending','reviewing','resolved','dismissed')
    else upr.status in ('pending','reviewing') end;

  return jsonb_build_object('items',v_items,'profile_items',v_profile_items,'has_more',coalesce(v_has_more,false));
end;
$function$;

-- Resolve all open reports for the same target and audit each platform action.
create or replace function public.resolve_platform_report(
  p_report_id uuid,
  p_action text,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid uuid:=auth.uid();
  v_rep public.signalement;
  v_note text:=nullif(btrim(p_note),'');
  v_new public.signalement_status;
  v_n integer;
  v_admin uuid;
  v_c record;
  v_profile_target uuid;
  v_community public.communities;
begin
  if v_uid is null then raise exception 'Utilisateur non authentifié'; end if;
  if not coalesce(public.is_admin_or_above(),false) then
    raise exception 'Action réservée aux administrateurs de la plateforme';
  end if;
  if p_action is null or p_action not in ('dismiss','remove_content','shadowban','suspend_user','suspend_community') then
    raise exception 'Action invalide';
  end if;
  if char_length(coalesce(v_note,''))>1000 then raise exception 'Note trop longue (1000 caractères maximum)'; end if;

  if p_action='dismiss' and not exists(select 1 from public.admin_permissions_for_current_user() p where p.permission='reports.reject') then
    raise exception 'Votre rôle ne permet pas de rejeter des signalements';
  end if;
  if p_action<>'dismiss' and not exists(select 1 from public.admin_permissions_for_current_user() p where p.permission='reports.resolve') then
    raise exception 'Votre rôle ne permet pas de résoudre des signalements';
  end if;
  if p_action='remove_content' and not exists(select 1 from public.admin_permissions_for_current_user() p where p.permission='posts.delete') then
    raise exception 'Votre rôle ne permet pas de supprimer du contenu';
  end if;
  if p_action='shadowban' and not exists(select 1 from public.admin_permissions_for_current_user() p where p.permission='posts.hide') then
    raise exception 'Votre rôle ne permet pas de masquer des publications';
  end if;
  if p_action='suspend_user' and not exists(select 1 from public.admin_permissions_for_current_user() p where p.permission='users.suspend') then
    raise exception 'Votre rôle ne permet pas de suspendre des comptes';
  end if;
  if p_action='suspend_community' and not exists(select 1 from public.admin_permissions_for_current_user() p where p.permission='communities.suspend') then
    raise exception 'Votre rôle ne permet pas de suspendre des communautés';
  end if;

  select id into v_admin from public.administrateur_profil where auth_id=v_uid and actif limit 1;

  -- Direct profile reports use their dedicated table.
  if exists(select 1 from public.user_profile_reports where id=p_report_id) then
    if p_action not in ('dismiss','suspend_user') then
      raise exception 'Action non disponible pour un signalement de profil';
    end if;
    select reported_user_id into v_profile_target from public.user_profile_reports where id=p_report_id for update;
    update public.user_profile_reports
      set status=case when p_action='dismiss' then 'dismissed' else 'resolved' end
      where reported_user_id=v_profile_target and status in ('pending','reviewing');
    get diagnostics v_n=row_count;
    if v_n=0 then raise exception 'Ce signalement de profil a déjà été traité'; end if;
    if p_action='suspend_user' then
      update public.user_profiles set account_status='suspended',updated_at=now()
      where user_id=v_profile_target and deleted_at is null;
      get diagnostics v_n=row_count;
      if v_n=0 then raise exception 'Utilisateur introuvable ou déjà supprimé'; end if;
      insert into public.admin_user_moderation_actions(user_id,admin_id,action,reason)
      values(v_profile_target,v_admin,'suspend',coalesce(v_note,'Suite à un signalement de profil'));
      insert into public.admin_content_moderation_actions(target_type,target_id,author_id,admin_id,action,reason)
      values('user',v_profile_target,v_profile_target,v_admin,'suspend_user',v_note);
    end if;
    return jsonb_build_object('updated',v_n,'status',case when p_action='dismiss' then 'dismissed' else 'resolved' end);
  end if;

  select * into v_rep from public.signalement where id=p_report_id for update;
  if not found then raise exception 'Signalement introuvable'; end if;
  if v_rep.status::text not in ('en_attente','en_cours') then raise exception 'Ce signalement a déjà été traité'; end if;

  if p_action='suspend_user' then
    if v_rep.target_type::text not in ('user','profile')
       or (v_rep.community_id is not null and v_rep.escalated_at is null) then
      raise exception 'La suspension de ce profil nécessite un signalement de profil direct ou escaladé';
    end if;
    update public.user_profiles set account_status='suspended',updated_at=now()
      where user_id=v_rep.target_id and deleted_at is null;
    get diagnostics v_n=row_count;
    if v_n=0 then raise exception 'Utilisateur introuvable ou déjà supprimé'; end if;
    insert into public.admin_user_moderation_actions(user_id,admin_id,action,reason)
      values(v_rep.target_id,v_admin,'suspend',coalesce(v_note,'Suite à un signalement'));
    insert into public.admin_content_moderation_actions(target_type,target_id,author_id,admin_id,action,reason)
      values('user',v_rep.target_id,v_rep.target_id,v_admin,'suspend_user',v_note);
    v_new:='resolu';

  elsif p_action='suspend_community' then
    if v_rep.target_type::text<>'community' then raise exception 'Ce signalement ne concerne pas une communauté'; end if;
    update public.communities set status='suspended',updated_at=now()
      where id=v_rep.target_id and status='active'
      returning * into v_community;
    if not found then raise exception 'Communauté introuvable ou déjà suspendue'; end if;
    insert into public.admin_content_moderation_actions(target_type,target_id,author_id,admin_id,action,reason)
      values('community',v_rep.target_id,v_community.creator_id,v_admin,'suspend_community',v_note);
    v_new:='resolu';

  elsif p_action='remove_content' then
    if v_rep.target_type::text='post' then
      select author_id,community_id,content into v_c
      from public.community_posts where id=v_rep.target_id for update;
      if not found then raise exception 'Publication introuvable ou déjà supprimée'; end if;
      -- Physical deletion does not fire the UPDATE reputation trigger: reverse the
      -- original post awards explicitly, using the same idempotency source as the trigger.
      perform public.reputation_award_event(v_c.author_id,'global',null,'meaningful_post','content_reversal',
        v_rep.target_id::text,-2,'quality',jsonb_build_object('reason','post_deleted_or_inactive','community_id',v_c.community_id));
      perform public.reputation_award_event(v_c.author_id,'community',v_c.community_id,'meaningful_post','content_reversal',
        v_rep.target_id::text,-2,'quality',jsonb_build_object('reason','post_deleted_or_inactive'));
      perform public.reputation_award_event(v_c.author_id,'global',null,'community_contribution','content_reversal',
        v_rep.target_id::text,-1,'communities','{"reason":"post_deleted_or_inactive"}'::jsonb);
      perform public.reputation_award_event(v_c.author_id,'community',v_c.community_id,'community_contribution','content_reversal',
        v_rep.target_id::text,-1,'communities','{"reason":"post_deleted_or_inactive"}'::jsonb);
      perform public.delete_post(v_rep.target_id,v_note);
      insert into public.admin_content_moderation_actions(target_type,target_id,author_id,admin_id,action,reason)
        values('post',v_rep.target_id,v_c.author_id,v_admin,'delete',v_note);
    elsif v_rep.target_type::text='story' then
      perform public.delete_story(v_rep.target_id,v_note);
      insert into public.admin_content_moderation_actions(target_type,target_id,admin_id,action,reason)
        values('story',v_rep.target_id,v_admin,'delete',v_note);
    elsif v_rep.target_type::text='comment' then
      select c.author_id,c.post_id,cp.community_id,left(coalesce(c.content,''),200) excerpt
        into v_c from public.community_post_comments c
        join public.community_posts cp on cp.id=c.post_id where c.id=v_rep.target_id;
      if not found then raise exception 'Commentaire introuvable ou déjà supprimé'; end if;
      delete from public.community_post_comments where id=v_rep.target_id;
      insert into public.content_removals(content_type,content_id,community_id,author_id,removed_by,removed_by_role,reason,excerpt)
        values('comment',v_rep.target_id,v_c.community_id,v_c.author_id,v_uid,'platform_admin',v_note,v_c.excerpt);
      insert into public.admin_content_moderation_actions(target_type,target_id,author_id,admin_id,action,reason)
        values('comment',v_rep.target_id,v_c.author_id,v_admin,'delete',v_note);
      perform private.notify_community_user(v_c.author_id,'comment_removed',v_uid,
        jsonb_build_object('post_id',v_c.post_id,'community_id',v_c.community_id,'actor_id',v_uid,'raison',coalesce(v_note,'')),
        'Commentaire supprimé','Votre commentaire a été supprimé par la modération.');
    else
      raise exception 'Suppression non disponible pour ce type de signalement';
    end if;
    v_new:='resolu';

  elsif p_action='shadowban' then
    if v_rep.target_type::text<>'post' then raise exception 'Le shadowban est uniquement disponible pour une publication'; end if;
    update public.community_posts
      set status='shadowbanned',moderation_reason=coalesce(v_note,'Masquée par la modération'),updated_at=now()
      where id=v_rep.target_id and status='active'
      returning author_id,community_id into v_c;
    if not found then raise exception 'Publication introuvable ou déjà modérée'; end if;
    insert into public.admin_content_moderation_actions(target_type,target_id,author_id,admin_id,action,reason)
      values('post',v_rep.target_id,v_c.author_id,v_admin,'shadowban',v_note);
    perform private.notify_community_user(v_c.author_id,'post_shadowbanned',v_uid,
      jsonb_build_object('post_id',v_rep.target_id,'community_id',v_c.community_id,'actor_id',v_uid,'raison',coalesce(v_note,'')),
      'Publication masquée','Votre publication a été masquée par la modération.');
    v_new:='resolu';
  else
    v_new:='rejete';
  end if;

  update public.signalement
    set status=v_new,reviewed_at=now(),reviewed_by=v_admin
    where target_type=v_rep.target_type and target_id=v_rep.target_id
      and community_id is not distinct from v_rep.community_id
      and status in ('en_attente','en_cours');
  get diagnostics v_n=row_count;
  return jsonb_build_object('updated',v_n,'status',v_new::text);
end;
$function$;

-- A reporter must not see a post again when opening the community-specific feed.
create or replace function public.get_community_feed(
  p_community_id uuid,
  p_limit integer default 20,
  p_cursor text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_user_id uuid:=auth.uid();
  v_limit int:=greatest(1,least(coalesce(p_limit,20),50));
  v_score numeric;
  v_created timestamptz;
  v_id uuid;
  v_items jsonb;
  v_next text;
begin
  if v_user_id is null then raise exception 'Authentication required'; end if;
  if not public.can_view_community(p_community_id) then raise exception 'Community is not accessible'; end if;
  if p_cursor is not null and length(trim(p_cursor))>0 then
    begin
      v_score:=split_part(p_cursor,'|',1)::numeric;
      v_created:=split_part(p_cursor,'|',2)::timestamptz;
      v_id:=split_part(p_cursor,'|',3)::uuid;
    exception when others then raise exception 'Invalid feed cursor'; end;
  end if;

  with pc as (
    select p.*,
      coalesce((select count(*) from public.community_post_comments c where c.post_id=p.id),0)::bigint comments_count,
      coalesce((select count(*) from public.community_post_reactions r where r.post_id=p.id and r.reaction='like'),0)::bigint likes_count,
      coalesce((select count(*) from public.community_post_reactions r where r.post_id=p.id and r.reaction='dislike'),0)::bigint dislikes_count,
      (select r.reaction from public.community_post_reactions r where r.post_id=p.id and r.user_id=v_user_id) viewer_reaction,
      coalesce((select jsonb_agg(jsonb_build_object('id',h.id,'name',h.name) order by h.name)
        from public.community_post_hashtags ph join public.hashtags h on h.id=ph.hashtag_id where ph.post_id=p.id),'[]'::jsonb) hashtags,
      coalesce((select jsonb_agg(jsonb_build_object('user_id',mu.user_id,'username',mup.username,'first_name',mup.first_name,
        'last_name',mup.last_name,'photo_url',mup.photo_url,'is_certified',exists(select 1 from public.user_certifications uc
          where uc.user_id=mup.user_id and uc.status::text='active' and uc.issued_at<=now()
            and (uc.expires_at is null or uc.expires_at>=now()))) order by mu.created_at)
        from public.community_post_mentions mu join public.user_profiles mup on mup.user_id=mu.user_id where mu.post_id=p.id),'[]'::jsonb) mentions,
      private.poll_state(p.id,v_user_id) poll
    from public.community_posts p
    where p.community_id=p_community_id and p.status='active'
      and not exists(select 1 from public.post_hides h where h.user_id=v_user_id and h.post_id=p.id)
  ), sc as (
    select pc.*,up.username,up.first_name,up.last_name,up.photo_url global_photo_url,
      exists(select 1 from public.user_certifications uc where uc.user_id=pc.author_id and uc.status::text='active'
        and uc.issued_at<=now() and (uc.expires_at is null or uc.expires_at>=now())) author_is_certified,
      (case when pc.author_id=v_user_id then 35 when public.are_friends(v_user_id,pc.author_id) then 100
        when exists(select 1 from public.user_follows uf where uf.follower_id=v_user_id and uf.followed_id=pc.author_id) then 70 else 0 end
       +least(40,(select count(*) from public.community_members a join public.community_members b
          on b.community_id=a.community_id and b.user_id=pc.author_id where a.user_id=v_user_id)*10)
       +least(40,(select count(*) from public.user_activity ua where ua.user_id=v_user_id and ua.owner_id=pc.author_id
          and ua.created_at>=now()-interval '90 days')*5)
       +least(40,floor(sqrt((pc.likes_count*2)::numeric+pc.comments_count::numeric*3+pc.dislikes_count::numeric+1)*8))
       +greatest(0,floor(35*exp(-extract(epoch from(now()-pc.created_at))/172800.0))))::numeric feed_score
    from pc join public.user_profiles up on up.user_id=pc.author_id
    where up.account_status='active' and up.deleted_at is null
  ), f as (
    select * from sc where v_score is null or feed_score<v_score
      or(feed_score=v_score and created_at<v_created)
      or(feed_score=v_score and created_at=v_created and id<v_id)
    order by feed_score desc,created_at desc,id desc limit v_limit+1
  ), pg as (
    select * from f order by feed_score desc,created_at desc,id desc limit v_limit
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'type','post','id',id,'community_id',community_id,'audience',audience,'allow_promotion',allow_promotion,
    'community',(select jsonb_build_object('id',cm.id,'name',cm.name,'slug',cm.slug,'photo_profile',cm.photo_profile,
      'visibility',cm.visibility,'allow_post_sharing',coalesce((select cs.allow_post_sharing from public.community_settings cs
        where cs.community_id=cm.id),true)) from public.communities cm where cm.id=community_id),
    'author_id',author_id,'content',content,'photo',photo,'photos',photos,
    'media',case when jsonb_typeof(media)='array' and jsonb_array_length(media)>0 then media else
      coalesce((select jsonb_agg(jsonb_build_object('type','photo','url',x) order by ord)
        from unnest(coalesce(photos,'{}'::text[])) with ordinality t(x,ord)),'[]'::jsonb)
      || case when video_url is null then '[]'::jsonb else jsonb_build_array(jsonb_build_object('type','video',
        'url',video_url,'thumbnail_url',video_thumbnail_url,'duration_ms',video_duration_ms,'size_bytes',video_size_bytes)) end end,
    'created_at',created_at,'updated_at',updated_at,'status',status,'comments_enabled',comments_enabled,
    'sharing_enabled',sharing_enabled,'reactions_enabled',reactions_enabled,
    'video',case when video_url is null then null else jsonb_build_object('url',video_url,'thumbnail_url',video_thumbnail_url,
      'duration_ms',video_duration_ms,'size_bytes',video_size_bytes) end,
    'hashtags',hashtags,'mentions',mentions,'poll',poll,
    'author',jsonb_build_object('user_id',author_id,'username',username,'first_name',first_name,'last_name',last_name,
      'photo_url',global_photo_url,'is_certified',author_is_certified,'pseudo',username,'bio',null),
    'comments_count',comments_count,'likes_count',likes_count,'dislikes_count',dislikes_count,'viewer_reaction',viewer_reaction
  )||private.post_extras(id,v_user_id) order by feed_score desc,created_at desc,id desc),'[]'::jsonb),
  case when(select count(*) from f)>v_limit then
    (select p2.feed_score::text||'|'||p2.created_at::text||'|'||p2.id::text
      from pg p2 order by p2.feed_score desc,p2.created_at desc,p2.id desc offset v_limit-1 limit 1) end
  into v_items,v_next from pg;
  return jsonb_build_object('items',v_items,'next_cursor',v_next,'has_more',v_next is not null);
end;
$function$;

create or replace function public.get_post(p_post_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare v_uid uuid:=auth.uid(); v_p public.community_posts;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  select * into v_p from public.community_posts where id=p_post_id;
  if not found then raise exception 'Publication indisponible'; end if;
  if not (v_p.author_id=v_uid
    or (v_p.status='active'
      and public.can_view_post_row(v_p.community_id,v_p.author_id,v_p.audience)
      and not private.users_blocked(v_uid,v_p.author_id)
      and not exists(select 1 from public.post_hides h where h.user_id=v_uid and h.post_id=v_p.id))) then
    raise exception 'Publication indisponible';
  end if;
  return private.post_item(p_post_id,v_uid);
end;
$function$;
