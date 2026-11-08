import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../centre/models/event_preview_model.dart';

class EventBudgetController extends GetxController {
  String? _eventId;
  late final String _sessionId;
  late final DateTime _openedAt;
  final RxBool isSaving = false.obs;

  Future<void> _recordAnalytics(
    String action, {
    Map<String, dynamic> metadata = const {},
  }) async {
    final client = Supabase.instance.client;
    if (_eventId == null || _eventId!.isEmpty || client.auth.currentUser == null) return;
    try {
      await client.rpc('record_event_analytics_event', params: {
        'p_event_id': _eventId,
        'p_action': action,
        'p_metadata': {'session_id': _sessionId, ...metadata},
      });
    } catch (error) {
      debugPrint('[EventBudgetController] analytics $action failed: $error');
    }
  }

  final List<EventPreviewTicket> tickets = <EventPreviewTicket>[];
  final List<EventPreviewActivity> activities = <EventPreviewActivity>[];

  final Rx<EventPreviewTicket?> selectedTicket = Rx<EventPreviewTicket?>(null);
  final RxList<String> selectedActivityIds = <String>[].obs;

  String _newUuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
  }

  @override
  void onInit() {
    super.onInit();
    _sessionId = _newUuid();
    _openedAt = DateTime.now();

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
      final savedTicketId = args['selectedTicketId']?.toString();
      if (savedTicketId != null && savedTicketId.isNotEmpty) {
        selectedTicket.value = tickets.firstWhereOrNull((ticket) => ticket.id == savedTicketId) ?? selectedTicket.value;
      }
      final savedActivityIds = args['selectedActivityIds'];
      if (savedActivityIds is List) {
        selectedActivityIds.addAll(savedActivityIds.map((id) => id.toString())
          .where((id) => activities.any((activity) => activity.activityId == id)));
      }
    }

    if (selectedTicket.value == null && tickets.isNotEmpty) {
      selectedTicket.value = tickets.first;
    }
    if (_eventId != null && _eventId!.isNotEmpty) {
      _recordAnalytics('simulation_open');
      final initialTicket = selectedTicket.value;
      if (initialTicket != null) {
        _recordAnalytics('simulation_ticket_selected', metadata: {
          'ticket_id': initialTicket.id,
          'estimated_total': totalBudget,
          'currency': currency,
        });
      }
    }
  }

  void selectTicket(EventPreviewTicket ticket) {
    if (selectedTicket.value?.id == ticket.id) return;
    selectedTicket.value = ticket;
    _recordAnalytics('simulation_ticket_selected', metadata: {
      'ticket_id': ticket.id,
      'estimated_total': totalBudget,
      'currency': currency,
    });
  }

  void toggleActivity(String activityId) {
    final wasSelected = selectedActivityIds.contains(activityId);
    if (wasSelected) {
      selectedActivityIds.remove(activityId);
    } else {
      selectedActivityIds.add(activityId);
    }
    _recordAnalytics(
      wasSelected ? 'simulation_activity_deselected' : 'simulation_activity_selected',
      metadata: {
        'activity_ids': [activityId],
        'estimated_total': totalBudget,
        'currency': currency,
      },
    );
  }

  Future<bool> completeSimulation() async {
    if (_eventId == null || _eventId!.isEmpty) {
      Get.snackbar('event_budget_save_error_title'.tr, 'event_budget_save_error_missing_event'.tr);
      return false;
    }
    if (Supabase.instance.client.auth.currentUser == null) {
      Get.snackbar('event_budget_save_error_title'.tr, 'event_budget_save_error_auth'.tr);
      return false;
    }
    if (isSaving.value) return false;

    isSaving.value = true;
    try {
      await Supabase.instance.client.rpc('record_event_preview_session', params: {
        'p_session_id': _sessionId,
        'p_event_id': _eventId,
        'p_opened_at': _openedAt.toUtc().toIso8601String(),
        'p_closed_at': DateTime.now().toUtc().toIso8601String(),
        'p_selected_ticket_id': selectedTicket.value?.id,
        'p_selected_activity_ids': selectedActivityIds.toList(),
      });

      await _recordAnalytics('simulation_completed', metadata: {
        'ticket_id': selectedTicket.value?.id,
        'activity_ids': selectedActivityIds.toList(),
        'estimated_total': totalBudget,
        'currency': currency,
      });
      return true;
    } catch (error) {
      debugPrint('[EventBudgetController] saving simulation failed: $error');
      Get.snackbar('event_budget_save_error_title'.tr, 'event_budget_save_error_message'.tr);
      return false;
    } finally {
      isSaving.value = false;
    }
  }

  double get totalBudget {
    double total = selectedTicket.value?.converted.amount ?? 0.0;
    for (final id in selectedActivityIds) {
      final act = activities.firstWhereOrNull((a) => a.activityId == id);
      if (act != null) total += act.converted.amount;
    }
    return total;
  }

  String get currency {
    if (selectedTicket.value != null) return selectedTicket.value!.converted.symbol;
    if (tickets.isNotEmpty) return tickets.first.converted.symbol;
    if (activities.isNotEmpty) return activities.first.converted.symbol;
    return 'FCFA';
  }
}
