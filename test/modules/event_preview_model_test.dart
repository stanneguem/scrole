import 'package:flutter_test/flutter_test.dart';
import 'package:scrole/modules/module_evenement/centre/models/event_preview_model.dart';

void main() {
  group('EventPreviewModel RPC JSON Parsing Tests', () {
    test('parses get_event_preview_public RPC response cleanly', () {
      final json = {
        'event': {
          'id': 'evt-preview-1',
          'name': 'Kamer Cosplay Championship',
          'starts_at': '2026-11-20T14:00:00Z',
          'is_free': false,
          'price': 2500.0,
          'currency': 'XAF',
        },
        'creator': {
          'user_id': 'usr-creator',
          'username': 'manga_master',
          'full_name': 'Manga Master',
          'photo_url': 'https://example.com/avatar.png',
        },
        'can_view': true,
        'can_view_public_preview': true,
        'viewer_role': 'public',
        'message': null,
        'can_access': true,
        'can_interact': true,
        'can_like': true,
        'can_comment': true,
        'can_rate': true,
        'can_share': true,
        'can_add_to_calendar': true,
        'can_register': true,
        'cheapest_ticket': {
          'id': 'tkt-1',
          'name': 'Pass Standard',
          'price': 2500.0,
          'currency_code': 'XAF',
          'converted': {
            'amount': 2500.0,
            'currency_code': 'XAF',
            'symbol': 'FCFA',
          },
        },
        'activities_liees': [
          {
            'activity_id': 'act-1',
            'name': 'Concours Dessin',
            'price': 1000.0,
            'currency_code': 'XAF',
            'converted': {
              'amount': 1000.0,
              'currency_code': 'XAF',
              'symbol': 'FCFA',
            },
          }
        ],
        'amis_dans_agenda_photos': [
          'https://example.com/friend1.png',
          'https://example.com/friend2.png',
        ],
        'amis_dans_agenda_count': 2,
        'classement': {
          'rang': 1,
          'sur': 50,
          'score': 98.5,
        },
        'prestige_score': 95.0,
        'prestige_stars': 4.8,
        'likes_count': 150,
        'attendee_count': 45,
        'is_liked_by_me': true,
        'is_in_my_calendar': false,
      };

      final model = EventPreviewModel.fromJson(json);

      expect(model.event.id, equals('evt-preview-1'));
      expect(model.event.name, equals('Kamer Cosplay Championship'));
      expect(model.canViewPublicPreview, isTrue);
      expect(model.viewerRole, equals('public'));
      expect(model.cheapestTicket, isNotNull);
      expect(model.cheapestTicket!.converted.amount, equals(2500.0));
      expect(model.cheapestTicket!.converted.symbol, equals('FCFA'));
      expect(model.activitiesLiees.length, equals(1));
      expect(model.activitiesLiees.first.converted.amount, equals(1000.0));
      expect(model.amisDansAgendaPhotos.length, equals(2));
      expect(model.ranking.rang, equals(1));
      expect(model.prestigeScore, equals(95.0));
      expect(model.prestigeStars, equals(4.8));
      expect(model.attendeeCount, equals(45));
      expect(model.isLikedByMe, isTrue);
    });

    test('parses restricted can_view_public_preview == false payload correctly', () {
      final json = {
        'event': {
          'id': 'evt-preview-owner',
          'name': 'Evénement Privé Organisateur',
        },
        'can_view': true,
        'can_view_public_preview': false,
        'viewer_role': 'owner',
        'message': 'En tant qu’organisateur, veuillez utiliser le tableau de bord de gestion.',
      };

      final model = EventPreviewModel.fromJson(json);

      expect(model.canViewPublicPreview, isFalse);
      expect(model.viewerRole, equals('owner'));
      expect(model.message, contains('organisateur'));
    });
  });
}
