-- REVIEW ONLY: group chat schema foundation.
-- Do not apply until the full migration and tests are reviewed.
-- Private group media must NOT use the current public chat-media bucket.

create table if not exists public.group_conversations (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(btrim(name)) between 1 and 80),
  avatar_url text,
  creator_id uuid not null references auth.users(id),
  status text not null default 'pending_members'
    check (status in ('pending_members','active','closed')),
  ever_activated boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  closed_at timestamptz
);

create table if not exists public.group_conversation_members (
  group_id uuid not null references public.group_conversations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'member'
    check (role in ('owner','administrator','member')),
  status text not null default 'active'
    check (status in ('active','left','removed')),
  joined_at timestamptz not null default now(),
  role_assigned_at timestamptz not null default now(),
  left_at timestamptz,
  last_read_at timestamptz,
  last_read_message_id uuid,
  primary key (group_id, user_id)
);
create index if not exists group_members_user_active_idx
  on public.group_conversation_members(user_id, joined_at)
  where status = 'active';
create index if not exists group_members_successor_idx
  on public.group_conversation_members(group_id, role, joined_at, user_id)
  where status = 'active';

create table if not exists public.group_conversation_invitations (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.group_conversations(id) on delete cascade,
  invited_user_id uuid not null references auth.users(id) on delete cascade,
  invited_by uuid not null references auth.users(id),
  status text not null default 'pending'
    check (status in ('pending','accepted','refused','revoked','expired')),
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  expires_at timestamptz,
  constraint group_invitation_not_self check (invited_user_id <> invited_by)
);
create unique index if not exists group_one_pending_invitation_idx
  on public.group_conversation_invitations(group_id, invited_user_id)
  where status = 'pending';

create table if not exists public.group_messages (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.group_conversations(id) on delete cascade,
  sender_id uuid not null references auth.users(id),
  text text,
  message_type text not null default 'text'
    check (message_type in ('text','image','video','audio','file','system')),
  media_paths text[] not null default '{}',
  replied_to_id uuid references public.group_messages(id) on delete set null,
  created_at timestamptz not null default now(),
  edited_at timestamptz,
  deleted_at timestamptz,
  constraint group_message_has_content check (
    message_type = 'system' or nullif(btrim(coalesce(text,'')), '') is not null
    or cardinality(media_paths) > 0
  )
);
create index if not exists group_messages_page_idx
  on public.group_messages(group_id, created_at desc, id desc);

create table if not exists public.group_message_receipts (
  message_id uuid not null references public.group_messages(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  delivered_at timestamptz,
  read_at timestamptz,
  created_at timestamptz not null default now(),
  primary key (message_id, user_id)
);

-- Personal wallpaper: each member's choice is independent.
create table if not exists public.group_member_wallpapers (
  group_id uuid not null references public.group_conversations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  wallpaper_key text not null default 'none'
    check (wallpaper_key in ('none','fond1','fond2','fond3')),
  updated_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

-- Never expose these tables directly to clients. Use vetted RPCs for mutations.
alter table public.group_conversations enable row level security;
alter table public.group_conversation_members enable row level security;
alter table public.group_conversation_invitations enable row level security;
alter table public.group_messages enable row level security;
alter table public.group_message_receipts enable row level security;
alter table public.group_member_wallpapers enable row level security;

revoke all on public.group_conversations, public.group_conversation_members,
  public.group_conversation_invitations, public.group_messages,
  public.group_message_receipts, public.group_member_wallpapers
  from anon, authenticated;

-- Helper is deliberately placed in public only for this review draft.
-- Before finalizing, evaluate moving authorization helpers to a non-exposed schema.
create or replace function public.group_is_active_member(p_group_id uuid, p_user_id uuid default auth.uid())
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.group_conversation_members m
    where m.group_id = p_group_id and m.user_id = auth.uid() and p_user_id = auth.uid() and m.status = 'active'
  );
$$;
revoke all on function public.group_is_active_member(uuid, uuid) from public, anon;
grant execute on function public.group_is_active_member(uuid, uuid) to authenticated;

-- Atomic owner succession. Called from the eventual leave/remove RPC in the same transaction.
create or replace function public.group_next_owner(p_group_id uuid, p_departing_user uuid)
returns uuid
language sql stable security definer set search_path = ''
as $$
  select m.user_id
  from public.group_conversation_members m
  where m.group_id = p_group_id
    and m.user_id <> p_departing_user
    and m.status = 'active'
    and m.role in ('administrator','member')
  order by case when m.role = 'administrator' then 0 else 1 end,
           m.joined_at asc, m.user_id asc
  limit 1;
$$;
revoke all on function public.group_next_owner(uuid, uuid) from public, anon, authenticated;

-- IMPORTANT: this is a schema foundation only. RPCs for create/invite/respond/send/read/leave,
-- RLS authorization wrappers, storage policies, notifications and Realtime publication changes
-- must be completed and tested before this draft can become an executable migration.
