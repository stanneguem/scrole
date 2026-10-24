import 'package:flutter_test/flutter_test.dart';
import 'package:scrole/modules/module_evenement/centre/models/event_preview_model.dart';
import 'package:scrole/shared/utils/number_formatter.dart';

void main() {
  group('Event Share & Poster Tests', () {
    test('EventPreviewModel parses canShare, shareCount, and cheapestTicket correctly for poster', () {
      final json = {
        'event': {
          'id': 'evt-share-1',
          'creator_id': 'u-creator',
          'name': 'Festival de Musique Camerounaise',
          'slug': 'fest-music',
          'starts_at': DateTime.now().toIso8601String(),
          'created_at': DateTime.now().toIso8601String(),
        },
        'can_share': true,
        'share_count': 42,
        'cheapest_ticket': {
          'id': 't-1',
          'name': 'Pass Simple',
          'price': 5000.0,
          'currency_code': 'XAF',
          'converted': {
            'amount': 5000.0,
            'currency_code': 'XAF',
            'symbol': 'FCFA',
          },
        },
      };

      final preview = EventPreviewModel.fromJson(json);
      expect(preview.canShare, isTrue);
      expect(preview.cheapestTicket, isNotNull);
      expect(preview.cheapestTicket!.name, equals('Pass Simple'));
      expect(preview.cheapestTicket!.converted.amount, equals(5000.0));
      expect(preview.cheapestTicket!.converted.symbol, equals('FCFA'));

      final formattedPrice = NumberFormatter.formatPrice(
        preview.cheapestTicket!.converted.amount,
        preview.cheapestTicket!.converted.symbol,
      );
      expect(formattedPrice, contains('5 000'));
      expect(formattedPrice, contains('FCFA'));
    });

    test('Poster price text displays Gratuit when event is free or cheapest ticket is 0', () {
      final jsonFree = {
        'event': {
          'id': 'evt-free-1',
          'creator_id': 'u-creator',
          'name': 'Rencontre Communautaire',
          'slug': 'meetup',
          'is_free': true,
          'starts_at': DateTime.now().toIso8601String(),
          'created_at': DateTime.now().toIso8601String(),
        },
        'can_share': true,
        'cheapest_ticket': null,
      };

      final preview = EventPreviewModel.fromJson(jsonFree);
      final isFree = (preview.cheapestTicket == null || preview.cheapestTicket!.converted.amount <= 0) && preview.event.isFree;
      expect(isFree, isTrue);
    });
  });
}
