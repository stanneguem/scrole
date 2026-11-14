create or replace function public.notify_community_salon_message()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_recipient uuid;
  v_notifications_enabled boolean;
begin
  if new.is_deleted then
    return new;
  end if;

  -- A reply notifies only the author of the original message.
  if new.replied_to_id is not null then
    select parent.sender_id
      into v_recipient
    from public.community_salon_messages parent
    where parent.id = new.replied_to_id
      and parent.salon_id = new.salon_id
      and not parent.is_deleted;

    if v_recipient is null or v_recipient = new.sender_id then
      return new;
    end if;

    select coalesce(preference.notifications_enabled, true)
      into v_notifications_enabled
    from public.community_salon_members member
    left join public.community_salon_user_preferences preference
      on preference.salon_id = member.salon_id
     and preference.user_id = member.user_id
    where member.salon_id = new.salon_id
      and member.user_id = v_recipient;

    if not coalesce(v_notifications_enabled, false) then
      return new;
    end if;

    if exists (
      select 1
      from private.salon_active_presence presence
      where presence.salon_id = new.salon_id
        and presence.user_id = v_recipient
        and presence.last_seen_at > now() - interval '2 minutes'
    ) then
      return new;
    end if;

    insert into public.notifications (
      user_id, type, title, body, actor_id, data, created_at
    )
    values (
      v_recipient,
      'community_salon_reply',
      'Réponse à ton message',
      'Un membre a répondu à ton message dans ce salon.',
      new.sender_id,
      jsonb_build_object(
        'salon_id', new.salon_id,
        'message_id', new.id,
        'replied_to_id', new.replied_to_id,
        'actor_id', new.sender_id
      ),
      now()
    );

    return new;
  end if;

  -- Regular messages still notify every eligible salon member.
  insert into public.notifications(user_id, type, title, body, actor_id, data, created_at)
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
    and coalesce(preference.notifications_enabled, true)
    and not exists (
      select 1
      from private.salon_active_presence presence
      where presence.salon_id = new.salon_id
        and presence.user_id = member.user_id
        and presence.last_seen_at > now() - interval '2 minutes'
    );

  return new;
end;
$$;

insert into private.notification_templates(type, language, title_template, body_template)
values
('community_salon_reply','fr','Réponse à ton message','{{actor_name}} a répondu à ton message dans {{salon_name}}.'),
('community_salon_reply','en','Reply to your message','{{actor_name}} replied to your message in {{salon_name}}.'),
('community_salon_reply','es','Respuesta a tu mensaje','{{actor_name}} respondió a tu mensaje en {{salon_name}}.'),
('community_salon_reply','de','Antwort auf deine Nachricht','{{actor_name}} hat auf deine Nachricht in {{salon_name}} geantwortet.'),
('community_salon_reply','it','Risposta al tuo messaggio','{{actor_name}} ha risposto al tuo messaggio in {{salon_name}}.'),
('community_salon_reply','pt','Resposta à tua mensagem','{{actor_name}} respondeu à tua mensagem em {{salon_name}}.'),
('community_salon_reply','zh','有人回复了你的消息','{{actor_name}} 在 {{salon_name}} 回复了你的消息。'),
('community_salon_reply','ja','あなたのメッセージへの返信','{{actor_name}}さんが{{salon_name}}であなたのメッセージに返信しました。'),
('community_salon_reply','ru','Ответ на ваше сообщение','{{actor_name}} ответил(а) на ваше сообщение в салоне «{{salon_name}}».')
on conflict (type, language) do update
set title_template = excluded.title_template,
    body_template = excluded.body_template;
