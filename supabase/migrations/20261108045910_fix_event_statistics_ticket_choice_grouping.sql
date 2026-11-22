DO $migration$
DECLARE
  v_definition text;
  v_old text := 's.event_id = p_event_id and s.selected_ticket_id::text = event_analytics_events.metadata->>''ticket_id''';
  v_new text := 's.event_id = p_event_id and s.selected_ticket_id::text = x.ticket_id';
BEGIN
  v_definition := pg_get_functiondef('public.get_event_statistics(uuid)'::regprocedure);
  IF position(v_old in v_definition) = 0 THEN
    RAISE EXCEPTION 'Expected ticket-choice correlation was not found';
  END IF;
  v_definition := replace(v_definition, v_old, v_new);
  EXECUTE v_definition;
END;
$migration$;
