create or replace function public.scrole_get_entity_certification_status(
  p_entity_type text,
  p_entity_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_certified boolean := false;
  v_is_owner boolean := false;
begin
  if p_entity_type not in ('event','community') or p_entity_id is null then
    raise exception 'invalid_certification_target' using errcode='22023';
  end if;

  if p_entity_type = 'event' then
    select exists (
      select 1
      from public.event_certifications ec
      where ec.event_id = p_entity_id
        and ec.status = 'active'
        and (ec.valid_until is null or ec.valid_until > now())
    ) into v_certified;

    select exists (
      select 1 from public.events e
      where e.id = p_entity_id
        and e.creator_id = auth.uid()
    ) into v_is_owner;
  else
    select exists (
      select 1
      from public.community_certifications cc
      where cc.community_id = p_entity_id
        and cc.status = 'active'
        and (cc.valid_until is null or cc.valid_until > now())
    ) into v_certified;

    select exists (
      select 1 from public.communities c
      where c.id = p_entity_id
        and c.creator_id = auth.uid()
    ) into v_is_owner;
  end if;

  return jsonb_build_object(
    'entity_type', p_entity_type,
    'entity_id', p_entity_id,
    'entity_certified', v_certified,
    'is_owner', v_is_owner
  );
end;
$function$;

revoke all on function public.scrole_get_entity_certification_status(text, uuid) from public;
grant execute on function public.scrole_get_entity_certification_status(text, uuid) to authenticated;