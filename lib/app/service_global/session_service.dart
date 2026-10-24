import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../modules/module_creation_de_compte/externe/repositories/user_repository.dart';
import '../local_storage/fast/fast_cache_service.dart';
import '../../modules/module_authentification/centre/services/auth_service.dart';
import '../../modules/module_creation_de_compte/centre/services/user_service.dart';
import '../local_storage/structured/app_cache_database.dart';
import '../../modules/module_discussion_direct/centre/services/chat_media_cache.dart';
import '../../shared/models/user_models.dart';
import 'preferences_service.dart';
import 'privacy_service.dart';
import 'sync_service.dart';

enum SessionEvent {
  authenticated,
  unauthenticated,
  banned,
  needsProfile,
  connectionError,
  loading,
}

class SessionService extends GetxService {
  final UserService _userService = Get.find<UserService>();
  final AuthService _authService = Get.find<AuthService>();
  final PreferencesService _prefsService = Get.find<PreferencesService>();
  final PrivacyService _privacyService = Get.find<PrivacyService>();
  final SyncService _syncService = Get.find<SyncService>();
  final FastCacheService _fastCache = Get.find<FastCacheService>();
  final AppDatabase _db = Get.find<AppDatabase>();

  final Rxn<Map<String, dynamic>> profile = Rxn<Map<String, dynamic>>();
  final Rx<SessionEvent> event = SessionEvent.loading.obs;

  StreamSubscription? _profileRealtimeSub;
  String? _activeUserId;
  String? get userId => _activeUserId;
  Future<void>? _resolveInFlight;
  Future<void>? _realtimeProfileFetchInFlight;

  void startSession(String userId) {
    if (_activeUserId == userId && _profileRealtimeSub != null) return;

    // Une session précédente ne doit jamais conserver son listener realtime.
    // On annule immédiatement et on libère la référence avant de démarrer
    // la nouvelle session afin d'éviter deux subscriptions simultanées.
    _profileRealtimeSub?.cancel();
    _profileRealtimeSub = null;
    _realtimeProfileFetchInFlight = null;

    _activeUserId = userId;
    final resolve = _resolveForUser(userId);
    _resolveInFlight = resolve;

    // Lancer le nettoyage des anciens médias en arrière-plan
    unawaited(ChatMediaCache.instance.purgeOldFiles());

    resolve.whenComplete(() {
      if (identical(_resolveInFlight, resolve)) {
        _resolveInFlight = null;
      }
    });
  }

  Future<void> stopSession() async {
    final uid = _activeUserId;
    _activeUserId = null;
    _cleanup();
    _prefsService.clearCache();
    _privacyService.clearCache();
    _syncService.clearCache();
    await _fastCache.clear();
    
    // Purge de la base SQLite pour cet utilisateur
    if (uid != null) {
      await _db.clearUserData(uid);
    }
    
    event.value = SessionEvent.unauthenticated;
  }

  Future<void> _resolveForUser(String userId) async {
    // Une résolution lancée pour un ancien utilisateur ne doit jamais
    // installer un listener pour le nouvel état de session.
    if (_activeUserId != userId) return;

    final cached = _userService.getCachedProfile();
    if (cached != null) {
      _applyProfile(cached, startSync: true);
      return;
    }

    await fetchProfileFromBackend(userId);
  }

  Future<void> fetchProfileFromBackend(
    String userId, {
    bool silent = false,
  }) async {
    if (_activeUserId != null && _activeUserId != userId) return;

    try {
      if (!silent) event.value = SessionEvent.loading;
      final fetched = await _userService.backendGetProfile(userId);
      if (fetched == null) {
        event.value = SessionEvent.needsProfile;
        return;
      }

      // Le profil peut être revenu après un changement de session.
      if (_activeUserId != userId) return;
      _applyProfile(fetched, startSync: true);
    } on AuthAccountMissingException catch (e) {
      debugPrint('Compte supprimé côté serveur: $e');
      event.value = SessionEvent.unauthenticated;
    } on AuthException catch (e) {
      final message = e.message.toLowerCase();
      final isTransient =
          e.statusCode == '429' ||
          e.code?.toLowerCase() == 'over_request_rate_limit' ||
          message.contains('rate limit') ||
          message.contains('too many requests') ||
          message.contains('socketexception') ||
          message.contains('failed host lookup') ||
          message.contains('handshakeexception') ||
          message.contains('timeout');
      if (isTransient) {
        debugPrint(
          '[Auth] Erreur temporaire ignorée: ${e.code ?? e.statusCode} - ${e.message}',
        );
        if (!silent) event.value = SessionEvent.connectionError;
        return;
      }
      event.value = SessionEvent.unauthenticated;
    } catch (e) {
      debugPrint('Échec de récupération du profil: $e');
      if (!silent) event.value = SessionEvent.connectionError;
    }
  }

  void applySessionData(UserSessionData data) {
    _prefsService.applyPreferences(data.preferences);
    _privacyService.applyPrivacy(data.privacy);
    _syncService.updateCursor(data.syncCursor);
    _applyProfile(data.profile, startSync: true);
  }

  void _applyProfile(
    Map<String, dynamic> profileData, {
    required bool startSync,
  }) {
    final accountStatus = profileData['account_status'] as String?;
    if (accountStatus == 'banned' || accountStatus == 'suspended') {
      profile.value = profileData;
      event.value = SessionEvent.banned;
      
      final userId = profileData['user_id'] as String? ?? profileData['id'] as String?;
      if (userId != null && userId == _activeUserId && _profileRealtimeSub == null) {
        _listenProfileRealtime(userId);
      }
      return;
    }

    profile.value = profileData;
    event.value = SessionEvent.authenticated;

    if (startSync && _profileRealtimeSub == null) {
      final userId =
          profileData['user_id'] as String? ?? profileData['id'] as String?;
      if (userId != null && userId == _activeUserId) {
        _startSync(userId);
      }
    }
  }

  void _startSync(String userId) {
    if (_activeUserId != userId || _profileRealtimeSub != null) return;

    _listenProfileRealtime(userId);
    _syncService.sync();
  }

  void _listenProfileRealtime(String userId) {
    if (_profileRealtimeSub != null || _activeUserId != userId) return;

    final subscription = _userService.watchProfile(userId).listen((data) {
      if (_activeUserId != userId) return;

      if (data.isEmpty) {
        profile.value = null;
        event.value = SessionEvent.needsProfile;
        return;
      }

      // Le flux realtime peut recevoir plusieurs événements rapprochés.
      // Une seule lecture backend à la fois évite les rafales de requêtes.
      if (_realtimeProfileFetchInFlight != null) return;

      final refresh = fetchProfileFromBackend(userId, silent: true);
      _realtimeProfileFetchInFlight = refresh;
      refresh.whenComplete(() {
        if (identical(_realtimeProfileFetchInFlight, refresh)) {
          _realtimeProfileFetchInFlight = null;
        }
      });
    }, onError: (e) => debugPrint('Realtime error: $e'));

    _profileRealtimeSub = subscription;
  }

  Future<Map<String, dynamic>?> updateProfile(
    String userId,
    Map<String, dynamic> data,
  ) async {
    final traceId = DateTime.now().millisecondsSinceEpoch.toString();
    debugPrint('[PROFILE_SAVE][$traceId] START userId=$userId fields=${data.keys.toList()}');
    try {
      final updated = await _userService.updateProfile(userId, data);
      debugPrint('[PROFILE_SAVE][$traceId] repository result=${updated == null ? 'null' : 'non-null'}');
      if (updated != null) {
        profile.value = updated;
        debugPrint('[PROFILE_SAVE][$traceId] SUCCESS profil en mémoire mis à jour');
      } else {
        debugPrint('[PROFILE_SAVE][$traceId] FAILURE: repository returned null');
      }
      return updated;
    } catch (e, stack) {
      debugPrint('[PROFILE_SAVE][$traceId] FAILURE type=${e.runtimeType} error=$e');
      debugPrint('[PROFILE_SAVE][$traceId] STACK_TRACE\n$stack');
      return null;
    }
  }

  void _cleanup() {
    _profileRealtimeSub?.cancel();
    _profileRealtimeSub = null;
    _resolveInFlight = null;
    _realtimeProfileFetchInFlight = null;
    profile.value = null;
  }

  @override
  void onClose() {
    _cleanup();
    super.onClose();
  }
}
