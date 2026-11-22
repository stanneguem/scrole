create or replace function public.get_event_budget_insights(p_event_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := (select auth.uid());
  v_event public.events;
  v_authorized boolean;
  v_result jsonb;
begin
  if v_user_id is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  select e.* into v_event from public.events e where e.id = p_event_id;
  if not found then raise exception 'Event not found' using errcode = 'P0002'; end if;
  v_authorized := v_user_id = v_event.creator_id
    or exists (select 1 from public.event_co_creators cc where cc.event_id=p_event_id and cc.user_id=v_user_id and cc.status in ('acceptee','accepted'))
    or exists (select 1 from public.event_staff es where es.event_id=p_event_id and es.user_id=v_user_id and es.status in ('acceptee','accepted'))
    or coalesce(public.is_admin_or_above(),false);
  if not v_authorized then raise exception 'Action non autorisée' using errcode = '42501'; end if;
  if not exists (select 1 from public.event_certifications ec where ec.event_id=p_event_id and ec.status='active' and (ec.valid_until is null or ec.valid_until>now())) then
    raise exception 'event_certification_required_for_statistics' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'sessions_started',(select count(*)::int from public.event_analytics_events where event_id=p_event_id and action='simulation_open'),
    'unique_users',(select count(distinct user_id)::int from public.event_analytics_events where event_id=p_event_id and action='simulation_open'),
    'sessions_confirmed',(select count(*)::int from public.event_preview_sessions where event_id=p_event_id),
    'average_confirmed_budget',(select round(avg(viewer_total),2) from public.event_preview_sessions where event_id=p_event_id),
    'confirmation_rate',case when (select count(*) from public.event_analytics_events where event_id=p_event_id and action='simulation_open')>0
      then round((select count(*)::numeric from public.event_preview_sessions where event_id=p_event_id)/
        (select count(*)::numeric from public.event_analytics_events where event_id=p_event_id and action='simulation_open')*100,2) else null end,
    'unconfirmed_sessions',greatest((select count(*)::int from public.event_analytics_events where event_id=p_event_id and action='simulation_open')-
      (select count(*)::int from public.event_preview_sessions where event_id=p_event_id),0),
    'ticket_selections',(select count(*)::int from public.event_analytics_events where event_id=p_event_id and action='simulation_ticket_selected'),
    'activity_selections',(select count(*)::int from public.event_analytics_events where event_id=p_event_id and action='simulation_activity_selected'),
    'ticket_choices',coalesce((
      select jsonb_agg(jsonb_build_object('ticket_id',q.ticket_id,'name',t.name,'selection_count',q.selection_count,'unique_users',q.unique_users,'confirmed_sessions',q.confirmed_sessions)
        order by q.selection_count desc,t.name)
      from (select metadata->>'ticket_id' ticket_id,count(*)::int selection_count,count(distinct user_id)::int unique_users,
        (select count(*)::int from public.event_preview_sessions s where s.event_id=p_event_id and s.selected_ticket_id::text=ev.metadata->>'ticket_id') confirmed_sessions
        from public.event_analytics_events ev where ev.event_id=p_event_id and ev.action='simulation_ticket_selected' and ev.metadata ? 'ticket_id'
        group by metadata->>'ticket_id') q join public.event_tickets t on t.id::text=q.ticket_id
    ),'[]'::jsonb),
    'activity_choices',coalesce((
      select jsonb_agg(jsonb_build_object('activity_id',q.activity_id,'name',q.name,'selection_interactions',q.selection_interactions,
        'deselection_interactions',q.deselection_interactions,'unique_users_selected',q.unique_users_selected,'confirmed_sessions',q.confirmed_sessions)
        order by q.selection_interactions desc,q.name)
      from (select a.id activity_id,a.name,
        count(*) filter(where ev.action='simulation_activity_selected')::int selection_interactions,
        count(*) filter(where ev.action='simulation_activity_deselected')::int deselection_interactions,
        count(distinct ev.user_id) filter(where ev.action='simulation_activity_selected')::int unique_users_selected,
        (select count(distinct s.session_id)::int from public.event_preview_activity_selections s where s.event_id=p_event_id and s.activity_id=a.id) confirmed_sessions
        from public.event_analytics_events ev
        cross join lateral jsonb_array_elements_text(case when jsonb_typeof(ev.metadata->'activity_ids')='array' then ev.metadata->'activity_ids' else '[]'::jsonb end) item(activity_id)
        join public.activities a on a.id::text=item.activity_id
        where ev.event_id=p_event_id and ev.action in ('simulation_activity_selected','simulation_activity_deselected')
        group by a.id,a.name) q
    ),'[]'::jsonb),
    'budget_by_currency',coalesce((
      select jsonb_agg(jsonb_build_object('currency',q.currency,'simulations',q.simulations,'average_budget',q.average_budget,'total_budget',q.total_budget))
      from (select viewer_currency currency,count(*)::int simulations,round(avg(viewer_total),2) average_budget,round(sum(viewer_total),2) total_budget
        from public.event_preview_sessions where event_id=p_event_id and viewer_currency is not null group by viewer_currency) q
    ),'[]'::jsonb)
  ) into v_result;
  return v_result;
end;
$function$;
revoke all on function public.get_event_budget_insights(uuid) from public, anon;
grant execute on function public.get_event_budget_insights(uuid) to authenticated;
