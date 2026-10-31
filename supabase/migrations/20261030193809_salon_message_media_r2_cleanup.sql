create or replace function private.enqueue_salon_message_media_for_cleanup()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_key text;
  v_keys jsonb;
begin
  if tg_op = 'UPDATE' then
    if old.is_deleted or not new.is_deleted then return new; end if;
    v_keys := coalesce(old.media_object_keys, '[]'::jsonb);
    if jsonb_typeof(v_keys) = 'array' then
      for v_key in select jsonb_array_elements_text(v_keys) loop
        if v_key ~ ('^salon-messages/' || old.salon_id::text || '/' || old.sender_id::text || '/[A-Za-z0-9_-]+\.(jpg|jpeg|png|webp|avif|gif|mp4|mov|m4a|aac|mp3|ogg|wav|webm)$') then
          insert into public.salon_message_media_cleanup_queue(object_key) values (v_key) on conflict (object_key) do nothing;
        end if;
      end loop;
    end if;
    foreach v_key in array array[old.media_object_key, old.audio_url] loop
      if v_key is not null and v_key ~ ('^salon-messages/' || old.salon_id::text || '/' || old.sender_id::text || '/[A-Za-z0-9_-]+\.(jpg|jpeg|png|webp|avif|gif|mp4|mov|m4a|aac|mp3|ogg|wav|webm)$') then
        insert into public.salon_message_media_cleanup_queue(object_key) values (v_key) on conflict (object_key) do nothing;
      end if;
    end loop;
    new.media_object_key := null;
    new.media_object_keys := '[]'::jsonb;
    new.audio_url := null;
    new.media_duration_seconds := null;
    if new.type in ('image','video','audio') then new.content := null; end if;
    return new;
  elsif tg_op = 'DELETE' then
    v_keys := coalesce(old.media_object_keys, '[]'::jsonb);
    if jsonb_typeof(v_keys) = 'array' then
      for v_key in select jsonb_array_elements_text(v_keys) loop
        if v_key ~ ('^salon-messages/' || old.salon_id::text || '/' || old.sender_id::text || '/[A-Za-z0-9_-]+\.(jpg|jpeg|png|webp|avif|gif|mp4|mov|m4a|aac|mp3|ogg|wav|webm)$') then
          insert into public.salon_message_media_cleanup_queue(object_key) values (v_key) on conflict (object_key) do nothing;
        end if;
      end loop;
    end if;
    foreach v_key in array array[old.media_object_key, old.audio_url] loop
      if v_key is not null and v_key ~ ('^salon-messages/' || old.salon_id::text || '/' || old.sender_id::text || '/[A-Za-z0-9_-]+\.(jpg|jpeg|png|webp|avif|gif|mp4|mov|m4a|aac|mp3|ogg|wav|webm)$') then
        insert into public.salon_message_media_cleanup_queue(object_key) values (v_key) on conflict (object_key) do nothing;
      end if;
    end loop;
    return old;
  end if;
  return null;
end;
$function$;

drop trigger if exists trg_enqueue_salon_message_media_cleanup_on_delete on public.community_salon_messages;
create trigger trg_enqueue_salon_message_media_cleanup_on_delete
before delete on public.community_salon_messages
for each row execute function private.enqueue_salon_message_media_for_cleanup();

drop trigger if exists trg_enqueue_salon_message_media_cleanup_on_global_delete on public.community_salon_messages;
create trigger trg_enqueue_salon_message_media_cleanup_on_global_delete
before update of is_deleted on public.community_salon_messages
for each row execute function private.enqueue_salon_message_media_for_cleanup();

create index if not exists salon_message_media_cleanup_queue_created_idx
on public.salon_message_media_cleanup_queue(created_at, id);

select cron.schedule(
  'salon-message-media-cleanup',
  '*/10 * * * *',
  $job$
    select net.http_post(
      url := 'https://djvmxrwfchnqdtzayhwf.supabase.co/functions/v1/salon-media-cleanup',
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
