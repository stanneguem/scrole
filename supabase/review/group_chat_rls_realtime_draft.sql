-- REVIEW ONLY: RLS and Realtime policies for group tables.
-- These policies require the foundation draft's group_is_active_member helper.
-- Keep write privileges revoked; mutations must go through SECURITY DEFINER RPCs.
-- Do not apply before testing on a disposable Supabase instance.

grant select on public.group_conversations,
  public.group_conversation_members,
  public.group_conversation_invitations,
  public.group_messages,
  public.group_message_receipts,
  public.group_member_wallpapers to authenticated;

drop policy if exists group_conversations_member_read on public.group_conversations;
create policy group_conversations_member_read on public.group_conversations
for select to authenticated
using (public.group_is_active_member(id, auth.uid()));

drop policy if exists group_members_member_read on public.group_conversation_members;
create policy group_members_member_read on public.group_conversation_members
for select to authenticated
using (public.group_is_active_member(group_id, auth.uid()));

drop policy if exists group_invitations_recipient_or_admin_read on public.group_conversation_invitations;
create policy group_invitations_recipient_or_admin_read on public.group_conversation_invitations
for select to authenticated
using (
  invited_user_id = auth.uid()
  or exists (
    select 1 from public.group_conversation_members m
    where m.group_id = group_conversation_invitations.group_id
      and m.user_id = auth.uid()
      and m.status = 'active'
      and m.role in ('owner','administrator')
  )
);

drop policy if exists group_messages_active_member_read on public.group_messages;
create policy group_messages_active_member_read on public.group_messages
for select to authenticated
using (public.group_is_active_member(group_id, auth.uid()));

drop policy if exists group_receipts_active_member_read on public.group_message_receipts;
create policy group_receipts_active_member_read on public.group_message_receipts
for select to authenticated
using (
  user_id = auth.uid()
  or exists (
    select 1 from public.group_messages msg
    where msg.id = group_message_receipts.message_id
      and public.group_is_active_member(msg.group_id, auth.uid())
  )
);

drop policy if exists group_wallpaper_owner_read on public.group_member_wallpapers;
create policy group_wallpaper_owner_read on public.group_member_wallpapers
for select to authenticated
using (user_id = auth.uid() and public.group_is_active_member(group_id, auth.uid()));

-- Realtime must only publish data for which the subscriber has SELECT privilege and
-- passes the corresponding RLS policy. Add these tables to supabase_realtime only
-- after confirming they are not already members; the DO block is idempotent.
do $$
declare v_table text;
begin
  foreach v_table in array array[
    'group_conversations','group_conversation_members','group_messages','group_message_receipts'
  ] loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname='supabase_realtime' and schemaname='public' and tablename=v_table
    ) then
      execute format('alter publication supabase_realtime add table public.%I', v_table);
    end if;
  end loop;
end $$;

-- Realtime authorization still needs integration tests with two active members and a removed
-- member. This policy draft does not itself create client subscriptions.
