import 'package:flutter_test/flutter_test.dart';
import 'package:scrole/modules/module_evenement/centre/models/event_comment.dart';

void main() {
  group('EventComment Role Badge Tests', () {
    test('EventComment.fromJson parses founder, co_founder, and staff event_role correctly', () {
      final jsonFounder = {
        'id': 'c-1',
        'event_id': 'evt-1',
        'user_id': 'u-1',
        'content': 'Commentaire du fondateur',
        'event_role': 'founder',
        'created_at': DateTime.now().toIso8601String(),
        'author': {'user_id': 'u-1', 'username': 'Gabriel'},
      };

      final jsonCoFounder = {
        'id': 'c-2',
        'event_id': 'evt-1',
        'user_id': 'u-2',
        'content': 'Commentaire du co-fondateur',
        'event_role': 'co_founder',
        'created_at': DateTime.now().toIso8601String(),
        'author': {'user_id': 'u-2', 'username': 'Sarah'},
      };

      final jsonStaff = {
        'id': 'c-3',
        'event_id': 'evt-1',
        'user_id': 'u-3',
        'content': 'Commentaire du staff',
        'event_role': 'staff',
        'created_at': DateTime.now().toIso8601String(),
        'author': {'user_id': 'u-3', 'username': 'Marc'},
      };

      final commentFounder = EventComment.fromJson(jsonFounder);
      final commentCoFounder = EventComment.fromJson(jsonCoFounder);
      final commentStaff = EventComment.fromJson(jsonStaff);

      expect(commentFounder.eventRole, equals('founder'));
      expect(commentCoFounder.eventRole, equals('co_founder'));
      expect(commentStaff.eventRole, equals('staff'));
    });

    test('EventComment.fromJson handles null and unknown event_role safely as null', () {
      final jsonNull = {
        'id': 'c-4',
        'event_id': 'evt-1',
        'user_id': 'u-4',
        'content': 'Commentaire membre lambda',
        'event_role': null,
        'created_at': DateTime.now().toIso8601String(),
        'author': {'user_id': 'u-4', 'username': 'Paul'},
      };

      final jsonUnknown = {
        'id': 'c-5',
        'event_id': 'evt-1',
        'user_id': 'u-5',
        'content': 'Role inconnu',
        'event_role': 'random_role',
        'created_at': DateTime.now().toIso8601String(),
        'author': {'user_id': 'u-5', 'username': 'Inconnu'},
      };

      final commentNull = EventComment.fromJson(jsonNull);
      final commentUnknown = EventComment.fromJson(jsonUnknown);

      expect(commentNull.eventRole, isNull);
      expect(commentUnknown.eventRole, isNull);
    });
  });
}
