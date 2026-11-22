# Nettoyage des médias de stories (Cloudflare R2)

## Fonctionnement
- Toute suppression d'une story image/vidéo met en file sa clé R2 canonique.
- Une story de repartage (`kind = 'post'`) ne déclenche jamais la suppression du média du post original.
- La fonction Edge `story-media-cleanup` supprime les lignes de stories expirées et vide la file R2.
- Les échecs restent dans `public.story_media_cleanup_queue` avec le nombre de tentatives et la dernière erreur; le prochain passage réessaie.
- La tâche `story-media-cleanup-every-10-minutes` est planifiée toutes les 10 minutes dans `pg_cron`.

## Secrets requis côté Edge Function
Les secrets suivants doivent exister dans l'environnement Supabase Edge Functions:
- `R2_ACCOUNT_ID`
- `R2_PRIVATE_ACCESS_KEY_ID`
- `R2_PRIVATE_SECRET_ACCESS_KEY`
- `R2_PRIVATE_BUCKET_NAME`
- `R2_PRIVATE_ENDPOINT` (facultatif; sinon l'endpoint est dérivé du compte)

Ils sont privés et ne doivent jamais être ajoutés au dépôt ou à l'application Flutter.

## Authentification de la tâche planifiée
Le cron appelle la fonction avec le JWT de passerelle stocké dans Vault sous `fcm_webhook_anon_key`, plus le secret de worker stocké sous `media_gc_worker_secret`. La fonction conserve `verify_jwt = true` et vérifie le secret via `verify_worker_secret`. La clé `service_role` n'est pas copiée dans la commande cron.

## Vérification
- Vérifier la fonction dans Supabase Edge Functions et ses logs.
- Vérifier le job avec `select jobname, schedule, active from cron.job where jobname = 'story-media-cleanup-every-10-minutes';`
- Vérifier la file avec `select count(*) from public.story_media_cleanup_queue;`
- Consulter `last_error`, `attempts` et `last_attempt_at` pour les échecs.

La migration de file et la planification sont additives. Le job est activé côté projet Supabase; aucune clé secrète n'est stockée dans Git.
