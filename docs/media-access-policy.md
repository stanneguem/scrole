# Scrole media privacy policy

This policy is the access-control contract for every media surface.

| Surface | Visibility |
| --- | --- |
| Profile avatar and cover | Public |
| Public feed posts | Visible to anyone allowed to view the post |
| Public community posts and media | Public, subject to normal post visibility/moderation |
| Private community posts and media | Active/approved community members only |
| Direct-message attachments | Only the sender and the other participant(s) authorized for that conversation |
| Story media | Same audience/visibility rules as the owning story; never public by storage URL alone |

## Security requirements

1. Storage privacy must be enforced by the storage origin, not by obscurity of object keys.
2. Upload authorization is not sufficient. Every private-media read must re-check the requesting user's current authorization.
3. Private media is delivered through short-lived signed URLs issued only after server-side authorization. Do not persist signed URLs in message/story/post rows; persist stable object keys.
4. Public feed/community media may use public delivery only after confirming the post/community is actually public. A public storage bucket must not contain private-community, story-audience-restricted, or DM files.
5. Profile avatar and cover media remain public.
6. Existing public URLs must be migrated carefully. Do not flip chat-media to private or remove its public-read policy until the client and Edge Function have switched to authorized signed URL resolution, otherwise existing conversations will break.
7. Story authorization must reuse the database's can_view_story_row(author_id, audience) rule. Private community media must check communities.visibility and membership/approval. DM authorization must check direct_conversation_members and/or both participants in direct_conversations, and must deny deleted/removed memberships.
8. Use fail-closed behavior: missing rows, RPC/database errors, unknown media categories, and invalid object keys deny access.
9. Tests must prove that a non-member cannot resolve or download a private-community asset, a non-participant cannot resolve or download a DM attachment, and a user excluded by story audience cannot resolve/download story media. Authorized users and public assets must still work.

## Rollout sequence (do not reorder)

1. Inventory all existing stored URL shapes and the clients that consume them.
2. Implement an authenticated media resolver that validates the owning row and current access before creating a short-lived signed URL.
3. Update Flutter image/video/audio/document consumers to resolve private object keys via the resolver and refresh expired URLs. Keep public URLs working for public categories.
4. Update upload flows to store stable object keys for private media. Ensure DM uploads are keyed to conversation IDs and membership is checked on upload and read.
5. Backfill legacy URL records to stable object keys where possible, with a report of records that cannot be safely classified. Do not guess visibility.
6. Verify privacy tests and existing-media compatibility.
7. Only then make private buckets private and remove public-read policies for buckets containing private assets. Keep avatars/public assets public or in a separate public bucket.
8. Deploy Edge Functions and apply reviewed SQL migration during a coordinated rollout.

## Current findings (inspection only)

- Supabase chat-media bucket is currently public and has a permissive chat_media_public_read SELECT policy.
- The deployed chat-media Edge Function uploads under user_id/conversation_id/... and checks conversation membership on upload, but returns a public URL and the bucket is configured public. That leaves a read path which does not check membership.
- group-chat-media is private, while community-videos, community-media, event-media, and avatars are public. The public community-media and community-videos buckets need classification before they can be considered safe for private-community content.
- Public/private classification must be based on the owning post/story/community/message, not merely the bucket name.
- No production storage policies or buckets should be changed until all client read paths are migrated.
