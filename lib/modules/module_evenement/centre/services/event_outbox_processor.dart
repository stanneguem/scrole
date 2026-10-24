import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../app/service_global/connectivity_service.dart';
import '../persistence/evenement_local_dao.dart';
import '../../externe/services/supabase_event_service.dart';

class EventOutboxProcessor extends GetxService {
  final EvenementLocalDao _dao;
  final SupabaseEventService _remote;
  final ConnectivityService _connectivity;

  StreamSubscription<InternetStatus>? _connectivitySub;
  bool _isProcessing = false;

  EventOutboxProcessor(this._dao, this._remote, this._connectivity);

  @override
  void onInit() {
    super.onInit();
    _listenConnectivity();
  }

  void _listenConnectivity() {
    _connectivitySub = _connectivity.onStatusChange.listen((status) {
      if (status == InternetStatus.connected) {
        final userId = _remote.client.auth.currentUser?.id;
        if (userId != null) {
          processPendingOutbox(userId);
        }
      }
    });
  }

  Future<void> processPendingOutbox(String userId) async {
    if (_isProcessing) return;
    if (!_connectivity.isConnected.value) return;

    _isProcessing = true;
    try {
      final pendingItems = await _dao.getPendingOutbox(userId);
      if (pendingItems.isEmpty) return;

      debugPrint('[Outbox] Processing ${pendingItems.length} pending event outbox items for user $userId...');

      for (final item in pendingItems) {
        final id = item['id'] as int;
        final eventId = item['event_id'] as String;
        final tableName = item['table_name'] as String;
        final operation = item['operation'] as String;
        final payloadRaw = item['payload'] as String;
        final attempts = (item['attempts'] as int? ?? 0) + 1;

        Map<String, dynamic> payload = {};
        try {
          payload = jsonDecode(payloadRaw) as Map<String, dynamic>;
        } catch (_) {}

        try {
          await _executeOperation(
            eventId: eventId,
            tableName: tableName,
            operation: operation,
            payload: payload,
          );

          // Success -> remove from outbox and mark local record as synced
          await _dao.removeFromOutbox(id);
          if (eventId.isNotEmpty) {
            await _dao.updateEventSyncStatusStructured(eventId, 'synced');
          }
          debugPrint('[Outbox] Successfully processed item $id ($operation on $tableName)');
        } on PostgrestException catch (pe) {
          final errorMsg = pe.message;
          debugPrint('[Outbox Error] PostgrestException on item $id ($operation): $errorMsg');

          await _dao.updateOutboxAttempts(id, attempts, errorMsg);
          if (eventId.isNotEmpty) {
            await _dao.updateEventSyncStatusStructured(eventId, 'rejected', error: errorMsg);
          }
          // Remove from outbox on definitive RPC rejection to avoid endless retry loop
          await _dao.removeFromOutbox(id);
        } catch (e) {
          final errorMsg = e.toString();
          debugPrint('[Outbox Error] Generic error on item $id ($operation): $errorMsg');

          await _dao.updateOutboxAttempts(id, attempts, errorMsg);
          if (attempts >= 5) {
            if (eventId.isNotEmpty) {
              await _dao.updateEventSyncStatusStructured(eventId, 'rejected', error: errorMsg);
            }
            await _dao.removeFromOutbox(id);
          }
        }
      }
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _executeOperation({
    required String eventId,
    required String tableName,
    required String operation,
    required Map<String, dynamic> payload,
  }) async {
    switch (operation) {
      case 'create_event':
        await _remote.createEvent(payload);
        break;

      case 'update_event':
        await _remote.updateEvent(eventId, payload);
        break;

      case 'delete_event':
        await _remote.deleteEvent(eventId);
        break;

      case 'add_to_calendar':
        await _remote.addEventToCalendar(eventId);
        break;

      case 'remove_from_calendar':
        await _remote.removeEventFromCalendar(eventId);
        break;

      case 'invite_staff':
        final userId = payload['p_user_id'] as String? ?? payload['user_id'] as String;
        final activityIds = (payload['p_activity_ids'] as List?)?.cast<String>() ?? [];
        await _remote.inviteStaff(eventId: eventId, userId: userId, activityIds: activityIds);
        break;

      case 'respond_staff_invite':
        final inviteId = payload['p_invite_id'] as String? ?? payload['invite_id'] as String;
        final accepted = payload['p_accepted'] as bool? ?? payload['accepted'] as bool? ?? false;
        await _remote.respondToStaffInvitation(staffEvenementId: inviteId, accept: accepted);
        break;

      case 'invite_co_creator':
        final userId = payload['p_user_id'] as String? ?? payload['user_id'] as String;
        await _remote.inviteCoCreator(eventId: eventId, userId: userId);
        break;

      case 'respond_co_creator_invite':
        final inviteId = payload['p_invite_id'] as String? ?? payload['invite_id'] as String;
        final accepted = payload['p_accepted'] as bool? ?? payload['accepted'] as bool? ?? false;
        await _remote.respondToCoCreatorInvite(inviteId: inviteId, accept: accepted);
        break;

      case 'propose_transfer':
        final targetUserId = payload['p_to_user_id'] as String? ?? payload['to_user_id'] as String;
        await _remote.proposeTransfer(eventId: eventId, targetUserId: targetUserId);
        break;

      case 'respond_transfer':
        final transferId = payload['p_transfer_id'] as String? ?? payload['transfer_id'] as String;
        final accepted = payload['p_accepted'] as bool? ?? payload['accepted'] as bool? ?? false;
        await _remote.respondToTransfer(transferId: transferId, accept: accepted);
        break;

      case 'checkin_scan':
        final userId = payload['p_user_id'] as String? ?? payload['user_id'] as String;
        final activityId = payload['p_activity_id'] as String?;
        await _remote.scanEventCheckin(eventId: eventId, userId: userId, activityId: activityId);
        break;

      case 'add_activity':
        final activityId = payload['p_activity_id'] as String? ?? payload['activity_id'] as String;
        final price = (payload['p_price'] as num? ?? payload['price'] as num? ?? 0).toDouble();
        final currency = payload['currency'] as String? ?? 'XAF';
        await _remote.addActivityToEvent(eventId: eventId, activityId: activityId, price: price, currency: currency);
        break;

      case 'remove_activity':
        final activityId = payload['p_activity_id'] as String? ?? payload['activity_id'] as String? ?? payload['id'] as String;
        await _remote.removeActivityFromEvent(eventId: eventId, activityId: activityId);
        break;

      case 'update_interests':
        final interestIds = (payload['p_interest_ids'] as List?)?.cast<String>() ?? [];
        await _remote.updateEventInterests(eventId: eventId, interestIds: interestIds);
        break;

      case 'link_community':
        final communityId = payload['p_community_id'] as String;
        await _remote.linkEventToCommunity(eventId: eventId, communityId: communityId);
        break;

      case 'add_ticket':
        await _remote.addTicket(payload);
        break;

      case 'delete_ticket':
        final ticketId = payload['id'] as String;
        await _remote.deleteTicket(ticketId);
        break;

      default:
        debugPrint('[Outbox Warning] Unknown operation $operation for table $tableName');
        break;
    }
  }

  @override
  void onClose() {
    _connectivitySub?.cancel();
    super.onClose();
  }
}
