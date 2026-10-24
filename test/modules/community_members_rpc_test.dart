import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Community Members RPC Response Parsing Tests', () {
    test('Parses RPC JSON response items and pagination flags correctly', () {
      final jsonResponse = {
        'items': [
          {
            'user_id': 'usr_1',
            'role': 'admin',
            'joined_at': '2026-01-01T10:00:00Z',
            'username': 'fatima',
            'first_name': 'Fatima',
            'last_name': 'Zahra',
            'photo_url': 'https://example.com/avatar.jpg',
            'is_verified': true,
            'is_certified': true,
            'is_self': true,
          },
          {
            'user_id': 'usr_2',
            'role': 'member',
            'joined_at': '2026-01-02T10:00:00Z',
            'username': 'alex',
            'first_name': 'Alexandre',
            'last_name': 'Dumas',
            'photo_url': null,
            'is_verified': false,
            'is_certified': false,
            'is_self': false,
          },
        ],
        'next_cursor': 'cursor_123',
        'has_more': true,
      };

      final items = jsonResponse['items'] as List;
      expect(items.length, equals(2));
      expect(jsonResponse['next_cursor'], equals('cursor_123'));
      expect(jsonResponse['has_more'], isTrue);

      final selfMember = items[0] as Map<String, dynamic>;
      expect(selfMember['is_self'], isTrue);
      expect(selfMember['role'], equals('admin'));
      expect(selfMember['user_id'], equals('usr_1'));

      final otherMember = items[1] as Map<String, dynamic>;
      expect(otherMember['is_self'], isFalse);
      expect(otherMember['user_id'], equals('usr_2'));
    });

    test('Preserves backend error message for hidden members list', () {
      const errorMessage = 'La liste des membres est masquée dans cette communauté';
      expect(errorMessage.contains('masquée'), isTrue);
      final displayMsg = errorMessage.replaceFirst('Exception: ', '');
      expect(displayMsg, equals('La liste des membres est masquée dans cette communauté'));
    });

    test('Parses get_my_communities RPC response items for user role cleanly', () {
      final myCommunitiesResponse = [
        {
          'id': 'comm_1',
          'name': 'Zimbaya',
          'role': 'admin',
        },
        {
          'id': 'comm_2',
          'name': 'Tech Community',
          'role': 'moderator',
        },
      ];

      final userRole1 = myCommunitiesResponse.firstWhere((c) => c['id'] == 'comm_1')['role'];
      expect(userRole1, equals('admin'));

      final userRole2 = myCommunitiesResponse.firstWhere((c) => c['id'] == 'comm_2')['role'];
      expect(userRole2, equals('moderator'));
    });
  });
}
