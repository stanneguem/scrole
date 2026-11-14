-- Persist an immutable global ranking snapshot for each completed event edition.
create table if not exists public.event_edition_ranking_snapshots (
  event_id uuid primary key references public.events(id) on delete cascade,
  series_id uuid,
  edition_number integer not null default 1,
  ranking_scope text not null default 'global',
  final_rank integer not null,
  total_events integer not null,
  ranking_score numeric(14,2) not null,
  prestige_score numeric(6,2),
  prestige_stars numeric(3,1),
  prestige_components jsonb not null default '{}'::jsonb,
  finalized_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint event_edition_ranking_snapshots_rank_positive check (final_rank > 0),
  constraint event_edition_ranking_snapshots_total_positive check (total_events > 0)
);

create index if not exists idx_event_edition_ranking_snapshots_series
  on public.event_edition_ranking_snapshots(series_id, edition_number);

alter table public.event_edition_ranking_snapshots enable row level security;
drop policy if exists "Public can read event edition ranking snapshots" on public.event_edition_ranking_snapshots;
create policy "Public can read event edition ranking snapshots"
  on public.event_edition_ranking_snapshots for select
  using (
    exists (
      select 1 from public.events e
      where e.id = event_id and e.is_public = true
    )
  );
grant select on public.event_edition_ranking_snapshots to anon, authenticated;

create or replace function public.capture_event_edition_ranking(p_event_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_event public.events%rowtype;
  v_score numeric(14,2);
  v_rank integer;
  v_total integer;
  v_prestige jsonb;
begin
  select * into v_event from public.events where id = p_event_id;
  if not found or v_event.status <> 'completed' then return; end if;
  if exists (select 1 from public.event_edition_ranking_snapshots s where s.event_id = p_event_id) then return; end if;

  select (select count(*) from public.event_calendar where event_id = p_event_id) * 2
       + (select count(*) from public.event_likes where event_id = p_event_id)
    into v_score;

  -- Compare against the same live cohort used by the event preview ranking.
  select 1 + count(*) filter (where peer.score > v_score), count(*) + 1
    into v_rank, v_total
  from (
    select e.id,
      (select count(*) from public.event_calendar ec where ec.event_id = e.id) * 2
      + (select count(*) from public.event_likes el where el.event_id = e.id) as score
    from public.events e
    where e.status = 'active' and e.id <> p_event_id
  ) peer;

  v_prestige := public.calculate_event_prestige(p_event_id);
  insert into public.event_edition_ranking_snapshots (
    event_id, series_id, edition_number, ranking_scope,
    final_rank, total_events, ranking_score,
    prestige_score, prestige_stars, prestige_components, finalized_at
  ) values (
    p_event_id, v_event.series_id, v_event.edition_number, 'global',
    v_rank, v_total, v_score,
    nullif(v_prestige->>'prestige_score', '')::numeric,
    nullif(v_prestige->>'prestige_stars', '')::numeric,
    coalesce(v_prestige->'components', '{}'::jsonb), now()
  ) on conflict (event_id) do nothing;
end;
$$;

create or replace function public.trg_capture_completed_event_ranking()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.status is distinct from new.status and new.status = 'completed' then
    perform public.capture_event_edition_ranking(new.id);
  end if;
  return new;
end;
$$;

drop trigger if exists trg_capture_completed_event_ranking on public.events;
create trigger trg_capture_completed_event_ranking
  after update of status on public.events
  for each row
  when (old.status is distinct from new.status and new.status = 'completed')
  execute function public.trg_capture_completed_event_ranking();

create or replace function public.get_event_preview_base(p_event_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $function$
declare
 v_event public.events; v_creator record; v_stats jsonb; v_prestige jsonb;
 v_likes_count integer; v_attendee_count integer; v_tickets jsonb; v_cheapest_ticket jsonb;
 v_activities jsonb; v_amis_agenda jsonb; v_amis_agenda_count integer;
 v_rang integer; v_total_compares integer; v_mon_score numeric; v_restrictions jsonb;
 v_event_json jsonb; v_country jsonb; v_city jsonb; v_snapshot record;
begin
 if not public.can_view_event(p_event_id) then raise exception 'Événement introuvable ou non accessible'; end if;
 select * into v_event from public.events where id=p_event_id;
 select up.username,(up.first_name||' '||up.last_name) full_name,up.photo_url into v_creator
 from public.user_profiles up where up.user_id=v_event.creator_id;
 select jsonb_build_object('id',c.id,'name',c.nom,'code_iso',c.code_iso) into v_country
 from public.countries c where c.id=v_event.country_id and c.is_active=true;
 select jsonb_build_object('id',c.id,'name',c.nom,'country_id',c.country_id) into v_city
 from public.cities c where c.id=v_event.city_id and c.is_active=true;
 select count(*) into v_likes_count from public.event_likes where event_id=p_event_id;
 select count(*) into v_attendee_count from public.event_calendar where event_id=p_event_id;
 v_tickets:='[]'::jsonb; v_cheapest_ticket:=null;
 if not v_event.is_free then
   select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'name',t.name,'converted',
     (select to_jsonb(c) from public.convert_to_viewer_currency(t.price,t.currency_code)c))),'[]'::jsonb)
   into v_tickets from public.event_tickets t where t.event_id=p_event_id;
   select jsonb_build_object('id',t.id,'name',t.name,'converted',
     (select to_jsonb(c) from public.convert_to_viewer_currency(t.price,t.currency_code)c))
   into v_cheapest_ticket
   from public.event_tickets t cross join lateral public.convert_to_viewer_currency(t.price,t.currency_code) c
   where t.event_id=p_event_id order by c.amount asc,t.id limit 1;
 end if;
 select coalesce(jsonb_agg(jsonb_build_object('activity_id',a.id,'name',a.name,'converted',
   (select to_jsonb(c) from public.convert_to_viewer_currency(ea.price,a.currency_code)c))),'[]'::jsonb)
 into v_activities from public.event_activities ea join public.activities a on a.id=ea.activity_id
 where ea.event_id=p_event_id;
 select coalesce(jsonb_agg(jsonb_build_object('user_id',up.user_id,'username',up.username,
   'full_name',(up.first_name||' '||up.last_name),'photo_url',up.photo_url)),'[]'::jsonb),count(*)
 into v_amis_agenda,v_amis_agenda_count
 from public.event_calendar ec join public.user_profiles up on up.user_id=ec.user_id
 where ec.event_id=p_event_id and public.are_friends(auth.uid(),ec.user_id);
 select to_jsonb(r) into v_restrictions from public.event_restrictions r where r.event_id=p_event_id;

 select * into v_snapshot from public.event_edition_ranking_snapshots s where s.event_id=p_event_id;
 if found then
   v_rang:=v_snapshot.final_rank; v_total_compares:=v_snapshot.total_events; v_mon_score:=v_snapshot.ranking_score;
 else
   with peers as (
     select e2.id,
       (select count(*) from public.event_calendar where event_id=e2.id)*2
       +(select count(*) from public.event_likes where event_id=e2.id) score
     from public.events e2 where e2.status='active'
   )
   select (select count(*) from peers where score>coalesce((select score from peers where id=v_event.id),0))+1,
          (select count(*) from peers),
          coalesce((select score from peers where id=v_event.id),0)
   into v_rang,v_total_compares,v_mon_score;
 end if;

 v_stats:=public.get_event_interaction_stats(p_event_id);
 v_prestige:=public.calculate_event_prestige(p_event_id);
 if v_snapshot.event_id is not null then
   v_prestige:=v_prestige||jsonb_build_object('prestige_score',v_snapshot.prestige_score,
     'prestige_stars',v_snapshot.prestige_stars,'components',v_snapshot.prestige_components);
 end if;
 v_event_json:=to_jsonb(v_event)-'country_id'-'city_id';
 v_event_json:=v_event_json||jsonb_build_object('country',v_country,'city',v_city);
 return v_stats||v_prestige||jsonb_build_object(
   'event',v_event_json,
   'creator',jsonb_build_object('user_id',v_event.creator_id,'username',v_creator.username,
     'full_name',v_creator.full_name,'photo_url',v_creator.photo_url),
   'likes_count',v_likes_count,'attendee_count',v_attendee_count,'share_count',v_event.share_count,
   'amis_dans_agenda',v_amis_agenda,'amis_dans_agenda_count',v_amis_agenda_count,
   'classement',jsonb_build_object('rang',v_rang,'sur',v_total_compares,'score',v_mon_score,
     'fige',v_snapshot.event_id is not null,'finalized_at',v_snapshot.finalized_at,
     'prestige_score',v_snapshot.prestige_score,'prestige_stars',v_snapshot.prestige_stars,
     'components',v_snapshot.prestige_components),
   'tickets',v_tickets,'cheapest_ticket',v_cheapest_ticket,
   'activities_liees',v_activities,'restrictions',v_restrictions
 );
end;
$function$;
