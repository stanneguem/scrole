-- Read-only smoke checks for the Scrole certification/quotas migrations.
-- Run the admin RPC section only through an authenticated admin session in a test project.
-- Do not run mutating test steps against production.

-- 1) Migration objects and safe mobile payload.
select to_regclass('public.scrole_subscriptions') as subscriptions,
       to_regclass('public.event_certifications') as event_certifications,
       to_regclass('public.community_certifications') as community_certifications,
       to_regclass('public.profile_certification_entitlements') as profile_entitlements,
       to_regclass('public.scrole_quota_settings') as quota_settings;\n\nselect public.get_community_certification_stats('00000000-0000-0000-0000-000000000000'::uuid); -- expected to fail: no test community/owner session

select public.get_scrole_public_quota_settings() as mobile_quotas;
select public.scrole_subscription_quotas('pro') as pro,
       public.scrole_subscription_quotas('premium') as premium;

select jobname, schedule, active
from cron.job
where jobname = 'scrole-expire-subscription-certifications';

-- 2) Authenticated admin session only (the SQL editor has no auth.uid() and should be denied):
-- select quota_key, value, category, min_value, max_value
-- from public.admin_get_scrole_quotas() order by category, quota_key;
-- select public.admin_update_scrole_quota('noncert_agenda_max_events', 3);
-- select * from public.admin_get_scrole_quotas()
-- where quota_key = 'noncert_agenda_max_events';
-- Expected: value=3 and a quota_updated row in public.scrole_certification_audit.
-- Restore the original value after the test.

-- 3) Functional tests with disposable user/event/subscription fixtures:
-- a. Uncertified profile cannot add a third distinct event to event_calendar.
-- b. Uncertified profile cannot add an event or selected participation day beyond configured horizon.
-- c. A profile with an active user_certifications row can add more agenda events.
-- d. Non-certified event cannot exceed configured start horizon or exact elapsed duration.
-- e. Certified event can be scheduled within certified_event_horizon_months but not beyond it.
-- e2. create_certified_event_with_subscription consumes exactly one included event quota atomically.
-- e3. The same RPC rejects users without an active subscription or without remaining event quota.\n-- o. get_community_certification_stats works only for a certified community's owner.\n-- p. link_event_to_community rejects an uncertified community.\n-- q. Tickets work with an event or its linked community certification; guest/sponsors still require event certification.
-- f. Non-certified event cannot exceed audience/cofounder/staff quotas.
-- g. Guest/sponsor/ticket insert, update and delete are denied without event-level certification.
-- h. Event financial/day-attendance/staff statistics are denied without event-level certification.
-- i. Premium -> Pro selection respects current quotas and suspends all unselected included certifications.
-- j. Expiration suspends included profile/event/community certifications without deleting rows.
-- k. Renewal reactivates only selected included event/community entitlements and included profile tier.
-- l. Purchased/admin-granted certifications remain independent.
-- m. Anonymous users and authenticated users without certifications.manage cannot change quotas.
-- n. Trusted grant/renewal/expiry functions cannot be executed by anon/authenticated.
