DO $migration$
DECLARE
  v_definition text;
  v_old text := '''creator'',jsonb_build_object(''user_id'',v_event.creator_id,''username'',v_creator.username,''full_name'',v_creator.full_name,''photo_url'',v_creator.photo_url),';
  v_new text := '''creator'',jsonb_build_object(''user_id'',v_event.creator_id,''username'',v_creator.username,''full_name'',v_creator.full_name,''photo_url'',v_creator.photo_url),
   ''is_platform_event'',exists(select 1 from public.admin_event_ownership ao where ao.event_id=p_event_id and (ao.ownership_type=''platform'' or (ao.ownership_type=''third_party'' and ao.ownership_status=''awaiting_proof''))),
   ''is_third_party_event'',exists(select 1 from public.admin_event_ownership ao where ao.event_id=p_event_id and ao.ownership_type=''third_party'' and ao.ownership_status=''awaiting_proof''),';
BEGIN
  v_definition := pg_get_functiondef('public.get_event_preview_base(uuid)'::regprocedure);
  IF position('is_platform_event' in v_definition) = 0 THEN
    IF position(v_old in v_definition) = 0 THEN RAISE EXCEPTION 'Could not locate creator payload'; END IF;
    v_definition := replace(v_definition, v_old, v_new);
    EXECUTE v_definition;
  END IF;
END;
$migration$;