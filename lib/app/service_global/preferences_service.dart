import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:scrole/app/local_storage/structured/app_cache_database.dart';
import 'package:scrole/app/local_storage/structured/preferences_local_dao.dart';
import 'package:scrole/app/service_global/connectivity_service.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:scrole/app/repository_global/preferences_repository.dart';
import 'package:scrole/shared/models/user_models.dart';
import 'package:scrole/modules/module_authentification/centre/services/auth_service.dart';
import '../local_storage/fast/fast_cache_service.dart';

class PreferencesService extends GetxService {
  final FastCacheService _cache = Get.find<FastCacheService>();
  final PreferencesRepository _repository = PreferencesRepository();
  late final PreferencesLocalDao _dao;
  
  static const String _cacheKey = 'user_preferences';
  static const String _privacyCacheKey = 'user_privacy';
  
  final Rx<AppPreferences> preferences = AppPreferences.defaultValues().obs;
  final Rx<AppPrivacy> privacy = AppPrivacy.defaultValues().obs;
  final RxBool isFlushingPending = false.obs;
  bool _flushRequested = false;

  RealtimeChannel? _userChannel;
  StreamSubscription<InternetStatus>? _connectivitySubscription;

  Future<PreferencesService> init() async {
    _dao = PreferencesLocalDao(Get.find<AppDatabase>());
    
    // 1. Chargement FastCache local
    final cached = _cache.get<Map<String, dynamic>>(_cacheKey);
    if (cached != null) {
      preferences.value = AppPreferences.fromJson(cached);
    }

    final cachedPrivacy = _cache.get<Map<String, dynamic>>(_privacyCacheKey);
    if (cachedPrivacy != null) {
      privacy.value = AppPrivacy.fromJson(cachedPrivacy);
    }

    // 2. Synchronisation initiale si l'utilisateur est connecté
    _initUserSync();

    // Rejoue les changements conservés dans l'outbox dès le retour du réseau.
    try {
      if (Get.isRegistered<ConnectivityService>()) {
        _connectivitySubscription = Get.find<ConnectivityService>().onStatusChange.listen((status) async {
          if (status == InternetStatus.connected) {
            await flushPending();
            await syncInitialSettings();
          }
        });
      }
    } catch (e) {
      debugPrint('[Preferences] connectivity listener unavailable: $e');
    }

    return this;
  }

  void _initUserSync() {
    try {
      if (Get.isRegistered<AuthService>()) {
        final auth = Get.find<AuthService>();
        final userId = auth.userId;
        if (userId != null) {
          unawaited(syncInitialSettings());
          listenRealtime(userId);
        }
      }
    } catch (_) {}
  }

  /// Applique un changement partiel (delta) uniquement
  /// Exemple: update({'theme': 'dark'}) ou update({'notif_messages': false})
  Future<void> update(Map<String, dynamic> changes) async {
    if (changes.isEmpty) return;

    // 1. Mise à jour locale réactive instantanée
    final currentPrefsMap = preferences.value.toJson();
    final currentPrivacyMap = privacy.value.toJson();

    currentPrefsMap.addAll(changes);
    currentPrivacyMap.addAll(changes);

    preferences.value = AppPreferences.fromJson(currentPrefsMap);
    privacy.value = AppPrivacy.fromJson(currentPrivacyMap);

    await _cache.set(_cacheKey, preferences.value.toJson());
    await _cache.set(_privacyCacheKey, privacy.value.toJson());

    final userId = _getUserId();
    if (userId == null) return;

    // 2. Écriture SQLite locale & Accumulation dans pending_changes (Outbox)
    await _dao.savePreferences({
      'user_id': userId,
      ...preferences.value.toJson(),
      'updated_at': DateTime.now().toIso8601String(),
      'sync_status': 'pending_push',
    });

    await _dao.addPendingChanges(userId, changes);

    // 3. Déclencheur d'envoi RPC
    unawaited(flushPending());
  }

  /// Traitement des changements en attente (pending_changes -> update_user_settings)
  Future<void> flushPending() async {
    final userId = _getUserId();
    if (userId == null) return;
    if (isFlushingPending.value) {
      _flushRequested = true;
      return;
    }

    isFlushingPending.value = true;
    var hasMorePending = false;
    try {
      // Process snapshots so a preference changed during an RPC remains queued.
      while (true) {
        final snapshot = await _dao.getPendingChangesSnapshot(userId);
        final mergedChanges = snapshot.changes;
        if (mergedChanges.isEmpty) break;

        final res = await _repository.updateUserSettingsRpc(mergedChanges);
        if (res == null) break;

        _applyServerState(res);
        await _dao.clearPendingChanges(userId, throughId: snapshot.throughId);

        // Keep newer optimistic edits visible if they were made while the
        // server request was in flight; the loop will send them next.
        final newer = await _dao.getPendingChangesSnapshot(userId);
        if (newer.changes.isNotEmpty) {
          final prefMap = preferences.value.toJson()..addAll(newer.changes);
          final privacyMap = privacy.value.toJson()..addAll(newer.changes);
          preferences.value = AppPreferences.fromJson(prefMap);
          privacy.value = AppPrivacy.fromJson(privacyMap);
          await _cache.set(_cacheKey, preferences.value.toJson());
          await _cache.set(_privacyCacheKey, privacy.value.toJson());
        }
      }
      hasMorePending = (await _dao.getPendingChangesSnapshot(userId)).changes.isNotEmpty;
    } catch (e) {
      debugPrint('[Error] flushPending preferences: $e');
    } finally {
      isFlushingPending.value = false;
    }

    if (hasMorePending || _flushRequested) {
      _flushRequested = false;
      unawaited(flushPending());
    }
  }

  /// Récupération initiale de l'état serveur (get_user_settings)
  Future<void> syncInitialSettings() async {
    final userId = _getUserId();
    if (userId == null) return;

    try {
      await flushPending();
      // If another update was already being flushed, wait for it before
      // applying the server snapshot so it cannot overwrite newer local edits.
      while (isFlushingPending.value) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      final serverData = await _repository.getUserSettingsRpc();
      if (serverData != null) {
        _applyServerState(serverData);
      }
    } catch (e) {
      debugPrint('[Error] syncInitialSettings preferences: $e');
    }
  }

  /// Applique l'état confirmé du serveur (preferences + privacy)
  void _applyServerState(Map<String, dynamic> serverData) {
    if (serverData['preferences'] is Map) {
      final prefMap = Map<String, dynamic>.from(serverData['preferences'] as Map);
      preferences.value = AppPreferences.fromJson(prefMap);
      _cache.set(_cacheKey, preferences.value.toJson());
    }

    if (serverData['privacy'] is Map) {
      final privMap = Map<String, dynamic>.from(serverData['privacy'] as Map);
      privacy.value = AppPrivacy.fromJson(privMap);
      _cache.set(_privacyCacheKey, privacy.value.toJson());
    }

    final userId = _getUserId();
    if (userId != null) {
      _dao.savePreferences({
        'user_id': userId,
        ...preferences.value.toJson(),
        'updated_at': DateTime.now().toIso8601String(),
        'sync_status': 'synced',
      });
    }
  }

  /// Écoute du canal Realtime `user:{userId}`
  void listenRealtime(String userId) {
    if (_userChannel != null) return;

    final session = Supabase.instance.client.auth.currentSession;
    if (session == null || session.isExpired) {
      debugPrint('[Realtime] Skipping preferences subscription: session expired or null');
      return;
    }

    _userChannel = Supabase.instance.client
        .channel('user:$userId', opts: const RealtimeChannelConfig(private: true))
        .onBroadcast(
          event: 'user_preferences_updated',
          callback: (_) => unawaited(syncInitialSettings()),
        )
        .onBroadcast(
          event: 'user_privacy_updated',
          callback: (_) => unawaited(syncInitialSettings()),
        )
        .subscribe((status, [error]) {
          if (status == RealtimeSubscribeStatus.subscribed) {
            unawaited(syncInitialSettings());
          }
        });
  }

  void applyPreferences(AppPreferences newPrefs) {
    update({
      'language': newPrefs.language,
      'theme': newPrefs.theme,
      'notifications_enabled': newPrefs.notificationsEnabled,
    });
  }

  String? _getUserId() {
    try {
      if (Get.isRegistered<AuthService>()) {
        return Get.find<AuthService>().userId;
      }
    } catch (_) {}
    return Supabase.instance.client.auth.currentUser?.id;
  }

  Future<void> clearCache() async {
    await _cache.remove(_cacheKey);
    await _cache.remove(_privacyCacheKey);
    preferences.value = AppPreferences.defaultValues();
    privacy.value = AppPrivacy.defaultValues();
  }

  @override
  void onClose() {
    _userChannel?.unsubscribe();
    _connectivitySubscription?.cancel();
    super.onClose();
  }
}
