import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../module_authentification/centre/services/auth_service.dart';
import '../../../module_notification/externe/repositories/fcm_token_repository.dart';
import '../../centre/repositories/messaging_repository.dart';

class FcmNotificationService with WidgetsBindingObserver {
  FcmNotificationService(this._repository)
    : _tokenRepository = FcmTokenRepository(Supabase.instance.client);

  final MessagingRepository _repository;
  final FcmTokenRepository _tokenRepository;
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  StreamSubscription<RemoteMessage>? _openedSubscription;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<String>? _tokenSubscription;
  Worker? _authWorker;

  Future<void> initialize() async {
    WidgetsBinding.instance.addObserver(this);

    if (!kIsWeb) {
      _openedSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
        (_) => _wakeSync(),
      );
      _foregroundSubscription = FirebaseMessaging.onMessage.listen((message) {
        unawaited(
          _repository.handlePushWake(message.data['conversation_id']?.toString()),
        );
      });
      _tokenSubscription = _fcm.onTokenRefresh.listen(
        (token) => _registerToken(token),
      );
    }
    try {
      final auth = Get.find<AuthService>();
      _authWorker = ever(auth.currentUser, (_) {
        unawaited(_registerCurrentToken());
        unawaited(_wakeSync());
      });
    } catch (_) {}
    await _registerCurrentToken();
    await _wakeSync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('[FCM] App resumed, triggering wake sync...');
      _wakeSync();
    }
  }

  Future<void> _registerCurrentToken() async {
    if (kIsWeb || _repository.currentUserId == null) return;
    try {
      final token = await _fcm.getToken();
      if (token != null) await _registerToken(token);
    } catch (_) {}
  }

  Future<void> _registerToken(String token) async {
    if (kIsWeb || _repository.currentUserId == null) return;
    try {
      await _tokenRepository.registerToken(
        token: token,
        platform:
            defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
      );
    } catch (_) {}
  }

  Future<void> _wakeSync() async {
    if (_repository.currentUserId == null) return;
    // On réveille la synchro complète (conversations + messages manqués)
    await _repository.handlePushWake(null);
    await _repository.processOutbox();
  }

  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    await _openedSubscription?.cancel();
    await _foregroundSubscription?.cancel();
    await _tokenSubscription?.cancel();
    _authWorker?.dispose();
    _authWorker = null;
  }
}
