# Group chats — live Supabase schema findings

Project inspected read-only: `scrole` (Postgres 17). No DDL or data mutations were performed.

## Existing messaging structures
- `public.direct_conversations`: `id`, `user_one_id`, `user_two_id`, timestamps. It is structurally a one-to-one conversation table.
- `public.direct_conversation_members`: conversation/user pair, `joined_at`, read cursor fields, `is_deleted`, `deleted_at`.
- `public.direct_messages`: message id, conversation id, sender, text/type/audio/media URLs, reply id, timestamps and soft-delete/edit flags.
- `public.direct_message_receipts`: message/user pair and delivered/read timestamps.
- The core tables have RLS enabled. Existing direct-message RPCs are SECURITY DEFINER; their authorization logic must not be reused blindly for groups.
- Existing direct-message Realtime publication includes members, messages and receipts.

## Security concern: current media bucket
- The existing `chat-media` bucket is configured as public.
- A policy named `chat_media_public_read` permits SELECT for the bucket.
- This means URL secrecy alone cannot enforce the user's requirement that departed/removed group members lose access to protected group media.
- Group attachments should use a dedicated private bucket and authorization-aware delivery (private signed URLs or an authenticated proxy), with Storage policies tied to active group membership. Do not put group files in `chat-media` unless its public-read posture is intentionally changed after impact review.

## Proposed isolated group data model
A draft has been committed at `supabase/review/group_chats_foundation_draft.sql` (review-only, not a migration). It introduces separate group conversations, members, invitations, messages, receipts and per-user wallpaper preferences. It is intentionally marked incomplete and must not be applied yet.

## Before turning the draft into a migration
1. Complete RPCs for group create, invite, respond, send, read/deliver, leave, remove and role management.
2. Enforce owner succession transactionally: oldest active administrator, otherwise oldest active ordinary member; group remains active if members remain.
3. Add precise table RLS and a private group-media bucket/policies. Ensure removed members cannot read new messages or fetch media.
4. Add notification insertion consistent with existing notification conventions, without exposing private group content.
5. Validate Realtime publication and filters for the new group tables.
6. Test against local/disposable Supabase and run security advisors.
7. Review the complete SQL and obtain explicit approval before any production migration.
