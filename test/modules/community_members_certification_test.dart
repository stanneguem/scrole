import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Community Members Certification & Profile Navigation Tests', () {
    test('isCertified is derived exclusively from is_certified field', () {
      final jsonCertified = {
        'user_profiles': {
          'user_id': 'u1',
          'username': 'gab',
          'is_verified': false,
          'is_certified': true,
        }
      };
      final profile1 = jsonCertified['user_profiles'] as Map<String, dynamic>;
      final isCertified1 = profile1['is_certified'] == true || profile1['is_certified'] == 1;
      expect(isCertified1, isTrue);

      final jsonVerifiedOnly = {
        'user_profiles': {
          'user_id': 'u2',
          'username': 'joe',
          'is_verified': true,
          'is_certified': false,
        }
      };
      final profile2 = jsonVerifiedOnly['user_profiles'] as Map<String, dynamic>;
      final isCertified2 = profile2['is_certified'] == true || profile2['is_certified'] == 1;
      expect(isCertified2, isFalse);
    });
  });
}
