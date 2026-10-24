import 'package:flutter_test/flutter_test.dart';
import 'package:scrole/modules/module_evenement/centre/models/event_day_models.dart';

void main() {
  group('Event Open Days Models Tests', () {
    test('EventOpenDay.fromJson parses date and is_open correctly', () {
      final json = {'date': '2026-10-01', 'is_open': true};
      final openDay = EventOpenDay.fromJson(json);

      expect(openDay.dateString, equals('2026-10-01'));
      expect(openDay.isOpen, isTrue);
    });

    test('EventPlannedDay.fromJson parses date correctly', () {
      final json = {'date': '2026-10-02'};
      final plannedDay = EventPlannedDay.fromJson(json);

      expect(plannedDay.dateString, equals('2026-10-02'));
    });

    test('EventDayAttendance.fromJson parses date and planned_attendees correctly', () {
      final json = {'date': '2026-10-03', 'planned_attendees': 25};
      final attendance = EventDayAttendance.fromJson(json);

      expect(attendance.dateString, equals('2026-10-03'));
      expect(attendance.plannedAttendees, equals(25));
    });
  });
}
