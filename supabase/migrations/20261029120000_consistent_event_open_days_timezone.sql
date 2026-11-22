-- Keep event-open-day dates aligned with the event's local calendar dates.
-- Events use timestamptz; comparing starts_at::date in the database session timezone
-- can shift the displayed day. Resolve dates using the event location timezone instead.

ALTER TABLE public.cities
  ADD COLUMN IF NOT EXISTS timezone_name text NOT NULL DEFAULT 'UTC';

UPDATE public.cities ci
SET timezone_name = CASE upper(co.code_iso)
  WHEN 'CM' THEN 'Africa/Douala'
  WHEN 'NG' THEN 'Africa/Lagos'
  WHEN 'GH' THEN 'Africa/Accra'
  WHEN 'SN' THEN 'Africa/Dakar'
  WHEN 'CI' THEN 'Africa/Abidjan'
  WHEN 'BF' THEN 'Africa/Ouagadougou'
  WHEN 'ML' THEN 'Africa/Bamako'
  WHEN 'NE' THEN 'Africa/Niamey'
  WHEN 'TD' THEN 'Africa/Ndjamena'
  WHEN 'CG' THEN 'Africa/Brazzaville'
  WHEN 'GA' THEN 'Africa/Libreville'
  WHEN 'BJ' THEN 'Africa/Porto-Novo'
  WHEN 'TG' THEN 'Africa/Lome'
  WHEN 'RW' THEN 'Africa/Kigali'
  WHEN 'UG' THEN 'Africa/Kampala'
  WHEN 'KE' THEN 'Africa/Nairobi'
  WHEN 'TZ' THEN 'Africa/Dar_es_Salaam'
  WHEN 'ZA' THEN 'Africa/Johannesburg'
  WHEN 'FR' THEN 'Europe/Paris'
  WHEN 'DE' THEN 'Europe/Berlin'
  WHEN 'GB' THEN 'Europe/London'
  WHEN 'MA' THEN 'Africa/Casablanca'
  WHEN 'EG' THEN 'Africa/Cairo'
  WHEN 'IN' THEN 'Asia/Kolkata'
  WHEN 'CN' THEN 'Asia/Shanghai'
  WHEN 'JP' THEN 'Asia/Tokyo'
  WHEN 'AE' THEN 'Asia/Dubai'
  WHEN 'SA' THEN 'Asia/Riyadh'
  ELSE ci.timezone_name
END
FROM public.countries co
WHERE co.id = ci.country_id;

CREATE OR REPLACE FUNCTION public.event_local_date_bounds(
  p_event_id uuid,
  OUT p_start_date date,
  OUT p_last_date date,
  OUT p_timezone text
)
RETURNS record
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_event public.events%ROWTYPE;
BEGIN
  SELECT * INTO v_event
  FROM public.events
  WHERE id = p_event_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Événement introuvable';
  END IF;

  SELECT COALESCE(NULLIF(c.timezone_name, ''), 'UTC')
  INTO p_timezone
  FROM public.cities c
  WHERE c.id = v_event.city_id;

  p_timezone := COALESCE(NULLIF(p_timezone, ''), 'UTC');
  p_start_date := (v_event.starts_at AT TIME ZONE p_timezone)::date;

  -- ends_at is exclusive when it is exactly midnight: subtract one microsecond
  -- so an event ending at 00:00 does not create an extra open day.
  IF v_event.ends_at IS NULL THEN
    p_last_date := p_start_date;
  ELSE
    p_last_date := ((v_event.ends_at - interval '1 microsecond') AT TIME ZONE p_timezone)::date;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_event_open_days(p_event_id uuid, p_dates date[])
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_start date;
  v_last date;
  v_timezone text;
  v_event_status text;
  v_dates date[] := COALESCE(p_dates, '{}');
BEGIN
  IF NOT public.is_event_owner(p_event_id) THEN
    RAISE EXCEPTION 'Action réservée au créateur ou aux co-créateurs de l''événement';
  END IF;

  SELECT status INTO v_event_status
  FROM public.events
  WHERE id = p_event_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Événement introuvable';
  END IF;

  SELECT p_start_date, p_last_date, p_timezone
  INTO v_start, v_last, v_timezone
  FROM public.event_local_date_bounds(p_event_id);

  IF v_event_status IN ('pending_deletion', 'deleted') THEN
    RAISE EXCEPTION 'Impossible de modifier les jours ouverts : événement supprimé ou en cours de suppression';
  END IF;

  IF v_last IS NULL OR v_last < v_start THEN
    RAISE EXCEPTION 'Période de l''événement invalide';
  END IF;

  IF v_last - v_start < 1 THEN
    RAISE EXCEPTION 'Les jours ouverts sont réservés aux événements couvrant au moins deux jours';
  END IF;

  IF EXISTS (
    SELECT 1 FROM unnest(v_dates) AS d
    WHERE d < v_start OR d > v_last
  ) THEN
    RAISE EXCEPTION 'Un ou plusieurs jours sont en dehors de la période de l''événement';
  END IF;

  IF (SELECT count(*) FROM unnest(v_dates)) <>
     (SELECT count(DISTINCT d) FROM unnest(v_dates) AS d) THEN
    RAISE EXCEPTION 'La liste des jours ouverts contient des doublons';
  END IF;

  DELETE FROM public.event_open_days WHERE event_id = p_event_id;

  INSERT INTO public.event_open_days(event_id, event_date)
  SELECT p_event_id, d
  FROM unnest(v_dates) AS d
  ORDER BY d;

  DELETE FROM public.event_calendar_days cd
  WHERE cd.event_id = p_event_id
    AND NOT EXISTS (
      SELECT 1 FROM public.event_open_days od
      WHERE od.event_id = cd.event_id
        AND od.event_date = cd.event_date
    );

  RETURN jsonb_build_object(
    'event_id', p_event_id,
    'start_date', v_start,
    'end_date', v_last,
    'timezone', v_timezone,
    'open_days', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('date', event_date, 'is_open', true) ORDER BY event_date)
      FROM public.event_open_days WHERE event_id = p_event_id
    ), '[]'::jsonb)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_event_open_days_after_date_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_start date;
  v_last date;
  v_timezone text;
BEGIN
  IF TG_OP = 'UPDATE'
     AND NEW.starts_at IS NOT DISTINCT FROM OLD.starts_at
     AND NEW.ends_at IS NOT DISTINCT FROM OLD.ends_at
     AND NEW.city_id IS NOT DISTINCT FROM OLD.city_id THEN
    RETURN NEW;
  END IF;

  SELECT p_start_date, p_last_date, p_timezone
  INTO v_start, v_last, v_timezone
  FROM public.event_local_date_bounds(NEW.id);

  DELETE FROM public.event_open_days od
  WHERE od.event_id = NEW.id
    AND (od.event_date < v_start OR od.event_date > v_last);

  DELETE FROM public.event_calendar_days cd
  WHERE cd.event_id = NEW.id
    AND NOT EXISTS (
      SELECT 1 FROM public.event_open_days od
      WHERE od.event_id = cd.event_id AND od.event_date = cd.event_date
    );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_event_open_days_after_date_change ON public.events;
CREATE TRIGGER trg_sync_event_open_days_after_date_change
AFTER INSERT OR UPDATE OF starts_at, ends_at, city_id
ON public.events
FOR EACH ROW
EXECUTE FUNCTION public.sync_event_open_days_after_date_change();

-- Repair previously saved days that are outside the local event date range.
DELETE FROM public.event_open_days od
WHERE NOT EXISTS (
  SELECT 1
  FROM public.event_local_date_bounds(od.event_id) b
  WHERE od.event_date BETWEEN b.p_start_date AND b.p_last_date
);

DELETE FROM public.event_calendar_days cd
WHERE NOT EXISTS (
  SELECT 1 FROM public.event_open_days od
  WHERE od.event_id = cd.event_id AND od.event_date = cd.event_date
);

REVOKE ALL ON FUNCTION public.event_local_date_bounds(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.sync_event_open_days_after_date_change() FROM PUBLIC;
