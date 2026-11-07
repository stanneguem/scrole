-- Explicit action notifications. The renderer resolves {{actor_name}} from actor_id.
create or replace function private.render_notification(
  p_type text,p_data jsonb,p_language text,p_fallback_title text,p_fallback_body text
)
returns jsonb language plpgsql stable security definer set search_path=''
as $function$
declare
  v_lang text := case when p_language in ('fr','en','es','de','it','pt','zh','ja','ru') then p_language else 'fr' end;
  v_title text; v_body text; v_activity_name text; v_event_name text;
  v_community_name text; v_salon_name text; v_actor_name text; v_reason text; v_date text;
begin
  select title_template,body_template into v_title,v_body from private.notification_templates where type=p_type and language=v_lang;
  if v_title is null then select title_template,body_template into v_title,v_body from private.notification_templates where type=p_type and language='fr'; end if;
  if v_title is null or p_type='message_received' then return jsonb_build_object('title',p_fallback_title,'body',coalesce(p_fallback_body,'')); end if;
  if p_data ? 'activity_id' then select a.name into v_activity_name from public.activities a where a.id=(p_data->>'activity_id')::uuid; end if;
  if p_data ? 'event_id' then select e.name into v_event_name from public.events e where e.id=(p_data->>'event_id')::uuid; end if;
  if p_data ? 'community_id' then select c.name into v_community_name from public.communities c where c.id=(p_data->>'community_id')::uuid; end if;
  if p_data ? 'salon_id' then select s.name into v_salon_name from public.community_salons s where s.id=(p_data->>'salon_id')::uuid; end if;
  if p_data ? 'actor_id' then
    select coalesce(nullif(trim(concat_ws(' ',up.first_name,up.last_name)),''),nullif(up.username,''),'Quelqu’un')
    into v_actor_name from public.user_profiles up where up.user_id=(p_data->>'actor_id')::uuid;
  end if;
  v_actor_name:=coalesce(v_actor_name,p_data->>'actor_name','Quelqu’un');
  v_community_name:=coalesce(v_community_name,p_data->>'community_name','');
  v_salon_name:=coalesce(v_salon_name,p_data->>'salon_name','');
  v_reason:=coalesce(p_data->>'raison','');
  if p_data ? 'scheduled_deletion_at' then v_date:=to_char((p_data->>'scheduled_deletion_at')::timestamptz,'DD/MM/YYYY'); end if;
  v_title:=replace(replace(replace(replace(replace(replace(replace(v_title,'{{activity_name}}',coalesce(v_activity_name,p_data->>'activity_name','')),'{{event_name}}',coalesce(v_event_name,p_data->>'event_name','')),'{{community_name}}',v_community_name),'{{salon_name}}',v_salon_name),'{{actor_name}}',v_actor_name),'{{raison}}',v_reason),'{{date}}',coalesce(v_date,''));
  v_body:=replace(replace(replace(replace(replace(replace(replace(v_body,'{{activity_name}}',coalesce(v_activity_name,p_data->>'activity_name','')),'{{event_name}}',coalesce(v_event_name,p_data->>'event_name','')),'{{community_name}}',v_community_name),'{{salon_name}}',v_salon_name),'{{actor_name}}',v_actor_name),'{{raison}}',v_reason),'{{date}}',coalesce(v_date,''));
  return jsonb_build_object('title',v_title,'body',v_body);
end
$function$;

insert into private.notification_templates(type,language,title_template,body_template) values
('community_salon_message','fr','Nouveau message dans {{salon_name}}','{{actor_name}} a écrit dans le salon « {{salon_name}} ».'),
('community_salon_message','en','New message in {{salon_name}}','{{actor_name}} posted in the “{{salon_name}}” salon.'),
('community_salon_message','es','Nuevo mensaje en {{salon_name}}','{{actor_name}} escribió en el salón «{{salon_name}}».'),
('community_salon_message','de','Neue Nachricht in {{salon_name}}','{{actor_name}} hat im Salon „{{salon_name}}“ geschrieben.'),
('community_salon_message','it','Nuovo messaggio in {{salon_name}}','{{actor_name}} ha scritto nel salone «{{salon_name}}».'),
('community_salon_message','pt','Nova mensagem em {{salon_name}}','{{actor_name}} escreveu no salão «{{salon_name}}».'),
('community_salon_message','zh','{{salon_name}} 中的新消息','{{actor_name}} 在「{{salon_name}}」聊天室中发了一条消息。'),
('community_salon_message','ja','{{salon_name}}の新しいメッセージ','{{actor_name}}さんが「{{salon_name}}」にメッセージを送信しました。'),
('community_salon_message','ru','Новое сообщение в {{salon_name}}','{{actor_name}} написал(а) в салоне «{{salon_name}}».'),
('new_follower','fr','Nouvel abonné','{{actor_name}} vous suit désormais.'),
('new_follower','en','New follower','{{actor_name}} is now following you.'),
('new_follower','es','Nuevo seguidor','{{actor_name}} ahora te sigue.'),
('new_follower','de','Neuer Follower','{{actor_name}} folgt dir jetzt.'),
('new_follower','it','Nuovo follower','{{actor_name}} ora ti segue.'),
('new_follower','pt','Novo seguidor','{{actor_name}} começou a seguir você.'),
('new_follower','zh','新增关注者','{{actor_name}} 现在关注了你。'),
('new_follower','ja','新しいフォロワー','{{actor_name}}さんがあなたをフォローしました。'),
('new_follower','ru','Новый подписчик','{{actor_name}} теперь подписан(а) на вас.'),
('new_friend','fr','Nouvel ami','{{actor_name}} est maintenant votre ami(e).'),
('new_friend','en','New friend','{{actor_name}} is now your friend.'),
('new_friend','es','Nuevo amigo','{{actor_name}} ahora es tu amigo.'),
('new_friend','de','Neuer Freund','{{actor_name}} ist jetzt dein Freund.'),
('new_friend','it','Nuovo amico','{{actor_name}} è ora tuo amico.'),
('new_friend','pt','Novo amigo','{{actor_name}} agora é seu amigo.'),
('new_friend','zh','新好友','{{actor_name}} 现在是你的好友。'),
('new_friend','ja','新しい友達','{{actor_name}}さんと友達になりました。'),
('new_friend','ru','Новый друг','{{actor_name}} теперь ваш друг.'),
('post_shared_story','fr','Publication partagée','{{actor_name}} a partagé votre publication dans sa story.'),
('post_shared_story','en','Post shared to a story','{{actor_name}} shared your post in their story.'),
('post_shared_story','es','Publicación compartida','{{actor_name}} compartió tu publicación en su historia.'),
('post_shared_story','de','Beitrag in Story geteilt','{{actor_name}} hat deinen Beitrag in seiner Story geteilt.'),
('post_shared_story','it','Post condiviso in una storia','{{actor_name}} ha condiviso il tuo post nella sua storia.'),
('post_shared_story','pt','Publicação compartilhada','{{actor_name}} compartilhou sua publicação no story.'),
('post_shared_story','zh','帖子已分享到快拍','{{actor_name}} 将你的帖子分享到其快拍。'),
('post_shared_story','ja','投稿がストーリーでシェアされました','{{actor_name}}さんがあなたの投稿をストーリーでシェアしました。'),
('post_shared_story','ru','Публикация добавлена в историю','{{actor_name}} поделился(лась) вашей публикацией в своей истории.')
on conflict(type,language) do update set title_template=excluded.title_template,body_template=excluded.body_template;
