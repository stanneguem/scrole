# Group chats — implementation contract

Branch: `feature/group-chats`

## Confirmed rules
- Group creation adds the creator as an active member, but the group is not yet message-enabled.
- The third active member accepting an invitation activates the group. Before this, groups with one or two members cannot send messages.
- `ever_activated` is a one-way latch. After activation the group remains message-enabled with two or one members; zero active members closes it.
- Invitations are not memberships. Only acceptance of a pending invitation grants membership.
- Only the creator and administrators can invite. Administrators may manage members within server-enforced permissions, but cannot appoint themselves creator.
- If the owner leaves, the group continues running and ownership transfers automatically: first choose the longest-serving active administrator; if there is no active administrator, choose the longest-serving active ordinary member.
- Succession must be performed atomically server-side so the group never has competing owners or a gap in ownership while active members remain. The new owner receives owner permissions; messages and group history remain intact.
- Leaving/removal revokes server access to group messages and protected media. Rejoining requires a new accepted invitation and does not grant access to history from the absence period.
- Wallpaper preference is per-user/per-group, never shared as group state.
- Membership changes, unread counts, receipts, notifications, message delivery and Realtime access must derive from the same authoritative membership state.
- Screens must support light/dark themes and small/large layouts.

## Sequence
1. Domain models and lifecycle tests (initial foundation added).
2. Audit current direct-message RPCs, tables, RLS and media storage policies before SQL changes.
3. Prepare a migration for groups, invitations, memberships, owner succession and protected media.
4. Wire repository/controllers and list, create/invitation, conversation, details/member management and personal wallpaper screens.
5. Test lifecycle transitions, authorization, unread/receipt consistency, Realtime and themes.

## Security boundary
Client checks are UX only. Every message fetch/send, media access, invitation response, role change, removal, leave and ownership action must be authorized server-side. Leaving must not rely only on unsubscribing from Realtime or clearing local cache.
