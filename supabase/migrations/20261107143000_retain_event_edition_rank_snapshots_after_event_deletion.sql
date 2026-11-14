alter table public.event_edition_ranking_snapshots
  drop constraint if exists event_edition_ranking_snapshots_event_id_fkey;
comment on table public.event_edition_ranking_snapshots is
  'Immutable historical ranking snapshots per event edition; intentionally retained if the source event is deleted.';