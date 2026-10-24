-- Scrole Reputation V2 foundation.
-- Review before applying to any Supabase environment.
-- This migration intentionally does not rewrite user_statistics.points/level:
-- the existing scoring path must be audited and migrated separately.

create table if not exists public.reputation_scoring_rules (
  rule_key text primary key,
  label text not null,
  points integer not null default 0,
  daily_cap integer,
  enabled boolean not null default true,
  config jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  constraint reputation_scoring_rules_key_not_blank check (length(trim(rule_key)) > 0),
  constraint reputation_scoring_rules_daily_cap_nonnegative check (daily_cap is null or daily_cap >= 0)
);

create table if not exists public.reputation_ledger (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  scope_type text not null default 'global',
  scope_id uuid,
  event_key text not null,
  source_type text not null,
  source_id text not null,
  points_delta integer not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint reputation_ledger_scope_type check (scope_type in ('global', 'community')),
  constraint reputation_ledger_source_not_blank check (
    length(trim(event_key)) > 0 and length(trim(source_type)) > 0 and length(trim(source_id)) > 0
  )
);

-- One event can award at most once per user and scope; retries are idempotent.
create unique index if not exists reputation_ledger_idempotency_idx
  on public.reputation_ledger (user_id, scope_type, coalesce(scope_id, '00000000-0000-0000-0000-000000000000'::uuid), event_key, source_type, source_id);

create index if not exists reputation_ledger_user_created_idx
  on public.reputation_ledger (user_id, created_at desc);

create index if not exists reputation_ledger_scope_created_idx
  on public.reputation_ledger (scope_type, scope_id, created_at desc)
  where scope_type = 'community';

create table if not exists public.user_community_reputation (
  user_id uuid not null references auth.users(id) on delete cascade,
  community_id uuid not null,
  points integer not null default 0,
  level integer not null default 1,
  last_meaningful_activity_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (user_id, community_id),
  constraint user_community_reputation_points_nonnegative check (points >= 0),
  constraint user_community_reputation_level_positive check (level >= 1)
);

create index if not exists user_community_reputation_leaderboard_idx
  on public.user_community_reputation (community_id, points desc);

-- Tables are not client-writable. Trusted server-side functions/admin tooling
-- must be added only after the existing admin-role policy and scoring paths
-- have been verified. Authenticated users may read their own ledger/score only.
alter table public.reputation_scoring_rules enable row level security;
alter table public.reputation_ledger enable row level security;
alter table public.user_community_reputation enable row level security;

drop policy if exists "Users can read own reputation ledger" on public.reputation_ledger;
create policy "Users can read own reputation ledger"
  on public.reputation_ledger for select to authenticated
  using (user_id = auth.uid());

drop policy if exists "Users can read own community reputation" on public.user_community_reputation;
create policy "Users can read own community reputation"
  on public.user_community_reputation for select to authenticated
  using (user_id = auth.uid());

drop policy if exists "Authenticated users can read enabled reputation rules" on public.reputation_scoring_rules;
create policy "Authenticated users can read enabled reputation rules"
  on public.reputation_scoring_rules for select to authenticated
  using (enabled = true);

-- Conservative initial defaults. Product/admin can tune these after the scoring path
-- and server-side award functions are reviewed. Values are not active until migration is applied.
-- points are internal ledger units; the displayed score must be normalized/weighted to 0.00–5.00.
insert into public.reputation_scoring_rules (rule_key, label, points, daily_cap, enabled, config)
values
  ('meaningful_post', 'Publication originale pertinente', 2, 6, true, '{"max_awards_per_day":3,"requires_non_spam":true,"public_score_scale":"0-5","dimension":"quality","dimension_weight":0.30,"saturation_k":24}'::jsonb),
  ('constructive_comment', 'Commentaire constructif', 1, 5, true, '{"max_awards_per_day":5,"requires_minimum_content":true,"public_score_scale":"0-5","dimension":"quality","dimension_weight":0.30,"saturation_k":30}'::jsonb),
  ('post_positive_reaction_received', 'Réaction positive reçue sur une publication', 1, 5, true, '{"distinct_reactors_only":true,"exclude_author":true,"public_score_scale":"0-5","dimension":"recognition","dimension_weight":0.25,"saturation_k":40}'::jsonb),
  ('comment_positive_reaction_received', 'Réaction positive reçue sur un commentaire', 1, 5, true, '{"distinct_reactors_only":true,"exclude_author":true,"public_score_scale":"0-5","dimension":"recognition","dimension_weight":0.25,"saturation_k":35}'::jsonb),
  ('helpful_reply', 'Réponse reconnue comme utile (activation après validation)', 3, 6, false, '{"max_awards_per_day":2,"single_award_per_source":true,"public_score_scale":"0-5","dimension":"quality","dimension_weight":0.30,"saturation_k":24}'::jsonb),
  ('meaningful_activity_day', 'Journée de participation significative', 1, 1, true, '{"max_awards_per_day":1,"public_score_scale":"0-5","dimension":"consistency","dimension_weight":0.20,"saturation_k":45,"requires_distinct_active_day":true}'::jsonb),
  ('confirmed_spam_penalty', 'Abus confirmé par modération', -3, null, true, '{"moderation_required":true,"must_reference_reversed_entry":true,"dimension":"trust","dimension_weight":0.10}'::jsonb),
  ('weekly_inactivity_decay', 'Décroissance hebdomadaire après inactivité', 0, null, true, '{"grace_days":30,"rate_percent":1,"period":"week","minimum_score":0,"applies_to_public_score":true}'::jsonb)
on conflict (rule_key) do nothing;

-- No INSERT/UPDATE/DELETE policies are intentionally defined for client roles.
