create or replace function public.mark_salon_messages_read(p_salon_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $function$
begin
  if not public.can_access_salon(p_salon_id) then
    raise exception 'Accès non autorisé à ce salon';
  end if;
  insert into public.community_salon_message_receipts
    (message_id, user_id, delivered_at, read_at)
  select m.id, auth.uid(), now(), now()
  from public.community_salon_messages m
  where m.salon_id = p_salon_id
    and m.sender_id <> auth.uid()
    and not m.is_deleted
  on conflict (message_id, user_id) do update
    set delivered_at = coalesce(community_salon_message_receipts.delivered_at, excluded.delivered_at),
        read_at = coalesce(community_salon_message_receipts.read_at, excluded.read_at);
end;
$function$;
revoke all on function public.mark_salon_messages_read(uuid) from public, anon;
grant execute on function public.mark_salon_messages_read(uuid) to authenticated;

create or replace function public.handle_salon_member_removal_mark_read()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
begin
  insert into public.community_salon_message_receipts
    (message_id, user_id, delivered_at, read_at)
  select m.id, old.user_id, now(), now()
  from public.community_salon_messages m
  where m.salon_id = old.salon_id
    and m.sender_id <> old.user_id
    and not m.is_deleted
  on conflict (message_id, user_id) do update
    set delivered_at = coalesce(community_salon_message_receipts.delivered_at, excluded.delivered_at),
        read_at = coalesce(community_salon_message_receipts.read_at, excluded.read_at);
  return old;
end;
$function$;
drop trigger if exists trg_salon_member_removal_mark_read on public.community_salon_members;
create trigger trg_salon_member_removal_mark_read
after delete on public.community_salon_members
for each row execute function public.handle_salon_member_removal_mark_read();

create or replace function public.list_community_chat_groups_with_preview(p_community_id uuid)
returns table(
  id uuid, community_id uuid, name text, description text, visibility text,
  created_by uuid, created_at timestamptz, updated_at timestamptz,
  avatar_url text, last_message text, last_message_type text,
  last_message_at timestamptz, last_message_sender_id uuid,
  last_message_sender_name text, unread_count bigint,
  last_message_all_read boolean, member_count bigint, my_status text,
  can_manage boolean
)
language plpgsql stable security definer set search_path = public
as $function$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null or not public.is_community_member(p_community_id) then
    raise exception 'Vous devez être membre de la communauté';
  end if;
  return query
  select s.id,s.community_id,s.name,s.description,s.visibility,s.created_by,s.created_at,s.updated_at,s.avatar_url,
    latest.content,latest.type,latest.sent_at,latest.sender_id,
    case when latest.sender_id=v_uid then 'Vous'
      else coalesce(nullif(trim(concat_ws(' ',up.first_name,up.last_name)),''),up.username,'Membre') end,
    case when not exists (
      select 1 from public.community_salon_members mine where mine.salon_id=s.id and mine.user_id=v_uid
    ) then 0::bigint else (
      select count(*) from public.community_salon_messages um
      left join public.community_salon_message_receipts ur on ur.message_id=um.id and ur.user_id=v_uid
      where um.salon_id=s.id and not um.is_deleted and um.sender_id<>v_uid and ur.read_at is null
    ) end,
    case when latest.id is null or latest.sender_id<>v_uid then false else (
      select count(*)>0 and count(*)=count(*) filter(where lr.read_at is not null)
      from public.community_salon_members lm
      left join public.community_salon_message_receipts lr on lr.message_id=latest.id and lr.user_id=lm.user_id
      where lm.salon_id=s.id and lm.user_id<>v_uid
    ) end,
    case when s.visibility='public' or s.created_by=v_uid or exists(
      select 1 from public.community_salon_members m where m.salon_id=s.id and m.user_id=v_uid
    ) then (select count(*) from public.community_salon_members m where m.salon_id=s.id) else null end,
    case when s.created_by=v_uid or exists(
      select 1 from public.community_salon_members m where m.salon_id=s.id and m.user_id=v_uid
    ) then 'member' else coalesce((select r.status from public.community_salon_join_requests r
      where r.salon_id=s.id and r.user_id=v_uid),'none') end,
    public.community_can(p_community_id,'can_create_salon')
  from public.community_salons s
  left join lateral (
    select m.id,m.content,m.type,m.sent_at,m.sender_id from public.community_salon_messages m
    where m.salon_id=s.id and not m.is_deleted order by m.sent_at desc limit 1
  ) latest on true
  left join public.user_profiles up on up.user_id=latest.sender_id
  where s.community_id=p_community_id and (
    s.visibility='public' or s.created_by=v_uid
    or exists(select 1 from public.community_salon_members m where m.salon_id=s.id and m.user_id=v_uid)
    or exists(select 1 from public.community_salon_join_requests r where r.salon_id=s.id and r.user_id=v_uid and r.status='pending')
  )
  order by coalesce(latest.sent_at,s.updated_at) desc,s.created_at desc;
end;
$function$;
