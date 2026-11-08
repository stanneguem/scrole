-- Keep personal itinerary plans editable only on selected, non-past event days.
CREATE OR REPLACE FUNCTION public.enforce_event_itinerary_plan_dates()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id uuid;
  v_event_id uuid;
  v_planned_date date;
  v_start_date date;
  v_end_date date;
  v_is_selected boolean;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_user_id := OLD.user_id;
    v_event_id := OLD.event_id;
    v_planned_date := OLD.planned_date;
  ELSE
    v_user_id := NEW.user_id;
    v_event_id := NEW.event_id;
    v_planned_date := NEW.planned_date;
  END IF;

  IF auth.uid() IS NULL OR v_user_id <> auth.uid() THEN
    RAISE EXCEPTION 'Vous ne pouvez modifier que votre propre planning';
  END IF;
  IF v_planned_date < timezone('Africa/Douala', now())::date THEN
    RAISE EXCEPTION 'Une journée passée est consultable mais ne peut plus être modifiée';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.event_calendar ec
    WHERE ec.user_id = v_user_id AND ec.event_id = v_event_id
  ) THEN
    RAISE EXCEPTION 'Cet événement ne figure pas dans votre agenda personnel';
  END IF;

  SELECT timezone('Africa/Douala', e.starts_at)::date,
         timezone('Africa/Douala', e.ends_at)::date
    INTO v_start_date, v_end_date
  FROM public.events e
  WHERE e.id = v_event_id;

  IF v_start_date IS NULL OR v_planned_date < v_start_date OR v_planned_date > v_end_date THEN
    RAISE EXCEPTION 'La date choisie ne fait pas partie de cet événement';
  END IF;

  IF v_start_date = v_end_date THEN
    v_is_selected := (v_planned_date = v_start_date);
  ELSE
    v_is_selected := EXISTS (
      SELECT 1 FROM public.event_calendar_days cd
      WHERE cd.user_id = v_user_id
        AND cd.event_id = v_event_id
        AND cd.event_date = v_planned_date
    );
  END IF;
  IF NOT v_is_selected THEN
    RAISE EXCEPTION 'Vous ne pouvez organiser que les journées que vous avez ajoutées à votre agenda';
  END IF;

  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS event_itinerary_plan_dates_guard ON public.event_itinerary_plans;
CREATE TRIGGER event_itinerary_plan_dates_guard
BEFORE INSERT OR UPDATE OR DELETE ON public.event_itinerary_plans
FOR EACH ROW EXECUTE FUNCTION public.enforce_event_itinerary_plan_dates();

-- Let authorized Scrole administrators validate event activities just like event owners.
DO $$
DECLARE
  v_definition text;
  v_old text := 'v_is_manager := public.is_event_owner(p_event_id);';
  v_new text := 'v_is_manager := public.is_event_owner(p_event_id) OR public.is_admin_or_above();';
BEGIN
  v_definition := pg_get_functiondef('public.checkin_scan(uuid,uuid,uuid,integer)'::regprocedure);
  IF position(v_old in v_definition) = 0 THEN
    RAISE EXCEPTION 'Expected checkin_scan authorization statement not found';
  END IF;
  EXECUTE replace(v_definition, v_old, v_new);
END $$;

-- Expose actual validated activity check-ins with their local event day to the
-- profile itinerary, while preserving the existing privacy and attendance gates.
CREATE OR REPLACE FUNCTION public.get_external_event_itinerary(p_user_id uuid, p_event_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_me uuid := auth.uid();
  v_visibility text := 'only_me';
  v_profile_visibility text := 'public';
  v_connected boolean := false;
  v_is_follower boolean := false;
  v_blocked boolean := false;
  v_is_event_member boolean := false;
  v_plans jsonb := '[]'::jsonb;
  v_validated_activities jsonb := '[]'::jsonb;
BEGIN
  IF v_me IS NULL OR p_user_id IS NULL OR p_event_id IS NULL THEN
    RAISE EXCEPTION 'invalid_event_itinerary_request';
  END IF;

  SELECT coalesce(event_itinerary_visibility,'only_me') INTO v_visibility
    FROM public.user_privacy WHERE user_id=p_user_id;
  SELECT coalesce(profile_visibility,'public') INTO v_profile_visibility
    FROM public.user_privacy WHERE user_id=p_user_id;

  SELECT EXISTS (SELECT 1 FROM public.blocage_utilisateur b WHERE b.statut
    AND ((b.bloqueur_id=v_me AND b.bloque_id=p_user_id) OR (b.bloqueur_id=p_user_id AND b.bloque_id=v_me))
    AND (b.bloque_jusquau IS NULL OR b.bloque_jusquau>now())) INTO v_blocked;
  IF v_blocked THEN RAISE EXCEPTION 'event_itinerary_not_available'; END IF;

  SELECT EXISTS (SELECT 1 FROM public.friendships f
    WHERE f.user_a_id=least(v_me,p_user_id) AND f.user_b_id=greatest(v_me,p_user_id)) INTO v_connected;
  SELECT EXISTS (SELECT 1 FROM public.user_follows f
    WHERE f.follower_id=v_me AND f.followed_id=p_user_id) INTO v_is_follower;

  IF v_me<>p_user_id THEN
    IF v_profile_visibility IN ('private','prive','privé') AND NOT v_connected AND NOT v_is_follower THEN
      RAISE EXCEPTION 'event_itinerary_not_available';
    END IF;
    IF NOT (v_visibility='everyone' OR (v_visibility='friends' AND v_connected)
      OR (v_visibility='followers' AND v_is_follower)) THEN
      RAISE EXCEPTION 'event_itinerary_private';
    END IF;
  END IF;

  SELECT EXISTS (SELECT 1 FROM public.events e
    WHERE e.id=p_event_id AND e.status IN ('active','completed') AND public.can_view_event(e.id)
      AND EXISTS (SELECT 1 FROM public.event_checkins ci
        WHERE ci.event_id=e.id AND ci.user_id=p_user_id
          AND ci.status='valid' AND ci.activity_id IS NULL)) INTO v_is_event_member;
  IF NOT v_is_event_member THEN RAISE EXCEPTION 'event_itinerary_not_available'; END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object('planned_date',p.planned_date,'plan',p.plan)
    ORDER BY p.planned_date),'[]'::jsonb)
    INTO v_plans FROM public.event_itinerary_plans p
    WHERE p.user_id=p_user_id AND p.event_id=p_event_id;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
      'planned_date', timezone('Africa/Douala', ci.created_at)::date,
      'activity_id', ci.activity_id
    ) ORDER BY ci.created_at),'[]'::jsonb)
    INTO v_validated_activities
    FROM public.event_checkins ci
    WHERE ci.user_id=p_user_id AND ci.event_id=p_event_id
      AND ci.status='valid' AND ci.activity_id IS NOT NULL;

  RETURN jsonb_build_object(
    'user_id',p_user_id,
    'event_id',p_event_id,
    'plans',v_plans,
    'validated_activities',v_validated_activities
  );
END;
$function$;

-- A one-day event is implicitly selected when it is added to the personal agenda.
-- Multi-day events continue to require explicit event_calendar_days selections.
CREATE OR REPLACE FUNCTION public.get_my_event_calendar_days(p_event_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SET search_path TO ''
AS $function$
  SELECT coalesce(
    jsonb_agg(jsonb_build_object('date', days.event_date) ORDER BY days.event_date),
    '[]'::jsonb
  )
  FROM (
    SELECT cd.event_date
    FROM public.event_calendar_days cd
    WHERE cd.user_id = (SELECT auth.uid())
      AND cd.event_id = p_event_id
    UNION
    SELECT timezone('Africa/Douala', e.starts_at)::date
    FROM public.events e
    JOIN public.event_calendar ec
      ON ec.event_id = e.id
     AND ec.user_id = (SELECT auth.uid())
    WHERE e.id = p_event_id
      AND timezone('Africa/Douala', e.starts_at)::date =
          timezone('Africa/Douala', e.ends_at)::date
      AND NOT EXISTS (
        SELECT 1 FROM public.event_calendar_days cd
        WHERE cd.user_id = ec.user_id AND cd.event_id = e.id
      )
  ) AS days;
$function$;

-- Return validated activity ids tagged with the event-local date (not device timezone).
CREATE OR REPLACE FUNCTION public.get_my_validated_event_activity_ids(p_event_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path TO ''
AS $function$
  SELECT coalesce(
    jsonb_agg(jsonb_build_object(
      'planned_date', timezone('Africa/Douala', ci.created_at)::date,
      'activity_id', ci.activity_id
    ) ORDER BY ci.created_at),
    '[]'::jsonb
  )
  FROM public.event_checkins ci
  WHERE ci.event_id = p_event_id
    AND ci.user_id = (SELECT auth.uid())
    AND ci.status = 'valid'
    AND ci.activity_id IS NOT NULL;
$function$;
REVOKE ALL ON FUNCTION public.get_my_validated_event_activity_ids(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_validated_event_activity_ids(uuid) TO authenticated;
