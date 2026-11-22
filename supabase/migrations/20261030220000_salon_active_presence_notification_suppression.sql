create table if not exists private.salon_active_presence (
  salon_id uuid not null,
  user_id uuid not null,
  active_since timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  primary key (salon_id, user_id)
);

revoke all on private.salon_active_presence from public, anon, authenticated;

create or replace function public.set_salon_active_presence(
  p_salon_id uuid,
  p_active boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'authentication_required';
  end if;

  if not exists (
    select 1
    from public.community_salon_members m
    where m.salon_id = p_salon_id
      and m.user_id = v_user_id
  ) then
    raise exception 'salon_membership_required';
  end if;

  if p_active then
    insert into private.salon_active_presence (
      salon_id, user_id, active_since, last_seen_at
    )
    values (p_salon_id, v_user_id, now(), now())
    on conflict (salon_id, user_id) do update
      set active_since = now(),
          last_seen_at = now();

    delete from public.notifications
    where user_id = v_user_id
      and type = 'community_salon_message'
      and data ->> 'salon_id' = p_salon_id::text;
  else
    delete from private.salon_active_presence
    where salon_id = p_salon_id
      and user_id = v_user_id;
  end if;
end;
$$;

revoke all on function public.set_salon_active_presence(uuid, boolean) from public, anon;
grant execute on function public.set_salon_active_presence(uuid, boolean) to authenticated;

create or replace function public.notify_community_salon_message()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
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
