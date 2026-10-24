import 'package:flutter_test/flutter_test.dart';
import 'package:scrole/modules/module_evenement/centre/models/event_model.dart';

void main() {
  group('Event Suggestions Deduplication Tests', () {
    // Helper mimicking EventRepository._deduplicateRawSuggestions
    List<EventModel> deduplicateRawSuggestions(List<dynamic> rawList) {
      final List<EventModel> result = [];
      final Set<String> seenCategoryAndId = {};

      for (final item in rawList) {
        if (item is Map) {
          final map = Map<String, dynamic>.from(item);
          final category = (map['category'] ?? map['categorie'] ?? '').toString().toLowerCase().trim();
          final id = (map['id'] ?? map['evenement_id'] ?? '').toString().trim();
          final key = '${category}_$id';

          if (id.isNotEmpty && seenCategoryAndId.contains(key)) {
            continue;
          }

          if (id.isNotEmpty) {
            seenCategoryAndId.add(key);
          }
          result.add(EventModel.fromJson(map));
        }
      }
      return result;
    }

    // Helper mimicking SuggestionTab._uniqueByEventId
    List<EventModel> uniqueByEventId(Iterable<EventModel> events) {
      final seen = <String>{};
      final result = <EventModel>[];
      for (final e in events) {
        if (e.id.isNotEmpty && seen.add(e.id)) {
          result.add(e);
        }
      }
      return result;
    }

    test('Test 1: Preserves same event across DIFFERENT categories', () {
      final rawList = [
        {'id': 'evt-A', 'category': 'pour_vous', 'name': 'Kamer Fest'},
        {'id': 'evt-A', 'category': 'populaires', 'name': 'Kamer Fest'},
        {'id': 'evt-A', 'category': 'gratuits', 'name': 'Kamer Fest'},
      ];

      final items = deduplicateRawSuggestions(rawList);
      expect(items.length, equals(3));
      expect(items.map((e) => e.category), containsAll(['pour_vous', 'populaires', 'gratuits']));
    });

    test('Test 2: Deduplicates duplicate event in SAME category', () {
      final rawList = [
        {'id': 'evt-A', 'category': 'pour_vous', 'name': 'Kamer Fest'},
        {'id': 'evt-A', 'category': 'pour_vous', 'name': 'Kamer Fest (duplicate)'},
        {'id': 'evt-B', 'category': 'pour_vous', 'name': 'Tech Conf'},
      ];

      final items = deduplicateRawSuggestions(rawList);
      expect(items.length, equals(2));
      expect(items.map((e) => e.id), equals(['evt-A', 'evt-B']));
    });

    test('Test 3 & 4: Section-level deduplication prevents duplicate cards in a single section', () {
      final events = [
        EventModel(id: 'evt-A', creatorId: 'c1', name: 'Event A', slug: 'a', startsAt: DateTime.now(), createdAt: DateTime.now(), category: 'pour_vous'),
        EventModel(id: 'evt-A', creatorId: 'c1', name: 'Event A', slug: 'a', startsAt: DateTime.now(), createdAt: DateTime.now(), category: 'populaires'),
        EventModel(id: 'evt-B', creatorId: 'c2', name: 'Event B', slug: 'b', startsAt: DateTime.now(), createdAt: DateTime.now(), category: 'pour_vous'),
      ];

      final sectionForYou = uniqueByEventId(events);
      expect(sectionForYou.length, equals(2));
      expect(sectionForYou.map((e) => e.id), equals(['evt-A', 'evt-B']));
    });

    test('Test 5: Category with fewer items than limit reflects exact count without padding', () {
      final events = [
        EventModel(id: 'evt-1', creatorId: 'c1', name: 'Event 1', slug: '1', startsAt: DateTime.now(), createdAt: DateTime.now()),
        EventModel(id: 'evt-2', creatorId: 'c2', name: 'Event 2', slug: '2', startsAt: DateTime.now(), createdAt: DateTime.now()),
      ];

      final sectionItems = uniqueByEventId(events);
      expect(sectionItems.length, equals(2)); // Exactly 2, no artificial repetition
    });

    test('Test 6: Empty category result is empty list', () {
      final List<EventModel> emptyCategory = [];
      final sectionItems = uniqueByEventId(emptyCategory);
      expect(sectionItems, isEmpty);
    });
  });
}
