alter table public.event_preview_sessions
  add column if not exists ticket_source_price numeric,
  add column if not exists ticket_source_currency text,
  add column if not exists ticket_viewer_price numeric,
  add column if not exists ticket_viewer_currency text;

create or replace function public.record_event_preview_session(
 p_session_id uuid,p_event_id uuid,p_opened_at timestamp with time zone,p_closed_at timestamp with time zone,
 p_selected_ticket_id uuid default null,p_selected_activity_ids uuid[] default '{}'::uuid[]
)
returns jsonb language plpgsql security definer set search_path='public'
as $function$
declare
 v_user uuid:=auth.uid(); v_ticket_price numeric:=0; v_ticket_currency text;
 v_ticket_viewer_price numeric:=0; v_ticket_viewer_currency text;
 v_activity_count integer:=0; v_source_total numeric:=0; v_viewer_total numeric:=0;
 v_viewer_currency text; v_bad integer; v_activity record; v_conv record;
begin
 if v_user is null then raise exception 'Authentification requise'; end if;
 if not can_view_event(p_event_id) then raise exception 'Événement introuvable ou non accessible'; end if;
 if exists(select 1 from events where id=p_event_id and creator_id=v_user)
  or exists(select 1 from event_staff where event_id=p_event_id and user_id=v_user and status='acceptee')
  or exists(select 1 from event_co_creators where event_id=p_event_id and user_id=v_user and status='acceptee') then
  raise exception 'Les managers ne peuvent pas enregistrer une simulation de preview';
 end if;
 if p_closed_at<p_opened_at then raise exception 'Période de preview invalide'; end if;
 if p_selected_ticket_id is not null then
  select price,currency_code into v_ticket_price,v_ticket_currency from event_tickets where id=p_selected_ticket_id and event_id=p_event_id;
  if not found then raise exception 'Billet invalide pour cet événement'; end if;
 end if;
 if coalesce(array_length(p_selected_activity_ids,1),0)>0 then
  select count(*) into v_bad from unnest(p_selected_activity_ids) x(id)
   where not exists(select 1 from event_activities ea where ea.event_id=p_event_id and ea.activity_id=x.id);
  if v_bad>0 then raise exception 'Une ou plusieurs activités ne sont pas liées à cet événement'; end if;
  select count(distinct id) into v_activity_count from unnest(p_selected_activity_ids) x(id);
 end if;
 if p_selected_ticket_id is not null then
  v_source_total:=v_source_total+coalesce(v_ticket_price,0);
  select * into v_conv from convert_to_viewer_currency(coalesce(v_ticket_price,0),v_ticket_currency,v_user);
  v_ticket_viewer_price:=coalesce(v_conv.amount,0); v_ticket_viewer_currency:=v_conv.currency_code;
  v_viewer_total:=v_viewer_total+v_ticket_viewer_price; v_viewer_currency:=v_ticket_viewer_currency;
 end if;
 for v_activity in
  select ea.activity_id,ea.price,a.currency_code from event_activities ea join activities a on a.id=ea.activity_id
  where ea.event_id=p_event_id and ea.activity_id=any(p_selected_activity_ids)
 loop
  v_source_total:=v_source_total+coalesce(v_activity.price,0);
  select * into v_conv from convert_to_viewer_currency(coalesce(v_activity.price,0),v_activity.currency_code,v_user);
  v_viewer_total:=v_viewer_total+coalesce(v_conv.amount,0); v_viewer_currency:=v_conv.currency_code;
 end loop;
 insert into event_preview_sessions(id,event_id,user_id,opened_at,closed_at,selected_ticket_id,source_total,viewer_total,viewer_currency,
  ticket_source_price,ticket_source_currency,ticket_viewer_price,ticket_viewer_currency)
 values(p_session_id,p_event_id,v_user,coalesce(p_opened_at,now()),coalesce(p_closed_at,now()),p_selected_ticket_id,
  v_source_total,v_viewer_total,v_viewer_currency,v_ticket_price,v_ticket_currency,v_ticket_viewer_price,v_ticket_viewer_currency)
 on conflict(id) do update set closed_at=excluded.closed_at,selected_ticket_id=excluded.selected_ticket_id,
  source_total=excluded.source_total,viewer_total=excluded.viewer_total,viewer_currency=excluded.viewer_currency,
  ticket_source_price=excluded.ticket_source_price,ticket_source_currency=excluded.ticket_source_currency,
  ticket_viewer_price=excluded.ticket_viewer_price,ticket_viewer_currency=excluded.ticket_viewer_currency;
 delete from event_preview_activity_selections where session_id=p_session_id and user_id=v_user;
 insert into event_preview_activity_selections(session_id,user_id,event_id,activity_id,source_price,source_currency,viewer_price,viewer_currency)
 select p_session_id,v_user,p_event_id,ea.activity_id,ea.price,a.currency_code,c.amount,c.currency_code
 from event_activities ea join activities a on a.id=ea.activity_id
 cross join lateral convert_to_viewer_currency(ea.price,a.currency_code,v_user)c
 where ea.event_id=p_event_id and ea.activity_id=any(p_selected_activity_ids);
 return jsonb_build_object('session_id',p_session_id,'event_id',p_event_id,'selected_ticket_id',p_selected_ticket_id,
  'selected_activity_count',v_activity_count,'source_total',v_source_total,'viewer_total',v_viewer_total,'viewer_currency',v_viewer_currency,
  'ticket_source_price',v_ticket_price,'ticket_source_currency',v_ticket_currency,
  'ticket_viewer_price',v_ticket_viewer_price,'ticket_viewer_currency',v_ticket_viewer_currency);
end;
$function$;

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
