-- Admin-created events use the creating administrator's profile as their creator identity.
-- Platform-created events receive an explicit admin_grant event certification.
DO $migration$
DECLARE
  v_preview text;
  v_create text;
  v_old_creator text := $old$
 select up.username,(up.first_name||' '||up.last_name) full_name,up.photo_url
 into v_creator from public.user_profiles up where up.user_id=v_event.creator_id;
$old$;
  v_new_creator text := $new$
 select
   case when ap.id is not null then '' else up.username end as username,
   coalesce(nullif(btrim(concat_ws(' ',ap.prenom,ap.nom)),''),nullif(btrim(concat_ws(' ',up.first_name,up.last_name)),''),up.username) as full_name,
   coalesce(nullif(ap.photo_url,''),up.photo_url) as photo_url,
   (ap.id is not null) as is_admin_creator
 into v_creator
 from public.user_profiles up
 left join public.admin_event_ownership ao
   on ao.event_id=p_event_id and ao.ownership_status in ('platform_owned','awaiting_proof')
 left join public.administrateur_profil ap on ap.id=ao.created_by_admin_id
 where up.user_id=v_event.creator_id;
$new$;
  v_old_payload text := $old$'creator',jsonb_build_object('user_id',v_event.creator_id,'username',v_creator.username,'full_name',v_creator.full_name,'photo_url',v_creator.photo_url),$old$;
  v_new_payload text := $new$'creator',jsonb_build_object('user_id',v_event.creator_id,'username',v_creator.username,'full_name',v_creator.full_name,'photo_url',v_creator.photo_url,'is_admin_creator',coalesce(v_creator.is_admin_creator,false)),$new$;
  v_old_return text := $old$ return v_event_id;
end;$old$;
  v_new_return text := $new$
 insert into public.event_certifications(event_id,source,status)
 values(v_event_id,'admin_grant','active');

 insert into public.scrole_certification_audit(
   actor_user_id,entity_type,entity_id,action,new_status,details
 ) values(
   p_creator_id,'event',v_event_id,'admin_event_auto_certified','active',
   jsonb_build_object('admin_profile_id',p_admin_profile_id,'ownership_type',p_ownership_type)
 );

 return v_event_id;
end;$new$;
BEGIN
  v_preview := pg_get_functiondef('public.get_event_preview_base(uuid)'::regprocedure);
  IF position('is_admin_creator' in v_preview)=0 THEN
    IF position(v_old_creator in v_preview)=0 OR position(v_old_payload in v_preview)=0 THEN
      RAISE EXCEPTION 'Impossible de localiser le bloc créateur de get_event_preview_base';
    END IF;
    v_preview := replace(v_preview,v_old_creator,v_new_creator);
    v_preview := replace(v_preview,v_old_payload,v_new_payload);
    EXECUTE v_preview;
  END IF;

  v_create := pg_get_functiondef('public.admin_create_event_from_console(uuid,uuid,jsonb,jsonb,jsonb,jsonb,jsonb,text,text)'::regprocedure);
  IF position('admin_event_auto_certified' in v_create)=0 THEN
    IF position(v_old_return in v_create)=0 THEN
      RAISE EXCEPTION 'Impossible de localiser le retour de admin_create_event_from_console';
    END IF;
    v_create := replace(v_create,v_old_return,v_new_return);
    EXECUTE v_create;
  END IF;
END;
$migration$;

-- Certify the already-created Yaoundé Otaku Festival 2026 event.
INSERT INTO public.event_certifications(event_id,source,status)
SELECT '21c66631-afca-4fee-b169-7b77c4614543'::uuid,'admin_grant','active'
WHERE NOT EXISTS (
  SELECT 1 FROM public.event_certifications
  WHERE event_id='21c66631-afca-4fee-b169-7b77c4614543'::uuid
    AND status='active'
);

INSERT INTO public.scrole_certification_audit(
  actor_user_id,entity_type,entity_id,action,new_status,details
)
SELECT
  '082a09d3-6873-4962-8460-40dd62020be8'::uuid,
  'event','21c66631-afca-4fee-b169-7b77c4614543'::uuid,
  'admin_event_auto_certified','active',
  jsonb_build_object('admin_profile_id','af0f2da6-c046-47a6-b0e4-c30ae101946b'::uuid,'ownership_type','platform','reason','admin_created_event_reclassified_as_platform')
WHERE NOT EXISTS (
  SELECT 1 FROM public.scrole_certification_audit
  WHERE entity_type='event'
    AND entity_id='21c66631-afca-4fee-b169-7b77c4614543'::uuid
    AND action='admin_event_auto_certified'
);
