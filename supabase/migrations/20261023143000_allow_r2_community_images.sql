-- Allow community profile/cover URLs hosted on Cloudflare R2.
-- Preserve compatibility with historical Supabase Storage URLs.
-- This migration is intentionally prepared for review; it has not been applied remotely.

create or replace function public.update_community_info(
  p_id uuid,
  p_name text default null,
  p_slogan text default null,
  p_description text default null,
  p_photo_profile text default null,
  p_photo_cover text default null
)
returns public.communities
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_row public.communities;
  v_name text := nullif(btrim(p_name), '');
  v_slogan text := nullif(btrim(p_slogan), '');
  v_profile text := nullif(btrim(p_photo_profile), '');
  v_cover text := nullif(btrim(p_photo_cover), '');
begin
  if auth.uid() is null then
    raise exception 'Utilisateur non authentifié';
  end if;

  if not exists (
    select 1 from public.communities c
    where c.id = p_id and c.status = 'active'
  ) then
    raise exception 'Communauté introuvable';
  end if;

  if not public.is_community_admin(p_id) then
    raise exception 'Action réservée aux administrateurs de la communauté';
  end if;

  if p_name is not null and v_name is null then
    raise exception 'Le nom ne peut pas être vide';
  end if;
  if v_name is not null and char_length(v_name) > 60 then
    raise exception 'Le nom est trop long (60 caractères maximum)';
  end if;
  if p_slogan is not null and v_slogan is not null and char_length(v_slogan) > 160 then
    raise exception 'Le slogan est trop long (160 caractères maximum)';
  end if;
  if p_description is not null and char_length(btrim(p_description)) > 500 then
    raise exception 'La description est trop longue (500 caractères maximum)';
  end if;

  -- Legacy URLs remain accepted. New R2 URLs must point to this community's
  -- expected media folder, preventing a URL for another entity being stored.
  if v_profile is not null and (
    position('..' in v_profile) > 0
    or (
      v_profile not like '%/storage/v1/object/public/%'
      and v_profile not like '%/communities/' || p_id::text || '/avatar/%'
    )
  ) then
    raise exception 'Photo de profil invalide';
  end if;
  if v_cover is not null and (
    position('..' in v_cover) > 0
    or (
      v_cover not like '%/storage/v1/object/public/%'
      and v_cover not like '%/communities/' || p_id::text || '/cover/%'
    )
  ) then
    raise exception 'Photo de couverture invalide';
  end if;

  update public.communities
  set name = coalesce(v_name, name),
      slogan = case when p_slogan is null then slogan else v_slogan end,
      description = case when p_description is null then description else btrim(p_description) end,
      photo_profile = coalesce(v_profile, photo_profile),
      photo_cover = coalesce(v_cover, photo_cover),
      updated_at = now()
  where id = p_id
  returning * into v_row;

  return v_row;
end;
$function$;
