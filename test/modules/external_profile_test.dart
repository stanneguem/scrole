import 'package:flutter_test/flutter_test.dart';
import 'package:scrole/modules/module_decouverte/externe/repositories/external_profile_repository.dart';
import 'package:scrole/modules/module_decouverte/centre/models/external_profile_model.dart';

void main() {
  group('ExternalProfileModel privacy fields', () {
    test('respects hidden location and message permission from backend payload', () {
      final profile = ExternalProfileModel.fromJson({
        'user_id': '00000000-0000-0000-0000-000000000001',
        'username': 'private_user',
        'first_name': 'Private',
        'last_name': 'User',
        'is_private': true,
        'country': null,
        'city': null,
        'can_message': false,
        'is_online': false,
        'last_seen_at': null,
        'interests': [],
      });

      expect(profile.isPrivate, isTrue);
      expect(profile.country, isNull);
      expect(profile.city, isNull);
      expect(profile.canMessage, isFalse);
      expect(profile.isOnline, isFalse);
      expect(profile.lastSeenAt, isNull);
    });

    test('parses online and last-seen values supplied by privacy-aware RPC', () {
      final profile = ExternalProfileModel.fromJson({
        'user_id': '00000000-0000-0000-0000-000000000002',
        'username': 'visible_user',
        'first_name': 'Visible',
        'last_name': 'User',
        'is_private': false,
        'country': 'Cameroon',
        'city': 'Yaounde',
        'can_message': true,
        'is_online': true,
        'last_seen_at': '2026-10-21T08:30:00Z',
        'interests': [],
      });

      expect(profile.canMessage, isTrue);
      expect(profile.isOnline, isTrue);
      expect(profile.lastSeenAt, isNotNull);
      expect(profile.country, 'Cameroon');
      expect(profile.city, 'Yaounde');
    });
  });

  group('ExternalProfileResult Status Tests', () {
    test('ExternalProfileResult correctly stores status and profile', () {
      const deletedRes = ExternalProfileResult(status: ProfileResultStatus.deleted);
      expect(deletedRes.status, equals(ProfileResultStatus.deleted));
      expect(deletedRes.profile, isNull);

      const notFoundRes = ExternalProfileResult(status: ProfileResultStatus.notFound);
      expect(notFoundRes.status, equals(ProfileResultStatus.notFound));
      expect(notFoundRes.profile, isNull);

      const suspendedRes = ExternalProfileResult(status: ProfileResultStatus.suspended);
      expect(suspendedRes.status, equals(ProfileResultStatus.suspended));

      const bannedRes = ExternalProfileResult(status: ProfileResultStatus.banned);
      expect(bannedRes.status, equals(ProfileResultStatus.banned));

      const errorRes = ExternalProfileResult(status: ProfileResultStatus.error, errorMessage: 'Erreur réseau');
      expect(errorRes.status, equals(ProfileResultStatus.error));
      expect(errorRes.errorMessage, equals('Erreur réseau'));
    });
  });
}
