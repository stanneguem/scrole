# Story media cleanup (Cloudflare R2)

This cleanup is intentionally additive. Applying the migration does not delete existing stories or R2 objects.

## What it does
- Any existing story deletion RPC that deletes from `public.stories` triggers a queue entry for that story's own canonical `stories/{author_id}/{uploadId}.{extension}` key.
- Repost stories (`kind = 'post'`) have no owned media key and are never used to delete the original post's media.
- The `story-media-cleanup` Edge Function removes expired story rows, drains queued R2 deletes, and keeps failures in the queue for retry.
- R2 delete is idempotent; repeat runs are safe.

## Deploy and schedule
1. Deploy `supabase/functions/story-media-cleanup/index.ts` as Edge Function `story-media-cleanup`.
2. Ensure its runtime has the existing Supabase service-role secret and these R2 secrets: `R2_ACCOUNT_ID`, `R2_PRIVATE_ACCESS_KEY_ID`, `R2_PRIVATE_SECRET_ACCESS_KEY`, `R2_PRIVATE_BUCKET_NAME`; optionally `R2_PRIVATE_ENDPOINT`.
3. Schedule a POST every 10–15 minutes to `/functions/v1/story-media-cleanup`, with header `Authorization: Bearer <SUPABASE_SERVICE_ROLE_KEY>` and `Content-Type: application/json`. Store the service-role key in Supabase Vault / scheduler secrets; do not commit it or put it in the Flutter app.
4. Monitor function logs and the `public.story_media_cleanup_queue` table. Failed deletions remain queued in `public.story_media_cleanup_queue` with attempt count and last error, then are retried on the next run.

The migration and function must be reviewed and deployed by the project owner; this change does not apply any remote migration or deploy the function automatically.
