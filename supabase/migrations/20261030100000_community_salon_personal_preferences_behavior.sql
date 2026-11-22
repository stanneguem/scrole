-- Per-member salon preferences:
-- 1) create a notification only for members who opted in for this salon;
-- 2) keep the notification and FCM pipeline per recipient;
-- 3) never notify the sender.
insert into private.notification_templates(type, language, title_template, body_template)
values
 ('community_salon_message','fr','Nouveau message dans un salon','{{actor_name}} a envoyé un message.'),
 ('community_salon_message','en','New message in a discussion','{{actor_name}} sent a message.'),
 ('community_salon_message','es','Nuevo mensaje en una conversación','{{actor_name}} envió un mensaje.'),
 ('community_salon_message','de','Neue Nachricht in einer Diskussion','{{actor_name}} hat eine Nachricht gesendet.'),
 ('community_salon_message','it','Nuovo messaggio in una discussione','{{actor_name}} ha inviato un messaggio.'),
 ('community_salon_message','pt','Nova mensagem numa discussão','{{actor_name}} enviou uma mensagem.'),
 ('community_salon_message','zh','讨论中有新消息','{{actor_name}}发送了一条消息。'),
 ('community_salon_message','ja','ディスカッションに新しいメッセージ','{{actor_name}}がメッセージを送信しました。'),
 ('community_salon_message','ru','Новое сообщение в обсуждении','{{actor_name}} отправил(а) сообщение.')
on conflict (type, language) do update
set title_template = excluded.title_template,
    body_template = excluded.body_template;

create or replace function public.notify_community_salon_message()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if new.is_deleted then
    return new;
  end if;

  insert into public.notifications (
    user_id, type, title, body, actor_id, data, created_at
  )
  select
    member.user_id,
    'community_salon_message',
    'Nouveau message dans un salon',
    'Un membre a envoyé un message.',
    new.sender_id,
    jsonb_build_object(
      'salon_id', new.salon_id,
      'message_id', new.id,
      'actor_id', new.sender_id
    ),
    now()
  from public.community_salon_members member
  left join public.community_salon_user_preferences preference
    on preference.salon_id = member.salon_id
   and preference.user_id = member.user_id
  where member.salon_id = new.salon_id
    and member.user_id <> new.sender_id
    and coalesce(preference.notifications_enabled, true);

  return new;
end;
$function$;

drop trigger if exists community_salon_message_notification
on public.community_salon_messages;

create trigger community_salon_message_notification
after insert on public.community_salon_messages
for each row
execute function public.notify_community_salon_message();

revoke all on function public.notify_community_salon_message()
from public, anon, authenticated;
