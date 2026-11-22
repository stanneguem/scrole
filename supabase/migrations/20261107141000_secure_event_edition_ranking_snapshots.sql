revoke all on public.event_edition_ranking_snapshots from anon, authenticated;
grant select on public.event_edition_ranking_snapshots to anon, authenticated;
revoke all on function public.capture_event_edition_ranking(uuid) from public, anon, authenticated;
revoke all on function public.trg_capture_completed_event_ranking() from public, anon, authenticated;