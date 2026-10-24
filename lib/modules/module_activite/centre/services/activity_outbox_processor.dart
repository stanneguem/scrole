import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import '../../../../app/local_storage/structured/app_cache_database.dart';
import '../../../module_authentification/centre/services/auth_service.dart';
import '../../externe/repositories/activity_repository.dart';
import '../models/activity_cache_entity.dart';
import '../persistence/activity_local_dao.dart';

/// Service indépendant chargé d'exécuter les mutations de la file Outbox
/// selon la spécification (§20, §21, §22, §27).
class ActivityOutboxProcessor extends GetxService {
  final ActivityRepository _repository = ActivityRepository();
  final AuthService _authService = Get.find<AuthService>();
  late final ActivityLocalDao _dao = ActivityLocalDao(Get.find<AppDatabase>());

  final RxBool isProcessing = false.obs;
  Timer? _pollingTimer;

  @override
  void onInit() {
    super.onInit();
    // Polling régulier pour traiter l'outbox quand du réseau est disponible
    _pollingTimer = Timer.periodic(const Duration(seconds: 15), (_) => processPendingOperations());
    unawaited(processPendingOperations());
  }

  @override
  void onClose() {
    _pollingTimer?.cancel();
    super.onClose();
  }

  /// Traite la file d'attente pour l'utilisateur actuellement authentifié (§27)
  Future<void> processPendingOperations() async {
    final currentUserId = _authService.userId;
    if (currentUserId == null || isProcessing.value) return;

    isProcessing.value = true;
    try {
      final pendingList = await _dao.getPendingOutboxOperations(currentUserId);
      for (final item in pendingList) {
        final id = (item['id'] as num).toInt();
        final operationId = item['operation_id'].toString();
        final viewerUserId = item['viewer_user_id'].toString();
        final activityId = item['activity_id'].toString();
        final operationType = item['operation_type'].toString();
        final attempts = (item['attempt_count'] as num).toInt();
        final payload = Map<String, dynamic>.from(jsonDecode(item['payload'].toString()));

        // Vérification de sécurité multi-compte (§27)
        if (viewerUserId != currentUserId) continue;

        // Verrouillage de l'opération
        await _dao.lockOutboxOperation(id);

        try {
          debugPrint('[ActivityOutboxProcessor] Executing operationId=$operationId type=$operationType for activityId=$activityId');

          await _executeOperation(
            operationType: operationType,
            activityId: activityId,
            viewerUserId: viewerUserId,
            payload: payload,
          );

          // Succès -> Marquer comme complété et supprimer de l'Outbox
          await _dao.markOutboxOperationCompleted(id);

          // Réconciliation post-mutation : refetch pour obtenir la donnée fraîche convertie (§32)
          await _reconcileActivityCache(viewerUserId, activityId);

        } catch (e) {
          final errStr = e.toString();
          debugPrint('[ActivityOutboxProcessor] Operation $operationId failed: $errStr');

          if (_isTerminalError(e)) {
            // Erreur définitive (section 22) -> Marquer comme failed
            await _dao.markOutboxOperationFailed(id: id, lastError: errStr);
          } else {
            // Erreur temporaire -> Calcul du backoff retry (section 21)
            final nextAttempt = attempts + 1;
            final retryDelay = _calculateBackoffDelay(nextAttempt);
            final nextRetryAt = DateTime.now().add(retryDelay).millisecondsSinceEpoch;

            await _dao.markOutboxOperationRetry(
              id: id,
              attemptCount: nextAttempt,
              nextRetryAt: nextRetryAt,
              lastError: errStr,
            );
          }
        }
      }
    } finally {
      isProcessing.value = false;
    }
  }

  Future<void> _executeOperation({
    required String operationType,
    required String activityId,
    required String viewerUserId,
    required Map<String, dynamic> payload,
  }) async {
    switch (operationType) {
      case 'create_activity':
        await _repository.createActivityRpc(
          id: activityId,
          name: payload['name'].toString(),
          basePrice: (payload['base_price'] as num?)?.toDouble() ?? 0.0,
          currencyCode: payload['currency_code']?.toString() ?? 'XAF',
          eventOnly: payload['event_only'] == true,
        );
        break;

      case 'update_activity':
        await _repository.updateActivityRpc(
          id: activityId,
          name: payload['name']?.toString(),
          description: payload['description']?.toString(),
          basePrice: (payload['base_price'] as num?)?.toDouble(),
          currencyCode: payload['currency_code']?.toString(),
          eventOnly: payload['event_only'] as bool?,
        );
        break;

      case 'request_activity_deletion':
        await _repository.requestActivityDeletionRpc(activityId);
        break;

      case 'cancel_activity_deletion':
        await _repository.cancelActivityDeletionRpc(activityId);
        break;

      case 'add_activity_to_event':
        final eventId = payload['event_id'].toString();
        final price = (payload['price'] as num?)?.toDouble() ?? 0.0;
        await _repository.addActivityToEventRpc(eventId: eventId, activityId: activityId, price: price);
        break;

      case 'remove_activity_from_event':
        final eventId = payload['event_id'].toString();
        await _repository.removeActivityFromEventRpc(eventId: eventId, activityId: activityId);
        break;

      case 'invite_activity_staff':
        final targetUserId = payload['target_user_id'].toString();
        await _repository.inviteActivityStaffRpc(activityId, targetUserId);
        break;

      case 'cancel_activity_staff_invite':
        final targetUserId = payload['target_user_id'].toString();
        await _repository.cancelActivityStaffInviteRpc(activityId, targetUserId);
        break;

      case 'respond_activity_staff_invite':
        final inviteId = payload['invite_id']?.toString() ?? activityId;
        final accepted = payload['accepted'] == true;
        await _repository.client.rpc('respond_activity_staff_invite', params: {
          'p_invite_id': inviteId,
          'p_accepted': accepted,
        });
        break;

      case 'remove_activity_staff':
        final targetUserId = payload['target_user_id'].toString();
        await _repository.removeActivityStaffRpc(activityId, targetUserId);
        break;

      case 'leave_activity_staff':
        await _repository.leaveActivityStaffRpc(activityId);
        break;

      default:
        debugPrint('[ActivityOutboxProcessor] Unknown operationType: $operationType');
        break;
    }
  }

  Future<void> _reconcileActivityCache(String viewerUserId, String activityId) async {
    try {
      final rawPreview = await _repository.getActivityPreviewRpc(activityId);
      final activityMap = rawPreview['activity'] is Map ? Map<String, dynamic>.from(rawPreview['activity'] as Map) : rawPreview;
      final entity = ActivityCacheEntity.fromRpcJson(viewerUserId: viewerUserId, json: activityMap);
      await _dao.saveActivityCache(entity);
    } catch (e) {
      debugPrint('[ActivityOutboxProcessor] Reconcile error: $e');
    }
  }

  bool _isTerminalError(dynamic error) {
    final str = error.toString().toLowerCase();
    return str.contains('permission denied') ||
        str.contains('not found') ||
        str.contains('not owner') ||
        str.contains('already accepted') ||
        str.contains('invalid parameters') ||
        str.contains('déjà supprimée') ||
        str.contains('deja supprimee') ||
        str.contains('ne peut pas être restaurée') ||
        str.contains('p0001') ||
        str.contains('42501') ||
        str.contains('23505') ||
        str.contains('400') ||
        str.contains('403') ||
        str.contains('404') ||
        str.contains('409') ||
        str.contains('422');
  }

  Duration _calculateBackoffDelay(int attempt) {
    switch (attempt) {
      case 1:
        return const Duration(seconds: 5);
      case 2:
        return const Duration(seconds: 15);
      case 3:
        return const Duration(seconds: 30);
      case 4:
        return const Duration(minutes: 1);
      case 5:
        return const Duration(minutes: 5);
      default:
        return Duration(minutes: 5 + (attempt - 5) * 5);
    }
  }
}
