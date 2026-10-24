import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../app/service_global/connectivity_service.dart';
import '../../../../app/service_global/supabse_service.dart';
import '../persistence/social_local_dao.dart';
import '../../externe/repositories/social_repository.dart';

class SocialOutboxProcessor extends GetxService {
  final SocialLocalDao _dao;
  final ConnectivityService _connectivity;
  final SupabaseClient _client = Get.find<SupabaseService>().client;

  StreamSubscription<InternetStatus>? _connectivitySub;
  bool _isProcessing = false;

  SocialOutboxProcessor(this._dao, this._connectivity);

  @override
  void onInit() {
    super.onInit();
    _listenConnectivity();
  }

  void _listenConnectivity() {
    _connectivitySub = _connectivity.onStatusChange.listen((status) {
      if (status == InternetStatus.connected) {
        final userId = _client.auth.currentUser?.id;
        if (userId != null) {
          SocialRepository.invalidateRelationshipCache();
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

      debugPrint('[SocialOutbox] Processing ${pendingItems.length} pending items for $userId...');

      for (final item in pendingItems) {
        final id = item['id'] as int;
        final operation = item['operation'] as String;
        final payloadRaw = item['payload'] as String;
        final attempts = (item['attempts'] as int? ?? 0) + 1;

        Map<String, dynamic> payload = {};
        try {
          payload = jsonDecode(payloadRaw) as Map<String, dynamic>;
        } catch (_) {}

        try {
          await _executeOperation(operation: operation, payload: payload);
          await _dao.removeFromOutbox(id);
          debugPrint('[SocialOutbox] Item $id ($operation) processed successfully.');
        } on PostgrestException catch (pe) {
          final msg = pe.message;
          final code = pe.code;
          debugPrint('[SocialOutbox Error] PostgrestException on item $id ($operation): $msg (code: $code)');

          if (_isIdempotentSuccess(operation, msg, code)) {
            debugPrint('[SocialOutbox] Treating idempotent error as SUCCESS for item $id ($operation)');
            await _dao.removeFromOutbox(id);
          } else {
            await _dao.updateOutboxAttempts(id, attempts, msg);
            if (attempts >= 3 && operation != 'generate_user_qr_code') {
              await _dao.removeFromOutbox(id);
            }
          }
        } catch (e) {
          final errorMsg = e.toString();
          debugPrint('[SocialOutbox Error] Generic error on item $id ($operation): $errorMsg');
          await _dao.updateOutboxAttempts(id, attempts, errorMsg);
          if (attempts >= 3 && operation != 'generate_user_qr_code') {
            await _dao.removeFromOutbox(id);
          }
        }
      }
    } finally {
      _isProcessing = false;
    }
  }

  bool _isIdempotentSuccess(String operation, String message, String? code) {
    if (code == '23505') return true; // Unique constraint violation

    final msgLower = message.toLowerCase();
    if (msgLower.contains('une demande est déjà en attente') ||
        msgLower.contains('déjà ami') ||
        msgLower.contains('déjà été traitée') ||
        msgLower.contains('demande introuvable ou déjà traitée') ||
        msgLower.contains('pas ami')) {
      return true;
    }
    return false;
  }

  Future<dynamic> _followRpc(String rpc, Map<String, dynamic> params) async {
    debugPrint('[FOLLOW] RPC $rpc params=$params');
    try {
      final response = await _client.rpc(rpc, params: params);
      debugPrint('[FOLLOW] RPC $rpc response=$response');
      return response;
    } catch (e, stack) {
      debugPrint('[FOLLOW] RPC $rpc exception=$e\\n$stack');
      rethrow;
    }
  }

  Future<void> _executeOperation({
    required String operation,
    required Map<String, dynamic> payload,
  }) async {
    switch (operation) {
      case 'follow_user':
      case 'send_friend_request':
        final userId = (payload['p_user_id'] ?? payload['receiver_id'])?.toString();
        if (userId == null || userId.isEmpty) throw StateError('p_user_id manquant');
        await _followRpc('follow_user', {'p_user_id': userId});
        break;

      case 'unfollow_user':
        await _followRpc('unfollow_user', {'p_user_id': payload['p_user_id']});
        break;

      case 'cancel_follow_request':
      case 'cancel_friend_request':
        final userId = (payload['p_user_id'] ?? payload['target_user_id'])?.toString();
        if (userId == null || userId.isEmpty) throw StateError('p_user_id manquant');
        await _followRpc('cancel_follow_request', {'p_user_id': userId});
        break;

      case 'respond_follow_request':
      case 'respond_friend_request':
        await _followRpc('respond_follow_request', {
          'p_request_id': payload['p_request_id'] ?? payload['request_id'],
          'p_accepted': payload['p_accepted'] ?? payload['accepted'],
        });
        break;

      case 'remove_follower':
        await _followRpc('remove_follower', {'p_user_id': payload['p_user_id']});
        break;

      case 'remove_friend':
      case 'remove_friendship':
        final userId = (payload['p_user_id'] ?? payload['other_user_id'])?.toString();
        if (userId == null || userId.isEmpty) throw StateError('p_user_id manquant');
        await _followRpc('remove_friend', {'p_user_id': userId});
        break;

      case 'generate_user_qr_code':
        final qrId = payload['id'] as String;
        await _client.rpc('generate_user_qr_code', params: {'p_id': qrId});
        await _dao.updateUserQrCodeSyncStatus(qrId, 'synced');
        break;

      case 'scan_qr_code':
        final qrId = payload['qr_id'] as String;
        await _followRpc('scan_qr_code', {'p_qr_id': qrId, 'p_mode': null});
        break;

      case 'block_user':
        final targetId = payload['bloque_id'] as String;
        final reason = payload['raison'] as String?;
        final until = payload['bloque_jusquau'] as String?;
        // Nettoyer les liens dans les deux sens avant d'enregistrer le blocage.
        for (final rpc in ['unfollow_user', 'remove_follower', 'cancel_follow_request', 'remove_friend']) {
          try {
            await _followRpc(rpc, {'p_user_id': targetId});
          } catch (e, stack) {
            debugPrint('[FOLLOW] RPC $rpc pendant blocage exception=$e\\n$stack');
          }
        }
        await _client.from('blocage_utilisateur').insert({
          'bloqueur_id': _client.auth.currentUser?.id,
          'bloque_id': targetId,
          if (reason != null && reason.isNotEmpty) 'raison': reason,
          if (until != null && until.isNotEmpty) 'bloque_jusquau': until,
        });
        break;

      case 'unblock_user':
        final targetId = payload['bloque_id'] as String;
        await _client
            .from('blocage_utilisateur')
            .delete()
            .eq('bloqueur_id', _client.auth.currentUser?.id ?? '')
            .eq('bloque_id', targetId);
        break;

      default:
        debugPrint('[SocialOutbox Warning] Unknown operation: $operation');
        break;
    }
  }

  @override
  void onClose() {
    _connectivitySub?.cancel();
    super.onClose();
  }
}
