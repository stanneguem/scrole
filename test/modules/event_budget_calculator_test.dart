import 'package:flutter_test/flutter_test.dart';
import 'package:scrole/modules/module_evenement/centre/models/event_preview_model.dart';
import 'package:scrole/modules/module_evenement/interne/controllers/event_budget_controller.dart';
import 'package:scrole/shared/utils/number_formatter.dart';

void main() {
  group('EventBudgetController Tests', () {
    test('calculates budget with 1 ticket + multiple selected activities', () {
      final controller = EventBudgetController();
      controller.tickets.addAll([
        const EventPreviewTicket(
          id: 't1',
          name: 'Pass Standard',
          price: 10000.0,
          currencyCode: 'XAF',
          converted: ConvertedPrice(amount: 10000.0, currencyCode: 'XAF', symbol: 'FCFA'),
        ),
        const EventPreviewTicket(
          id: 't2',
          name: 'Pass VIP',
          price: 25000.0,
          currencyCode: 'XAF',
          converted: ConvertedPrice(amount: 25000.0, currencyCode: 'XAF', symbol: 'FCFA'),
        ),
      ]);

      controller.activities.addAll([
        const EventPreviewActivity(
          activityId: 'a1',
          name: 'Atelier Dessin',
          price: 500.0,
          currencyCode: 'XAF',
          converted: ConvertedPrice(amount: 500.0, currencyCode: 'XAF', symbol: 'FCFA'),
        ),
        const EventPreviewActivity(
          activityId: 'a2',
          name: 'Concert Nocturne',
          price: 5000.0,
          currencyCode: 'XAF',
          converted: ConvertedPrice(amount: 5000.0, currencyCode: 'XAF', symbol: 'FCFA'),
        ),
      ]);

      controller.selectedTicket.value = controller.tickets.first;
      expect(controller.totalBudget, equals(10000.0));

      controller.toggleActivity('a1');
      expect(controller.totalBudget, equals(10500.0));

      controller.toggleActivity('a2');
      expect(controller.totalBudget, equals(15500.0));

      // Switch to VIP ticket
      controller.selectedTicket.value = controller.tickets[1];
      expect(controller.totalBudget, equals(30500.0));

      // Formatting check
      final formatted = NumberFormatter.formatPrice(controller.totalBudget, controller.currency);
      expect(formatted, contains('30 500'));
      expect(formatted, contains('FCFA'));
    });

    test('handles case with no tickets (free entry) and paid activities', () {
      final controller = EventBudgetController();
      controller.activities.add(
        const EventPreviewActivity(
          activityId: 'a1',
          name: 'Atelier Photo',
          price: 2000.0,
          currencyCode: 'XAF',
          converted: ConvertedPrice(amount: 2000.0, currencyCode: 'XAF', symbol: 'FCFA'),
        ),
      );

      expect(controller.tickets.isEmpty, isTrue);
      expect(controller.selectedTicket.value, isNull);
      expect(controller.totalBudget, equals(0.0));

      controller.toggleActivity('a1');
      expect(controller.totalBudget, equals(2000.0));
      expect(controller.currency, equals('FCFA'));
    });

    test('handles case with no tickets and no activities (free event)', () {
      final controller = EventBudgetController();

      expect(controller.tickets.isEmpty, isTrue);
      expect(controller.activities.isEmpty, isTrue);
      expect(controller.totalBudget, equals(0.0));
    });
  });
}
