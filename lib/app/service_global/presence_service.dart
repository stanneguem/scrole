import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:scrole/modules/module_authentification/centre/services/auth_service.dart';
import 'notification_service.dart';

/// Publie un heartbeat seulement lorsque l'application est au premier plan.
/// Le serveur expose le statut « en ligne » pendant 2 minutes après le dernier
/// heartbeat, ce qui tolère de courtes pauses réseau sans garder les utilisateurs
/// en ligne longtemps après la fermeture ou la mise en arrière-plan de l'app.
class PresenceService extends GetxService with WidgetsBindingObserver {
  final SupabaseClient _client = Supabase.instance.client;
  Timer? _heartbeatTimer;
  Worker? _authWorker;
  bool _isForeground = true;
  bool _sendingHeartbeat = false;
  bool _activatingPresence = false;

  static const Duration _heartbeatInterval = Duration(seconds: 45);

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    _authWorker = ever<User?>(
      Get.find<AuthService>().currentUser,
      (user) {
        if (user == null) {
          _heartbeatTimer?.cancel();
          _heartbeatTimer = null;
        } else if (_isForeground) {
          unawaited(_activatePresence());
        }
      },
    );

    if (_client.auth.currentUser != null) {
      unawaited(_activatePresence());
    }
  }

  void _startTimer() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      if (_isForeground) unawaited(_sendHeartbeat());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isForeground = state == AppLifecycleState.resumed;
    if (_isForeground && _client.auth.currentUser != null) {
      unawaited(_activatePresence());
    } else {
      _heartbeatTimer?.cancel();
      _heartbeatTimer = null;
    }
  }

  Future<void> _activatePresence() async {
    if (_activatingPresence || !_isForeground || _client.auth.currentUser == null) {
      return;
    }
    _activatingPresence = true;
    try {
      await NotificationService.instance.ensureCurrentDeviceRegistered();
      if (_isForeground && _client.auth.currentUser != null) {
        await _sendHeartbeat();
        _startTimer();
      }
    } catch (error) {
      Get.log('[Presence] Activation impossible: $error');
    } finally {
      _activatingPresence = false;
    }
  }

  Future<void> _sendHeartbeat() async {
    if (!_isForeground || _sendingHeartbeat || _client.auth.currentUser == null) {
      return;
    }
    _sendingHeartbeat = true;
    try {
      final token = await NotificationService.instance.getDeviceToken();
      if (token == null || token.isEmpty) return;
      await _client.rpc(
        'heartbeat_user_presence',
        params: {'p_device_token': token},
      );
    } catch (error) {
      // La présence est facultative : une erreur réseau ne doit pas bloquer l'app.
      Get.log('[Presence] Heartbeat non envoyé: $error');
    } finally {
      _sendingHeartbeat = false;
    }
  }

  @override
  void onClose() {
    _heartbeatTimer?.cancel();
    _authWorker?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.onClose();
  }
}
