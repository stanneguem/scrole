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

  v_version := coalesce(nullif(trim(new.current_version), ''), '1.0.0');
  v_message := nullif(trim(coalesce(new.update_message, '')), '');

  insert into public.notifications (user_id, type, title, body, actor_id, data)
  select
    up.user_id,
    'app_version_published',
    case lower(coalesce(pref.language, 'fr'))
      when 'en' then 'New Scrole version'
      when 'es' then 'Nueva versión de Scrole'
      when 'de' then 'Neue Scrole-Version'
      when 'it' then 'Nuova versione di Scrole'
      when 'pt' then 'Nova versão do Scrole'
      when 'zh' then 'Scrole 新版本'
      when 'ja' then 'Scrole の新バージョン'
      when 'ru' then 'Новая версия Scrole'
      else 'Nouvelle version de Scrole'
    end,
    concat(
      case lower(coalesce(pref.language, 'fr'))
        when 'en' then 'Version ' || v_version || ' is now available.'
        when 'es' then 'La versión ' || v_version || ' ya está disponible.'
        when 'de' then 'Version ' || v_version || ' ist jetzt verfügbar.'
        when 'it' then 'La versione ' || v_version || ' è disponibile.'
        when 'pt' then 'A versão ' || v_version || ' já está disponível.'
        when 'zh' then '新版本 ' || v_version || ' 已发布。'
        when 'ja' then 'バージョン ' || v_version || ' が公開されました。'
        when 'ru' then 'Версия ' || v_version || ' уже доступна.'
        else 'La version ' || v_version || ' est disponible.'
      end,
      case when v_message is not null then E'\n' || v_message else '' end
    ),
    null,
    jsonb_build_object(
      'version', v_version,
      'message', coalesce(v_message, ''),
      'android_store_url', coalesce(new.android_store_url, ''),
      'ios_store_url', coalesce(new.ios_store_url, ''),
      'source_type', 'app_version'
    )
  from public.user_profiles up
  left join public.user_preferences pref on pref.user_id = up.user_id
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
