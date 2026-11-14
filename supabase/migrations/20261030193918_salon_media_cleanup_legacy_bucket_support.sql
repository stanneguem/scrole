create or replace function private.enqueue_salon_message_media_for_cleanup()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_key text;
  v_keys jsonb;
  v_pattern text;
begin
  v_pattern := '^salon-messages/' || old.salon_id::text || '/' || old.sender_id::text || '/[A-Za-z0-9_-]+\.(jpg|jpeg|png|webp|avif|gif|mp4|mov|m4a|aac|mp3|ogg|wav|webm)$|^' || old.salon_id::text || '/' || old.sender_id::text || '/[A-Za-z0-9_-]+\.(jpg|jpeg|png|webp|avif|gif|mp4|mov|m4a|aac|mp3|ogg|wav|webm)$';
  if tg_op = 'UPDATE' then
    if old.is_deleted or not new.is_deleted then return new; end if;
    v_keys := coalesce(old.media_object_keys, '[]'::jsonb);
    if jsonb_typeof(v_keys) = 'array' then
      for v_key in select jsonb_array_elements_text(v_keys) loop
        if v_key ~ v_pattern then
          insert into public.salon_message_media_cleanup_queue(object_key) values (v_key) on conflict (object_key) do nothing;
        end if;
      end loop;
    end if;
    foreach v_key in array array[old.media_object_key, old.audio_url] loop
      if v_key is not null and v_key ~ v_pattern then
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
        if v_key ~ v_pattern then
          insert into public.salon_message_media_cleanup_queue(object_key) values (v_key) on conflict (object_key) do nothing;
        end if;
      end loop;
    end if;
    foreach v_key in array array[old.media_object_key, old.audio_url] loop
      if v_key is not null and v_key ~ v_pattern then
        insert into public.salon_message_media_cleanup_queue(object_key) values (v_key) on conflict (object_key) do nothing;
      end if;
    end loop;
    return old;
  end if;
  return null;
end;
$function$;
