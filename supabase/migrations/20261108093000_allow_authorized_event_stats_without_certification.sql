-- General event statistics are available to the event creator, accepted
-- co-creators, accepted staff, and administrators, regardless of certification.
-- Financial and staff-specific RPCs retain their independent certification gates.

CREATE OR REPLACE FUNCTION public.get_event_statistics(p_event_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user_id uuid := (select auth.uid());
  v_event public.events;
  v_authorized boolean := false;
  v_result jsonb;
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select e.* into v_event from public.events e where e.id = p_event_id;
  if not found then
    raise exception 'Event not found' using errcode = 'P0002';
  end if;

  v_authorized :=
       v_user_id = v_event.creator_id
    or exists (
      select 1 from public.event_co_creators cc
      where cc.event_id = p_event_id and cc.user_id = v_user_id
        and cc.status in ('acceptee', 'accepted')
    )
    or exists (
      select 1 from public.event_staff es
      where es.event_id = p_event_id and es.user_id = v_user_id
        and es.status in ('acceptee', 'accepted')
    )
    or coalesce(public.is_admin_or_above(), false);

  if not v_authorized then
    raise exception 'Action non autorisée' using errcode = '42501';
  end if;

  -- General event analytics are available to authorized event managers
  -- even when the event has no active certification or no recorded activity.

  v_result := private.get_event_statistics(p_event_id);

  return v_result || jsonb_build_object(
    'budget_insights', jsonb_build_object(
      'sessions_started',
        (select count(*)::int from public.event_analytics_events
         where event_id = p_event_id and action = 'simulation_open'),
      'unique_budget_users',
        (select count(distinct user_id)::int from public.event_analytics_events
         where event_id = p_event_id and action = 'simulation_open'),
      'sessions_confirmed',
        (select count(*)::int from public.event_preview_sessions where event_id = p_event_id),
      'average_confirmed_budget',
        (select round(avg(viewer_total), 2) from public.event_preview_sessions where event_id = p_event_id),
      'confirmed_budget_currency',
        (select viewer_currency from public.event_preview_sessions
         where event_id = p_event_id and viewer_currency is not null
         group by viewer_currency order by count(*) desc limit 1),
      'ticket_choices',
        coalesce((
          select jsonb_agg(jsonb_build_object(
            'ticket_id', t.id,
            'name', t.name,
            'selection_count', x.selection_count,
            'unique_users', x.unique_users,
            'confirmed_sessions', x.confirmed_sessions
          ) order by x.selection_count desc, t.name)
          from (
            select metadata->>'ticket_id' ticket_id,
              count(*)::int selection_count,
              count(distinct user_id)::int unique_users,
              (select count(*)::int from public.event_preview_sessions s
               where s.event_id = p_event_id and s.selected_ticket_id::text = event_analytics_events.metadata->>'ticket_id') confirmed_sessions
            from public.event_analytics_events
            where event_id = p_event_id
              and action = 'simulation_ticket_selected'
              and metadata ? 'ticket_id'
            group by metadata->>'ticket_id'
          ) x
          join public.event_tickets t on t.id::text = x.ticket_id
        ), '[]'::jsonb),
      'activity_choices',
        coalesce((
          select jsonb_agg(jsonb_build_object(
            'activity_id', z.activity_id,
            'name', z.name,
            'selection_interactions', z.selection_interactions,
            'deselection_interactions', z.deselection_interactions,
            'unique_users_selected', z.unique_users_selected,
            'confirmed_sessions', z.confirmed_sessions
          ) order by z.selection_interactions desc, z.name)
          from (
            select a.id activity_id,
              a.name,
              count(*) filter (where ev.action = 'simulation_activity_selected')::int selection_interactions,
              count(*) filter (where ev.action = 'simulation_activity_deselected')::int deselection_interactions,
              count(distinct ev.user_id) filter (where ev.action = 'simulation_activity_selected')::int unique_users_selected,
              (select count(distinct s.session_id)::int
               from public.event_preview_activity_selections s
               where s.event_id = p_event_id and s.activity_id = a.id) confirmed_sessions
            from public.event_analytics_events ev
            cross join lateral jsonb_array_elements_text(
              case when jsonb_typeof(ev.metadata->'activity_ids') = 'array'
                then ev.metadata->'activity_ids' else '[]'::jsonb end
            ) item(activity_id)
            join public.activities a on a.id::text = item.activity_id
            where ev.event_id = p_event_id
              and ev.action in ('simulation_activity_selected', 'simulation_activity_deselected')
            group by a.id, a.name
          ) z
        ), '[]'::jsonb),
      'confirmation_rate',
        case
          when (select count(*) from public.event_analytics_events
                where event_id = p_event_id and action = 'simulation_open') > 0
          then round(
            (select count(*)::numeric from public.event_preview_sessions where event_id = p_event_id)
            / (select count(*)::numeric from public.event_analytics_events
               where event_id = p_event_id and action = 'simulation_open') * 100, 2
          )
          else null
        end,
      'unconfirmed_sessions',
        greatest(
          (select count(*)::int from public.event_analytics_events
           where event_id = p_event_id and action = 'simulation_open')
          - (select count(*)::int from public.event_preview_sessions where event_id = p_event_id),
          0
        )
    )
  );
end;
$function$

