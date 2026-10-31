-- Allow each salon member to hide a message only for themselves.
-- Global deletion remains handled by delete_salon_message.

create table if not exists public.community_salon_message_hidden_for (
  message_id uuid not null references public.community_salon_messages(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  hidden_at timestamptz not null default now(),
  primary key (message_id, user_id)
);

alter table public.community_salon_message_hidden_for enable row level security;

drop policy if exists "Users can read own hidden salon messages"
  on public.community_salon_message_hidden_for;
create policy "Users can read own hidden salon messages"
  on public.community_salon_message_hidden_for
  for select to authenticated
  using (user_id = auth.uid());

drop policy if exists "Users can hide own salon messages"
  on public.community_salon_message_hidden_for;
create policy "Users can hide own salon messages"
  on public.community_salon_message_hidden_for
  for insert to authenticated
  with check (user_id = auth.uid());

create or replace function public.hide_salon_message_for_me(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_salon_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentification requise';
  end if;

  select salon_id into v_salon_id
  from public.community_salon_messages
  where id = p_id;

  if v_salon_id is null then
    raise exception 'Message introuvable';
  end if;

  if not public.can_access_salon(v_salon_id) then
    raise exception 'Accès non autorisé';
  end if;

  insert into public.community_salon_message_hidden_for(message_id, user_id)
  values (p_id, auth.uid())
  on conflict do nothing;
end;
$$;

revoke all on function public.hide_salon_message_for_me(uuid) from public, anon;
grant execute on function public.hide_salon_message_for_me(uuid) to authenticated;

create or replace function public.get_salon_messages(
  p_salon_id uuid,
  p_limit integer default 50,
  p_before timestamptz default null
)
returns setof public.community_salon_messages
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.can_access_salon(p_salon_id) then
    raise exception 'Accès non autorisé à ce salon';
  end if;

  return query
  select m.*
  from public.community_salon_messages m
  where m.salon_id = p_salon_id
    and m.is_deleted = false
    and (p_before is null or m.sent_at < p_before)
    and not exists (
      select 1
      from public.community_salon_message_hidden_for h
      where h.message_id = m.id
        and h.user_id = auth.uid()
    )
  order by m.sent_at desc
  limit p_limit;
end;
$$;

revoke all on function public.get_salon_messages(uuid, integer, timestamptz) from public, anon;
grant execute on function public.get_salon_messages(uuid, integer, timestamptz) to authenticated;
