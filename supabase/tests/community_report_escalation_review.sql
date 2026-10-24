-- Read-only verification assertions for the community report escalation flow.
-- Run after applying 20261024230000_complete_community_report_escalation.sql.
do $$
declare
  v_report_content text;
  v_community_reports text;
  v_platform_reports text;
  v_resolve_platform text;
  v_escalator text;
begin
  select pg_get_functiondef('public.report_content(text,uuid,uuid,text)'::regprocedure) into v_report_content;
  if position('is not distinct from v_report_community_id' in lower(v_report_content)) = 0 then
    raise exception 'report_content must scope deduplication by community_id including NULL';
  end if;

  select pg_get_functiondef('public.get_community_reports(uuid,text,integer,integer)'::regprocedure) into v_community_reports;
  if position('target_type::text in (''post'', ''comment'')' in lower(v_community_reports)) = 0 then
    raise exception 'Community content queue must not include member reports';
  end if;

  select pg_get_functiondef('public.get_platform_reports(text,integer,integer)'::regprocedure) into v_platform_reports;
  if position('''user''' in lower(v_platform_reports)) = 0
     or position('escalated_at is not null' in lower(v_platform_reports)) = 0 then
    raise exception 'Platform queue must include escalated member reports';
  end if;

  select pg_get_functiondef('public.resolve_platform_report(uuid,text,text)'::regprocedure) into v_resolve_platform;
  if position('suspend_user' in lower(v_resolve_platform)) = 0
     or position('community_id is not distinct from v_rep.community_id' in lower(v_resolve_platform)) = 0 then
    raise exception 'Platform decisions must support escalated member reports and remain community-scoped';
  end if;

  select pg_get_functiondef('public.escalate_stale_community_reports()'::regprocedure) into v_escalator;
  if position('interval ''48 hours''' in lower(v_escalator)) = 0 then
    raise exception 'Community escalation threshold must remain 48 hours';
  end if;
  if position('en_cours' in lower(v_escalator)) = 0 then
    raise exception 'Community reports left in progress must also escalate after 48 hours';
  end if;

  if not exists (
    select 1 from cron.job
    where active and command ilike '%escalate_stale_community_reports%'
  ) then
    raise exception 'Hourly escalation cron job is missing or inactive';
  end if;
end;
$$;
