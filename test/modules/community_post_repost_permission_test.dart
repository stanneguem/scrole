import 'package:flutter_test/flutter_test.dart';
import 'package:scrole/modules/module_principale/centre/models/community_post.dart';

void main() {
  group('Community post repost permissions', () {
    CommunityPost makePost({
      bool sharingEnabled = true,
      bool? communitySharingEnabled,
    }) {
      return CommunityPost.fromMap({
        'id': 'post-1',
        'author_id': 'user-1',
        'author': {
          'user_id': 'user-1',
          'username': 'member_one',
        },
        'content': 'Publication de test',
        'created_at': '2026-10-24T10:00:00Z',
        'sharing_enabled': sharingEnabled,
        'community': {
          'id': 'community-1',
          if (communitySharingEnabled != null)
            'allow_post_sharing': communitySharingEnabled,
        },
      });
    }

    test('community administrators can disable reposting for all posts', () {
      final post = makePost(communitySharingEnabled: false);

      expect(post.sharingEnabled, isTrue);
      expect(post.communitySharingEnabled, isFalse);
      expect(post.canRepost, isFalse);
    });

    test('post-level sharing permission is still enforced', () {
      final post = makePost(
        sharingEnabled: false,
        communitySharingEnabled: true,
      );

      expect(post.canRepost, isFalse);
    });

    test('reposting stays enabled when both levels allow it', () {
      final post = makePost(
        sharingEnabled: true,
        communitySharingEnabled: true,
      );

      expect(post.canRepost, isTrue);
    });

    test('older payloads default the community setting to enabled', () {
      final post = makePost();

      expect(post.communitySharingEnabled, isTrue);
      expect(post.canRepost, isTrue);
    });
  });
}
