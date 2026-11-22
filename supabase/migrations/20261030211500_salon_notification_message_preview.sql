
create or replace function private.render_notification(
  p_type text,p_data jsonb,p_language text,p_fallback_title text,p_fallback_body text
)
returns jsonb language plpgsql stable security definer set search_path=''
as $function$
declare
  v_lang text := case when p_language in ('fr','en','es','de','it','pt','zh','ja','ru') then p_language else 'fr' end;
  v_title text; v_body text; v_activity_name text; v_event_name text;
  v_community_name text; v_salon_name text; v_actor_name text; v_reason text; v_date text;
  v_message_preview text; v_message_type text;
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
  if p_type='community_salon_message' and p_data ? 'message_id' then
    select m.type,
      case m.type
        when 'image' then case v_lang when 'en' then 'Photo' when 'es' then 'Foto' when 'de' then 'Foto' when 'it' then 'Foto' when 'pt' then 'Foto' when 'zh' then '照片' when 'ja' then '写真' when 'ru' then 'Фото' else 'Photo' end
        when 'video' then case v_lang when 'en' then 'Video' when 'es' then 'Vídeo' when 'de' then 'Video' when 'it' then 'Video' when 'pt' then 'Vídeo' when 'zh' then '视频' when 'ja' then '動画' when 'ru' then 'Видео' else 'Vidéo' end
        when 'audio' then case v_lang when 'en' then 'Voice message' when 'es' then 'Mensaje de voz' when 'de' then 'Sprachnachricht' when 'it' then 'Messaggio vocale' when 'pt' then 'Mensagem de voz' when 'zh' then '语音消息' when 'ja' then '音声メッセージ' when 'ru' then 'Голосовое сообщение' else 'Message audio' end
        when 'file' then case v_lang when 'en' then 'File' when 'es' then 'Archivo' when 'de' then 'Datei' when 'it' then 'File' when 'pt' then 'Arquivo' when 'zh' then '文件' when 'ja' then 'ファイル' when 'ru' then 'Файл' else 'Fichier' end
        else left(coalesce(nullif(trim(m.content),''),case v_lang when 'en' then 'Message' when 'es' then 'Mensaje' when 'de' then 'Nachricht' when 'it' then 'Messaggio' when 'pt' then 'Mensagem' when 'zh' then '消息' when 'ja' then 'メッセージ' when 'ru' then 'Сообщение' else 'Message' end),140)
      end
    into v_message_type,v_message_preview
    from public.community_salon_messages m
    where m.id=(p_data->>'message_id')::uuid and m.salon_id=(p_data->>'salon_id')::uuid and not m.is_deleted;
  end if;
  v_actor_name:=coalesce(v_actor_name,p_data->>'actor_name','Quelqu’un');
  v_community_name:=coalesce(v_community_name,p_data->>'community_name','');
  v_salon_name:=coalesce(v_salon_name,p_data->>'salon_name','');
  v_message_preview:=coalesce(v_message_preview,p_data->>'message_preview',case v_lang when 'en' then 'New message' when 'es' then 'Nuevo mensaje' when 'de' then 'Neue Nachricht' when 'it' then 'Nuovo messaggio' when 'pt' then 'Nova mensagem' when 'zh' then '新消息' when 'ja' then '新しいメッセージ' when 'ru' then 'Новое сообщение' else 'Nouveau message' end);
  v_reason:=coalesce(p_data->>'raison','');
  if p_data ? 'scheduled_deletion_at' then v_date:=to_char((p_data->>'scheduled_deletion_at')::timestamptz,'DD/MM/YYYY'); end if;
  v_title:=replace(replace(replace(replace(replace(replace(replace(replace(v_title,'{{activity_name}}',coalesce(v_activity_name,p_data->>'activity_name','')),'{{event_name}}',coalesce(v_event_name,p_data->>'event_name','')),'{{community_name}}',v_community_name),'{{salon_name}}',v_salon_name),'{{actor_name}}',v_actor_name),'{{message_preview}}',v_message_preview),'{{raison}}',v_reason),'{{date}}',coalesce(v_date,''));
  v_body:=replace(replace(replace(replace(replace(replace(replace(replace(v_body,'{{activity_name}}',coalesce(v_activity_name,p_data->>'activity_name','')),'{{event_name}}',coalesce(v_event_name,p_data->>'event_name','')),'{{community_name}}',v_community_name),'{{salon_name}}',v_salon_name),'{{actor_name}}',v_actor_name),'{{message_preview}}',v_message_preview),'{{raison}}',v_reason),'{{date}}',coalesce(v_date,''));
  return jsonb_build_object('title',v_title,'body',v_body);
end
$function$;

update private.notification_templates set body_template=case language
  when 'en' then '{{actor_name}} posted in the “{{salon_name}}” salon: {{message_preview}}'
  when 'es' then '{{actor_name}} escribió en el salón «{{salon_name}}»: {{message_preview}}'
  when 'de' then '{{actor_name}} hat im Salon „{{salon_name}}“ geschrieben: {{message_preview}}'
  when 'it' then '{{actor_name}} ha scritto nel salone «{{salon_name}}»: {{message_preview}}'
  when 'pt' then '{{actor_name}} escreveu no salão «{{salon_name}}»: {{message_preview}}'
  when 'zh' then '{{actor_name}} 在「{{salon_name}}」聊天室中发了一条消息：{{message_preview}}'
  when 'ja' then '{{actor_name}}さんが「{{salon_name}}」にメッセージを送信しました：{{message_preview}}'
  when 'ru' then '{{actor_name}} написал(а) в салоне «{{salon_name}}»: {{message_preview}}'
  else '{{actor_name}} a écrit dans le salon « {{salon_name}} » : {{message_preview}}'
end where type='community_salon_message';
