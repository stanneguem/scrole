-- Certified community capabilities: owner analytics, event linking and ticketing.
-- Community certification does not implicitly certify the linked event.

create or replace function public.get_community_certification_stats(p_community_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_user uuid := auth.uid();
  v_result jsonb;
begin
  if v_user is null then raise exception 'authentication_required' using errcode='28000'; end if;

  if not exists (
    select 1 from public.communities c
    where c.id=p_community_id and c.creator_id=v_user
  ) then
    raise exception 'community_owner_required' using errcode='42501';
  end if;

  if not exists (
    select 1 from public.community_certifications cc
    where cc.community_id=p_community_id and cc.status='active'
      and (cc.valid_until is null or cc.valid_until > now())
  ) then
    raise exception 'community_certification_required_for_statistics' using errcode='42501';
  end if;

  select jsonb_build_object(
    'community_id',p_community_id,
    'members_count',(select count(*) from public.community_members cm where cm.community_id=p_community_id),
    'new_members_30d',(select count(*) from public.community_members cm where cm.community_id=p_community_id and cm.joined_at >= now()-interval '30 days'),
    'active_posts_count',(select count(*) from public.community_posts cp where cp.community_id=p_community_id and cp.status='active' and cp.deleted_at is null),
    'new_posts_30d',(select count(*) from public.community_posts cp where cp.community_id=p_community_id and cp.status='active' and cp.deleted_at is null and cp.created_at >= now()-interval '30 days'),
    'comments_count',(select count(*) from public.community_post_comments cpc join public.community_posts cp on cp.id=cpc.post_id where cp.community_id=p_community_id and cp.status='active' and cp.deleted_at is null),
    'reactions_count',(select count(*) from public.community_post_reactions cpr join public.community_posts cp on cp.id=cpr.post_id where cp.community_id=p_community_id and cp.status='active' and cp.deleted_at is null),
    'generated_at',now()
  ) into v_result;

  return v_result;
end;
$function$;

revoke all on function public.get_community_certification_stats(uuid) from public,anon;
grant execute on function public.get_community_certification_stats(uuid) to authenticated;

create or replace function public.link_event_to_community(p_event_id uuid,p_community_id uuid)
returns public.events
language plpgsql
security definer
set search_path = 'public'
as $function$
declare
  v_row public.events;
begin
  if not public.is_event_owner(p_event_id) then
    raise exception 'Vous devez être créateur ou co-créateur de l''événement' using errcode='42501';
  end if;
  if not public.is_community_owner_or_co_owner(p_community_id) then
    raise exception 'Vous devez être propriétaire ou co-propriétaire de la communauté' using errcode='42501';
  end if;
  if not exists (
    select 1 from public.community_certifications cc
    where cc.community_id=p_community_id and cc.status='active'
      and (cc.valid_until is null or cc.valid_until > now())
  ) then
    raise exception 'community_certification_required_to_link_event' using errcode='42501';
  end if;

  update public.events set community_id=p_community_id where id=p_event_id returning * into v_row;
  if not found then raise exception 'event_not_found' using errcode='P0002'; end if;
  return v_row;
end;
$function$;

-- Ticketing may be enabled by either an event certification or a certification
-- of the community that owns/hosts that event. Guest and sponsor management remain
-- reserved to event-certified events.
create or replace function public.scrole_require_event_certification_for_management()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_event_id uuid;
  v_allowed boolean := false;
begin
  v_event_id := case when tg_op='DELETE' then old.event_id else new.event_id end;

  select exists (
    select 1 from public.event_certifications ec
    where ec.event_id=v_event_id and ec.status='active'
      and (ec.valid_until is null or ec.valid_until > now())
  ) into v_allowed;

  if tg_table_name='event_tickets' and not v_allowed then
    select exists (
      select 1 from public.events e
      join public.community_certifications cc on cc.community_id=e.community_id
      where e.id=v_event_id and cc.status='active'
        and (cc.valid_until is null or cc.valid_until > now())
    ) into v_allowed;
  end if;

  if not v_allowed then
    raise exception 'event_or_community_certification_required'
      using errcode='42501',
      detail=case when tg_table_name='event_tickets'
        then 'La certification de l’événement ou de sa communauté est nécessaire pour gérer la billetterie.'
        else 'La certification de l’événement est nécessaire pour gérer les invitations Guest et les sponsors.'
      end;
  end if;

  if tg_op='DELETE' then return old; end if;
  return new;
end;
$function$;

revoke all on function public.get_community_certification_stats(uuid) from public,anon;
grant execute on function public.get_community_certification_stats(uuid) to authenticated;
