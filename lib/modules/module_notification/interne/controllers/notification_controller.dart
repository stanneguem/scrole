import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../module_authentification/centre/services/auth_service.dart';
import '../../centre/services/notification_db_service.dart';
import '../../externe/repositories/notification_repository.dart';
import '../../../../app/routes/app_pages.dart';
import '../../../module_evenement/centre/repositories/event_repository.dart';
import '../../../module_decouverte/centre/models/external_profile_model.dart';
import '../../../module_decouverte/externe/repositories/external_profile_repository.dart';

class NotificationController extends GetxController {
  final NotificationDbService _service = Get.find<NotificationDbService>();
  final AuthService _authService = Get.find<AuthService>();
  final NotificationRepository _repository = NotificationRepository();
  final ExternalProfileRepository _profileRepository = ExternalProfileRepository();
  final EventRepository _eventRepository = Get.find<EventRepository>();

  final RxList<NotificationEntry> notifications = <NotificationEntry>[].obs;
  final RxInt unreadCount = 0.obs;
  final RxBool isLoading = false.obs;
  final RxBool _isProcessingOutbox = false.obs;
  Worker? _authWorker;

  @override
  void onInit() {
    super.onInit();
    _listenToNotifications();
    unawaited(_syncRemoteNotifications());
    unawaited(processOutbox());
    _authWorker = ever(_authService.currentUser, (_) {
      notifications.clear();
      unreadCount.value = 0;
      _listenToNotifications();
      unawaited(_syncRemoteNotifications());
      unawaited(processOutbox());
    });
  }

  Future<void> processOutbox() async {
    final userId = _authService.userId;
    if (userId == null || _isProcessingOutbox.value) return;

    _isProcessingOutbox.value = true;
    try {
      final pending = await _service.getPendingOutbox(userId);
      for (final item in pending) {
        final nid = item['notification_id'].toString();
        final type = item['action_type'].toString();

        try {
          if (type == 'delete') {
            await _repository.deleteNotification(nid);
          } else if (type == 'mark_read') {
            await _repository.markAsRead(nid);
          }
          await _service.removeFromOutbox(userId, nid, type);
        } catch (e) {
          debugPrint('[Sync] Outbox item $nid ($type) failed: $e');
          await _service.markOutboxAttempt(userId, nid, type);
        }
      }
    } finally {
      _isProcessingOutbox.value = false;
    }
  }

  void _listenToNotifications() {
    final userId = _authService.userId;
    if (userId == null) {
      isLoading.value = false;
      notifications.clear();
      return;
    }

    isLoading.value = true;
    try {
      final stream = _service.watchNotifications(userId);
      
      // On écoute le stream une seule fois pour mettre à jour la liste ET gérer le chargement
      notifications.bindStream(stream);
      
      // On utilise un worker 'once' pour détecter la première émission et arrêter le loader
      once(notifications, (_) => isLoading.value = false);
      
      unreadCount.bindStream(_service.watchUnreadCount(userId));
    } catch (e) {
      isLoading.value = false;
      debugPrint('[Error] Exception lors de l\'écoute des notifications: $e');
    }
  }

  // Suppression de _waitForFirstNotificationEmission qui provoquait le double listen

  Future<void> _syncRemoteNotifications() async {
    final userId = _authService.userId;
    if (userId == null) return;
    try {
      final remote = await _repository.getMyNotifications(limit: 100);
      for (final notification in remote) {
        await _service.saveNotification(
          id: notification.id,
          userId: userId,
          title: notification.title,
          message: notification.body,
          type: notification.type,
          payload: notification.localPayload,
          isRead: notification.isRead,
          createdAt: notification.createdAt,
        );
      }
    } catch (e) {
      debugPrint('[Error] Synchronisation notifications Supabase: $e');
    } finally {
      isLoading.value = false;
    }
  }

  Map<String, dynamic> payloadOf(NotificationEntry notification) {
    final payload = notification.payload;
    if (payload == null || payload.isEmpty) return const {};
    try {
      final decoded = jsonDecode(payload);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : const {};
    } catch (_) {
      return const {};
    }
  }

  String? _userIdFromNotification(NotificationEntry notification) {
    final payload = payloadOf(notification);
    final data = payload['data'];
    if (data is Map && data['user_id'] != null) return data['user_id'].toString();
    return payload['actor_id']?.toString();
  }

  String? requestIdOf(NotificationEntry notification) {
    final payload = payloadOf(notification);
    final data = payload['data'];
    return data is Map ? data['request_id']?.toString() : null;
  }

  String? photoUrlOf(NotificationEntry notification) {
    final payload = payloadOf(notification);
    final data = payload['data'];
    if (data is Map && data['photo_url'] != null) {
      final value = data['photo_url'].toString();
      if (value.isNotEmpty) return value;
    }
    return null;
  }

  Future<ExternalProfileModel?> getRequesterProfile(NotificationEntry notification) async {
    final userId = _userIdFromNotification(notification);
    if (userId == null || userId.isEmpty) return null;
    return _profileRepository.getProfile(userId);
  }

  Future<void> respondToConnectionRequest(String notificationId, String requestId, bool accept) async {
    if (requestId.isEmpty) throw ArgumentError('requestId vide');
    final userId = _authService.userId;
    if (userId == null) return;
    try {
      await _profileRepository.respondConnectionRequest(requestId, accept);
      await _service.updateActionStatus(notificationId, accept ? 'accepted' : 'refused', userId: userId);
    } catch (e, stackTrace) {
      debugPrint('[Error] Réponse demande connexion: $e');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<void> respondToTransferRequest(String notificationId, String transferId, bool accept) async {
    if (transferId.isEmpty) throw ArgumentError('transferId vide');
    final userId = _authService.userId;
    if (userId == null) return;
    try {
      await _eventRepository.respondToTransfer(transferId, accept);
      await _service.updateActionStatus(notificationId, accept ? 'accepted' : 'refused', userId: userId);
    } catch (e) {
      debugPrint('[Error] Réponse transfert: $e');
      rethrow;
    }
  }

  Future<void> respondToStaffInvitation(String notificationId, String staffId, bool accept) async {
    if (staffId.isEmpty) throw ArgumentError('staffId vide');
    final userId = _authService.userId;
    if (userId == null) return;
    try {
      await _eventRepository.respondToStaffInvitation(staffId, accept);
      await _service.updateActionStatus(notificationId, accept ? 'accepted' : 'refused', userId: userId);
    } catch (e) {
      debugPrint('[Error] Réponse invitation staff: $e');
      rethrow;
    }
  }

  Future<void> respondToGuestInvitation(String notificationId, String inviteId, bool accept) async {
    if (inviteId.isEmpty) throw ArgumentError('inviteId vide');
    final userId = _authService.userId;
    if (userId == null) return;
    try {
      await _eventRepository.respondToGuestInvite(inviteId: inviteId, accept: accept);
      await _service.updateActionStatus(notificationId, accept ? 'accepted' : 'refused', userId: userId);
    } catch (e) {
      debugPrint('[Error] Réponse invitation invité d\'honneur: $e');
      rethrow;
    }
  }

  Future<void> respondToSponsorInvitation(String notificationId, String inviteId, bool accept) async {
    if (inviteId.isEmpty) throw ArgumentError('inviteId vide');
    final userId = _authService.userId;
    if (userId == null) return;
    try {
      await _eventRepository.respondToSponsorInvite(inviteId: inviteId, accept: accept);
      await _service.updateActionStatus(notificationId, accept ? 'accepted' : 'refused', userId: userId);
    } catch (e) {
      debugPrint('[Error] Réponse invitation sponsor: $e');
      rethrow;
    }
  }

  Future<void> respondToActivityStaffInvitation(String notificationId, String inviteId, bool accept) async {
    if (inviteId.isEmpty) throw ArgumentError('inviteId vide');
    final userId = _authService.userId;
    if (userId == null) return;
    try {
      try {
        await Supabase.instance.client.rpc(
          'respond_activity_staff_invite',
          params: {'p_invite_id': inviteId, 'p_accepted': accept},
        );
      } catch (e1) {
        debugPrint('[NotificationController] respond_activity_staff_invite p_invite_id failed: $e1. Trying direct update fallback...');
        try {
          await Supabase.instance.client.rpc(
            'respond_activity_staff_invite',
            params: {'p_activity_id': inviteId, 'p_accepted': accept},
          );
        } catch (_) {
          await Supabase.instance.client.from('activity_staff').update({
            'status': accept ? 'acceptee' : 'refusee',
          }).or('id.eq.$inviteId,activity_id.eq.$inviteId');
        }
      }
      await _service.updateActionStatus(notificationId, accept ? 'accepted' : 'refused', userId: userId);
    } catch (e) {
      debugPrint('[Error] Réponse invitation staff activité: $e');
      rethrow;
    }
  }

  Future<void> respondToActivityTransferRequest(String notificationId, String transferId, bool accept) async {
    if (transferId.isEmpty) throw ArgumentError('transferId vide');
    final userId = _authService.userId;
    if (userId == null) return;
    try {
      await Supabase.instance.client.rpc(
        'respond_activity_transfer',
        params: {'p_transfer_id': transferId, 'p_accepted': accept},
      );
      await _service.updateActionStatus(notificationId, accept ? 'accepted' : 'refused', userId: userId);
    } catch (e) {
      debugPrint('[Error] Réponse transfert activité: $e');
      rethrow;
    }
  }

  Future<void> respondToCoCreatorInvitation(String notificationId, String inviteId, bool accept) async {
    if (inviteId.isEmpty) throw ArgumentError('inviteId vide');
    final userId = _authService.userId;
    if (userId == null) return;
    try {
      await _eventRepository.respondToCoCreatorInvite(inviteId, accept);
      await _service.updateActionStatus(notificationId, accept ? 'accepted' : 'refused', userId: userId);
    } catch (e) {
      debugPrint('[Error] Réponse invitation co-créateur: $e');
      rethrow;
    }
  }

  Future<void> markAsRead(String id) async {
    final userId = _authService.userId;
    if (userId == null) return;
    await _service.markAsRead(id, userId: userId);
    try {
      await _repository.markAsRead(id);
    } catch (e) {
      debugPrint('[Error] Marquage notification Supabase: $e');
    }
  }

  Future<void> markAllAsRead() async {
    final userId = _authService.userId;
    if (userId == null) return;
    await _service.markAllAsRead(userId);
    try {
      final remote = await _repository.getMyNotifications(limit: 100);
      for (final notification in remote.where((n) => !n.isRead)) {
        await _repository.markAsRead(notification.id);
      }
    } catch (e) {
      debugPrint('[Error] Marquage global notifications: $e');
    }
  }

  Future<void> deleteNotification(String id) async {
    final userId = _authService.userId;
    if (userId == null) return;
    await _service.deleteNotification(id, userId: userId);
    unawaited(processOutbox());
  }

  Future<void> deleteAllNotifications() async {
    final userId = _authService.userId;
    if (userId == null) return;
    await _service.deleteAllNotifications(userId);
    unawaited(processOutbox());
  }

  Future<void> refreshNotifications() async {
    await _syncRemoteNotifications();
    await processOutbox();
  }

  Future<void> goToEventPreview(String eventId) async {
    try {
      final event = await _eventRepository.getEventById(eventId);
      Get.toNamed(AppPages.eventPreview.replaceFirst(':id', eventId), arguments: event);
    } catch (e) {
      debugPrint('[Error] Navigation preview event: $e');
      Get.snackbar('Événement', 'Impossible de charger les détails de l\'événement.');
    }
  }

  @override
  void onClose() {
    _authWorker?.dispose();
    super.onClose();
  }
}
