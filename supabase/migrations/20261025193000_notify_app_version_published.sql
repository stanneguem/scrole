begin;

create or replace function public.notify_app_version_published()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_version text;
  v_message text;
begin
  if tg_op <> 'UPDATE' or new.current_version is not distinct from old.current_version then
    return new;
  end if;

  v_version := coalesce(nullif(trim(new.current_version), ''), 'nouvelle version');
  v_message := nullif(trim(coalesce(new.update_message, '')), '');

  insert into public.notifications (user_id, type, title, body, actor_id, data)
  select
    up.user_id,
    'app_version_published',
    'Nouvelle version de Scrole',
    concat('La version ', v_version, ' est disponible.', case when v_message is not null then E'\n' || v_message else '' end),
    null,
    jsonb_build_object(
      'version', v_version,
      'message', coalesce(v_message, ''),
      'android_store_url', coalesce(new.android_store_url, ''),
      'ios_store_url', coalesce(new.ios_store_url, ''),
      'source_type', 'app_version'
    )
  from public.user_profiles up
  where up.user_id is not null
    and coalesce(up.account_status, 'active') = 'active'
    and up.deleted_at is null;

  return new;
end;
$$;

drop trigger if exists trg_notify_app_version_published on public.app_config;
create trigger trg_notify_app_version_published
after update of current_version on public.app_config
for each row
execute function public.notify_app_version_published();

commit;
