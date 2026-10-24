-- Inline mentions for communities and events in community posts/comments.
create table if not exists public.community_content_entity_mentions (
  id uuid primary key default gen_random_uuid(),
  source_type text not null check (source_type in ('post','comment')),
  source_id uuid not null,
  entity_type text not null check (entity_type in ('community','event')),
  entity_id uuid not null,
  actor_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint community_content_entity_mentions_unique unique (source_type, source_id, entity_type, entity_id)
);
create index if not exists idx_content_entity_mentions_source on public.community_content_entity_mentions (source_type, source_id);
create index if not exists idx_content_entity_mentions_entity on public.community_content_entity_mentions (entity_type, entity_id);
alter table public.community_content_entity_mentions enable row level security;

CREATE OR REPLACE FUNCTION public.save_content_entity_mentions(p_source_type text, p_source_id uuid, p_community_ids uuid[] DEFAULT '{}'::uuid[], p_event_ids uuid[] DEFAULT '{}'::uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := auth.uid();
  v_community_id uuid;
  v_event_id uuid;
  v_post_community_id uuid;
  v_content text;
  v_saved integer := 0;
  v_context text;
  v_title text;
  v_body text;
  v_recipient uuid;
  v_is_organizer boolean;
begin
  if v_actor is null then raise exception 'Authentication required'; end if;
  if p_source_type not in ('post','comment') then raise exception 'Source invalide'; end if;

  if p_source_type = 'post' then
    select p.community_id, p.content into v_post_community_id, v_content
    from public.community_posts p
    where p.id = p_source_id and p.author_id = v_actor and p.status = 'active';
    if not found then raise exception 'Publication introuvable ou non autorisée'; end if;
  else
    select p.community_id, c.content into v_post_community_id, v_content
    from public.community_post_comments c
    join public.community_posts p on p.id = c.post_id
    where c.id = p_source_id and c.author_id = v_actor and p.status = 'active';
    if not found then raise exception 'Commentaire introuvable ou non autorisé'; end if;
  end if;

  v_context := case when p_source_type = 'post' then 'publication' else 'commentaire' end;

  foreach v_community_id in array coalesce(p_community_ids, '{}'::uuid[]) loop
    if exists (select 1 from public.communities c where c.id = v_community_id and c.status = 'active' and position('~' || c.name in coalesce(v_content,'')) > 0)
       and not exists (select 1 from public.community_content_entity_mentions m where m.source_type=p_source_type and m.source_id=p_source_id and m.entity_type='community' and m.entity_id=v_community_id) then
      insert into public.community_content_entity_mentions(source_type,source_id,entity_type,entity_id,actor_id)
      values(p_source_type,p_source_id,'community',v_community_id,v_actor)
      on conflict do nothing;
      v_saved := v_saved + 1;
      v_title := 'Votre communauté a été mentionnée';
      v_body := 'Votre communauté a été mentionnée dans un ' || v_context || '.';
      for v_recipient in
        select cm.user_id from public.community_members cm
        join public.user_profiles up on up.user_id=cm.user_id
        where cm.community_id=v_community_id and up.account_status='active' and up.deleted_at is null
        union
        select c.creator_id from public.communities c where c.id=v_community_id
      loop
        perform private.notify_community_user(
          v_recipient,
          case when p_source_type='post' then 'community_mentioned_in_post' else 'community_mentioned_in_comment' end,
          v_actor,
          jsonb_build_object('community_id',v_community_id,'source_type',p_source_type,'source_id',p_source_id,'post_id',case when p_source_type='post' then p_source_id else null end,'comment_id',case when p_source_type='comment' then p_source_id else null end,'actor_id',v_actor),
          v_title,v_body
        );
      end loop;
    end if;
  end loop;

  foreach v_event_id in array coalesce(p_event_ids, '{}'::uuid[]) loop
    if exists (select 1 from public.events e where e.id=v_event_id and coalesce(e.status,'active') not in ('deleted','cancelled','archived') and position('*' || e.name in coalesce(v_content,'')) > 0)
       and not exists (select 1 from public.community_content_entity_mentions m where m.source_type=p_source_type and m.source_id=p_source_id and m.entity_type='event' and m.entity_id=v_event_id) then
      insert into public.community_content_entity_mentions(source_type,source_id,entity_type,entity_id,actor_id)
      values(p_source_type,p_source_id,'event',v_event_id,v_actor)
      on conflict do nothing;
      v_saved := v_saved + 1;
      for v_recipient in
        select ec.user_id from public.event_calendar ec where ec.event_id=v_event_id
        union select e.creator_id from public.events e where e.id=v_event_id
        union select cc.user_id from public.event_co_creators cc where cc.event_id=v_event_id and coalesce(cc.status,'accepted') in ('accepted','active')
        union select es.user_id from public.event_staff es where es.event_id=v_event_id and coalesce(es.status,'accepted') in ('accepted','active')
      loop
        select
          exists(select 1 from public.events e where e.id=v_event_id and e.creator_id=v_recipient)
          or exists(select 1 from public.event_co_creators cc where cc.event_id=v_event_id and cc.user_id=v_recipient and coalesce(cc.status,'accepted') in ('accepted','active'))
          or exists(select 1 from public.event_staff es where es.event_id=v_event_id and es.user_id=v_recipient and coalesce(es.status,'accepted') in ('accepted','active'))
        into v_is_organizer;

        if v_is_organizer then
          v_title := 'Votre événement a été mentionné';
          v_body := 'Votre événement a été mentionné dans un ' || v_context || '.';
        else
          v_title := 'Un événement de votre calendrier a été mentionné';
          v_body := 'Un événement auquel vous souhaitez participer a été mentionné dans un ' || v_context || '.';
        end if;

        perform private.notify_community_user(
          v_recipient,
          case when v_is_organizer then
            case when p_source_type='post' then 'event_organizer_mentioned_in_post' else 'event_organizer_mentioned_in_comment' end
          else
            case when p_source_type='post' then 'event_mentioned_in_post' else 'event_mentioned_in_comment' end
          end,
          v_actor,
          jsonb_build_object('event_id',v_event_id,'source_type',p_source_type,'source_id',p_source_id,'post_id',case when p_source_type='post' then p_source_id else null end,'comment_id',case when p_source_type='comment' then p_source_id else null end,'actor_id',v_actor,'recipient_role',case when v_is_organizer then 'organizer' else 'calendar' end),
          v_title,v_body
        );
      end loop;
    end if;
  end loop;

  return jsonb_build_object('success',true,'saved',v_saved);
end;
$function$
;
revoke all on function public.save_content_entity_mentions(text,uuid,uuid[],uuid[]) from public;
grant execute on function public.save_content_entity_mentions(text,uuid,uuid[],uuid[]) to authenticated;

insert into private.notification_templates(type,language,title_template,body_template)
values
('community_mentioned_in_post','fr','Votre communauté a été mentionnée','Votre communauté a été mentionnée dans une publication.'),
('community_mentioned_in_comment','fr','Votre communauté a été mentionnée','Votre communauté a été mentionnée dans un commentaire.'),
('event_mentioned_in_post','fr','Un événement a été mentionné','Un événement de votre calendrier a été mentionné dans une publication.'),
('event_mentioned_in_comment','fr','Un événement a été mentionné','Un événement de votre calendrier a été mentionné dans un commentaire.'),
('community_mentioned_in_post','en','Your community was mentioned','Your community was mentioned in a post.'),
('community_mentioned_in_comment','en','Your community was mentioned','Your community was mentioned in a comment.'),
('event_mentioned_in_post','en','An event was mentioned','An event in your calendar was mentioned in a post.'),
('event_mentioned_in_comment','en','An event was mentioned','An event in your calendar was mentioned in a comment.'),
('community_mentioned_in_post','es','Se mencionó tu comunidad','Tu comunidad fue mencionada en una publicación.'),
('community_mentioned_in_comment','es','Se mencionó tu comunidad','Tu comunidad fue mencionada en un comentario.'),
('event_mentioned_in_post','es','Se mencionó un evento','Se mencionó en una publicación un evento de tu calendario.'),
('event_mentioned_in_comment','es','Se mencionó un evento','Se mencionó en un comentario un evento de tu calendario.'),
('community_mentioned_in_post','de','Deine Community wurde erwähnt','Deine Community wurde in einem Beitrag erwähnt.'),
('community_mentioned_in_comment','de','Deine Community wurde erwähnt','Deine Community wurde in einem Kommentar erwähnt.'),
('event_mentioned_in_post','de','Eine Veranstaltung wurde erwähnt','Eine Veranstaltung in deinem Kalender wurde in einem Beitrag erwähnt.'),
('event_mentioned_in_comment','de','Eine Veranstaltung wurde erwähnt','Eine Veranstaltung in deinem Kalender wurde in einem Kommentar erwähnt.'),
('event_organizer_mentioned_in_post','fr','Votre événement a été mentionné','Votre événement a été mentionné dans une publication.'),
('event_organizer_mentioned_in_comment','fr','Votre événement a été mentionné','Votre événement a été mentionné dans un commentaire.'),
('event_organizer_mentioned_in_post','en','Your event was mentioned','Your event was mentioned in a post.'),
('event_organizer_mentioned_in_comment','en','Your event was mentioned','Your event was mentioned in a comment.'),
('event_organizer_mentioned_in_post','es','Se mencionó tu evento','Tu evento fue mencionado en una publicación.'),
('event_organizer_mentioned_in_comment','es','Se mencionó tu evento','Tu evento fue mencionado en un comentario.'),
('event_organizer_mentioned_in_post','de','Deine Veranstaltung wurde erwähnt','Deine Veranstaltung wurde in einem Beitrag erwähnt.'),
('event_organizer_mentioned_in_comment','de','Deine Veranstaltung wurde erwähnt','Deine Veranstaltung wurde in einem Kommentar erwähnt.')
on conflict (type,language) do update
set title_template=excluded.title_template, body_template=excluded.body_template, updated_at=now();
