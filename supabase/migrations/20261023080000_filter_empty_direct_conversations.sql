-- Keep direct inbox limited to conversations with at least one message visible to the current user.
-- Existing return signature is preserved for Flutter RPC decoding.
CREATE OR REPLACE FUNCTION public.get_my_direct_conversations()
RETURNS TABLE(
  id uuid,
  other_user_id uuid,
  other_username text,
  other_first_name text,
  other_last_name text,
  other_photo_url text,
  last_message_text text,
  last_message_type text,
  last_message_at timestamp with time zone,
  last_message_sender_id uuid,
  unread_count bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
select
  c.id,
  case when c.user_one_id=auth.uid() then c.user_two_id else c.user_one_id end,
  p.username,
  p.first_name,
  p.last_name,
  p.photo_url,
  case
    when lm.type='image' then '🖼️ Photo'
    when lm.type='video' then '🎥 Vidéo'
    when lm.type='audio' then '🎤 Audio'
    when lm.type='file' then coalesce(nullif(lm.text,''),'📎 Fichier')
    when lm.type='poll' then '📊 Sondage'
    else lm.text
  end,
  lm.type,
  lm.created_at,
  lm.sender_id,
  coalesce((
    select count(*)
    from public.direct_messages um
    where um.conversation_id=c.id
      and um.sender_id<>auth.uid()
      and um.created_at>coalesce(cm.last_read_at,to_timestamp(0))
      and um.deleted_at is null
      and not exists(
        select 1 from public.direct_message_hidden_for h
        where h.message_id=um.id and h.user_id=auth.uid()
      )
  ),0)
from public.direct_conversations c
join public.direct_conversation_members cm
  on cm.conversation_id=c.id
 and cm.user_id=auth.uid()
 and cm.is_deleted=false
join public.user_profiles p
  on p.user_id=case when c.user_one_id=auth.uid() then c.user_two_id else c.user_one_id end
join lateral(
  select m.text,m.type,m.created_at,m.sender_id
  from public.direct_messages m
  where m.conversation_id=c.id
    and m.deleted_at is null
    and not exists(
      select 1 from public.direct_message_hidden_for h
      where h.message_id=m.id and h.user_id=auth.uid()
    )
  order by m.created_at desc
  limit 1
) lm on true
order by lm.created_at desc;
$function$;
