create or replace function public.get_my_event_budget_sessions(p_limit integer default 50)
returns jsonb language plpgsql stable security definer set search_path=''
as $function$
declare v_user_id uuid:=(select auth.uid()); v_result jsonb;
begin
 if v_user_id is null then raise exception 'Authentication required' using errcode='42501'; end if;
 select coalesce(jsonb_agg(item.payload order by item.created_at desc),'[]'::jsonb) into v_result
 from (
  select s.created_at,jsonb_build_object(
   'session_id',s.id,'event_id',s.event_id,'event_name',e.name,'event_photo',e.photo,
   'event_starts_at',e.starts_at,'event_ends_at',e.ends_at,'saved_at',s.created_at,
   'opened_at',s.opened_at,'closed_at',s.closed_at,'ticket_id',s.selected_ticket_id,'ticket_name',t.name,
   'ticket_source_price',s.ticket_source_price,'ticket_source_currency',s.ticket_source_currency,
   'ticket_viewer_price',s.ticket_viewer_price,'ticket_viewer_currency',s.ticket_viewer_currency,
   'source_total',s.source_total,'viewer_total',s.viewer_total,'currency',s.viewer_currency,
   'activities',coalesce((select jsonb_agg(jsonb_build_object('activity_id',a.id,'name',a.name,
    'source_price',sel.source_price,'source_currency',sel.source_currency,'price',sel.viewer_price,'currency',sel.viewer_currency) order by a.name)
    from public.event_preview_activity_selections sel join public.activities a on a.id=sel.activity_id
    where sel.session_id=s.id and sel.user_id=v_user_id),'[]'::jsonb)
  ) payload
  from public.event_preview_sessions s join public.events e on e.id=s.event_id
  left join public.event_tickets t on t.id=s.selected_ticket_id
  where s.user_id=v_user_id order by s.created_at desc limit greatest(1,least(coalesce(p_limit,50),100))
 ) item;
 return v_result;
end;
$function$;
revoke all on function public.get_my_event_budget_sessions(integer) from public,anon;
grant execute on function public.get_my_event_budget_sessions(integer) to authenticated;
