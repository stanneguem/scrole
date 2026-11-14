
-- Event attendance, activity completion and personal itinerary reminders.

CREATE OR REPLACE FUNCTION private.render_notification(p_type text, p_data jsonb, p_language text, p_fallback_title text, p_fallback_body text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_lang text := CASE WHEN p_language IN ('fr','en','es','de','it','pt','zh','ja','ru') THEN p_language ELSE 'fr' END;
  v_title text; v_body text; v_activity_name text; v_event_name text;
  v_community_name text; v_salon_name text; v_actor_name text; v_reason text; v_date text;
  v_message_preview text; v_message_type text; v_planned_time text;
BEGIN
  SELECT title_template, body_template INTO v_title, v_body
  FROM private.notification_templates WHERE type = p_type AND language = v_lang;
  IF v_title IS NULL THEN
    SELECT title_template, body_template INTO v_title, v_body
    FROM private.notification_templates WHERE type = p_type AND language = 'fr';
  END IF;
  IF v_title IS NULL OR p_type = 'message_received' THEN
    RETURN jsonb_build_object('title', p_fallback_title, 'body', coalesce(p_fallback_body,''));
  END IF;

  IF p_data ? 'activity_id' THEN
    SELECT a.name INTO v_activity_name FROM public.activities a WHERE a.id = (p_data->>'activity_id')::uuid;
  END IF;
  IF p_data ? 'event_id' THEN
    SELECT e.name INTO v_event_name FROM public.events e WHERE e.id = (p_data->>'event_id')::uuid;
  END IF;
  IF p_data ? 'community_id' THEN
    SELECT c.name INTO v_community_name FROM public.communities c WHERE c.id = (p_data->>'community_id')::uuid;
  END IF;
  IF p_data ? 'salon_id' THEN
    SELECT s.name INTO v_salon_name FROM public.community_salons s WHERE s.id = (p_data->>'salon_id')::uuid;
  END IF;
  IF p_data ? 'actor_id' THEN
    SELECT coalesce(nullif(trim(concat_ws(' ',up.first_name,up.last_name)),''),nullif(up.username,''),'Quelqu’un')
    INTO v_actor_name FROM public.user_profiles up WHERE up.user_id = (p_data->>'actor_id')::uuid;
  END IF;
  IF p_type = 'community_salon_message' AND p_data ? 'message_id' THEN
    SELECT m.type,
      CASE m.type
        WHEN 'image' THEN CASE v_lang WHEN 'en' THEN 'Photo' WHEN 'es' THEN 'Foto' WHEN 'de' THEN 'Foto' WHEN 'it' THEN 'Foto' WHEN 'pt' THEN 'Foto' WHEN 'zh' THEN '照片' WHEN 'ja' THEN '写真' WHEN 'ru' THEN 'Фото' ELSE 'Photo' END
        WHEN 'video' THEN CASE v_lang WHEN 'en' THEN 'Video' WHEN 'es' THEN 'Vídeo' WHEN 'de' THEN 'Video' WHEN 'it' THEN 'Video' WHEN 'pt' THEN 'Vídeo' WHEN 'zh' THEN '视频' WHEN 'ja' THEN '動画' WHEN 'ru' THEN 'Видео' ELSE 'Vidéo' END
        WHEN 'audio' THEN CASE v_lang WHEN 'en' THEN 'Voice message' WHEN 'es' THEN 'Mensaje de voz' WHEN 'de' THEN 'Sprachnachricht' WHEN 'it' THEN 'Messaggio vocale' WHEN 'pt' THEN 'Mensagem de voz' WHEN 'zh' THEN '语音消息' WHEN 'ja' THEN '音声メッセージ' WHEN 'ru' THEN 'Голосовое сообщение' ELSE 'Message audio' END
        WHEN 'file' THEN CASE v_lang WHEN 'en' THEN 'File' WHEN 'es' THEN 'Archivo' WHEN 'de' THEN 'Datei' WHEN 'it' THEN 'File' WHEN 'pt' THEN 'Arquivo' WHEN 'zh' THEN '文件' WHEN 'ja' THEN 'ファイル' WHEN 'ru' THEN 'Файл' ELSE 'Fichier' END
        ELSE left(coalesce(nullif(trim(m.content),''),case v_lang WHEN 'en' THEN 'Message' WHEN 'es' THEN 'Mensaje' WHEN 'de' THEN 'Nachricht' WHEN 'it' THEN 'Messaggio' WHEN 'pt' THEN 'Mensagem' WHEN 'zh' THEN '消息' WHEN 'ja' THEN 'メッセージ' WHEN 'ru' THEN 'Сообщение' ELSE 'Message' END),140)
      END
    INTO v_message_type, v_message_preview
    FROM public.community_salon_messages m
    WHERE m.id = (p_data->>'message_id')::uuid
      AND m.salon_id = (p_data->>'salon_id')::uuid
      AND NOT m.is_deleted;
  END IF;

  v_actor_name := coalesce(v_actor_name,p_data->>'actor_name','Quelqu’un');
  v_community_name := coalesce(v_community_name,p_data->>'community_name','');
  v_salon_name := coalesce(v_salon_name,p_data->>'salon_name','');
  v_message_preview := coalesce(v_message_preview,p_data->>'message_preview',
    CASE v_lang WHEN 'en' THEN 'New message' WHEN 'es' THEN 'Nuevo mensaje' WHEN 'de' THEN 'Neue Nachricht' WHEN 'it' THEN 'Nuovo messaggio' WHEN 'pt' THEN 'Nova mensagem' WHEN 'zh' THEN '新消息' WHEN 'ja' THEN '新しいメッセージ' WHEN 'ru' THEN 'Новое сообщение' ELSE 'Nouveau message' END);
  v_reason := coalesce(p_data->>'raison','');
  IF p_data ? 'scheduled_deletion_at' THEN
    v_date := to_char((p_data->>'scheduled_deletion_at')::timestamptz,'DD/MM/YYYY');
  END IF;
  v_planned_time := coalesce(p_data->>'planned_time','');

  v_title := replace(replace(replace(replace(replace(replace(replace(replace(replace(
    v_title,'{{activity_name}}',coalesce(v_activity_name,p_data->>'activity_name','')),
    '{{event_name}}',coalesce(v_event_name,p_data->>'event_name','')),
    '{{community_name}}',v_community_name),'{{salon_name}}',v_salon_name),
    '{{actor_name}}',v_actor_name),'{{message_preview}}',v_message_preview),
    '{{raison}}',v_reason),'{{date}}',coalesce(v_date,'')),'{{planned_time}}',v_planned_time);

  v_body := replace(replace(replace(replace(replace(replace(replace(replace(replace(
    v_body,'{{activity_name}}',coalesce(v_activity_name,p_data->>'activity_name','')),
    '{{event_name}}',coalesce(v_event_name,p_data->>'event_name','')),
    '{{community_name}}',v_community_name),'{{salon_name}}',v_salon_name),
    '{{actor_name}}',v_actor_name),'{{message_preview}}',v_message_preview),
    '{{raison}}',v_reason),'{{date}}',coalesce(v_date,'')),'{{planned_time}}',v_planned_time);

  RETURN jsonb_build_object('title',v_title,'body',v_body);
END
$function$
;



INSERT INTO private.notification_templates(type,language,title_template,body_template,updated_at)
VALUES
('event_presence_validated','fr','Présence confirmée !','Ta présence à l’événement « {{event_name}} » a été validée. Profite bien de l’événement !',now()),
('event_activity_completed','fr','Bravo, activité terminée !','Tu viens de terminer « {{activity_name}} » à « {{event_name}} ». Félicitations !',now()),
('event_arrival_reminder','fr','Ton arrivée approche','Tu avais prévu d’arriver à « {{event_name}} » à {{planned_time}}. C’est bientôt l’heure !',now()),
('event_departure_reminder','fr','Ton départ approche','Tu avais prévu de quitter « {{event_name}} » à {{planned_time}}. Pense à t’organiser !',now()),
('event_presence_validated','en','Attendance confirmed!','Your attendance at “{{event_name}}” has been confirmed. Enjoy the event!',now()),
('event_activity_completed','en','Well done, activity completed!','You just completed “{{activity_name}}” at “{{event_name}}”. Congratulations!',now()),
('event_arrival_reminder','en','Your arrival is coming up','You planned to arrive at “{{event_name}}” at {{planned_time}}. It’s almost time!',now()),
('event_departure_reminder','en','Your departure is coming up','You planned to leave “{{event_name}}” at {{planned_time}}. Get ready!',now()),
('event_presence_validated','es','¡Asistencia confirmada!','Tu asistencia al evento «{{event_name}}» ha sido confirmada. ¡Disfruta del evento!',now()),
('event_activity_completed','es','¡Bien hecho, actividad completada!','Acabas de completar «{{activity_name}}» en «{{event_name}}». ¡Felicidades!',now()),
('event_arrival_reminder','es','Se acerca tu llegada','Planeaste llegar a «{{event_name}}» a las {{planned_time}}. ¡Ya casi es hora!',now()),
('event_departure_reminder','es','Se acerca tu salida','Planeaste salir de «{{event_name}}» a las {{planned_time}}. ¡Prepárate!',now()),
('event_presence_validated','de','Anwesenheit bestätigt!','Deine Anwesenheit bei „{{event_name}}“ wurde bestätigt. Viel Spaß bei der Veranstaltung!',now()),
('event_activity_completed','de','Gut gemacht, Aktivität abgeschlossen!','Du hast gerade „{{activity_name}}“ bei „{{event_name}}“ abgeschlossen. Glückwunsch!',now()),
('event_arrival_reminder','de','Deine Ankunft steht bevor','Du wolltest um {{planned_time}} bei „{{event_name}}“ ankommen. Es ist bald so weit!',now()),
('event_departure_reminder','de','Deine Abfahrt steht bevor','Du wolltest „{{event_name}}“ um {{planned_time}} verlassen. Mach dich bereit!',now()),
('event_presence_validated','it','Presenza confermata!','La tua presenza all’evento «{{event_name}}» è stata confermata. Goditi l’evento!',now()),
('event_activity_completed','it','Ottimo, attività completata!','Hai appena completato «{{activity_name}}» a «{{event_name}}». Complimenti!',now()),
('event_arrival_reminder','it','Il tuo arrivo si avvicina','Avevi previsto di arrivare a «{{event_name}}» alle {{planned_time}}. Ci siamo quasi!',now()),
('event_departure_reminder','it','La tua partenza si avvicina','Avevi previsto di lasciare «{{event_name}}» alle {{planned_time}}. Preparati!',now()),
('event_presence_validated','pt','Presença confirmada!','Sua presença no evento «{{event_name}}» foi confirmada. Aproveite o evento!',now()),
('event_activity_completed','pt','Muito bem, atividade concluída!','Você acabou de concluir «{{activity_name}}» em «{{event_name}}». Parabéns!',now()),
('event_arrival_reminder','pt','Sua chegada está próxima','Você planejou chegar a «{{event_name}}» às {{planned_time}}. Está quase na hora!',now()),
('event_departure_reminder','pt','Sua saída está próxima','Você planejou sair de «{{event_name}}» às {{planned_time}}. Prepare-se!',now()),
('event_presence_validated','zh','已确认到场！','你已成功确认参加「{{event_name}}」。祝你活动愉快！',now()),
('event_activity_completed','zh','做得好，活动已完成！','你刚刚完成了「{{event_name}}」的「{{activity_name}}」。恭喜！',now()),
('event_arrival_reminder','zh','即将到达活动现场','你计划在 {{planned_time}} 到达「{{event_name}}」。时间快到了！',now()),
('event_departure_reminder','zh','即将离开活动现场','你计划在 {{planned_time}} 离开「{{event_name}}」。请做好准备！',now()),
('event_presence_validated','ja','来場が確認されました！','「{{event_name}}」への参加が確認されました。イベントを楽しんでください！',now()),
('event_activity_completed','ja','おめでとうございます、アクティビティ完了！','「{{event_name}}」で「{{activity_name}}」を完了しました。おめでとうございます！',now()),
('event_arrival_reminder','ja','到着予定時刻が近づいています','「{{event_name}}」への到着予定時刻は {{planned_time}} です。もうすぐです！',now()),
('event_departure_reminder','ja','出発予定時刻が近づいています','「{{event_name}}」からの出発予定時刻は {{planned_time}} です。準備しましょう！',now()),
('event_presence_validated','ru','Посещение подтверждено!','Ваше присутствие на мероприятии «{{event_name}}» подтверждено. Приятного мероприятия!',now()),
('event_activity_completed','ru','Отлично, активность завершена!','Вы завершили «{{activity_name}}» на мероприятии «{{event_name}}». Поздравляем!',now()),
('event_arrival_reminder','ru','Скоро время прибытия','Вы планировали прибыть на «{{event_name}}» в {{planned_time}}. Уже скоро!',now()),
('event_departure_reminder','ru','Скоро время отъезда','Вы планировали покинуть «{{event_name}}» в {{planned_time}}. Пора готовиться!',now())
ON CONFLICT(type,language) DO UPDATE SET
 title_template=excluded.title_template,body_template=excluded.body_template,updated_at=now();

CREATE TABLE IF NOT EXISTS private.event_itinerary_reminder_deliveries (
 user_id uuid NOT NULL,
 event_id uuid NOT NULL,
 planned_date date NOT NULL,
 reminder_type text NOT NULL CHECK (reminder_type IN ('arrival','departure')),
 delivered_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(user_id,event_id,planned_date,reminder_type)
);

CREATE INDEX IF NOT EXISTS event_itinerary_plans_planned_date_idx
 ON public.event_itinerary_plans(planned_date);

CREATE OR REPLACE FUNCTION private.notify_event_checkin_insert()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
 IF NEW.status IS DISTINCT FROM 'valid' THEN RETURN NEW; END IF;
 IF NEW.activity_id IS NULL THEN
  INSERT INTO public.notifications(user_id,type,title,body,actor_id,data)
  VALUES(NEW.user_id,'event_presence_validated','Présence confirmée !',
   'Ta présence à cet événement a été validée.',NEW.validated_by_user_id,
   jsonb_build_object('event_id',NEW.event_id,'checkin_id',NEW.id,'validated_by_user_id',NEW.validated_by_user_id));
 ELSE
  INSERT INTO public.notifications(user_id,type,title,body,actor_id,data)
  VALUES(NEW.user_id,'event_activity_completed','Bravo, activité terminée !',
   'Tu viens de terminer une activité. Félicitations !',NEW.validated_by_user_id,
   jsonb_build_object('event_id',NEW.event_id,'activity_id',NEW.activity_id,'checkin_id',NEW.id,'validated_by_user_id',NEW.validated_by_user_id));
 END IF;
 RETURN NEW;
END
$function$;

DROP TRIGGER IF EXISTS trg_notify_event_checkin_insert ON public.event_checkins;
CREATE TRIGGER trg_notify_event_checkin_insert
AFTER INSERT ON public.event_checkins
FOR EACH ROW EXECUTE FUNCTION private.notify_event_checkin_insert();

CREATE OR REPLACE FUNCTION private.dispatch_event_itinerary_reminders()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
 v_plan record; v_kind text; v_time text; v_target timestamptz;
 v_type text; v_claimed boolean; v_sent integer:=0;
BEGIN
 FOR v_plan IN
  SELECT p.user_id,p.event_id,p.planned_date,p.plan,e.name AS event_name
  FROM public.event_itinerary_plans p JOIN public.events e ON e.id=p.event_id
  WHERE p.planned_date>=timezone('Africa/Douala',now())::date
    AND p.planned_date<=timezone('Africa/Douala',now()+interval '1 day')::date
    AND e.status='active'
 LOOP
  FOREACH v_kind IN ARRAY ARRAY['arrival','departure'] LOOP
   v_time:=nullif(btrim(v_plan.plan->>CASE WHEN v_kind='arrival' THEN 'day_start' ELSE 'day_end' END),'');
   IF v_time IS NULL OR v_time !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' THEN CONTINUE; END IF;
   v_target:=((v_plan.planned_date::text||' '||v_time)::timestamp AT TIME ZONE 'Africa/Douala');
   IF v_target<=now() OR v_target>now()+interval '30 minutes' THEN CONTINUE; END IF;
   v_type:=CASE WHEN v_kind='arrival' THEN 'event_arrival_reminder' ELSE 'event_departure_reminder' END;
   v_claimed:=false;
   INSERT INTO private.event_itinerary_reminder_deliveries(user_id,event_id,planned_date,reminder_type)
   VALUES(v_plan.user_id,v_plan.event_id,v_plan.planned_date,v_kind)
   ON CONFLICT DO NOTHING RETURNING true INTO v_claimed;
   IF coalesce(v_claimed,false) THEN
    INSERT INTO public.notifications(user_id,type,title,body,data)
    VALUES(v_plan.user_id,v_type,
     CASE WHEN v_kind='arrival' THEN 'Ton arrivée approche' ELSE 'Ton départ approche' END,
     CASE WHEN v_kind='arrival' THEN 'Tu avais prévu d’arriver à cet événement à '||v_time||'.'
       ELSE 'Tu avais prévu de quitter cet événement à '||v_time||'.' END,
     jsonb_build_object('event_id',v_plan.event_id,'planned_date',v_plan.planned_date,
       'planned_time',v_time,'reminder_type',v_kind));
    v_sent:=v_sent+1;
   END IF;
  END LOOP;
 END LOOP;
 RETURN v_sent;
END
$function$;

REVOKE ALL ON FUNCTION private.notify_event_checkin_insert() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION private.dispatch_event_itinerary_reminders() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION private.dispatch_event_itinerary_reminders() TO postgres;

SELECT cron.schedule('scrole-event-itinerary-reminders','* * * * *',
 'SELECT private.dispatch_event_itinerary_reminders();');
