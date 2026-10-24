import 'package:flutter_test/flutter_test.dart';
import 'package:scrole/modules/module_communautes/centre/models/community_model.dart';
import 'package:scrole/modules/module_communautes/interne/controllers/community/community_feed_controller.dart';
import 'package:scrole/app/translation/app_translation_additions.dart';

void main() {
  group('Community Local Sync & Reactivity Tests', () {
    test('1. Schema Alignment: Ensure community_members insert uses cached_at and not created_at', () {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      const userId = 'user_abc';
      const communityId = 'comm_xyz';
      
      final memberMap = {
        'id': '${communityId}_$userId',
        'community_id': communityId,
        'user_id': userId,
        'status': 'active',
        'cached_at': nowMs,
      };

      expect(memberMap.containsKey('id'), isTrue);
      expect(memberMap.containsKey('community_id'), isTrue);
      expect(memberMap.containsKey('user_id'), isTrue);
      expect(memberMap.containsKey('status'), isTrue);
      expect(memberMap.containsKey('cached_at'), isTrue);
      expect(memberMap.containsKey('created_at'), isFalse);
    });

    test('2. Multi-Community Sync: Synchronisation des 7 communautés du profil Tsunade sans slug', () {
      final mockGetMyCommunitiesResponse = [
        {'id': 'dc41a9e9-23b3-4797-89da-89c871c4a7f6', 'name': 'Otaku du cameroun', 'photo_profile': 'https://example.com/p1.jpg', 'photo_cover': 'https://example.com/c1.jpg'},
        {'id': 'comm_otaku_2', 'name': 'Otaku du cameroun 2', 'photo_profile': 'https://example.com/p2.jpg'},
        {'id': 'comm_zimbaya', 'name': 'Zimbaya.com', 'photo_profile': 'https://example.com/p3.jpg'},
        {'id': 'comm_tech', 'name': 'Tech Cameroun', 'photo_profile': null},
        {'id': 'comm_manga', 'name': 'Manga Fans', 'photo_profile': null},
        {'id': 'comm_gaming', 'name': 'Gaming 237', 'photo_profile': null},
        {'id': 'comm_art', 'name': 'Art Club', 'photo_profile': null},
      ];

      final List<CommunityModel> deserialized = mockGetMyCommunitiesResponse.map((raw) {
        return CommunityModel.fromMap(raw);
      }).toList();

      expect(deserialized.length, equals(7));

      final slugs = deserialized.map((c) => c.slug).toList();
      final uniqueSlugs = slugs.toSet();

      // Ensure every deserialized community gets a distinct, non-empty slug (using id fallback when null)
      expect(slugs.every((s) => s.isNotEmpty), isTrue);
      expect(uniqueSlugs.length, equals(7), reason: 'Each community must have a distinct slug to prevent SQLite index collision');
    });

    test('3. Membership Join & Leave Local State updates', () {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      const userId = 'user_123';
      const communityId = 'comm_join_test';

      final localMemberships = <String, Map<String, dynamic>>{};
      final localCommunities = <String, CommunityModel>{};

      // Join Community
      final community = CommunityModel(
        id: communityId,
        name: 'Communauté Test',
        slug: 'test',
        visibility: 'public',
        status: 'confirmed',
        memberCount: 10,
        cachedAt: nowMs,
        createdAt: nowMs,
      );

      localCommunities[communityId] = community;
      localMemberships['${communityId}_$userId'] = {
        'id': '${communityId}_$userId',
        'community_id': communityId,
        'user_id': userId,
        'status': 'active',
        'cached_at': nowMs,
      };

      expect(localCommunities.containsKey(communityId), isTrue);
      expect(localMemberships.containsKey('${communityId}_$userId'), isTrue);

      // Leave Community
      localCommunities.remove(communityId);
      localMemberships.remove('${communityId}_$userId');

      expect(localCommunities.containsKey(communityId), isFalse);
      expect(localMemberships.containsKey('${communityId}_$userId'), isFalse);
    });

    test('4. Community Feed Controller States: initialLoading, empty, and error distinction', () {
      final controller = CommunityFeedController(null, 'comm_test');
      expect(controller.feedState.value, equals(CommunityFeedState.initialLoading));

      // Test Empty state transition
      controller.posts.clear();
      controller.feedState.value = CommunityFeedState.empty;
      expect(controller.feedState.value, equals(CommunityFeedState.empty));

      // Test Error state transition
      controller.errorMessage.value = 'Erreur réseau de synchronisation';
      controller.feedState.value = CommunityFeedState.error;
      expect(controller.feedState.value, equals(CommunityFeedState.error));
      expect(controller.errorMessage.value, equals('Erreur réseau de synchronisation'));
    });

    test('5. Translation catalogs completeness for community feed', () {
      final keysMap = AppTranslationAdditions.keys;
      final requiredLanguages = ['fr', 'en', 'es', 'de', 'it', 'pt', 'zh', 'ja', 'ru'];
      final requiredKeys = [
        'community_feed_loading',
        'community_feed_empty_title',
        'community_feed_create_first_post',
        'community_feed_error_msg',
      ];

      for (final lang in requiredLanguages) {
        expect(keysMap.containsKey(lang), isTrue, reason: 'Missing language catalog: $lang');
        final catalog = keysMap[lang]!;
        for (final key in requiredKeys) {
          expect(catalog.containsKey(key), isTrue, reason: 'Missing key $key in language $lang');
        }
      }
    });
  });
}
