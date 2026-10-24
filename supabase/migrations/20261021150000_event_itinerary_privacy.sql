alter table public.user_privacy
  add column if not exists event_itinerary_visibility text not null default 'only_me';

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'user_privacy_event_itinerary_visibility_check'
      and conrelid = 'public.user_privacy'::regclass
  ) then
    alter table public.user_privacy
      add constraint user_privacy_event_itinerary_visibility_check
      check (event_itinerary_visibility in ('only_me', 'friends', 'followers', 'everyone'));
  end if;
end
$$;

create or replace function public.get_external_event_itinerary(
  p_user_id uuid,
  p_event_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_me uuid := auth.uid();
  v_visibility text := 'only_me';
  v_connected boolean := false;
  v_is_follower boolean := false;
  v_blocked boolean := false;
  v_is_event_member boolean := false;
  v_plans jsonb := '[]'::jsonb;
begin
  if v_me is null then
    raise exception 'not_authenticated';
  end if;
  if p_user_id is null or p_event_id is null then
    raise exception 'invalid_event_itinerary_request';
  end if;

  select coalesce(up.event_itinerary_visibility, 'only_me')
    into v_visibility
  from public.user_privacy up
  where up.user_id = p_user_id;
  v_visibility := coalesce(v_visibility, 'only_me');

  select exists (
    select 1
    from public.blocage_utilisateur b
    where b.statut
      and ((b.bloqueur_id = v_me and b.bloque_id = p_user_id)
        or (b.bloqueur_id = p_user_id and b.bloque_id = v_me))
      and (b.bloque_jusquau is null or b.bloque_jusquau > now())
  ) into v_blocked;

  if v_blocked then
    raise exception 'event_itinerary_not_available';
  end if;

  select exists (
    select 1
    from public.friendships f
    where f.user_a_id = least(v_me, p_user_id)
      and f.user_b_id = greatest(v_me, p_user_id)
  ) into v_connected;

  select exists (
    select 1
    from public.user_follows f
    where f.follower_id = v_me and f.followed_id = p_user_id
  ) into v_is_follower;

  if v_me <> p_user_id and not (
    v_visibility = 'everyone'
    or (v_visibility = 'friends' and v_connected)
    or (v_visibility = 'followers' and v_is_follower)
  ) then
    raise exception 'event_itinerary_private';
  end if;

  select exists (
    select 1
    from public.events e
    where e.id = p_event_id
      and e.status = 'active'
      and public.can_view_event(e.id)
      and (
        e.creator_id = p_user_id
        or exists (
          select 1 from public.event_co_creators cc
          where cc.event_id = e.id and cc.user_id = p_user_id and cc.status = 'acceptee'
        )
        or exists (
          select 1 from public.event_staff es
          where es.event_id = e.id and es.user_id = p_user_id and es.status = 'acceptee'
        )
        or exists (
          select 1 from public.event_calendar ec
          where ec.event_id = e.id and ec.user_id = p_user_id
        )
        or exists (
          select 1 from public.event_checkins ci
          where ci.event_id = e.id and ci.user_id = p_user_id and ci.status = 'valid'
        )
        or exists (
          select 1 from public.event_guest_invitations gi
          where gi.event_id = e.id and gi.user_id = p_user_id and gi.status = 'acceptee'
        )
      )
  ) into v_is_event_member;

  if not v_is_event_member then
    raise exception 'event_itinerary_not_available';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object('planned_date', p.planned_date, 'plan', p.plan)
      order by p.planned_date
    ),
    '[]'::jsonb
  )
  into v_plans
  from public.event_itinerary_plans p
  where p.user_id = p_user_id and p.event_id = p_event_id;

  return jsonb_build_object(
    'user_id', p_user_id,
    'event_id', p_event_id,
    'plans', v_plans
  );
end;
$function$;

revoke all on function public.get_external_event_itinerary(uuid, uuid) from public;
revoke all on function public.get_external_event_itinerary(uuid, uuid) from anon;
grant execute on function public.get_external_event_itinerary(uuid, uuid) to authenticated;
