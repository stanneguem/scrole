create or replace function public.handle_profile_update_locks()
returns trigger
language plpgsql
set search_path = 'public'
as $$
declare
  lock_interval interval := '90 days';
  v_verified_country_update boolean :=
    coalesce(current_setting('scrole.country_verification_update', true), '') = 'on'
    and coalesce(current_setting('request.jwt.claim.role', true), '') = 'service_role';
begin
  if new.username is distinct from old.username then
    if old.username_updated_at is not null and old.username_updated_at > now() - lock_interval then
      raise exception 'Modification du pseudo refusée : délai de 90 jours non respecté.';
    end if;
    new.username_updated_at = now();
  end if;

  if new.country_id is distinct from old.country_id or new.city_id is distinct from old.city_id then
    if not v_verified_country_update and old.location_updated_at is not null and old.location_updated_at > now() - lock_interval then
      raise exception 'Modification de la localisation refusée : délai de 90 jours non respecté.';
    end if;
    new.location_updated_at = now();
  end if;

  if new.gender is distinct from old.gender then
    if old.gender_updated_at is not null and old.gender_updated_at > now() - lock_interval then
      raise exception 'Modification du genre refusée : délai de 90 jours non respecté.';
    end if;
    new.gender_updated_at = now();
  end if;

  if new.birth_date is distinct from old.birth_date then
    if old.birth_date_updated_at is not null and old.birth_date_updated_at > now() - lock_interval then
      raise exception 'Modification de la date de naissance refusée : délai de 90 jours non respecté.';
    end if;
    new.birth_date_updated_at = now();
  end if;

  return new;
end;
$$;