-- Read-position tracking for community salon conversations.
drop function if exists public.get_salon_read_position(uuid);
create function public.get_salon_read_position(p_salon_id uuid)
returns table(last_read_message_id uuid, first_unread_message_id uuid, unread_count bigint)
language plpgsql stable security definer set search_path=''
as $function$
declare v_joined_at timestamptz;
begin
  if auth.uid() is null or not public.can_access_salon(p_salon_id) then raise exception 'Accès non autorisé à ce salon'; end if;
  select m.joined_at into v_joined_at from public.community_salon_members m where m.salon_id=p_salon_id and m.user_id=auth.uid();
  if v_joined_at is null then select s.created_at into v_joined_at from public.community_salons s where s.id=p_salon_id and s.created_by=auth.uid(); end if;
  return query
  select
    (select msg.id from public.community_salon_messages msg join public.community_salon_message_receipts r on r.message_id=msg.id and r.user_id=auth.uid() and r.read_at is not null where msg.salon_id=p_salon_id and msg.sent_at>=coalesce(v_joined_at,now()) and not msg.is_deleted order by msg.sent_at desc,msg.id desc limit 1),
    (select msg.id from public.community_salon_messages msg left join public.community_salon_message_receipts r on r.message_id=msg.id and r.user_id=auth.uid() where msg.salon_id=p_salon_id and msg.sent_at>=coalesce(v_joined_at,now()) and msg.sender_id<>auth.uid() and not msg.is_deleted and r.read_at is null and not exists(select 1 from public.community_salon_message_hidden_for h where h.message_id=msg.id and h.user_id=auth.uid()) order by msg.sent_at asc,msg.id asc limit 1),
    (select count(*)::bigint from public.community_salon_messages msg left join public.community_salon_message_receipts r on r.message_id=msg.id and r.user_id=auth.uid() where msg.salon_id=p_salon_id and msg.sent_at>=coalesce(v_joined_at,now()) and msg.sender_id<>auth.uid() and not msg.is_deleted and r.read_at is null and not exists(select 1 from public.community_salon_message_hidden_for h where h.message_id=msg.id and h.user_id=auth.uid()));
end;
$function$;
grant execute on function public.get_salon_read_position(uuid) to authenticated;

create or replace function public.mark_salon_messages_read_through(p_salon_id uuid,p_message_id uuid)
returns void language plpgsql security definer set search_path=''
as $function$
declare v_joined_at timestamptz; v_target_at timestamptz;
begin
  if auth.uid() is null or not public.can_access_salon(p_salon_id) then raise exception 'Accès non autorisé à ce salon'; end if;
  select m.joined_at into v_joined_at from public.community_salon_members m where m.salon_id=p_salon_id and m.user_id=auth.uid();
  if v_joined_at is null then select s.created_at into v_joined_at from public.community_salons s where s.id=p_salon_id and s.created_by=auth.uid(); end if;
  select sent_at into v_target_at from public.community_salon_messages where id=p_message_id and salon_id=p_salon_id and not is_deleted and sent_at>=coalesce(v_joined_at,now());
  if v_target_at is null then return; end if;
  insert into public.community_salon_message_receipts(message_id,user_id,delivered_at,read_at)
  select m.id,auth.uid(),now(),now() from public.community_salon_messages m
  where m.salon_id=p_salon_id and m.sent_at>=coalesce(v_joined_at,now()) and (m.sent_at,m.id)<=(v_target_at,p_message_id)
    and m.sender_id<>auth.uid() and not m.is_deleted
    and not exists(select 1 from public.community_salon_message_hidden_for h where h.message_id=m.id and h.user_id=auth.uid())
  on conflict(message_id,user_id) do update set delivered_at=coalesce(public.community_salon_message_receipts.delivered_at,excluded.delivered_at),read_at=coalesce(public.community_salon_message_receipts.read_at,excluded.read_at);
end;
$function$;
grant execute on function public.mark_salon_messages_read_through(uuid,uuid) to authenticated;

create or replace function public.get_my_community_salon_unread_counts()
returns table(community_id uuid, unread_count bigint)
language sql stable security definer set search_path=''
as $function$
  select s.community_id,count(m.id)::bigint
  from public.community_salons s
  join public.community_salon_messages m on m.salon_id=s.id and not m.is_deleted and m.sender_id<>auth.uid()
  left join public.community_salon_message_receipts r on r.message_id=m.id and r.user_id=auth.uid()
  where auth.uid() is not null
    and m.sent_at>=coalesce((select mine.joined_at from public.community_salon_members mine where mine.salon_id=s.id and mine.user_id=auth.uid()),case when s.created_by=auth.uid() then s.created_at else now() end)
    and (s.created_by=auth.uid() or exists(select 1 from public.community_salon_members mine where mine.salon_id=s.id and mine.user_id=auth.uid()))
    and r.read_at is null
    and not exists(select 1 from public.community_salon_message_hidden_for h where h.message_id=m.id and h.user_id=auth.uid())
  group by s.community_id having count(m.id)>0;
$function$;
grant execute on function public.get_my_community_salon_unread_counts() to authenticated;

create or replace function public.get_salon_messages_around(p_salon_id uuid,p_message_id uuid,p_before integer default 30,p_after integer default 50)
returns setof public.community_salon_messages
language plpgsql stable security definer set search_path=''
as $function$
declare v_joined_at timestamptz; v_target_at timestamptz;
begin
  if auth.uid() is null or not public.can_access_salon(p_salon_id) then raise exception 'Accès non autorisé à ce salon'; end if;
  select m.joined_at into v_joined_at from public.community_salon_members m where m.salon_id=p_salon_id and m.user_id=auth.uid();
  if v_joined_at is null then select s.created_at into v_joined_at from public.community_salons s where s.id=p_salon_id and s.created_by=auth.uid(); end if;
  select sent_at into v_target_at from public.community_salon_messages where id=p_message_id and salon_id=p_salon_id and not is_deleted and sent_at>=coalesce(v_joined_at,now());
  if v_target_at is null then raise exception 'Message introuvable ou inaccessible'; end if;
  return query with before_rows as (
    select m.* from public.community_salon_messages m where m.salon_id=p_salon_id and m.sent_at>=coalesce(v_joined_at,now()) and m.sent_at<v_target_at and not m.is_deleted
    and not exists(select 1 from public.community_salon_message_hidden_for h where h.message_id=m.id and h.user_id=auth.uid())
    order by m.sent_at desc,m.id desc limit greatest(0,least(coalesce(p_before,30),100))
  ), after_rows as (
    select m.* from public.community_salon_messages m where m.salon_id=p_salon_id and m.sent_at>=v_target_at and not m.is_deleted
    and not exists(select 1 from public.community_salon_message_hidden_for h where h.message_id=m.id and h.user_id=auth.uid())
    order by m.sent_at asc,m.id asc limit greatest(1,least(coalesce(p_after,50),100))
  )
  select * from (select * from before_rows union all select * from after_rows) combined order by sent_at asc,id asc;
end;
$function$;
grant execute on function public.get_salon_messages_around(uuid,uuid,integer,integer) to authenticated;
