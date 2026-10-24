import 'package:flutter_test/flutter_test.dart';
import 'package:scrole/modules/module_evenement/centre/models/event_preview_model.dart';
import 'package:scrole/shared/utils/number_formatter.dart';

void main() {
  group('Event Like Tests', () {
    test('EventPreviewModel parses isLikedByMe, likesCount, and canLike correctly', () {
      final json = {
        'event': {
          'id': 'evt-1',
          'creator_id': 'u-1',
          'name': 'Fest',
          'slug': 'fest',
          'starts_at': DateTime.now().toIso8601String(),
          'created_at': DateTime.now().toIso8601String(),
        },
        'is_liked_by_me': true,
        'likes_count': 15,
        'can_like': true,
      };

      final preview = EventPreviewModel.fromJson(json);
      expect(preview.isLikedByMe, isTrue);
      expect(preview.likesCount, equals(15));
      expect(preview.canLike, isTrue);
    });

    test('optimistic like computation increments count and toggles state', () {
      bool isLiked = false;
      int likesCount = 10;

      // Click like
      isLiked = !isLiked;
      likesCount = isLiked ? likesCount + 1 : (likesCount > 0 ? likesCount - 1 : 0);

      expect(isLiked, isTrue);
      expect(likesCount, equals(11));
      expect(NumberFormatter.formatCount(likesCount), equals('11'));

      // Click unlike
      isLiked = !isLiked;
      likesCount = isLiked ? likesCount + 1 : (likesCount > 0 ? likesCount - 1 : 0);

      expect(isLiked, isFalse);
      expect(likesCount, equals(10));
    });

    test('respects can_like authorization', () {
      final jsonCannotLike = {
        'event': {
          'id': 'evt-2',
          'creator_id': 'u-2',
          'name': 'Private Event',
          'slug': 'private',
          'starts_at': DateTime.now().toIso8601String(),
          'created_at': DateTime.now().toIso8601String(),
        },
        'is_liked_by_me': false,
        'likes_count': 5,
        'can_like': false,
      };

      final preview = EventPreviewModel.fromJson(jsonCannotLike);
      expect(preview.canLike, isFalse);
    });
  });
}
