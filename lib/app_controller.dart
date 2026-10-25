import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:scrole/app/service_global/app_config_service.dart';
import 'package:scrole/app/service_global/connectivity_service.dart';
import 'package:scrole/app/service_global/session_service.dart';
import 'package:scrole/app/service_global/sync_service.dart';
import 'package:scrole/modules/module_authentification/centre/services/auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:scrole/modules/module_authentification/interne/enums/auth_statut.dart';
import 'package:scrole/modules/module_creation_de_compte/interne/controllers/create_account_controller.dart';
import 'package:scrole/modules/module_evenement/centre/persistence/evenement_local_dao.dart';
import 'package:scrole/modules/module_evenement/interne/controllers/event_controller.dart';
import 'package:scrole/shared/etats/connectivity_states.dart';

class AppController extends GetxController {
  AppController({
    AuthService? authService,
    SessionService? sessionService,
    ConnectivityService? connectivityService,
    AppConfigService? configService,
    SyncService? syncService,
  }) : _authService = authService ?? Get.find<AuthService>(),
       _sessionService = sessionService ?? Get.find<SessionService>(),
       _connectivityService =
           connectivityService ?? Get.find<ConnectivityService>(),
       _configService = configService ?? Get.find<AppConfigService>(),
       _syncService = syncService ?? Get.find<SyncService>();

  final AuthService _authService;
  final SessionService _sessionService;
  final ConnectivityService _connectivityService;
  final AppConfigService _configService;
  final SyncService _syncService;

  Rxn<User> get authUser => _authService.currentUser;
  bool get isLoggedIn => _authService.isLoggedIn;
  RxBool get isConnected => _connectivityService.isConnected;
  Rx<ConnectionBannerState> get bannerState => _connectivityService.bannerState;
  Rxn<Map<String, dynamic>> get profile => _sessionService.profile;

  Rx<AppStatus> status = AppStatus.loading.obs;

  StreamSubscription? _sessionEventSub;
  StreamSubscription? _connectivityWaitSub;
  Worker? _authWorker;
  String? _sessionUserId;
  bool _isHandlingSignOut = false;

  @override
  void onInit() {
    super.onInit();
    _listenToServices();
    _bootstrap();
  }

  void _listenToServices() {
    _authWorker = ever<User?>(_authService.currentUser, (user) {
      if (user == null) {
        if (_isHandlingSignOut) return;
        _sessionUserId = null;
        _handleSignedOut();
        return;
      }

      if (_sessionUserId == user.id) return;
      _sessionUserId = user.id;
      _sessionService.startSession(user.id);
    });

    _sessionEventSub = _sessionService.event.listen(
      _mapSessionEventToAppStatus,
    );
  }

  void _bootstrap() {
    status.value = AppStatus.loading;

    if (_configService.isMaintenance.value) {
      status.value = AppStatus.maintenance;
      return;
    }

    if (_configService.needsUpdate.value) {
      status.value = AppStatus.updateRequired;
      return;
    }

    final user = _authService.currentUser.value;
    if (user == null) {
      status.value = AppStatus.unauthenticated;
    } else {
      _sessionUserId = user.id;
      _sessionService.startSession(user.id);
    }
  }

  void _mapSessionEventToAppStatus(SessionEvent event) {
    switch (event) {
      case SessionEvent.loading:
        status.value = AppStatus.loading;
        break;
      case SessionEvent.authenticated:
        status.value = AppStatus.authenticated;
        break;
      case SessionEvent.unauthenticated:
        status.value = AppStatus.unauthenticated;
        break;
      case SessionEvent.banned:
        status.value = AppStatus.banned;
        break;
      case SessionEvent.needsProfile:
        if (!Get.isRegistered<CreateAccountController>()) {
          Get.lazyPut<CreateAccountController>(() => CreateAccountController());
        }
        status.value = AppStatus.needsProfile;
        break;
      case SessionEvent.connectionError:
        status.value = AppStatus.connectionError;
        break;
    }
  }

  Future<void> retryAfterConnectionError() async {
    final userId = _authService.currentUser.value?.id;
    if (userId == null) {
      status.value = AppStatus.unauthenticated;
      return;
    }

    status.value = AppStatus.loading;
    final connected = await _waitForConnection();

    if (connected) {
      await _sessionService.fetchProfileFromBackend(userId);
    } else {
      status.value = AppStatus.connectionError;
    }
  }

  Future<bool> _waitForConnection({
    Duration timeout = const Duration(seconds: 20),
  }) async {
    if (isConnected.value) return true;

    final completer = Completer<bool>();
    _connectivityWaitSub = _connectivityService.onStatusChange.listen((s) {
      if (s == InternetStatus.connected && !completer.isCompleted) {
        completer.complete(true);
      }
    });

    final connected = await completer.future.timeout(
      timeout,
      onTimeout: () => false,
    );
    await _connectivityWaitSub?.cancel();
    return connected;
  }

  Future<void> _handleSignedOut() async {
    if (_isHandlingSignOut) return;
    _isHandlingSignOut = true;
    try {
      if (Get.isRegistered<EventController>()) {
        final evCtrl = Get.find<EventController>();
        evCtrl.suggestedEvents.clear();
        evCtrl.calendarEvents.clear();
        evCtrl.events.clear();
      }
      if (Get.isRegistered<EvenementLocalDao>()) {
        await Get.find<EvenementLocalDao>().purgeEventCacheOnly();
      }
      await _sessionService.stopSession();
      _setUnauthenticated();
    } finally {
      _isHandlingSignOut = false;
    }
  }

  void _setUnauthenticated() {
    final appAlreadyRendered = status.value != AppStatus.loading;
    status.value = AppStatus.unauthenticated;

    if (appAlreadyRendered) {
      Get.until((route) => route.isFirst);
    }
  }

  Future<void> forceRefresh() async {
    if (!isConnected.value) {
      debugPrint('[Sync] Refresh ignoré car hors-ligne');
      return;
    }

    final userId = _authService.currentUser.value?.id;
    if (userId != null) await _sessionService.fetchProfileFromBackend(userId);
  }

  void applyRegisteredProfile(Map<String, dynamic> profileData) {
    _sessionService.profile.value = profileData;
    status.value = AppStatus.authenticated;
  }

  /// Called only after initialize_account succeeds for a newly created profile.
  void startOnboarding() => status.value = AppStatus.onboarding;

  /// The onboarding is intentionally session-scoped: existing accounts are never
  /// sent back here on a later login.
  void finishOnboarding() => status.value = AppStatus.authenticated;

  Future<Map<String, dynamic>?> updateProfile(Map<String, dynamic> data) async {
    final user = _authService.currentUser.value;
    if (user == null) return null;
    return await _sessionService.updateProfile(user.id, data);
  }

  @override
  void onClose() {
    _authWorker?.dispose();
    _sessionEventSub?.cancel();
    _connectivityWaitSub?.cancel();
    super.onClose();
  }
}
