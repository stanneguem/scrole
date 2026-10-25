-- Scrole follow semantics: following is immediate for public and private profiles.
-- A mutual follow is represented as friendship by the existing user_follows trigger.
-- Keep follow_requests only for legacy/invitation compatibility; follow_user no longer creates them.

create or replace function public.follow_user(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_me uuid := auth.uid();
  v_reverse boolean;
begin
  if v_me is null then
    raise exception 'Authentication required';
  end if;

  if p_user_id is null or p_user_id = v_me then
    raise exception 'Vous ne pouvez pas vous suivre vous-même';
  end if;

  if not exists (
    select 1
      from public.user_profiles up
     where up.user_id = p_user_id
       and up.account_status = 'active'
       and up.deleted_at is null
  ) then
    raise exception 'Utilisateur introuvable';
  end if;

  if not exists (
    select 1
      from public.user_profiles up
     where up.user_id = v_me
       and up.account_status = 'active'
       and up.deleted_at is null
  ) then
    raise exception 'Compte indisponible';
  end if;

  if private.users_blocked(v_me, p_user_id) then
    raise exception 'Action impossible';
  end if;

  -- Idempotent: a repeated tap does not create a duplicate follow or notification.
  if exists (
    select 1 from public.user_follows f
     where f.follower_id = v_me and f.followed_id = p_user_id
  ) then
    return public.get_relationship(p_user_id);
  end if;

  if (
    select count(*) from public.user_follows f
     where f.follower_id = v_me
       and f.created_at > now() - interval '24 hours'
  ) >= 200 then
    raise exception 'Limite atteinte : 200 nouveaux abonnements par 24 heures';
  end if;

  if (
    select count(*) from public.user_follows f
     where f.follower_id = v_me
  ) >= 5000 then
    raise exception 'Limite atteinte : 5000 abonnements maximum';
  end if;

  v_reverse := exists (
    select 1 from public.user_follows f
     where f.follower_id = p_user_id and f.followed_id = v_me
  );

  -- Follow immediately regardless of profile privacy. Privacy controls what
  -- profile content is visible, not whether the follower needs approval.
  insert into public.user_follows (follower_id, followed_id)
  values (v_me, p_user_id)
  on conflict do nothing;

  -- Remove any stale pending request for this pair so UI state is consistent.
  delete from public.follow_requests
   where requester_id = v_me and target_id = p_user_id;

  if v_reverse then
    perform private.notify_community_user(
      p_user_id,
      'new_friend',
      v_me,
      jsonb_build_object('user_id', v_me, 'actor_id', v_me),
      'Nouvel ami',
      'Vous êtes maintenant amis.'
    );
  elsif not exists (
    select 1
      from public.notifications n
     where n.user_id = p_user_id
       and n.type = 'new_follower'
       and n.actor_id = v_me
       and n.created_at > now() - interval '24 hours'
  ) then
    perform private.notify_community_user(
      p_user_id,
      'new_follower',
      v_me,
      jsonb_build_object('user_id', v_me, 'actor_id', v_me),
      'Nouvel abonné',
      'Quelqu''un a commencé à vous suivre.'
    );
  end if;

  perform private.broadcast_relationship(v_me, p_user_id);
  return public.get_relationship(p_user_id);
end;
$function$;
