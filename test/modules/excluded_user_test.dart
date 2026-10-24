import 'package:flutter_test/flutter_test.dart';
import 'package:scrole/modules/module_communautes/centre/models/excluded_user.dart';

void main() {
  group('ExcludedUser Model & Certification Tests', () {
    test('isVerified is parsed as true when is_verified is true', () {
      final json = {
        'user': {
          'user_id': 'u1',
          'first_name': 'John',
          'last_name': 'Doe',
          'is_verified': true,
        },
        'reason': 'spam'
      };
      final user = ExcludedUser.fromJson(json);
      expect(user.isVerified, isTrue);
      expect(user.displayName, 'John Doe');
      expect(user.reason, 'spam');
    });

    test('isVerified defaults to false when is_verified is false, null, or absent', () {
      final jsonFalse = {
        'user': {
          'user_id': 'u2',
          'username': 'janesmith',
          'is_verified': false,
        }
      };
      expect(ExcludedUser.fromJson(jsonFalse).isVerified, isFalse);

      final jsonNull = {
        'user': {
          'user_id': 'u3',
          'username': 'bob',
          'is_verified': null,
        }
      };
      expect(ExcludedUser.fromJson(jsonNull).isVerified, isFalse);

      final jsonAbsent = {
        'user': {
          'user_id': 'u4',
          'username': 'alice',
        }
      };
      expect(ExcludedUser.fromJson(jsonAbsent).isVerified, isFalse);
    });
  });
}
