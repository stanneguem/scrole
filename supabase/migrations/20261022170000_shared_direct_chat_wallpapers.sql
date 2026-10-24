-- Shared direct-chat wallpaper preferences. Review before applying to Supabase.

create table if not exists public.direct_conversation_wallpapers (
  conversation_id uuid primary key references public.direct_conversations(id) on delete cascade,
  wallpaper_key text not null,
  updated_by uuid not null references auth.users(id) on delete cascade,
  updated_at timestamptz not null default now(),
  constraint direct_conversation_wallpapers_key_check
    check (wallpaper_key in ('none', 'fond1', 'fond2', 'fond3'))
);

alter table public.direct_conversation_wallpapers enable row level security;
revoke all on public.direct_conversation_wallpapers from anon, authenticated;

create or replace function public.get_direct_conversation_wallpaper(p_conversation_id uuid)
returns jsonb language plpgsql stable security definer set search_path = ''
as $function$
declare v_wallpaper text;
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if not exists (
    select 1 from public.direct_conversation_members m
    where m.conversation_id = p_conversation_id and m.user_id = auth.uid()
      and not coalesce(m.is_deleted, false)
  ) and not exists (
    select 1 from public.direct_conversations c
    where c.id = p_conversation_id and auth.uid() in (c.user_one_id, c.user_two_id)
  ) then raise exception 'conversation_access_denied' using errcode = '42501'; end if;
  select w.wallpaper_key into v_wallpaper from public.direct_conversation_wallpapers w
  where w.conversation_id = p_conversation_id;
  return jsonb_build_object('wallpaper_key', v_wallpaper);
end;
$function$;

create or replace function public.set_direct_conversation_wallpaper(
  p_conversation_id uuid, p_wallpaper_key text
) returns jsonb language plpgsql security definer set search_path = ''
as $function$
declare v_level text;
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if p_wallpaper_key not in ('none', 'fond1', 'fond2', 'fond3') then
    raise exception 'invalid_wallpaper_key' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.direct_conversation_members m
    where m.conversation_id = p_conversation_id and m.user_id = auth.uid()
      and not coalesce(m.is_deleted, false)
  ) and not exists (
    select 1 from public.direct_conversations c
    where c.id = p_conversation_id and auth.uid() in (c.user_one_id, c.user_two_id)
  ) then raise exception 'conversation_access_denied' using errcode = '42501'; end if;
  v_level := public.get_public_profile_certification_level(auth.uid());
  if coalesce(v_level, 'none') not in ('basique', 'pro', 'premium') then
    raise exception 'certification_required' using errcode = '42501';
  end if;
  insert into public.direct_conversation_wallpapers(conversation_id, wallpaper_key, updated_by, updated_at)
  values (p_conversation_id, p_wallpaper_key, auth.uid(), now())
  on conflict (conversation_id) do update
    set wallpaper_key = excluded.wallpaper_key, updated_by = excluded.updated_by, updated_at = excluded.updated_at;
  return jsonb_build_object('success', true, 'wallpaper_key', p_wallpaper_key, 'updated_at', now());
end;
$function$;

revoke all on function public.get_direct_conversation_wallpaper(uuid) from public, anon;
revoke all on function public.set_direct_conversation_wallpaper(uuid, text) from public, anon;
grant execute on function public.get_direct_conversation_wallpaper(uuid) to authenticated;
grant execute on function public.set_direct_conversation_wallpaper(uuid, text) to authenticated;
