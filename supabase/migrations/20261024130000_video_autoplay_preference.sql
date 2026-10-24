-- Persist video autoplay and all supported privacy/preferences settings.
-- Additive schema change; existing users keep autoplay enabled by default.
begin;

alter table public.user_preferences
  add column if not exists auto_play_videos boolean not null default true;

create or replace function public.update_user_settings(p_changes jsonb)
returns jsonb
language plpgsql
set search_path to 'public'
as $function$
declare
  v_user_id uuid := auth.uid();
  v_preferences jsonb;
  v_privacy jsonb;
  v_cursor bigint;
  v_pref_changed boolean := false;
  v_priv_changed boolean := false;
begin
  if v_user_id is null then
    raise exception 'Utilisateur non authentifié';
  end if;
  if p_changes is null or jsonb_typeof(p_changes) <> 'object' then
    raise exception 'p_changes doit être un objet JSON';
  end if;

  insert into public.user_preferences (user_id)
  values (v_user_id) on conflict (user_id) do nothing;
  insert into public.user_privacy (user_id)
  values (v_user_id) on conflict (user_id) do nothing;

  update public.user_preferences
  set
    language = case when p_changes ? 'language' then p_changes->>'language' else language end,
    theme = case when p_changes ? 'theme' then p_changes->>'theme' else theme end,
    notifications_enabled = case when p_changes ? 'notifications_enabled' then (p_changes->>'notifications_enabled')::boolean else notifications_enabled end,
    notif_push = case when p_changes ? 'notif_push' then (p_changes->>'notif_push')::boolean else notif_push end,
    notif_messages = case when p_changes ? 'notif_messages' then (p_changes->>'notif_messages')::boolean else notif_messages end,
    notif_evenements = case when p_changes ? 'notif_evenements' then (p_changes->>'notif_evenements')::boolean else notif_evenements end,
    notif_communautes = case when p_changes ? 'notif_communautes' then (p_changes->>'notif_communautes')::boolean else notif_communautes end,
    notif_social = case when p_changes ? 'notif_social' then (p_changes->>'notif_social')::boolean else notif_social end,
    auto_play_videos = case when p_changes ? 'auto_play_videos' then (p_changes->>'auto_play_videos')::boolean else auto_play_videos end,
    updated_at = now()
  where user_id = v_user_id
    and (
      p_changes ? 'language' or p_changes ? 'theme'
      or p_changes ? 'notifications_enabled' or p_changes ? 'notif_push'
      or p_changes ? 'notif_messages' or p_changes ? 'notif_evenements'
      or p_changes ? 'notif_communautes' or p_changes ? 'notif_social'
      or p_changes ? 'auto_play_videos'
    );
  v_pref_changed := found;

  update public.user_privacy
  set
    profile_visibility = case when p_changes ? 'profile_visibility' then p_changes->>'profile_visibility' else profile_visibility end,
    show_online_status = case when p_changes ? 'show_online_status' then (p_changes->>'show_online_status')::boolean else show_online_status end,
    allow_messages_from = case when p_changes ? 'allow_messages_from' then p_changes->>'allow_messages_from' else allow_messages_from end,
    afficher_pays = case when p_changes ? 'afficher_pays' then (p_changes->>'afficher_pays')::boolean else afficher_pays end,
    afficher_ville = case when p_changes ? 'afficher_ville' then (p_changes->>'afficher_ville')::boolean else afficher_ville end,
    afficher_derniere_connexion = case when p_changes ? 'afficher_derniere_connexion' then (p_changes->>'afficher_derniere_connexion')::boolean else afficher_derniere_connexion end,
    event_itinerary_visibility = case when p_changes ? 'event_itinerary_visibility' then p_changes->>'event_itinerary_visibility' else event_itinerary_visibility end,
    updated_at = now()
  where user_id = v_user_id
    and (
      p_changes ? 'profile_visibility' or p_changes ? 'show_online_status'
      or p_changes ? 'allow_messages_from' or p_changes ? 'afficher_pays'
      or p_changes ? 'afficher_ville' or p_changes ? 'afficher_derniere_connexion'
      or p_changes ? 'event_itinerary_visibility'
    );
  v_priv_changed := found;

  if not v_pref_changed and not v_priv_changed then
    raise exception 'Aucun champ de préférence ou confidentialité reconnu';
  end if;

  select to_jsonb(up) - 'user_id' into v_preferences
  from public.user_preferences up where up.user_id = v_user_id;
  select to_jsonb(uv) - 'user_id' into v_privacy
  from public.user_privacy uv where uv.user_id = v_user_id;

  insert into public.sync_log (user_id, entity_type, entity_id, action, payload)
  values (v_user_id, 'user_settings', v_user_id::text, 'updated',
          jsonb_build_object('preferences', v_preferences, 'privacy', v_privacy))
  returning id into v_cursor;

  return jsonb_build_object('preferences', v_preferences, 'privacy', v_privacy, 'server_cursor', v_cursor);
end;
$function$;

commit;
