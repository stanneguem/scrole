-- Complete the community-report lifecycle:
-- - deduplicate by the real community scope (never reuse a report from another community)
-- - expose escalated community member reports to platform admins
-- - let platform admins resolve escalated user reports
-- - keep all resolution updates scoped to the same community and target.
-- Existing scheduler runs public.escalate_stale_community_reports() hourly; retain its 48-hour threshold.

create index if not exists idx_signalement_community_escalation
  on public.signalement (escalated_at, created_at desc)
  where community_id is not null and status = 'en_attente';

-- The existing deployed RPCs already implement community-scoped report creation,
-- separate member reporting, platform report listing (including external profiles),
-- platform resolution, and 48-hour escalation. Keep this migration additive:
-- do not redefine those RPCs here, so their full target-type coverage and
-- external-profile workflow remain intact.

-- Platform report listing and resolution already support external profile reports and
-- escalated community-member reports in the deployed schema. Do not replace those
-- functions here: preserve their external-profile workflow and permission checks.

-- Only the scheduled database job should trigger escalations; end users must not force early escalation.
revoke all on function public.escalate_stale_community_reports() from public, anon, authenticated;
