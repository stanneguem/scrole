import 'package:flutter_test/flutter_test.dart';
import 'package:scrole/modules/module_evenement/interne/controllers/event_controller.dart';

void main() {
  group('EventSuggestionsStatus and EventCalendarStatus', () {
    test('EventSuggestionsStatus has expected state machine values', () {
      expect(EventSuggestionsStatus.values.length, equals(5));
      expect(EventSuggestionsStatus.initial, isA<EventSuggestionsStatus>());
      expect(EventSuggestionsStatus.loading, isA<EventSuggestionsStatus>());
      expect(EventSuggestionsStatus.successWithData, isA<EventSuggestionsStatus>());
      expect(EventSuggestionsStatus.successEmpty, isA<EventSuggestionsStatus>());
      expect(EventSuggestionsStatus.error, isA<EventSuggestionsStatus>());
    });

    test('EventCalendarStatus has expected state machine values', () {
      expect(EventCalendarStatus.values.length, equals(5));
      expect(EventCalendarStatus.initial, isA<EventCalendarStatus>());
      expect(EventCalendarStatus.loading, isA<EventCalendarStatus>());
      expect(EventCalendarStatus.successWithData, isA<EventCalendarStatus>());
      expect(EventCalendarStatus.successEmpty, isA<EventCalendarStatus>());
      expect(EventCalendarStatus.error, isA<EventCalendarStatus>());
    });
  });
}
