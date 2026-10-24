import 'package:flutter_test/flutter_test.dart';
import 'package:scrole/modules/module_communautes/centre/models/community_model.dart';
import 'package:scrole/app/translation/app_translation_additions.dart';

void main() {
  group('Community Open & Preview Tests', () {
    test('Parses open_community RPC response for active member (destination = community)', () {
      final jsonResponse = {
        'destination': 'community',
        'membership_status': 'active',
        'community': {
          'id': 'comm_1',
          'name': 'Zimbaya Active',
          'slug': 'zimbaya',
          'visibility': 'public',
          'member_count': 42,
        },
      };

      final result = CommunityOpenResult.fromJson(jsonResponse);
      expect(result.destination, equals('community'));
      expect(result.isMember, isTrue);
      expect(result.id, equals('comm_1'));
      expect(result.name, equals('Zimbaya Active'));
      expect(result.memberCount, equals(42));
    });

    test('Parses open_community RPC response for preview with join action (destination = preview, join_action = join)', () {
      final jsonResponse = {
        'destination': 'preview',
        'membership_status': 'none',
        'join_action': 'join',
        'community': {
          'id': 'comm_2',
          'name': 'Public Otaku CM',
          'slug': 'otaku-cm',
          'description': 'Description de test',
          'photo_profile': 'https://example.com/avatar.jpg',
          'photo_cover': 'https://example.com/cover.jpg',
          'visibility': 'public',
          'member_count': 150,
        },
      };

      final result = CommunityOpenResult.fromJson(jsonResponse);
      expect(result.destination, equals('preview'));
      expect(result.joinAction, equals('join'));
      expect(result.isMember, isFalse);
      expect(result.isPending, isFalse);
      expect(result.id, equals('comm_2'));
      expect(result.name, equals('Public Otaku CM'));
      expect(result.description, equals('Description de test'));
      expect(result.photoProfile, equals('https://example.com/avatar.jpg'));
      expect(result.photoCover, equals('https://example.com/cover.jpg'));
      expect(result.memberCount, equals(150));
    });

    test('Parses open_community RPC response for preview with request action (destination = preview, join_action = request)', () {
      final jsonResponse = {
        'destination': 'preview',
        'membership_status': 'none',
        'join_action': 'request',
        'community': {
          'id': 'comm_3',
          'name': 'Private Tech CM',
          'visibility': 'prive',
        },
      };

      final result = CommunityOpenResult.fromJson(jsonResponse);
      expect(result.destination, equals('preview'));
      expect(result.joinAction, equals('request'));
      expect(result.visibility, equals('prive'));
    });

    test('Parses non-eligible preview with reasons list (join_action = none)', () {
      final jsonResponse = {
        'destination': 'preview',
        'membership_status': 'none',
        'join_action': 'none',
        'reasons': [
          'GENDER_RESTRICTION',
          'AGE_REQUIREMENT_NOT_MET',
        ],
        'community': {
          'id': 'comm_4',
          'name': 'Restricted Club',
        },
      };

      final result = CommunityOpenResult.fromJson(jsonResponse);
      expect(result.destination, equals('preview'));
      expect(result.joinAction, equals('none'));
      expect(result.reasons, contains('GENDER_RESTRICTION'));
      expect(result.reasons, contains('AGE_REQUIREMENT_NOT_MET'));
    });

    test('Parses pending request status (membership_status = pending or request_status = en_attente)', () {
      final jsonResponse = {
        'destination': 'preview',
        'membership_status': 'pending',
        'request_status': 'en_attente',
        'join_action': 'none',
        'community': {
          'id': 'comm_5',
          'name': 'Pending Club',
        },
      };

      final result = CommunityOpenResult.fromJson(jsonResponse);
      expect(result.destination, equals('preview'));
      expect(result.isPending, isTrue);
    });

    test('Parses unavailable destination (destination = unavailable)', () {
      final jsonResponse = {
        'destination': 'unavailable',
        'reasons': ['COMMUNITY_UNAVAILABLE'],
      };

      final result = CommunityOpenResult.fromJson(jsonResponse);
      expect(result.destination, equals('unavailable'));
      expect(result.isMember, isFalse);
    });

    test('All 11 reason codes and action keys exist in all 9 language catalogs', () {
      final keysMap = AppTranslationAdditions.keys;
      final requiredLanguages = ['fr', 'en', 'es', 'de', 'it', 'pt', 'zh', 'ja', 'ru'];
      final reasonCodes = [
        'community_reason_AUTHENTICATION_REQUIRED',
        'community_reason_COMMUNITY_UNAVAILABLE',
        'community_reason_PROFILE_INCOMPLETE',
        'community_reason_COUNTRY_NOT_ALLOWED',
        'community_reason_CITY_NOT_ALLOWED',
        'community_reason_GENDER_RESTRICTION',
        'community_reason_CERTIFICATION_REQUIRED',
        'community_reason_BIRTH_DATE_REQUIRED',
        'community_reason_AGE_REQUIREMENT_NOT_MET',
        'community_reason_AGE_LIMIT_EXCEEDED',
        'community_reason_REQUEST_PENDING',
        'community_join_button',
        'community_request_button',
        'community_request_pending',
        'community_cannot_join',
        'community_unavailable_msg',
        'community_preview_title',
      ];

      for (final lang in requiredLanguages) {
        expect(keysMap.containsKey(lang), isTrue, reason: 'Missing language catalog: $lang');
        final catalog = keysMap[lang]!;
        for (final key in reasonCodes) {
          expect(catalog.containsKey(key), isTrue, reason: 'Missing key $key in language $lang');
        }
      }
    });

    test('Filters out community posts from suspended, banned or deleted authors', () {
      bool isAuthorActiveAndValid(Map<String, dynamic> postMap) {
        final authorMap = postMap['author'] is Map ? Map<String, dynamic>.from(postMap['author']) : <String, dynamic>{};
        final status = (authorMap['account_status'] ?? authorMap['status'] ?? postMap['author_status'] ?? 'active').toString().toLowerCase();
        if (status != 'active' || status == 'suspended' || status == 'banned' || status == 'deleted') {
          return false;
        }
        if (authorMap['deleted_at'] != null || authorMap['is_deleted'] == true || postMap['author_deleted_at'] != null) {
          return false;
        }
        return true;
      }

      final activePost = {
        'id': 'p1',
        'content': 'Valid post',
        'author': {'user_id': 'u1', 'username': 'active_user', 'account_status': 'active'},
      };

      final suspendedPost = {
        'id': 'p2',
        'content': 'Suspended author post',
        'author': {'user_id': 'u2', 'username': 'suspended_user', 'account_status': 'suspended'},
      };

      final deletedPost = {
        'id': 'p3',
        'content': 'Deleted author post',
        'author': {'user_id': 'u3', 'username': 'deleted_user', 'account_status': 'active', 'deleted_at': '2026-01-01T00:00:00Z'},
      };

      expect(isAuthorActiveAndValid(activePost), isTrue);
      expect(isAuthorActiveAndValid(suspendedPost), isFalse);
      expect(isAuthorActiveAndValid(deletedPost), isFalse);
    });
  });
}
