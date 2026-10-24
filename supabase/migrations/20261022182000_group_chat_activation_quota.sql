-- Make group activation threshold configurable from Scrole Admin.
alter table public.scrole_quota_settings
  drop constraint if exists scrole_quota_settings_category_check;
alter table public.scrole_quota_settings
  add constraint scrole_quota_settings_category_check
  check (category = any (array['agenda','events','team','subscriptions','messaging']::text[]));

insert into public.scrole_quota_settings
  (quota_key, value, label, description, category, min_value, max_value, updated_at)
values
  ('group_chat_min_active_members', 3,
   'Membres requis pour activer une discussion de groupe',
   'Nombre de membres actifs ayant accepté leur invitation avant que le groupe puisse envoyer des messages. Après activation, le groupe reste utilisable même si le nombre de membres diminue.',
   'messaging', 2, 20, now())
on conflict (quota_key) do update set
  label = excluded.label,
  description = excluded.description,
  category = excluded.category,
  min_value = excluded.min_value,
  max_value = excluded.max_value;

create or replace function public.respond_to_group_invitation(p_invitation_id uuid,p_accept boolean)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
 v_uid uuid:=auth.uid();
 v_inv public.group_conversation_invitations%rowtype;
 v_group public.group_conversations%rowtype;
 v_count integer;
 v_min_members integer;
begin
 if v_uid is null then raise exception 'authentication_required' using errcode='28000'; end if;
 select * into v_inv
 from public.group_conversation_invitations
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
  on conflict(group_id,user_id) do update
    set role='member',status='active',joined_at=now(),left_at=null,role_assigned_at=now();
  select count(*) into v_count
  from public.group_conversation_members
  where group_id=v_inv.group_id and status='active';
  if not v_group.ever_activated then
    select value into v_min_members
    from public.scrole_quota_settings
    where quota_key='group_chat_min_active_members';
    v_min_members := greatest(2, coalesce(v_min_members,3));
    if v_count>=v_min_members then
      update public.group_conversations
      set status='active',ever_activated=true,updated_at=now()
      where id=v_inv.group_id;
    end if;
  end if;
 else
  update public.group_conversation_invitations set status='refused',responded_at=now() where id=v_inv.id;
 end if;
 return jsonb_build_object('accepted',p_accept,'group_id',v_inv.group_id);
end $$;

create or replace function public.get_scrole_public_quota_settings()
returns jsonb
language sql stable security definer set search_path = ''
as $$
  select jsonb_build_object(
    'noncert_agenda_max_events', (select value from public.scrole_quota_settings where quota_key = 'noncert_agenda_max_events'),
    'noncert_agenda_horizon_months', (select value from public.scrole_quota_settings where quota_key = 'noncert_agenda_horizon_months'),
    'noncert_event_horizon_months', (select value from public.scrole_quota_settings where quota_key = 'noncert_event_horizon_months'),
    'noncert_event_max_duration_days', (select value from public.scrole_quota_settings where quota_key = 'noncert_event_max_duration_days'),
    'noncert_event_agenda_max_people', (select value from public.scrole_quota_settings where quota_key = 'noncert_event_agenda_max_people'),
    'certified_event_horizon_months', (select value from public.scrole_quota_settings where quota_key = 'certified_event_horizon_months'),
    'group_chat_min_active_members', (select value from public.scrole_quota_settings where quota_key = 'group_chat_min_active_members')
  );
$$;
