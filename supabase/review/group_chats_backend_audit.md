# Group chats — backend audit before migration

Branch: `feature/group-chats`
Status: repository inspection only; no remote database changes performed.

## Confirmed from tracked code
- The Flutter service `lib/modules/module_discussion_direct/externe/services/supabase_messaging_service.dart` calls the existing RPCs:
  - `get_or_create_direct_conversation`
  - `get_direct_messages`
  - `get_direct_messages_after`
  - `get_my_direct_conversations`
  - `insert_direct_message`
  - `edit_direct_message`
  - `delete_direct_message`
  - `mark_direct_message_delivered`
  - `mark_direct_conversation_read_cursor`
  - `delete_my_direct_conversation`
- `Conversation` already has an `isGroup` client field, but the inspected service currently constructs direct conversations and calls direct-message RPCs.
- The tracked migration `20261022170000_shared_direct_chat_wallpapers.sql` references `public.direct_conversations` and `public.direct_conversation_members`, and uses `is_deleted` to check active access.
- That wallpaper migration stores one wallpaper per conversation, so it must not be reused for group wallpaper preferences, which are personal.
- The tracked migration list does not expose a complete base schema for the direct messaging tables/RPCs. Their full definitions and all active RLS/storage policies could not be verified from the tracked migration files alone.

## Implementation implications
1. Keep group tables and RPCs isolated from direct-chat RPCs until the full deployed schema has been inspected.
2. Server-side membership must be the source of truth for group message reads, writes, invitations, removals, Realtime and protected media.
3. Use an immutable membership `joined_at` (and role-change timestamp/history if needed) to determine the longest-serving eligible successor.
4. Owner succession on departure must be one transaction: oldest active administrator first; if none, oldest active ordinary member. The group continues while active members remain.
5. Activation is latched when the third member accepts. Thereafter the group remains message-enabled with two or one active members; zero active members closes it.
6. Group wallpaper settings must be keyed by (group, user), not by group alone.
7. Do not apply SQL migrations to the remote Supabase project until reviewed and explicitly approved.

## Verification still needed before finalizing the migration
- Retrieve deployed table definitions for direct conversations, members, messages, receipts and attachment/media metadata.
- Inspect policies on the relevant tables and `storage.objects`, plus publication/Realtime configuration.
- Confirm existing profile/auth foreign-key conventions and how notification rows are inserted.
- Run migration and lifecycle/security tests against a local or disposable Supabase database before any remote application.
