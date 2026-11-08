DO $migration$
DECLARE
  v_definition text;
  v_old_count text := '(select count(*)::int from public.event_preview_sessions s
               where s.event_id = p_event_id and s.selected_ticket_id::text = x.ticket_id) confirmed_sessions';
  v_new_count text := '0::int confirmed_sessions';
  v_old_join text := ') x
          join public.event_tickets t on t.id::text = x.ticket_id';
  v_new_join text := ') x
          join public.event_tickets t on t.id::text = x.ticket_id
          left join lateral (
            select count(*)::int confirmed_sessions
            from public.event_preview_sessions s
            where s.event_id = p_event_id
              and s.selected_ticket_id::text = x.ticket_id
          ) cs on true';
BEGIN
  v_definition := pg_get_functiondef('public.get_event_statistics(uuid)'::regprocedure);
  IF position(v_old_count in v_definition) = 0
     OR position(v_old_join in v_definition) = 0
     OR position('''confirmed_sessions'', x.confirmed_sessions' in v_definition) = 0 THEN
    RAISE EXCEPTION 'Expected ticket-choice aggregate fragments were not found';
  END IF;
  v_definition := replace(v_definition, v_old_count, v_new_count);
  v_definition := replace(v_definition, v_old_join, v_new_join);
  v_definition := replace(v_definition, '''confirmed_sessions'', x.confirmed_sessions', '''confirmed_sessions'', cs.confirmed_sessions');
  EXECUTE v_definition;
END;
$migration$;
