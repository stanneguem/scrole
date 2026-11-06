-- Create a new edition from a completed event without mutating the archive.
-- The new edition receives its own activity records, tickets and event-specific settings.
CREATE OR REPLACE FUNCTION public.create_next_event_edition(
  p_source_event_id uuid,
  p_starts_at timestamptz
)
RETURNS public.events
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_source public.events%ROWTYPE;
  v_root public.events%ROWTYPE;
  v_new public.events%ROWTYPE;
  v_activity record;
  v_new_activity_id uuid;
  v_series_id uuid;
  v_next_number integer;
  v_slug text;
  v_duration interval;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF p_source_event_id IS NULL OR p_starts_at IS NULL THEN
    RAISE EXCEPTION 'event_and_start_datetime_required';
  END IF;
  IF p_starts_at <= now() THEN RAISE EXCEPTION 'new_edition_must_start_in_future'; END IF;

  SELECT * INTO v_source FROM public.events WHERE id = p_source_event_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'event_not_found'; END IF;
  IF v_source.creator_id <> v_user_id THEN
    RAISE EXCEPTION 'only_event_creator_can_create_edition';
  END IF;
  IF v_source.status <> 'completed' THEN RAISE EXCEPTION 'source_event_must_be_completed'; END IF;

  v_series_id := coalesce(v_source.series_id, v_source.id);
  SELECT * INTO v_root FROM public.events WHERE id = v_series_id FOR UPDATE;
  IF NOT FOUND OR v_root.creator_id <> v_user_id THEN RAISE EXCEPTION 'event_series_unavailable'; END IF;

  SELECT coalesce(max(e.edition_number), 1) + 1 INTO v_next_number
  FROM public.events e WHERE coalesce(e.series_id, e.id) = v_series_id;

  v_slug := left(coalesce(nullif(v_root.slug, ''), 'event'), 150) || '-edition-' || v_next_number::text;
  WHILE EXISTS (SELECT 1 FROM public.events WHERE slug = v_slug) LOOP
    v_slug := left(coalesce(nullif(v_root.slug, ''), 'event'), 135)
              || '-edition-' || v_next_number::text || '-' || substr(gen_random_uuid()::text, 1, 6);
  END LOOP;

  v_duration := CASE
    WHEN v_source.ends_at IS NOT NULL AND v_source.ends_at > v_source.starts_at
      THEN v_source.ends_at - v_source.starts_at
    ELSE NULL
  END;

  INSERT INTO public.events (
    creator_id, name, slug, description, photo, country_id, city_id,
    starts_at, ends_at, is_free, status, community_id, is_virtual,
    virtual_link, address, is_public, real_created_at, share_count,
    slug_locked_until, series_id, edition_number
  )
  VALUES (
    v_source.creator_id, v_source.name, v_slug, v_source.description, v_source.photo,
    v_source.country_id, v_source.city_id, p_starts_at,
    CASE WHEN v_duration IS NULL THEN NULL ELSE p_starts_at + v_duration END,
    v_source.is_free, 'active', v_source.community_id, v_source.is_virtual,
    v_source.virtual_link, v_source.address, v_source.is_public, current_date,
    0, now() + interval '30 days', v_series_id, v_next_number
  )
  RETURNING * INTO v_new;

  -- Clone activity definitions so future edits do not change archived editions.
  FOR v_activity IN
    SELECT a.*, ea.price AS edition_price
    FROM public.event_activities ea
    JOIN public.activities a ON a.id = ea.activity_id
    WHERE ea.event_id = v_source.id
  LOOP
    INSERT INTO public.activities (
      creator_id, name, base_price, status, added_count, event_only,
      scheduled_deletion_at, currency_code, description
    )
    VALUES (
      v_user_id, v_activity.name, v_activity.base_price, 'active', 0,
      v_activity.event_only, NULL, v_activity.currency_code, v_activity.description
    )
    RETURNING id INTO v_new_activity_id;

    INSERT INTO public.event_activities (event_id, activity_id, price, added_by)
    VALUES (v_new.id, v_new_activity_id, v_activity.edition_price, v_user_id);
  END LOOP;

  INSERT INTO public.event_interests (event_id, interest_id)
  SELECT v_new.id, ei.interest_id FROM public.event_interests ei
  WHERE ei.event_id = v_source.id
  ON CONFLICT (event_id, interest_id) DO NOTHING;

  INSERT INTO public.event_restrictions (
    event_id, min_age, serves_alcohol, overnight_event, id_required,
    smoking_allowed, other_restrictions, max_age, allowed_genders
  )
  SELECT v_new.id, er.min_age, er.serves_alcohol, er.overnight_event, er.id_required,
         er.smoking_allowed, er.other_restrictions, er.max_age, er.allowed_genders
  FROM public.event_restrictions er WHERE er.event_id = v_source.id
  ON CONFLICT (event_id) DO NOTHING;

  -- Ticket definitions are copied; purchases and registrations stay edition-specific.
  INSERT INTO public.event_tickets (event_id, name, price, currency_code)
  SELECT v_new.id, et.name, et.price, et.currency_code
  FROM public.event_tickets et WHERE et.event_id = v_source.id;

  RETURN v_new;
END;
$function$;

REVOKE ALL ON FUNCTION public.create_next_event_edition(uuid, timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_next_event_edition(uuid, timestamptz) TO authenticated;
