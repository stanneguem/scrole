-- Final API hardening for event certification feature gates.
-- Reversible function/trigger changes only; no existing rows are deleted.

create or replace function public.get_scrole_public_quota_settings()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
  select jsonb_build_object(
    'noncert_agenda_max_events', (select value from public.scrole_quota_settings where quota_key = 'noncert_agenda_max_events'),
    'noncert_agenda_horizon_months', (select value from public.scrole_quota_settings where quota_key = 'noncert_agenda_horizon_months'),
    'noncert_event_horizon_months', (select value from public.scrole_quota_settings where quota_key = 'noncert_event_horizon_months'),
    'noncert_event_max_duration_days', (select value from public.scrole_quota_settings where quota_key = 'noncert_event_max_duration_days'),
    'noncert_event_agenda_max_people', (select value from public.scrole_quota_settings where quota_key = 'noncert_event_agenda_max_people'),
    'certified_event_horizon_months', (select value from public.scrole_quota_settings where quota_key = 'certified_event_horizon_months')
  );
$function$;

-- Block deletion as well as creation/editing of guest/sponsor/ticket records
-- when an event certification is absent or suspended.
create or replace function public.scrole_require_event_certification_for_management()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_event_id uuid;
begin
  v_event_id := case when tg_op = 'DELETE' then old.event_id else new.event_id end;
  if not exists (
    select 1 from public.event_certifications ec
    where ec.event_id = v_event_id
      and ec.status = 'active'
      and (ec.valid_until is null or ec.valid_until > now())
  ) then
    raise exception 'event_certification_required'
      using errcode = '42501',
      detail = 'La certification de cet événement est nécessaire pour gérer les invitations Guest, les sponsors et la billetterie.';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$function$;

drop trigger if exists scrole_guest_requires_event_certification on public.event_guest_invitations;
create trigger scrole_guest_requires_event_certification
before insert or update or delete on public.event_guest_invitations
for each row execute function public.scrole_require_event_certification_for_management();

drop trigger if exists scrole_sponsor_requires_event_certification on public.event_sponsor_invitations;
create trigger scrole_sponsor_requires_event_certification
before insert or update or delete on public.event_sponsor_invitations
for each row execute function public.scrole_require_event_certification_for_management();

drop trigger if exists scrole_ticket_requires_event_certification on public.event_tickets;
create trigger scrole_ticket_requires_event_certification
before insert or update or delete on public.event_tickets
for each row execute function public.scrole_require_event_certification_for_management();

create or replace function public.get_event_financial_stats(p_event_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = 'public'
as $function$
declare
  v_event public.events;
  v_par_activite jsonb;
  v_total_converti numeric;
  v_devise_ref text;
  v_attendee_count integer;
  v_billet_min numeric;
  v_billet_min_currency text;
  v_estimation_billetterie jsonb;
begin
  if not exists (
    select 1 from public.event_certifications ec
    where ec.event_id=p_event_id and ec.status='active'
      and (ec.valid_until is null or ec.valid_until > now())
  ) then
    raise exception 'event_certification_required_for_statistics' using errcode='42501';
  end if;
  if not public.is_event_owner(p_event_id) then
    raise exception 'Réservé au créateur ou aux co-créateurs de l''événement';
  end if;

  select * into v_event from public.events where id=p_event_id;

  with per_activite as (
    select a.id as activity_id,a.name,c.nb,ea.price,a.currency_code,
      (c.nb*ea.price) as revenu_brut,
      (public.convert_to_viewer_currency(c.nb*ea.price,a.currency_code)).*
    from public.event_activities ea
    join public.activities a on a.id=ea.activity_id
    join lateral (
      select count(*) as nb from public.event_checkins
      where event_id=p_event_id and activity_id=ea.activity_id and status='valid'
    ) c on true
    where ea.event_id=p_event_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'activity_id',activity_id,'name',name,'nombre_participations',nb,
      'prix_dans_cet_event',price,'currency_code',currency_code,
      'revenu_estime_brut',revenu_brut,
      'revenu_estime_converti',jsonb_build_object('amount',amount,'currency_code',currency_code)
    )),'[]'::jsonb),
    coalesce(sum(amount),0),max(currency_code)
  into v_par_activite,v_total_converti,v_devise_ref
  from per_activite;

  select count(*) into v_attendee_count from public.event_calendar where event_id=p_event_id;

  if not v_event.is_free then
    select price,currency_code into v_billet_min,v_billet_min_currency
    from public.event_tickets where event_id=p_event_id order by price asc limit 1;
    if v_billet_min is not null then
      v_estimation_billetterie := jsonb_build_object(
        'billet_le_moins_cher',v_billet_min,'currency_code',v_billet_min_currency,
        'nombre_dans_agenda',v_attendee_count,
        'estimation_min_convertie',(select to_jsonb(cv) from public.convert_to_viewer_currency(v_attendee_count*v_billet_min,v_billet_min_currency) cv),
        'note','estimation basse, calculée sur le nombre de personnes ayant ajouté l''événement à leur agenda et le prix du billet le moins cher — aucune vente réelle n''est suivie'
      );
    else
      v_estimation_billetterie := null;
    end if;
  else
    v_estimation_billetterie := null;
  end if;

  return jsonb_build_object(
    'activites',v_par_activite,
    'revenu_total_activites_estime_converti',jsonb_build_object('amount',v_total_converti,'currency_code',coalesce(v_devise_ref,'XAF')),
    'billetterie_estimee',v_estimation_billetterie
  );
end;
$function$;

create or replace function public.get_event_day_attendance(p_event_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = 'public'
as $function$
begin
  if not exists (
    select 1 from public.event_certifications ec
    where ec.event_id=p_event_id and ec.status='active'
      and (ec.valid_until is null or ec.valid_until > now())
  ) then
    raise exception 'event_certification_required_for_statistics' using errcode='42501';
  end if;
  if not public.is_event_owner(p_event_id) then
    raise exception 'Action réservée au créateur ou aux co-créateurs de l''événement';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'date',od.event_date,
      'planned_attendees',(
        select count(*) from public.event_calendar_days cd
        where cd.event_id=od.event_id and cd.event_date=od.event_date
      )
    ) order by od.event_date)
    from public.event_open_days od where od.event_id=p_event_id
  ),'[]'::jsonb);
end;
$function$;

create or replace function public.get_event_staff_stats(p_event_staff_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = 'public'
as $function$
declare
  v_event_id uuid;
  v_staff_user_id uuid;
  v_result jsonb;
begin
  select es.event_id,es.user_id into v_event_id,v_staff_user_id
  from public.event_staff es where es.id=p_event_staff_id;

  if v_event_id is null then raise exception 'Membre du staff introuvable'; end if;
  if not exists (
    select 1 from public.event_certifications ec
    where ec.event_id=v_event_id and ec.status='active'
      and (ec.valid_until is null or ec.valid_until > now())
  ) then
    raise exception 'event_certification_required_for_statistics' using errcode='42501';
  end if;
  if not public.is_event_owner(v_event_id) and not public.is_event_staff_member(v_event_id) then
    raise exception 'Accès réservé au staff ou au gestionnaire de cet événement';
  end if;

  select jsonb_build_object(
    'event',jsonb_build_object('id',e.id,'name',e.name,'status',e.status),
    'staff',jsonb_build_object('event_staff_id',es.id,'user_id',es.user_id,'status',es.status,
      'created_at',es.created_at,'responded_at',es.responded_at),
    'total_scans',coalesce((
      select count(*) from public.event_checkins ec
      where ec.event_id=v_event_id and ec.validated_by_user_id=v_staff_user_id
        and ec.status='valid' and ec.activity_id is not null
    ),0),
    'activities',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',a.id,'name',a.name,
        'scan_count',coalesce((
          select count(*) from public.event_checkins ec
          where ec.event_id=v_event_id and ec.validated_by_user_id=v_staff_user_id
            and ec.activity_id=a.id and ec.status='valid'
        ),0)
      ) order by a.name)
      from public.event_staff_activities esa
      join public.activities a on a.id=esa.activity_id
      where esa.event_staff_id=p_event_staff_id
    ),'[]'::jsonb)
  ) into v_result
  from public.event_staff es join public.events e on e.id=es.event_id
  where es.id=p_event_staff_id;

  return v_result;
end;
$function$;

revoke all on function public.scrole_require_event_certification_for_management() from public,anon,authenticated;
