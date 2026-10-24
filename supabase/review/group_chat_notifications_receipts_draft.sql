-- REVIEW ONLY: group invitation notifications and receipt query.
-- Assumes the existing public.notifications columns were inspected on the live project.
-- Notification payload deliberately contains IDs only, not private message content.

create or replace function public.notify_group_invitation_created()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare v_group_name text;
begin
  if new.status <> 'pending' then return new; end if;
  select name into v_group_name
  from public.group_conversations where id = new.group_id;

  insert into public.notifications(user_id,type,title,body,actor_id,data,created_at)
  values (
    new.invited_user_id,
    'group_invitation',
    'Invitation à un groupe',
    'Vous avez reçu une invitation à rejoindre un groupe.',
    new.invited_by,
    jsonb_build_object(
      'group_id', new.group_id,
      'invitation_id', new.id,
      'group_name', coalesce(v_group_name,'')
    ),
    now()
  );
  return new;
end $$;

drop trigger if exists group_invitation_notification_trigger
on public.group_conversation_invitations;
create trigger group_invitation_notification_trigger
after insert on public.group_conversation_invitations
for each row execute function public.notify_group_invitation_created();

revoke all on function public.notify_group_invitation_created() from public, anon, authenticated;

create or replace function public.get_group_message_receipts(p_message_id uuid)
returns table(user_id uuid, delivered_at timestamptz, read_at timestamptz)
language plpgsql security definer set search_path = ''
as $$
declare v_uid uuid := auth.uid(); v_group_id uuid;
begin
  if v_uid is null then raise exception 'authentication_required' using errcode='28000'; end if;
  select group_id into v_group_id from public.group_messages where id=p_message_id;
  if v_group_id is null then raise exception 'message_not_found' using errcode='P0002'; end if;
  if not public.group_is_active_member(v_group_id,v_uid) then
    raise exception 'not_a_group_member' using errcode='42501';
  end if;
  return query
  select r.user_id,r.delivered_at,r.read_at
  from public.group_message_receipts r
  where r.message_id=p_message_id
  order by r.user_id;
end $$;

revoke all on function public.get_group_message_receipts(uuid) from public, anon;
grant execute on function public.get_group_message_receipts(uuid) to authenticated;

-- For read receipts, the existing mark_group_conversation_read function updates receipts.
-- Inserted messages create one receipt row for each member active at send time.
