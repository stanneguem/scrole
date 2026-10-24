-- Escalate community reports even if a moderator opened them but did not decide.
create index if not exists idx_signalement_community_escalation_reviewing
  on public.signalement (escalated_at, created_at desc)
  where community_id is not null
    and status in ('en_attente'::public.signalement_status, 'en_cours'::public.signalement_status)
    and escalated_at is null;

create or replace function public.escalate_stale_community_reports()
returns integer
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_count integer;
begin
  with updated as (
    update public.signalement
    set escalated_at = now()
    where community_id is not null
      and status in ('en_attente'::public.signalement_status, 'en_cours'::public.signalement_status)
      and escalated_at is null
      and created_at < now() - interval '48 hours'
    returning 1
  )
  select count(*) into v_count from updated;
  return v_count;
end;
$function$;

revoke all on function public.escalate_stale_community_reports() from public, anon, authenticated;
