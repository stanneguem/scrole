import 'package:flutter_test/flutter_test.dart';
import 'package:scrole/modules/module_evenement/centre/models/event_comment.dart';

void main() {
  group('EventComment Threading Tests', () {
    test('EventComment.fromJson parses comment, author, and nested replies correctly', () {
      final json = {
        'id': 'c-100',
        'event_id': 'evt-1',
        'user_id': 'u-1',
        'content': 'Super événement ! Hâte d\'y être.',
        'created_at': DateTime.now().toIso8601String(),
        'author': {
          'user_id': 'u-1',
          'username': 'Alexandre',
          'first_name': 'Alexandre',
          'last_name': 'Dumas',
          'photo_url': 'https://example.com/photo.jpg',
        },
        'replies': [
          {
            'id': 'c-101',
            'event_id': 'evt-1',
            'user_id': 'u-2',
            'content': 'Moi aussi, à samedi !',
            'parent_comment_id': 'c-100',
            'created_at': DateTime.now().toIso8601String(),
            'author': {
              'user_id': 'u-2',
              'username': 'Sophie',
              'first_name': 'Sophie',
              'photo_url': null,
            },
          }
        ]
      };

      final comment = EventComment.fromJson(json);

      expect(comment.id, equals('c-100'));
      expect(comment.author.displayName, contains('Alexandre'));
      expect(comment.content, equals('Super événement ! Hâte d\'y être.'));
      expect(comment.replies.length, equals(1));

      final reply = comment.replies.first;
      expect(reply.id, equals('c-101'));
      expect(reply.author.displayName, equals('Sophie'));
      expect(reply.parentCommentId, equals('c-100'));
    });

    test('EventComment.fromJson parses replies_count, likes_count and is_liked correctly for initial load without replies', () {
      final json = {
        'id': 'c-200',
        'event_id': 'evt-2',
        'user_id': 'u-3',
        'content': 'Commentaire sans réponses chargées initialement',
        'created_at': DateTime.now().toIso8601String(),
        'replies_count': 5,
        'likes_count': 12,
        'is_liked': true,
        'replies': [],
        'author': {
          'user_id': 'u-3',
          'username': 'Paul',
        },
      };

      final comment = EventComment.fromJson(json);

      expect(comment.id, equals('c-200'));
      expect(comment.repliesCount, equals(5));
      expect(comment.likesCount, equals(12));
      expect(comment.isLiked, isTrue);
      expect(comment.replies, isEmpty);
      expect(comment.areRepliesLoaded, isFalse);
    });
  });
}
