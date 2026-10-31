-- Schedule the story media cleanup worker every ten minutes.
-- Authentication uses existing Vault secrets, never a committed service-role key.
select cron.schedule(
  'story-media-cleanup-every-10-minutes',
  '*/10 * * * *',
  $job$
    select net.http_post(
      url := 'https://djvmxrwfchnqdtzayhwf.supabase.co/functions/v1/story-media-cleanup',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'fcm_webhook_anon_key'),
        'x-worker-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'media_gc_worker_secret')
      ),
      body := '{}'::jsonb,
      timeout_milliseconds := 20000
    );
  $job$
);
