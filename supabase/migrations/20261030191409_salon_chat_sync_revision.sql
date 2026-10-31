-- Monotonic synchronization revision catches edits/deletions made while a device is offline.
alter table public.community_salon_messages
  add column if not exists sync_updated_at timestamptz not null default now();

update public.community_salon_messages
set sync_updated_at = coalesce(edited_at, sent_at, created_at, now())
where sync_updated_at is null;

create or replace function public.touch_salon_message_sync_revision()
returns trigger
language plpgsql
set search_path = public
as $function$
begin
  new.sync_updated_at := greatest(clock_timestamp(), old.sync_updated_at + interval '1 microsecond');
  return new;
end;
$function$;

drop trigger if exists trg_touch_salon_message_sync_revision on public.community_salon_messages;
create trigger trg_touch_salon_message_sync_revision
before update on public.community_salon_messages
for each row execute function public.touch_salon_message_sync_revision();

create index if not exists idx_salon_messages_sync_revision
on public.community_salon_messages(salon_id, sync_updated_at, id);

create or replace function public.get_salon_messages_since(
  p_salon_id uuid,
  p_after_sent_at timestamptz default null,
  p_after_id uuid default '00000000-0000-0000-0000-000000000000'::uuid,
  p_limit integer default 200
)
returns setof public.community_salon_messages
language plpgsql
stable
security definer
set search_path = public
as $function$
declare v_joined_at timestamptz;
begin
  if auth.uid() is null or not public.can_access_salon(p_salon_id) then
    raise exception 'Accès non autorisé à ce salon';
  end if;
  select joined_at into v_joined_at from public.community_salon_members
  where salon_id=p_salon_id and user_id=auth.uid();
  if v_joined_at is null then
    select created_at into v_joined_at from public.community_salons
    where id=p_salon_id and created_by=auth.uid();
  end if;
  if v_joined_at is null then raise exception 'Date d’adhésion introuvable'; end if;
  return query
  select m.* from public.community_salon_messages m
  where m.salon_id=p_salon_id and m.sent_at>=v_joined_at
    and (p_after_sent_at is null or (m.sync_updated_at,m.id) >
      (p_after_sent_at,coalesce(p_after_id,'00000000-0000-0000-0000-000000000000'::uuid)))
    and not exists(select 1 from public.community_salon_message_hidden_for h
      where h.message_id=m.id and h.user_id=auth.uid())
  order by m.sync_updated_at asc,m.id asc
  limit greatest(1,least(coalesce(p_limit,200),500));
end;
$function$;

create or replace function public.get_salon_message_delta(p_message_id uuid)
returns setof public.community_salon_messages
language plpgsql stable security definer set search_path=public
as $function$
declare v_salon_id uuid; v_joined_at timestamptz;
begin
  if auth.uid() is null then raise exception 'Authentification requise'; end if;
  select salon_id into v_salon_id from public.community_salon_messages where id=p_message_id;
  if v_salon_id is null or not public.can_access_salon(v_salon_id) then return; end if;
  select joined_at into v_joined_at from public.community_salon_members
  where salon_id=v_salon_id and user_id=auth.uid();
  if v_joined_at is null then
    select created_at into v_joined_at from public.community_salons
    where id=v_salon_id and created_by=auth.uid();
  end if;
  if v_joined_at is null then return; end if;
  return query select m.* from public.community_salon_messages m
  where m.id=p_message_id and m.salon_id=v_salon_id and m.sent_at>=v_joined_at
    and not exists(select 1 from public.community_salon_message_hidden_for h
      where h.message_id=m.id and h.user_id=auth.uid());
end;
$function$;

revoke all on function public.get_salon_messages_since(uuid,timestamptz,uuid,integer) from public,anon;
revoke all on function public.get_salon_message_delta(uuid) from public,anon;
grant execute on function public.get_salon_messages_since(uuid,timestamptz,uuid,integer) to authenticated;
grant execute on function public.get_salon_message_delta(uuid) to authenticated;
