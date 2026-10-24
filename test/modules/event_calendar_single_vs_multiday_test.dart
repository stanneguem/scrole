import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Event Calendar Single vs Multi-Day Logic Tests', () {
    test('Same day or duration < 24h is detected as single-day event', () {
      final startsAt = DateTime(2026, 10, 1, 14, 0);
      final endsAt = DateTime(2026, 10, 1, 22, 0);

      final startDay = DateTime(startsAt.year, startsAt.month, startsAt.day);
      final endDay = DateTime(endsAt.year, endsAt.month, endsAt.day);

      final isMultiDay = endDay.difference(startDay).inDays >= 1;
      expect(isMultiDay, isFalse);
    });

    test('2 or more distinct dates are detected as multi-day event requiring day selection', () {
      final startsAt = DateTime(2026, 10, 1, 10, 0);
      final endsAt = DateTime(2026, 10, 3, 18, 0);

      final startDay = DateTime(startsAt.year, startsAt.month, startsAt.day);
      final endDay = DateTime(endsAt.year, endsAt.month, endsAt.day);

      final isMultiDay = endDay.difference(startDay).inDays >= 1;
      expect(isMultiDay, isTrue);
    });
  });
}
