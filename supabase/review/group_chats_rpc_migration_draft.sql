-- REVIEW ONLY: complete group-chat RPC migration draft.
-- This file is not applied. Review schema names, execute on a disposable local Supabase,
-- and validate storage/RLS behavior before proposing production deployment.

create or replace function public.get_my_group_conversations()
returns table (
  id uuid, name text, avatar_url text, creator_id uuid, status text,
  ever_activated boolean, active_member_count integer, created_at timestamptz,
  updated_at timestamptz, last_message_at timestamptz, last_message_text text,
  last_message_type text, unread_count bigint
)
language plpgsql security definer set search_path = ''
as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'authentication_required' using errcode='28000'; end if;
  return query
  select g.id,g.name,g.avatar_url,g.creator_id,g.status,g.ever_activated,
    (select count(*)::integer from public.group_conversation_members m where m.group_id=g.id and m.status='active'),
    g.created_at,g.updated_at,
    lm.created_at,lm.text,lm.message_type,
    (select count(*) from public.group_messages unread
      where unread.group_id=g.id and unread.sender_id<>v_uid and unread.deleted_at is null
      and (m.last_read_at is null or unread.created_at>m.last_read_at))
  from public.group_conversations g
  join public.group_conversation_members m on m.group_id=g.id and m.user_id=v_uid and m.status='active'
  left join lateral (select msg.created_at,msg.text,msg.message_type from public.group_messages msg
    where msg.group_id=g.id and msg.deleted_at is null order by msg.created_at desc,msg.id desc limit 1) lm on true
  where g.status <> 'closed'
  order by coalesce(lm.created_at,g.updated_at) desc;
end $$;

create or replace function public.get_my_pending_group_invitations()
returns table (
 id uuid, group_id uuid, invited_user_id uuid, invited_by uuid, status text,
 created_at timestamptz, responded_at timestamptz, group_name text, inviter_name text
)
language plpgsql security definer set search_path = ''
as $$
declare v_uid uuid := auth.uid();
begin
 if v_uid is null then raise exception 'authentication_required' using errcode='28000'; end if;
 return query
 select i.id,i.group_id,i.invited_user_id,i.invited_by,i.status,i.created_at,i.responded_at,
        g.name, coalesce(p.username,'')
 from public.group_conversation_invitations i
 join public.group_conversations g on g.id=i.group_id
 left join public.user_profiles p on p.user_id=i.invited_by
 where i.invited_user_id=v_uid and i.status='pending'
   and (i.expires_at is null or i.expires_at>now())
 order by i.created_at desc;
end $$;

create or replace function public.create_group_conversation(
 p_name text, p_avatar_url text default null, p_invited_user_ids uuid[] default '{}'
)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_uid uuid := auth.uid(); v_group public.group_conversations%rowtype; v_target uuid;
begin
 if v_uid is null then raise exception 'authentication_required' using errcode='28000'; end if;
 if length(btrim(coalesce(p_name,''))) not between 1 and 80 then raise exception 'invalid_group_name'; end if;
 insert into public.group_conversations(name,avatar_url,creator_id)
 values(btrim(p_name),p_avatar_url,v_uid) returning * into v_group;
 insert into public.group_conversation_members(group_id,user_id,role,status)
 values(v_group.id,v_uid,'owner','active');
 foreach v_target in array coalesce(p_invited_user_ids,'{}'::uuid[]) loop
   if v_target <> v_uid then
     insert into public.group_conversation_invitations(group_id,invited_user_id,invited_by)
     values(v_group.id,v_target,v_uid)
     on conflict (group_id,invited_user_id) where status='pending' do nothing;
   end if;
 end loop;
 return jsonb_build_object('id',v_group.id,'name',v_group.name,'avatar_url',v_group.avatar_url,
  'creator_id',v_group.creator_id,'status',v_group.status,'ever_activated',v_group.ever_activated,
  'active_member_count',1,'created_at',v_group.created_at,'updated_at',v_group.updated_at);
end $$;

create or replace function public.invite_group_members(p_group_id uuid,p_invited_user_ids uuid[])
returns integer language plpgsql security definer set search_path = ''
as $$
declare v_uid uuid:=auth.uid(); v_target uuid; v_count integer:=0;
begin
 if v_uid is null then raise exception 'authentication_required' using errcode='28000'; end if;
 if not exists(select 1 from public.group_conversation_members where group_id=p_group_id and user_id=v_uid and status='active' and role in ('owner','administrator')) then
   raise exception 'not_allowed_to_invite' using errcode='42501';
 end if;
 foreach v_target in array coalesce(p_invited_user_ids,'{}'::uuid[]) loop
  if v_target<>v_uid and not exists(select 1 from public.group_conversation_members where group_id=p_group_id and user_id=v_target and status='active') then
   insert into public.group_conversation_invitations(group_id,invited_user_id,invited_by)
   values(p_group_id,v_target,v_uid)
   on conflict (group_id,invited_user_id) where status='pending' do nothing;
   if found then v_count:=v_count+1; end if;
  end if;
 end loop;
 return v_count;
end $$;

create or replace function public.respond_to_group_invitation(p_invitation_id uuid,p_accept boolean)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_uid uuid:=auth.uid(); v_inv public.group_conversation_invitations%rowtype;
 v_group public.group_conversations%rowtype; v_count integer;
begin
 if v_uid is null then raise exception 'authentication_required' using errcode='28000'; end if;
 select * into v_inv from public.group_conversation_invitations
 where id=p_invitation_id and invited_user_id=v_uid and status='pending'
 for update;
 if not found then raise exception 'invitation_not_pending' using errcode='P0002'; end if;
 if v_inv.expires_at is not null and v_inv.expires_at<=now() then
  update public.group_conversation_invitations set status='expired',responded_at=now() where id=v_inv.id;
  raise exception 'invitation_expired';
 end if;
 select * into v_group from public.group_conversations where id=v_inv.group_id for update;
 if v_group.status='closed' then raise exception 'group_closed'; end if;
 if p_accept then
  update public.group_conversation_invitations set status='accepted',responded_at=now() where id=v_inv.id;
  insert into public.group_conversation_members(group_id,user_id,role,status,joined_at)
  values(v_inv.group_id,v_uid,'member','active',now())
  on conflict(group_id,user_id) do update set role='member',status='active',joined_at=now(),left_at=null,role_assigned_at=now();
  select count(*) into v_count from public.group_conversation_members where group_id=v_inv.group_id and status='active';
  if v_count>=3 then
   update public.group_conversations set status='active',ever_activated=true,updated_at=now() where id=v_inv.group_id;
  end if;
 else
  update public.group_conversation_invitations set status='refused',responded_at=now() where id=v_inv.id;
 end if;
 return jsonb_build_object('accepted',p_accept,'group_id',v_inv.group_id);
end $$;

create or replace function public.get_group_members(p_group_id uuid)
returns table(user_id uuid,role text,status text,joined_at timestamptz,display_name text,avatar_url text)
language plpgsql security definer set search_path = ''
as $$
declare v_uid uuid:=auth.uid();
begin
 if v_uid is null then raise exception 'authentication_required' using errcode='28000'; end if;
 if not exists(select 1 from public.group_conversation_members where group_id=p_group_id and user_id=v_uid and status='active') then
  raise exception 'not_a_group_member' using errcode='42501';
 end if;
 return query select m.user_id,m.role,m.status,m.joined_at,
  coalesce(nullif(btrim(concat_ws(' ',p.first_name,p.last_name)),''),p.username,''),
  p.photo_url
 from public.group_conversation_members m left join public.user_profiles p on p.user_id=m.user_id
 where m.group_id=p_group_id and m.status='active' order by m.joined_at,m.user_id;
end $$;

create or replace function public.get_group_messages(p_group_id uuid,p_limit integer default 50,p_before timestamptz default null)
returns setof jsonb language plpgsql security definer set search_path = ''
as $$
declare v_uid uuid:=auth.uid(); v_activated boolean; v_status text;
begin
 if v_uid is null then raise exception 'authentication_required' using errcode='28000'; end if;
 if not exists(select 1 from public.group_conversation_members where group_id=p_group_id and user_id=v_uid and status='active') then
  raise exception 'not_a_group_member' using errcode='42501';
 end if;
 select ever_activated,status into v_activated,v_status from public.group_conversations where id=p_group_id;
 if v_status='closed' or not v_activated then return; end if;
 return query select to_jsonb(x) from (
  select msg.id,msg.group_id as conversation_id,msg.sender_id,
    coalesce(nullif(btrim(concat_ws(' ',p.first_name,p.last_name)),''),p.username,'') as sender_name,
    msg.text as content,msg.message_type as type,msg.media_paths as media_urls,
    msg.replied_to_id,msg.created_at,msg.edited_at,msg.deleted_at
  from public.group_messages msg
  left join public.user_profiles p on p.user_id=msg.sender_id
  where msg.group_id=p_group_id and (p_before is null or msg.created_at<p_before)
  order by msg.created_at desc,msg.id desc limit greatest(1,least(coalesce(p_limit,50),100))
 ) x;
end $$;

create or replace function public.insert_group_message(
 p_group_id uuid,p_text text default null,p_type text default 'text',
 p_media_paths text[] default '{}',p_replied_to_id uuid default null
)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_uid uuid:=auth.uid(); v_group public.group_conversations%rowtype; v_msg public.group_messages%rowtype;
begin
 if v_uid is null then raise exception 'authentication_required' using errcode='28000'; end if;
 select * into v_group from public.group_conversations where id=p_group_id for update;
 if not found or v_group.status='closed' or not v_group.ever_activated then raise exception 'group_not_active'; end if;
 if not exists(select 1 from public.group_conversation_members where group_id=p_group_id and user_id=v_uid and status='active') then
  raise exception 'not_a_group_member' using errcode='42501';
 end if;
 if p_type not in ('text','image','video','audio','file','system') then raise exception 'invalid_message_type'; end if;
 if p_type<>'system' and nullif(btrim(coalesce(p_text,'')),'') is null and cardinality(coalesce(p_media_paths,'{}'))=0 then raise exception 'empty_message'; end if;
 if p_replied_to_id is not null and not exists(select 1 from public.group_messages where id=p_replied_to_id and group_id=p_group_id) then raise exception 'invalid_reply_target'; end if;
 insert into public.group_messages(group_id,sender_id,text,message_type,media_paths,replied_to_id)
 values(p_group_id,v_uid,nullif(btrim(p_text),''),p_type,coalesce(p_media_paths,'{}'),p_replied_to_id)
 returning * into v_msg;
 insert into public.group_message_receipts(message_id,user_id,delivered_at,read_at)
 select v_msg.id,m.user_id,case when m.user_id=v_uid then now() else null end,case when m.user_id=v_uid then now() else null end
 from public.group_conversation_members m where m.group_id=p_group_id and m.status='active'
 on conflict(message_id,user_id) do nothing;
 update public.group_conversations set updated_at=now() where id=p_group_id;
 return jsonb_build_object('id',v_msg.id,'group_id',v_msg.group_id,'conversation_id',v_msg.group_id,
  'sender_id',v_msg.sender_id,'text',v_msg.text,'content',v_msg.text,'type',v_msg.message_type,
  'media_urls',v_msg.media_paths,'replied_to_id',v_msg.replied_to_id,'created_at',v_msg.created_at);
end $$;

create or replace function public.mark_group_conversation_read(p_group_id uuid,p_last_read_message_id uuid default null,p_last_read_at timestamptz default now())
returns void language plpgsql security definer set search_path = ''
as $$
declare v_uid uuid:=auth.uid();
begin
 if v_uid is null then raise exception 'authentication_required' using errcode='28000'; end if;
 update public.group_conversation_members set last_read_at=coalesce(p_last_read_at,now()),last_read_message_id=p_last_read_message_id
 where group_id=p_group_id and user_id=v_uid and status='active';
 if not found then raise exception 'not_a_group_member' using errcode='42501'; end if;
 update public.group_message_receipts r set delivered_at=coalesce(r.delivered_at,now()),read_at=coalesce(r.read_at,now())
 from public.group_messages m where r.message_id=m.id and m.group_id=p_group_id and r.user_id=v_uid and m.sender_id<>v_uid;
end $$;

create or replace function public.set_group_personal_wallpaper(p_group_id uuid,p_wallpaper_key text)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_uid uuid:=auth.uid();
begin
 if v_uid is null then raise exception 'authentication_required' using errcode='28000'; end if;
 if p_wallpaper_key not in ('none','fond1','fond2','fond3') then raise exception 'invalid_wallpaper'; end if;
 if not exists(select 1 from public.group_conversation_members where group_id=p_group_id and user_id=v_uid and status='active') then raise exception 'not_a_group_member' using errcode='42501'; end if;
 insert into public.group_member_wallpapers(group_id,user_id,wallpaper_key,updated_at)
 values(p_group_id,v_uid,p_wallpaper_key,now())
 on conflict(group_id,user_id) do update set wallpaper_key=excluded.wallpaper_key,updated_at=now();
end $$;


create or replace function public.get_group_personal_wallpaper(p_group_id uuid)
returns text language plpgsql security definer set search_path = ''
as $$
declare v_uid uuid := auth.uid(); v_wallpaper text;
begin
 if v_uid is null then raise exception 'authentication_required' using errcode='28000'; end if;
 if not exists(select 1 from public.group_conversation_members where group_id=p_group_id and user_id=v_uid and status='active') then
  raise exception 'not_a_group_member' using errcode='42501';
 end if;
 select wallpaper_key into v_wallpaper from public.group_member_wallpapers where group_id=p_group_id and user_id=v_uid;
 return coalesce(v_wallpaper,'none');
end $$;

create or replace function public.leave_group_conversation(p_group_id uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_uid uuid:=auth.uid(); v_role text; v_next uuid; v_count integer;
begin
 if v_uid is null then raise exception 'authentication_required' using errcode='28000'; end if;
 perform 1 from public.group_conversations where id=p_group_id for update;
 select role into v_role from public.group_conversation_members where group_id=p_group_id and user_id=v_uid and status='active' for update;
 if not found then raise exception 'not_a_group_member'; end if;
 if v_role='owner' then
  v_next:=public.group_next_owner(p_group_id,v_uid);
  if v_next is not null then
   update public.group_conversation_members set role='owner',role_assigned_at=now() where group_id=p_group_id and user_id=v_next and status='active';
  end if;
 end if;
 update public.group_conversation_members set status='left',left_at=now() where group_id=p_group_id and user_id=v_uid;
 delete from public.group_member_wallpapers where group_id=p_group_id and user_id=v_uid;
 select count(*) into v_count from public.group_conversation_members where group_id=p_group_id and status='active';
 if v_count=0 then update public.group_conversations set status='closed',closed_at=now(),updated_at=now() where id=p_group_id; end if;
end $$;

create or replace function public.remove_group_member(p_group_id uuid,p_user_id uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_uid uuid:=auth.uid(); v_target_role text; v_next uuid; v_count integer;
begin
 if v_uid is null then raise exception 'authentication_required' using errcode='28000'; end if;
 if v_uid=p_user_id then raise exception 'use_leave_group'; end if;
 if not exists(select 1 from public.group_conversation_members where group_id=p_group_id and user_id=v_uid and status='active' and role in ('owner','administrator')) then raise exception 'not_allowed' using errcode='42501'; end if;
 select role into v_target_role from public.group_conversation_members where group_id=p_group_id and user_id=p_user_id and status='active' for update;
 if not found then raise exception 'member_not_active'; end if;
 if v_target_role='owner' then raise exception 'owner_must_leave_to_transfer'; end if;
 if (select role from public.group_conversation_members where group_id=p_group_id and user_id=v_uid)='administrator' and v_target_role='administrator' then raise exception 'admin_cannot_remove_admin'; end if;
 update public.group_conversation_members set status='removed',left_at=now() where group_id=p_group_id and user_id=p_user_id;
 delete from public.group_member_wallpapers where group_id=p_group_id and user_id=p_user_id;
 select count(*) into v_count from public.group_conversation_members where group_id=p_group_id and status='active';
 if v_count=0 then update public.group_conversations set status='closed',closed_at=now(),updated_at=now() where id=p_group_id; end if;
end $$;

create or replace function public.change_group_member_role(p_group_id uuid,p_user_id uuid,p_role text)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_uid uuid:=auth.uid();
begin
 if v_uid is null then raise exception 'authentication_required' using errcode='28000'; end if;
 if p_role not in ('administrator','member') then raise exception 'invalid_role'; end if;
 if not exists(select 1 from public.group_conversation_members where group_id=p_group_id and user_id=v_uid and status='active' and role='owner') then raise exception 'owner_only' using errcode='42501'; end if;
 if not exists(select 1 from public.group_conversation_members where group_id=p_group_id and user_id=p_user_id and status='active' and role<>'owner') then raise exception 'target_not_eligible'; end if;
 update public.group_conversation_members set role=p_role,role_assigned_at=now() where group_id=p_group_id and user_id=p_user_id;
end $$;

do $$
declare v_fn regprocedure;
begin
 foreach v_fn in array array[
  'public.get_my_group_conversations()'::regprocedure,
  'public.get_my_pending_group_invitations()'::regprocedure,
  'public.create_group_conversation(text,text,uuid[])'::regprocedure,
  'public.invite_group_members(uuid,uuid[])'::regprocedure,
  'public.respond_to_group_invitation(uuid,boolean)'::regprocedure,
  'public.get_group_members(uuid)'::regprocedure,
  'public.get_group_messages(uuid,integer,timestamptz)'::regprocedure,
  'public.insert_group_message(uuid,text,text,text[],uuid)'::regprocedure,
  'public.mark_group_conversation_read(uuid,uuid,timestamptz)'::regprocedure,
  'public.set_group_personal_wallpaper(uuid,text)'::regprocedure,
  'public.get_group_personal_wallpaper(uuid)'::regprocedure,
  'public.leave_group_conversation(uuid)'::regprocedure,
  'public.remove_group_member(uuid,uuid)'::regprocedure,
  'public.change_group_member_role(uuid,uuid,text)'::regprocedure
 ] loop
  execute format('revoke all on function %s from public, anon',v_fn);
  execute format('grant execute on function %s to authenticated',v_fn);
 end loop;
end $$;

-- Security: base tables remain inaccessible to anon/authenticated. Access is through these
-- SECURITY DEFINER RPCs. Group media must use a private bucket with separate reviewed policies.
