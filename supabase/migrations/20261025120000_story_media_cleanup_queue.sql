-- Queue story media for R2 cleanup without making story deletion depend on R2 availability.
-- Additive only: existing stories are not deleted by this migration.
create schema if not exists private;

create table if not exists private.story_media_cleanup_queue (
  id bigint generated always as identity primary key,
  object_key text not null unique,
  created_at timestamptz not null default now(),
  attempts integer not null default 0,
  last_error text,
  last_attempt_at timestamptz
);

revoke all on private.story_media_cleanup_queue from public, anon, authenticated;
grant select, insert, update, delete on private.story_media_cleanup_queue to service_role;

create or replace function private.enqueue_story_media_for_cleanup()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_key text;
begin
  -- Repost stories reference a post and have no image_url; never touch original post media.
  if old.kind in ('image', 'video') and old.image_url is not null then
    v_key := btrim(old.image_url);
    -- Only queue canonical private R2 story keys. Ignore legacy Supabase URLs and arbitrary URLs.
    if v_key ~ ('^stories/' || old.author_id::text || '/[A-Za-z0-9_-]+\.(jpg|jpeg|png|webp|avif|gif|mp4|mov)$') then
      insert into private.story_media_cleanup_queue(object_key)
      values (v_key)
      on conflict (object_key) do nothing;
    end if;
  end if;
  return old;
end;
$function$;

drop trigger if exists stories_enqueue_r2_media_cleanup on public.stories;
create trigger stories_enqueue_r2_media_cleanup
after delete on public.stories
for each row execute function private.enqueue_story_media_for_cleanup();

-- No immediate data cleanup is performed here. The Edge Function below handles
-- expired rows and retries queued R2 deletions when scheduled.
