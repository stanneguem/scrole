create or replace function public.record_event_analytics_event(p_event_id uuid,p_action text,p_metadata jsonb default '{}'::jsonb)
returns void language plpgsql security definer set search_path=''
as $function$
declare v_user_id uuid:=(select auth.uid()); v_metadata jsonb:=coalesce(p_metadata,'{}'::jsonb);
begin
 if v_user_id is null then raise exception 'Authentification requise'; end if;
 if p_action not in ('detail_open','simulation_open','simulation_ticket_selected','simulation_activity_selected','simulation_activity_deselected','simulation_completed') then
  raise exception 'Action analytique non autorisée'; end if;
 if not exists(select 1 from public.events e where e.id=p_event_id and e.status<>'deleted'
  and (e.is_public=true or e.creator_id=v_user_id
   or exists(select 1 from public.event_co_creators cc where cc.event_id=e.id and cc.user_id=v_user_id and cc.status='acceptee')
   or exists(select 1 from public.event_staff es where es.event_id=e.id and es.user_id=v_user_id and es.status='acceptee'))) then
  raise exception 'Événement non accessible'; end if;
 if jsonb_typeof(v_metadata)<>'object' then v_metadata:='{}'::jsonb; end if;
 insert into public.event_analytics_events(event_id,user_id,action,metadata)
 values(p_event_id,v_user_id,p_action,jsonb_strip_nulls(jsonb_build_object(
  'session_id',case when coalesce(v_metadata->>'session_id','') ~* '^[0-9a-f-]{36}$' then v_metadata->>'session_id' end,
  'ticket_id',case when v_metadata ? 'ticket_id' then v_metadata->>'ticket_id' end,
  'activity_ids',case when jsonb_typeof(v_metadata->'activity_ids')='array' then v_metadata->'activity_ids' else '[]'::jsonb end,
  'estimated_total',case when jsonb_typeof(v_metadata->'estimated_total')='number' then (v_metadata->>'estimated_total')::numeric end,
  'currency',case when length(coalesce(v_metadata->>'currency',''))<=8 then v_metadata->>'currency' end
 )));
end;
$function$;
revoke all on function public.record_event_analytics_event(uuid,text,jsonb) from public,anon;
grant execute on function public.record_event_analytics_event(uuid,text,jsonb) to authenticated;

create or replace function public.get_event_budget_insights(p_event_id uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $function$
declare v_user_id uuid:=(select auth.uid()); v_event public.events; v_authorized boolean; v_result jsonb;
begin
 if v_user_id is null then raise exception 'Authentication required' using errcode='42501'; end if;
 select e.* into v_event from public.events e where e.id=p_event_id;
 if not found then raise exception 'Event not found' using errcode='P0002'; end if;
 v_authorized:=v_user_id=v_event.creator_id
  or exists(select 1 from public.event_co_creators cc where cc.event_id=p_event_id and cc.user_id=v_user_id and cc.status in ('acceptee','accepted'))
  or exists(select 1 from public.event_staff es where es.event_id=p_event_id and es.user_id=v_user_id and es.status in ('acceptee','accepted'))
  or coalesce(public.is_admin_or_above(),false);
 if not v_authorized then raise exception 'Action non autorisée' using errcode='42501'; end if;
 if not exists(select 1 from public.event_certifications ec where ec.event_id=p_event_id and ec.status='active' and (ec.valid_until is null or ec.valid_until>now())) then
  raise exception 'event_certification_required_for_statistics' using errcode='42501'; end if;
 select jsonb_build_object(
  'sessions_started',(select count(distinct metadata->>'session_id')::int from public.event_analytics_events where event_id=p_event_id and action='simulation_open'),
  'unique_budget_users',(select count(distinct user_id)::int from public.event_analytics_events where event_id=p_event_id and action='simulation_open'),
  'sessions_confirmed',(select count(*)::int from public.event_preview_sessions where event_id=p_event_id),
  'average_confirmed_budget',(select round(avg(viewer_total),2) from public.event_preview_sessions where event_id=p_event_id),
  'confirmation_rate',case when (select count(distinct metadata->>'session_id') from public.event_analytics_events where event_id=p_event_id and action='simulation_open')>0
   then round((select count(*)::numeric from public.event_preview_sessions where event_id=p_event_id)/
    (select count(distinct metadata->>'session_id')::numeric from public.event_analytics_events where event_id=p_event_id and action='simulation_open')*100,2) else null end,
  'unconfirmed_sessions',(select count(distinct ev.metadata->>'session_id')::int from public.event_analytics_events ev
   where ev.event_id=p_event_id and ev.action='simulation_open' and not exists(select 1 from public.event_preview_sessions s where s.id::text=ev.metadata->>'session_id')),
  'ticket_choices',coalesce((select jsonb_agg(jsonb_build_object('ticket_id',t.id,'name',t.name,'selection_count',coalesce(q.selection_count,0),'unique_users',coalesce(q.unique_users,0),
   'confirmed_sessions',(select count(*)::int from public.event_preview_sessions s where s.event_id=p_event_id and s.selected_ticket_id=t.id)) order by coalesce(q.selection_count,0) desc,t.name)
   from public.event_tickets t left join lateral(select count(distinct ev.metadata->>'session_id')::int selection_count,count(distinct ev.user_id)::int unique_users
    from public.event_analytics_events ev where ev.event_id=p_event_id and ev.action='simulation_ticket_selected' and ev.metadata->>'ticket_id'=t.id::text) q on true where t.event_id=p_event_id),'[]'::jsonb),
  'activity_choices',coalesce((select jsonb_agg(jsonb_build_object('activity_id',a.id,'name',a.name,'selection_interactions',coalesce(q.selection_interactions,0),
   'deselection_interactions',coalesce(q.deselection_interactions,0),'unique_users_selected',coalesce(q.unique_users_selected,0),
   'confirmed_sessions',(select count(distinct s.session_id)::int from public.event_preview_activity_selections s where s.event_id=p_event_id and s.activity_id=a.id))
   order by coalesce(q.selection_interactions,0) desc,a.name)
   from public.event_activities ea join public.activities a on a.id=ea.activity_id
   left join lateral(select count(distinct ev.metadata->>'session_id') filter(where ev.action='simulation_activity_selected')::int selection_interactions,
    count(distinct ev.metadata->>'session_id') filter(where ev.action='simulation_activity_deselected')::int deselection_interactions,
    count(distinct ev.user_id) filter(where ev.action='simulation_activity_selected')::int unique_users_selected
    from public.event_analytics_events ev cross join lateral jsonb_array_elements_text(case when jsonb_typeof(ev.metadata->'activity_ids')='array' then ev.metadata->'activity_ids' else '[]'::jsonb end) token(activity_id)
    where ev.event_id=p_event_id and ev.action in ('simulation_activity_selected','simulation_activity_deselected') and token.activity_id=a.id::text) q on true
   where ea.event_id=p_event_id),'[]'::jsonb),
  'budget_by_currency',coalesce((select jsonb_agg(jsonb_build_object('currency',q.currency,'simulations',q.simulations,'average_budget',q.average_budget,'total_budget',q.total_budget))
   from(select viewer_currency currency,count(*)::int simulations,round(avg(viewer_total),2) average_budget,round(sum(viewer_total),2) total_budget
    from public.event_preview_sessions where event_id=p_event_id and viewer_currency is not null group by viewer_currency) q),'[]'::jsonb)
 ) into v_result;
 return v_result;
end;
$function$;
revoke all on function public.get_event_budget_insights(uuid) from public,anon;
grant execute on function public.get_event_budget_insights(uuid) to authenticated;
