# Group chats — implementation and validation status

Branch: `feature/group-chats`
Pull request: https://github.com/stanneguem/scrole_mobile/pull/3

## Supabase backend
- Applied migration `20261022170631_group_chats`: tables for conversations, members, invitations, messages, receipts and personal wallpaper; group RPCs; RLS; Realtime publication; private media bucket and invitation notifications.
- Applied migration `20261022171500_group_chat_invite_search`: server-authorized user search for group invitations.
- Invitation notifications open the group inbox from both the in-app notification center and the shared push/local-notification deep-link router.
- Both SQL migrations were executed inside a transaction and rolled back first as schema/syntax preflights, then applied through Supabase's migration API.
- Post-apply queries confirmed the six group tables, RLS enabled with scoped policies, and private `group-chat-media` bucket.
- The existing direct-message bucket `chat-media` and its data were not modified.

## Flutter frontend
- Group list and creation; invitation inbox with accept/refuse.
- Group chat with send, private image upload/display via short-lived signed URL, message refresh and activation-state refresh via Realtime.
- Member management, role updates, removal, leave-group flow and oldest-admin/oldest-member ownership succession on the backend.
- Personal wallpaper preference persisted per user and applied as a subtle theme-aware tint.
- Invitation picker now searches by username/name; callers no longer need to know a user UUID.
- Group service registered in MessagingBinding and entry point added to the existing message inbox.
- CI workflow added for formatting, analyzer and lifecycle unit tests.

## Validation status
- SQL syntax/schema preflight: passed for both migrations.
- Supabase deployment: successful.
- Supabase post-deployment schema/policy/storage checks: passed.
- GitHub Actions Flutter validation: pending at last check. Do not claim Flutter compilation/tests passed until the workflow concludes successfully.
- Real-user integration tests for read-receipt presentation, invitation concurrency and post-removal access still require end-to-end testing.
- Signed media URLs are short-lived (5 minutes); already-issued URLs may remain usable until expiry, even after membership is revoked.

## Core contract
- Messages are disabled until the third member accepts.
- After activation, the group remains usable with two or one active members; zero active members closes it.
- Owner departure: oldest active administrator succeeds; if none, oldest active ordinary member.
- Invitation acceptance is required before membership is created.
- Wallpapers are per user.
- Server-side membership checks protect message RPCs, Realtime and private media.

