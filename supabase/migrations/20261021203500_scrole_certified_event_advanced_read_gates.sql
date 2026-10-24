-- Protect event guest/sponsor list RPCs as well as the write triggers.
create or replace function public.get_event_guest_invitations(p_event_id uuid)
returns table(id uuid,event_id uuid,user_id uuid,invited_by uuid,status text,created_at timestamptz,responded_at timestamptz,username text,first_name text,last_name text,photo_url text)
language plpgsql security definer set search_path='public' as $function$
begin
 if not exists(select 1 from public.event_certifications ec where ec.event_id=p_event_id and ec.status='active' and (ec.valid_until is null or ec.valid_until>now())) then raise exception 'event_certification_required_for_guest_invitations' using errcode='42501'; end if;
 if not public.is_event_owner(p_event_id) then raise exception 'Action réservée au créateur ou aux co-créateurs de l''événement'; end if;
 return query select gi.id,gi.event_id,gi.user_id,gi.invited_by,gi.status,gi.created_at,gi.responded_at,up.username,up.first_name,up.last_name,up.photo_url from public.event_guest_invitations gi join public.user_profiles up on up.user_id=gi.user_id where gi.event_id=p_event_id and gi.status<>'annulee' order by gi.created_at desc;
end;$function$;
create or replace function public.get_event_sponsor_candidates(p_event_id uuid,p_search text default null)
returns table(user_id uuid,username text,first_name text,last_name text,photo_url text,country_id uuid,city_id uuid)
language plpgsql security definer set search_path='public' as $function$
begin
 if not exists(select 1 from public.event_certifications ec where ec.event_id=p_event_id and ec.status='active' and (ec.valid_until is null or ec.valid_until>now())) then raise exception 'event_certification_required_for_sponsors' using errcode='42501'; end if;
 if not public.is_event_owner(p_event_id) then raise exception 'Action réservée au créateur ou aux co-créateurs de l''événement'; end if;
 return query select up.user_id,up.username,up.first_name,up.last_name,up.photo_url,up.country_id,up.city_id from public.user_profiles up join public.user_privacy priv on priv.user_id=up.user_id
 where up.account_status='active' and up.deleted_at is null and lower(coalesce(priv.profile_visibility,'public'))='public'
 and up.user_id<>(select e.creator_id from public.events e where e.id=p_event_id)
 and not exists(select 1 from public.event_co_creators cc where cc.event_id=p_event_id and cc.user_id=up.user_id and cc.status='acceptee')
 and not exists(select 1 from public.event_staff es where es.event_id=p_event_id and es.user_id=up.user_id and es.status='acceptee')
 and not exists(select 1 from public.event_sponsor_invitations si where si.event_id=p_event_id and si.user_id=up.user_id and si.status in ('en_attente','acceptee'))
 and (nullif(trim(p_search),'') is null or lower(coalesce(up.username,'')) like '%'||lower(trim(p_search))||'%' or lower(coalesce(up.first_name,'')) like '%'||lower(trim(p_search))||'%' or lower(coalesce(up.last_name,'')) like '%'||lower(trim(p_search))||'%' or lower(trim(coalesce(up.first_name,'')||' '||coalesce(up.last_name,''))) like '%'||lower(trim(p_search))||'%')
 order by lower(coalesce(up.username,up.first_name,''));
end;$function$;
create or replace function public.get_event_sponsor_invitations(p_event_id uuid)
returns table(id uuid,event_id uuid,user_id uuid,invited_by uuid,status text,created_at timestamptz,responded_at timestamptz,username text,first_name text,last_name text,photo_url text)
language plpgsql security definer set search_path='public' as $function$
begin
 if not exists(select 1 from public.event_certifications ec where ec.event_id=p_event_id and ec.status='active' and (ec.valid_until is null or ec.valid_until>now())) then raise exception 'event_certification_required_for_sponsors' using errcode='42501'; end if;
 if not public.is_event_owner(p_event_id) then raise exception 'Action réservée au créateur ou aux co-créateurs de l''événement'; end if;
 return query select si.id,si.event_id,si.user_id,si.invited_by,si.status,si.created_at,si.responded_at,up.username,up.first_name,up.last_name,up.photo_url from public.event_sponsor_invitations si join public.user_profiles up on up.user_id=si.user_id where si.event_id=p_event_id and si.status<>'annulee' order by si.created_at desc;
end;$function$;
revoke all on function public.get_event_guest_invitations(uuid) from public,anon;
grant execute on function public.get_event_guest_invitations(uuid) to authenticated;
revoke all on function public.get_event_sponsor_candidates(uuid,text) from public,anon;
grant execute on function public.get_event_sponsor_candidates(uuid,text) to authenticated;
revoke all on function public.get_event_sponsor_invitations(uuid) from public,anon;
grant execute on function public.get_event_sponsor_invitations(uuid) to authenticated;
