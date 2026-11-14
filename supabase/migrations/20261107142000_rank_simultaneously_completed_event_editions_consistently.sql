-- A statement-level trigger sees all editions completed by one scheduler pass.
-- This ensures simultaneous completions are ranked against the same pre-close cohort.
create or replace function public.trg_capture_completed_event_ranking()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_target record;
  v_score numeric(14,2);
  v_rank integer;
  v_total integer;
  v_prestige jsonb;
begin
  for v_target in
    select n.id, n.series_id, n.edition_number
    from new_events n
    join old_events o on o.id = n.id
    where o.status is distinct from n.status and n.status = 'completed'
  loop
    if exists (select 1 from public.event_edition_ranking_snapshots s where s.event_id = v_target.id) then
      continue;
    end if;

    select count(*) * 2
      + (select count(*) from public.event_likes where event_id = v_target.id)
    into v_score
    from public.event_calendar where event_id = v_target.id;

    with cohort_ids as (
      select e.id from public.events e where e.status = 'active'
      union
      select n.id from new_events n
      join old_events o on o.id = n.id
      where o.status = 'active' and n.status = 'completed'
    ),
    cohort_scores as (
      select ids.id,
        (select count(*) from public.event_calendar ec where ec.event_id = ids.id) * 2
        + (select count(*) from public.event_likes el where el.event_id = ids.id) as score
      from cohort_ids ids
    )
    select 1 + count(*) filter (where cs.score > v_score), count(*)
    into v_rank, v_total
    from cohort_scores cs;

    v_prestige := public.calculate_event_prestige(v_target.id);
    insert into public.event_edition_ranking_snapshots (
      event_id, series_id, edition_number, ranking_scope, final_rank,
      total_events, ranking_score, prestige_score, prestige_stars,
      prestige_components, finalized_at
    ) values (
      v_target.id, v_target.series_id, v_target.edition_number, 'global',
      v_rank, greatest(v_total, 1), v_score,
      nullif(v_prestige->>'prestige_score', '')::numeric,
      nullif(v_prestige->>'prestige_stars', '')::numeric,
      coalesce(v_prestige->'components', '{}'::jsonb), now()
    ) on conflict (event_id) do nothing;
  end loop;
  return null;
end;
$$;

drop trigger if exists trg_capture_completed_event_ranking on public.events;
create trigger trg_capture_completed_event_ranking
  after update on public.events
  referencing old table as old_events new table as new_events
  for each statement
  execute function public.trg_capture_completed_event_ranking();
