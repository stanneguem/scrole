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
      and type in ('community_salon_message', 'community_salon_reply')
      and data ->> 'salon_id' = p_salon_id::text;
  else
    delete from private.salon_active_presence
    where salon_id = p_salon_id
      and user_id = v_user_id;
  end if;
end;
$$;
