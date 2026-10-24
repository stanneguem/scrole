import 'package:flutter_test/flutter_test.dart';
import 'package:scrole/modules/module_evenement/centre/models/event_model.dart';

void main() {
  group('Calendar Events Pipeline & Deduplication Tests', () {
    List<EventModel> deduplicateCalendarEvents(List<dynamic> rawList) {
      final Set<String> seenIds = {};
      final List<EventModel> result = [];

      for (final item in rawList) {
        if (item is Map) {
          final map = Map<String, dynamic>.from(item);
          final id = (map['id'] ?? map['evenement_id'] ?? '').toString().trim();

          if (id.isNotEmpty && seenIds.contains(id)) {
            continue;
          }

          if (id.isNotEmpty) {
            seenIds.add(id);
          }
          result.add(EventModel.fromJson(map));
        }
      }
      return result;
    }

    test('parses get_home_calendar_events RPC rows correctly', () {
      final json = {
        'id': 'evt-cal-1',
        'title': 'Kamer Gaming Night',
        'photo_url': 'https://example.com/cover.png',
        'starts_at': '2026-10-15T18:00:00Z',
        'ends_at': '2026-10-15T22:00:00Z',
        'city_id': 'city-yaounde',
        'country_id': 'country-cm',
        'is_free': true,
        'is_virtual': false,
        'event_date': '2026-10-15',
      };

      final model = EventModel.fromJson(json);
      expect(model.id, equals('evt-cal-1'));
      expect(model.name, equals('Kamer Gaming Night'));
      expect(model.coverImageUrl, equals('https://example.com/cover.png'));
      expect(model.isFree, isTrue);
      expect(model.isOnline, isFalse);
    });

    test('deduplicates duplicate events by event.id for calendar', () {
      final rawList = [
        {
          'id': 'evt-cal-1',
          'title': 'Event 1',
          'starts_at': '2026-10-15T18:00:00Z',
        },
        {
          'id': 'evt-cal-1',
          'title': 'Event 1 Duplicate',
          'starts_at': '2026-10-15T18:00:00Z',
        },
        {
          'id': 'evt-cal-2',
          'title': 'Event 2',
          'starts_at': '2026-10-16T18:00:00Z',
        },
      ];

      final items = deduplicateCalendarEvents(rawList);
      expect(items.length, equals(2));
      expect(items.map((e) => e.id), equals(['evt-cal-1', 'evt-cal-2']));
    });

    test('controlled merge map retains unique event.id after refreshes', () {
      final existingEvents = [
        EventModel(id: 'evt-1', creatorId: 'c1', name: 'Event 1', slug: '1', startsAt: DateTime.now(), createdAt: DateTime.now()),
        EventModel(id: 'evt-2', creatorId: 'c2', name: 'Event 2', slug: '2', startsAt: DateTime.now(), createdAt: DateTime.now()),
      ];

      final newFetch = [
        EventModel(id: 'evt-2', creatorId: 'c2', name: 'Event 2 Updated', slug: '2', startsAt: DateTime.now(), createdAt: DateTime.now()),
        EventModel(id: 'evt-3', creatorId: 'c3', name: 'Event 3', slug: '3', startsAt: DateTime.now(), createdAt: DateTime.now()),
      ];

      final Map<String, EventModel> map = { for (var e in existingEvents) e.id: e };
      for (var e in newFetch) { map[e.id] = e; }
      final merged = map.values.toList();

      expect(merged.length, equals(3));
      expect(merged.map((e) => e.id), equals(['evt-1', 'evt-2', 'evt-3']));
      expect(merged.firstWhere((e) => e.id == 'evt-2').name, equals('Event 2 Updated'));
    });

    test('calculates 180-day window start and end dates correctly', () {
      final startMonth = DateTime(2026, 10, 1);
      const nbMonths = 6; // 180 days (~6 months)

      final startDate = DateTime(startMonth.year, startMonth.month, 1);
      final endDate = DateTime(startMonth.year, startMonth.month + nbMonths, 0);

      final startDateStr = '${startDate.year}-${startDate.month.toString().padLeft(2, '0')}-01';
      final endDateStr = '${endDate.year}-${endDate.month.toString().padLeft(2, '0')}-${endDate.day.toString().padLeft(2, '0')}';

      expect(startDateStr, equals('2026-10-01'));
      expect(endDateStr, equals('2027-03-31'));
    });
  });
}
