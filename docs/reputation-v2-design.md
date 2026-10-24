# Scrole Reputation V2 — design and rollout

## Why this is a foundation, not a score cutover

The live `public.user_statistics` table currently exposes `points`, `level`, `posts_count`, and `communities_count`. A read-only scan of public routine definitions found references to that table in the admin user detail function, but did not identify the definitive points-awarding routine. Therefore V2 must not silently overwrite existing points or change level thresholds until the awarding triggers, RPCs, and client-side display/calculation paths are fully traced.

## Reputation affichée sur 5 (règle obligatoire)

Le score public total est toujours compris entre **0,00 et 5,00**. Les valeurs du journal (`points_delta`) sont des unités techniques d'événement, pas le score affiché. On ne doit jamais afficher la somme brute du journal comme une réputation.

### Agrégation pondérée

Chaque dimension est normalisée séparément sur 0–5, puis combinée :

- Qualité et utilité des contributions : **30 %**
- Reconnaissance reçue de personnes distinctes : **25 %**
- Régularité de participation sur la durée : **20 %**
- Contribution dans les communautés et niches : **15 %**
- Fiabilité comportementale et modération : **10 %**

`score_base = 0.30 × qualité + 0.25 × reconnaissance + 0.20 × régularité + 0.15 × communautés + 0.10 × fiabilité`

Chaque dimension reste entre 0 et 5, donc le résultat aussi. Les événements bruts doivent être normalisés avec une courbe de saturation, par exemple `dimension = 5 × (1 - exp(-evidence / k))`, avec un `k` configurable par dimension. Cela empêche 20 réactions ou 20 commentaires de faire mécaniquement bondir le score et rend chaque action supplémentaire progressivement moins rentable.

### Régularité et décroissance

La régularité doit dépendre des jours actifs distincts et de la continuité sur plusieurs semaines, pas du nombre d'actions dans une seule journée. Les plafonds limitent l'accumulation; la saturation limite la progression à long terme. Une inactivité prolongée applique ensuite une baisse lente et calculée une seule fois par période. La réputation ne peut jamais descendre sous 0 ni dépasser 5.

Un nouveau compte ne reçoit pas artificiellement une note élevée avec quelques actions. La confiance dans le score augmente avec des preuves réparties dans le temps et venant de personnes distinctes. Une note élevée doit demander une participation durable et reconnue, sans devenir impossible à atteindre.

## Principles

- Reputation reflects sustained, constructive participation and community recognition, not raw volume or paid status.
- Keep a global score and a separate score for each community. Niche participation can be highly respected locally without requiring a massive global audience.
- Treat reputation as a useful signal, never proof that a person's claim is true.
- Every award/reversal is auditable and idempotent; clients cannot directly award points.
- Reward distinct, meaningful interactions; penalize spam/manipulation; apply diminishing returns and daily caps.
- Inactivity decay is gradual and starts only after a grace period. It must be applied deterministically and idempotently, not by repeatedly subtracting points on every profile view.

## Initial candidate weights (admin configurable)

| Event | Candidate points | Guardrail |
| --- | ---: | --- |
| Meaningful original post | +2 | First 3/day eligible; quality/anti-spam checks |
| Constructive comment | +1 | First 5/day eligible; minimum content quality checks |
| Comment receives positive reaction | +1 | Per distinct reactor; cap per comment and per day |
| Post receives positive reaction | +1 | Distinct non-author reactors; cap per day |
| Helpful reply marked by recipient/community process | +3 | One award per source event |
| Meaningful activity day | +1 | Once/day; streak bonus grows slowly and caps |
| Spam/moderation-confirmed abuse | negative | Reversal references source ledger entry; moderation-only |

These are starting defaults for review, not hard-coded product decisions. They are internal event units only; the public reputation is separately normalized and weighted on a 0–5 scale. Follows, friends, raw membership counts, views, self-reactions, repeated reactions, and paid certification should not directly grant reputation.

## Anti-abuse

- Enforce unique ledger identity for each user, scope, event, and source.
- No self-reactions; only count eligible reactions from distinct accounts.
- Apply daily caps and diminishing returns by action type.
- Do not reward repeated edits, repost loops, duplicate comments, or repeated toggling of a reaction.
- Detect reciprocal/repeated small-group reaction rings before granting high-value awards; do not punish legitimate niche communities solely for being small.
- Reverse points when the source action is deleted or invalidated, with a compensating ledger entry instead of deleting history.

## Decay

- Start after 30 days without meaningful activity (configurable).
- Reduce only a small fraction of the inactive score per week (candidate 1%, capped per week), with a configurable floor and no negative total.
- Apply decay as a dated ledger event with a unique period key so retries cannot double-charge.
- Community reputation decays independently from global reputation based on meaningful activity in that community.
- Preserve earned history; do not decay solely because a user is on vacation or cannot access the service.

## Levels

Levels should use a slowly increasing threshold curve rather than one point per action. Level is derived from current score and configurable thresholds; it is not an independent award source. Avoid resetting existing user levels until historical scores have been reconciled.

## Community reputation

Community-scoped ledger entries require a verified community context (post/comment/reaction belongs to that community). Show the community score in that community's member/profile surfaces; show global score elsewhere. Avoid adding scores from arbitrary communities together in a way that allows joining many inactive communities to inflate the global score.

## Admin controls and security

- Manage rule weights, daily caps, grace period, decay rate, and level thresholds through a platform-admin-only interface backed by a server-verified admin check.
- Client roles get read-only access to enabled rules and their own score/ledger. No client insert/update/delete policies for ledger or scoring rules.
- Use trusted SQL functions/triggers or server-side code for awards. Never accept arbitrary point deltas from the mobile client.
- Log rule version and decision metadata for auditability.

## Rollout checklist

1. Inventory all routines/triggers and Flutter/admin code that writes or reads points and levels.
2. Establish a baseline and simulate V2 scores on production-shaped data without mutating live scores.
3. Add ledger and community-score storage (migration provided separately).
4. Add server-side idempotent award/reversal functions and tests.
5. Add admin-configurable rules with strict admin authorization.
6. Backfill/simulate, compare results, and review with product owner.
7. Enable V2 behind a feature flag; migrate profile/comment/community UI to the correct scope.
8. Only after validation, decide how legacy points and levels are mapped.

## Current migration safety

`20261022090000_reputation_v2_foundation.sql` creates only new tables/indexes/policies and does not change `user_statistics`, award points, or alter existing data. Review it before applying to any environment.


## V2 implementation files

- `supabase/migrations/20261022090000_reputation_v2_foundation.sql`: ledger, rule storage, community score storage, RLS.
- `supabase/migrations/20261022100000_reputation_v2_engine.sql`: weighted score RPC, idempotent award/reversal ledger, post/comment/reaction triggers, community batch score RPC, admin rule RPCs, and moderation penalty RPC.
- Flutter profile and external-profile controllers call `get_user_reputation` and render the public value as `x.xx/5`; community member lists batch-load local community scores.
- Scroll Admin has a reputation settings page for rule weights, saturation, daily caps, inactivity grace/rate, and audited moderation penalties.

## Implemented award sources

- Original non-shared community posts with at least 20 characters.
- Constructive comments with at least 20 characters.
- Positive reactions from distinct non-authors on posts and comments.
- One meaningful activity-day award per UTC day, separately for global and community scope.
- Reverse the source contribution when an eligible post becomes inactive/deleted or a comment is deleted; reaction removal/reversal is idempotent.
- Confirmed moderation penalties through the admin-only RPC.

The helpful-reply rule is intentionally seeded disabled until Scrole defines a trustworthy "marked helpful" workflow. This avoids awarding points for an event the product does not yet record.

## Deployment and validation status

The migration files are committed to the feature branch but have **not** been applied to Supabase. The app/admin code has not been compiled in this environment. Before enabling this feature, apply both migrations in order after review, run Flutter analysis and the admin TypeScript/Vite build, and test: daily caps, repeated reaction toggles, deleted content, private profiles, community membership visibility, and moderator authorization.
