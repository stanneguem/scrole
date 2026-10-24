-- Manual SQL test checklist for the Scrole certification migration.
-- Execute only in a disposable Supabase branch/project after applying the migration there.
-- Do not run against production as a test script.

-- 1) Schema smoke test:
select to_regclass('public.scrole_subscriptions') as subscriptions,
       to_regclass('public.event_certifications') as event_certifications,
       to_regclass('public.community_certifications') as community_certifications,
       to_regclass('public.scrole_certification_audit') as audit_log;

-- 2) Quota contract:
select public.scrole_subscription_quotas('pro') as pro_quotas;
select public.scrole_subscription_quotas('premium') as premium_quotas;

-- Expected: {"events":1,"communities":1} and {"events":4,"communities":4}.

-- 3) Security review (inspect grants/policies; run as database owner in test project):
select routine_name, grantee, privilege_type
from information_schema.routine_privileges
where routine_schema='public'
  and routine_name in (
    'scrole_subscription_quotas',
    'scrole_change_subscription_plan',
    'scrole_suspend_expired_subscription_certifications'
  )
order by routine_name, grantee;

select tablename, policyname, cmd, qual, with_check
from pg_policies
where schemaname='public'
  and tablename in (
    'scrole_subscriptions',
    'event_certifications',
    'community_certifications',
    'scrole_certification_audit'
  )
order by tablename, policyname;

-- 4) Functional tests require fixtures for auth.users, events, communities,
-- scrole_subscriptions and certification rows. Exercise through authenticated
-- sessions, not only the SQL editor:
--   a. user A downgrades their Premium subscription to Pro, selecting one
--      included event and one included community.
--   b. all other included rows are suspended, selected rows remain active.
--   c. purchased/admin_grant rows remain unchanged.
--   d. user B cannot invoke the downgrade for user A's subscription.
--   e. after ends_at passes, the trusted lifecycle function expires the
--      subscription and suspends its active included certifications.
--   f. no entity/profile rows are deleted or changed by lifecycle transitions.
