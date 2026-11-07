-- Permission settings for who may create community chat salons.
CREATE TABLE IF NOT EXISTS public.community_salon_creation_settings (
  community_id uuid PRIMARY KEY REFERENCES public.communities(id) ON DELETE CASCADE,
  allowed_creators text NOT NULL DEFAULT 'admins_moderators'
    CHECK (allowed_creators IN ('admins_only', 'admins_moderators', 'all_members')),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.community_salon_creation_settings ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.community_salon_creation_settings FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_community_salon_creation_setting(p_community_id uuid)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $fn$
DECLARE v_uid uuid := auth.uid(); v_role text; v_allowed text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Utilisateur non authentifié'; END IF;
  SELECT role::text INTO v_role FROM public.community_members
    WHERE community_id=p_community_id AND user_id=v_uid;
  IF v_role IS NULL THEN RAISE EXCEPTION 'Vous devez être membre de la communauté'; END IF;
  SELECT allowed_creators INTO v_allowed FROM public.community_salon_creation_settings
    WHERE community_id=p_community_id;
  RETURN COALESCE(v_allowed, 'admins_moderators');
END;
$fn$;
REVOKE ALL ON FUNCTION public.get_community_salon_creation_setting(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_community_salon_creation_setting(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.set_community_salon_creation_setting(p_community_id uuid, p_allowed_creators text)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $fn$
DECLARE v_uid uuid := auth.uid(); v_role text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Utilisateur non authentifié'; END IF;
  SELECT role::text INTO v_role FROM public.community_members
    WHERE community_id=p_community_id AND user_id=v_uid;
  IF v_role IS DISTINCT FROM 'admin' THEN
    RAISE EXCEPTION 'Seul un administrateur de la communauté peut modifier ce paramètre';
  END IF;
  IF p_allowed_creators NOT IN ('admins_only', 'admins_moderators', 'all_members') THEN
    RAISE EXCEPTION 'Option de création invalide';
  END IF;
  INSERT INTO public.community_salon_creation_settings(community_id, allowed_creators, updated_at)
  VALUES (p_community_id, p_allowed_creators, now())
  ON CONFLICT (community_id) DO UPDATE SET
    allowed_creators=EXCLUDED.allowed_creators, updated_at=now();
  RETURN p_allowed_creators;
END;
$fn$;
REVOKE ALL ON FUNCTION public.set_community_salon_creation_setting(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_community_salon_creation_setting(uuid, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.create_community_chat_group(
  p_id uuid, p_community_id uuid, p_name text, p_description text DEFAULT '',
  p_visibility text DEFAULT 'public', p_countries_enabled boolean DEFAULT NULL,
  p_allowed_countries uuid[] DEFAULT NULL, p_cities_enabled boolean DEFAULT NULL,
  p_allowed_cities uuid[] DEFAULT NULL, p_certification_required boolean DEFAULT NULL,
  p_gender_restriction genre_enum DEFAULT NULL, p_age_min integer DEFAULT NULL,
  p_age_max integer DEFAULT NULL
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $fn$
DECLARE
  v_uid uuid := auth.uid();
  v_id uuid := COALESCE(p_id, gen_random_uuid());
  v_role text;
  v_allowed text;
  v_rules public.community_access_rules;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Utilisateur non authentifié'; END IF;
  SELECT role::text INTO v_role FROM public.community_members
    WHERE community_id=p_community_id AND user_id=v_uid;
  IF v_role IS NULL THEN RAISE EXCEPTION 'Vous devez être membre de la communauté pour créer une discussion'; END IF;
  SELECT allowed_creators INTO v_allowed FROM public.community_salon_creation_settings
    WHERE community_id=p_community_id;
  v_allowed := COALESCE(v_allowed, 'admins_moderators');
  IF NOT (v_role='admin' OR (v_allowed='admins_moderators' AND v_role='moderator') OR v_allowed='all_members') THEN
    RAISE EXCEPTION 'Action non autorisée : vous ne pouvez pas créer de salon dans cette communauté';
  END IF;
  IF p_name IS NULL OR length(trim(p_name)) < 2 OR length(trim(p_name)) > 80 THEN RAISE EXCEPTION 'Nom du groupe invalide'; END IF;
  IF p_visibility NOT IN ('public','private') THEN RAISE EXCEPTION 'Visibilité invalide'; END IF;
  SELECT * INTO v_rules FROM public.community_access_rules WHERE community_id=p_community_id;
  INSERT INTO public.community_salons(id,community_id,name,type,audio_messages_allowed,created_by,visibility,description)
  VALUES(v_id,p_community_id,trim(p_name),'texte',false,v_uid,p_visibility,COALESCE(trim(p_description),''));
  INSERT INTO public.community_salon_access_rules(
    salon_id,countries_enabled,allowed_countries,cities_enabled,allowed_cities,
    certification_required,gender_restriction,age_min,age_max
  ) VALUES (
    v_id,COALESCE(p_countries_enabled,v_rules.countries_enabled,false),
    COALESCE(p_allowed_countries,v_rules.allowed_countries,'{}'),
    COALESCE(p_cities_enabled,v_rules.cities_enabled,false),
    COALESCE(p_allowed_cities,v_rules.allowed_cities,'{}'),
    COALESCE(p_certification_required,v_rules.certification_required,false),
    COALESCE(p_gender_restriction,v_rules.gender_restriction),
    COALESCE(p_age_min,v_rules.age_min),COALESCE(p_age_max,v_rules.age_max)
  );
  INSERT INTO public.community_salon_members(salon_id,user_id,role)
  VALUES(v_id,v_uid,'owner') ON CONFLICT(salon_id,user_id) DO NOTHING;
  RETURN v_id;
END;
$fn$;
REVOKE ALL ON FUNCTION public.create_community_chat_group(uuid,uuid,text,text,text,boolean,uuid[],boolean,uuid[],boolean,genre_enum,integer,integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_community_chat_group(uuid,uuid,text,text,text,boolean,uuid[],boolean,uuid[],boolean,genre_enum,integer,integer) TO authenticated;
