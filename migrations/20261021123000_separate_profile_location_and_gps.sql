-- Keep profile location user-declared; GPS detections are operational signals only.
-- Remove the former mechanism that forced the profile country to match GPS.
DROP TRIGGER IF EXISTS guard_profile_current_country ON public.user_profiles;
DROP FUNCTION IF EXISTS public.guard_profile_current_country();
DROP FUNCTION IF EXISTS public.apply_verified_current_country(uuid, uuid);

CREATE OR REPLACE FUNCTION public.handle_profile_update_locks()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = 'public'
AS $$
DECLARE
  lock_interval interval := '90 days';
BEGIN
  IF NEW.username IS DISTINCT FROM OLD.username THEN
    IF OLD.username_updated_at IS NOT NULL AND OLD.username_updated_at > now() - lock_interval THEN
      RAISE EXCEPTION 'Modification du pseudo refusée : délai de 90 jours non respecté.';
    END IF;
    NEW.username_updated_at = now();
  END IF;

  IF NEW.country_id IS DISTINCT FROM OLD.country_id OR NEW.city_id IS DISTINCT FROM OLD.city_id THEN
    IF OLD.location_updated_at IS NOT NULL AND OLD.location_updated_at > now() - lock_interval THEN
      RAISE EXCEPTION 'Modification de la localisation refusée : délai de 90 jours non respecté.';
    END IF;
    NEW.location_updated_at = now();
  END IF;

  IF NEW.gender IS DISTINCT FROM OLD.gender THEN
    IF OLD.gender_updated_at IS NOT NULL AND OLD.gender_updated_at > now() - lock_interval THEN
      RAISE EXCEPTION 'Modification du genre refusée : délai de 90 jours non respecté.';
    END IF;
    NEW.gender_updated_at = now();
  END IF;

  IF NEW.birth_date IS DISTINCT FROM OLD.birth_date THEN
    IF OLD.birth_date_updated_at IS NOT NULL AND OLD.birth_date_updated_at > now() - lock_interval THEN
      RAISE EXCEPTION 'Modification de la date de naissance refusée : délai de 90 jours non respecté.';
    END IF;
    NEW.birth_date_updated_at = now();
  END IF;

  RETURN NEW;
END;
$$;
