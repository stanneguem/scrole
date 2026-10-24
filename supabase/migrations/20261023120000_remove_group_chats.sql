-- Retire group chats completely. Direct messaging (including chat-media) is untouched.
begin;

-- Remove group-only Storage access rules.
drop policy if exists "group_media_active_members_read" on storage.objects;
drop policy if exists "group_media_members_upload_own_folder" on storage.objects;
drop policy if exists "group_media_uploader_delete_own_files" on storage.objects;

-- Remove table policies first because they depend on group_is_active_member().
drop policy if exists group_conversations_member_read on public.group_conversations;
drop policy if exists group_members_member_read on public.group_conversation_members;
drop policy if exists group_invitations_recipient_or_admin_read on public.group_conversation_invitations;
drop policy if exists group_messages_active_member_read on public.group_messages;
drop policy if exists group_receipts_active_member_read on public.group_message_receipts;
drop policy if exists group_wallpaper_owner_read on public.group_member_wallpapers;

-- Remove group invitation trigger and all dedicated RPCs.
drop trigger if exists group_invitation_notification_trigger on public.group_conversation_invitations;
drop function if exists public.notify_group_invitation_created();
drop function if exists public.get_group_message_receipts(uuid);
drop function if exists public.search_users_for_group_invite(uuid, text);
drop function if exists public.get_group_messages(uuid, integer, timestamptz);
drop function if exists public.insert_group_message(uuid, text, text, text[], uuid);
drop function if exists public.mark_group_conversation_read(uuid, uuid, timestamptz);
drop function if exists public.set_group_personal_wallpaper(uuid, text);
drop function if exists public.get_group_personal_wallpaper(uuid);
drop function if exists public.get_group_members(uuid);
drop function if exists public.get_my_pending_group_invitations();
drop function if exists public.get_my_group_conversations();
drop function if exists public.invite_group_members(uuid, uuid[]);
drop function if exists public.respond_to_group_invitation(uuid, boolean);
drop function if exists public.create_group_conversation(text, text, uuid[]);
drop function if exists public.change_group_member_role(uuid, uuid, text);
drop function if exists public.remove_group_member(uuid, uuid);
drop function if exists public.leave_group_conversation(uuid);
drop function if exists public.group_next_owner(uuid, uuid);
drop function if exists public.group_is_active_member(uuid, uuid);

-- Remove group-only Realtime publication entries before dropping tables.
do $$
declare v_table text;
begin
  foreach v_table in array array[
    'group_conversations','group_conversation_members','group_messages','group_message_receipts'
  ] loop
    if exists (
      select 1 from pg_publication_tables
      where pubname='supabase_realtime' and schemaname='public' and tablename=v_table
    ) then
      execute format('alter publication supabase_realtime drop table public.%I', v_table);
    end if;
  end loop;
end $$;

drop table if exists public.group_message_receipts;
drop table if exists public.group_messages;
drop table if exists public.group_member_wallpapers;
drop table if exists public.group_conversation_invitations;
drop table if exists public.group_conversation_members;
drop table if exists public.group_conversations;

-- Group-only objects/data and quota.
delete from storage.objects where bucket_id = 'group-chat-media';
delete from storage.buckets where id = 'group-chat-media';
delete from public.scrole_quota_settings where quota_key = 'group_chat_min_active_members';
delete from public.notifications where type = 'group_invitation';

commit;
