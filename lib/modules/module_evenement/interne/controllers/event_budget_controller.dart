import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../centre/models/event_preview_model.dart';

class EventBudgetController extends GetxController {
  String? _eventId;

  Future<void> _recordAnalytics(String action, {Map<String, dynamic> metadata = const {}}) async {
    final client = Supabase.instance.client;
    if (_eventId == null || _eventId!.isEmpty || client.auth.currentUser == null) return;
    try {
      await client.rpc('record_event_analytics_event', params: {
        'p_event_id': _eventId,
        'p_action': action,
        'p_metadata': metadata,
      });
    } catch (error) {
      debugPrint('[EventBudgetController] analytics $action failed: $error');
    }
  }
  final List<EventPreviewTicket> tickets = <EventPreviewTicket>[];
  final List<EventPreviewActivity> activities = <EventPreviewActivity>[];

  final Rx<EventPreviewTicket?> selectedTicket = Rx<EventPreviewTicket?>(null);
  final RxList<String> selectedActivityIds = <String>[].obs;

  @override
  void onInit() {
    super.onInit();
    final args = Get.arguments;
    if (args is Map) {
      _eventId = (args['eventId'] ?? args['event_id'])?.toString();
      if (args['tickets'] is List) {
        tickets.clear();
        tickets.addAll((args['tickets'] as List).whereType<EventPreviewTicket>());
      }
      if (args['activities'] is List) {
        activities.clear();
        activities.addAll((args['activities'] as List).whereType<EventPreviewActivity>());
      }
      if (args['cheapestTicket'] is EventPreviewTicket) {
        selectedTicket.value = args['cheapestTicket'] as EventPreviewTicket;
      }
    }

    if (selectedTicket.value == null && tickets.isNotEmpty) {
      selectedTicket.value = tickets.first;
    }
    if (_eventId != null && _eventId!.isNotEmpty) {
      _recordAnalytics('simulation_open');
    }
  }

  void selectTicket(EventPreviewTicket ticket) {
    selectedTicket.value = ticket;
    if (_eventId != null) {
      _recordAnalytics('simulation_ticket_selected', metadata: {'ticket_id': ticket.id});
    }
  }

  void toggleActivity(String activityId) {
    if (selectedActivityIds.contains(activityId)) {
      selectedActivityIds.remove(activityId);
    } else {
      selectedActivityIds.add(activityId);
      if (_eventId != null) {
        _recordAnalytics('simulation_activity_selected', metadata: {'activity_ids': [activityId]});
      }
    }
  }

  void completeSimulation() {
    if (_eventId == null || _eventId!.isEmpty) return;
    _recordAnalytics('simulation_completed', metadata: {
      'ticket_id': selectedTicket.value?.id,
      'activity_ids': selectedActivityIds.toList(),
      'estimated_total': totalBudget,
      'currency': currency,
    });
  }

  double get totalBudget {
    double total = selectedTicket.value?.converted.amount ?? 0.0;
    for (final id in selectedActivityIds) {
      final act = activities.firstWhereOrNull((a) => a.activityId == id);
      if (act != null) {
        total += act.converted.amount;
      }
    }
    return total;
  }

  String get currency {
    if (selectedTicket.value != null) {
      return selectedTicket.value!.converted.symbol;
    }
    if (tickets.isNotEmpty) {
      return tickets.first.converted.symbol;
    }
    if (activities.isNotEmpty) {
      return activities.first.converted.symbol;
    }
    return 'FCFA';
  }
}
