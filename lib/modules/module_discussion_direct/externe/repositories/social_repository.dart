import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../app/local_storage/structured/app_cache_database.dart';
import '../../../../app/local_storage/fast/fast_cache_service.dart';
import '../../../../app/service_global/supabse_service.dart';
import '../../centre/persistence/social_local_dao.dart';

class SocialRepository {
  final SupabaseClient _client;
  final SocialLocalDao _dao;

  SocialRepository({
    SupabaseClient? client,
    SocialLocalDao? dao,
  })  : _client = client ?? Get.find<SupabaseService>().client,
        _dao = dao ?? SocialLocalDao(Get.find<AppDatabase>());

  SocialLocalDao get dao => _dao;

  String? get currentUserId => _client.auth.currentUser?.id;

  // Cache mémoire des relations : invalidé par les appels d'action et la reconnexion.
  static final Map<String, Map<String, dynamic>> _relationshipCache = <String, Map<String, dynamic>>{};

  static String _relationshipCacheKey(String userId) {
    final currentId = Get.isRegistered<SupabaseService>()
        ? (Get.find<SupabaseService>().client.auth.currentUser?.id ?? 'anonymous')
        : 'anonymous';
    return 'follow_relationship_${currentId}_$userId';
  }

  static void invalidateRelationshipCache([String? userId]) {
    if (userId == null) {
      _relationshipCache.clear();
      if (Get.isRegistered<FastCacheService>()) {
        unawaited(Get.find<FastCacheService>().clearPattern('follow_relationship_'));
      }
    } else {
      _relationshipCache.removeWhere((key, _) => key.endsWith('_$userId'));
      if (Get.isRegistered<FastCacheService>()) {
        unawaited(Get.find<FastCacheService>().clearPattern('follow_relationship_'));
      }
    }
  }

  FastCacheService? get _fastCache =>
      Get.isRegistered<FastCacheService>() ? Get.find<FastCacheService>() : null;

  Future<Map<String, dynamic>> getRelationship(String targetUserId, {bool forceRefresh = false}) async {
    final cacheKey = _relationshipCacheKey(targetUserId);
    if (!forceRefresh && _relationshipCache.containsKey(cacheKey)) {
      return Map<String, dynamic>.from(_relationshipCache[cacheKey]!);
    }
    if (!forceRefresh) {
      final persisted = _fastCache?.get<Map<String, dynamic>>(
        _relationshipCacheKey(targetUserId),
        maxAge: const Duration(minutes: 5),
      );
      if (persisted != null && persisted.isNotEmpty) {
        _relationshipCache[cacheKey] = persisted;
        return Map<String, dynamic>.from(persisted);
      }
    }
    debugPrint('[FOLLOW] RPC get_relationship params={p_user_id: $targetUserId}');
    try {
      final response = await _client.rpc('get_relationship', params: {'p_user_id': targetUserId});
      if (response is! Map) throw StateError('Réponse get_relationship invalide');
      final relation = Map<String, dynamic>.from(response);
      _relationshipCache[cacheKey] = relation;
      await _fastCache?.set(_relationshipCacheKey(targetUserId), relation);
      debugPrint('[FOLLOW] RPC get_relationship response=$relation');
      return Map<String, dynamic>.from(relation);
    } catch (e, stack) {
      debugPrint('[FOLLOW] RPC get_relationship exception=$e\n$stack');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _relationshipAction(
    String operation,
    String rpc,
    Map<String, dynamic> params,
    String targetUserId,
  ) async {
    invalidateRelationshipCache(targetUserId);
    final uid = currentUserId;
    if (uid == null) throw StateError('Utilisateur non connecté');
    await _dao.enqueueOutbox(userId: uid, operation: operation, payload: params);
    debugPrint('[FOLLOW] RPC $rpc params=$params');
    try {
      final response = await _client.rpc(rpc, params: params);
      if (response is! Map) throw StateError('Réponse $rpc invalide');
      final relation = Map<String, dynamic>.from(response);
      _relationshipCache[_relationshipCacheKey(targetUserId)] = relation;
      await _fastCache?.set(_relationshipCacheKey(targetUserId), relation);
      debugPrint('[FOLLOW] RPC $rpc response=$relation');
      return relation;
    } catch (e, stack) {
      debugPrint('[FOLLOW] RPC $rpc exception=$e\n$stack');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> followUser(String targetUserId) =>
      _relationshipAction('follow_user', 'follow_user', {'p_user_id': targetUserId}, targetUserId);

  Future<Map<String, dynamic>> unfollowUser(String targetUserId) =>
      _relationshipAction('unfollow_user', 'unfollow_user', {'p_user_id': targetUserId}, targetUserId);

  Future<Map<String, dynamic>> cancelFollowRequest(String targetUserId) =>
      _relationshipAction('cancel_follow_request', 'cancel_follow_request', {'p_user_id': targetUserId}, targetUserId);

  Future<Map<String, dynamic>> respondFollowRequest(String requestId, bool accepted, {required String targetUserId}) async {
    invalidateRelationshipCache(targetUserId);
    final uid = currentUserId;
    if (uid == null) throw StateError('Utilisateur non connecté');
    final params = {'p_request_id': requestId, 'p_accepted': accepted};
    await _dao.enqueueOutbox(userId: uid, operation: 'respond_follow_request', payload: {...params, 'target_user_id': targetUserId});
    debugPrint('[FOLLOW] RPC respond_follow_request params=$params');
    try {
      final response = await _client.rpc('respond_follow_request', params: params);
      if (response is! Map) throw StateError('Réponse respond_follow_request invalide');
      final body = Map<String, dynamic>.from(response);
      final relationRaw = body['relationship'];
      final relation = relationRaw is Map ? Map<String, dynamic>.from(relationRaw) : body;
      _relationshipCache[_relationshipCacheKey(targetUserId)] = relation;
      await _fastCache?.set(_relationshipCacheKey(targetUserId), relation);
      debugPrint('[FOLLOW] RPC respond_follow_request response=$body');
      return body;
    } catch (e, stack) {
      debugPrint('[FOLLOW] RPC respond_follow_request exception=$e\n$stack');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> removeFollower(String targetUserId) =>
      _relationshipAction('remove_follower', 'remove_follower', {'p_user_id': targetUserId}, targetUserId);

  Future<Map<String, dynamic>> removeFriend(String targetUserId) =>
      _relationshipAction('remove_friend', 'remove_friend', {'p_user_id': targetUserId}, targetUserId);

  Future<Map<String, dynamic>> getFollowStats({String? userId}) async {
    final params = <String, dynamic>{if (userId != null) 'p_user_id': userId};
    debugPrint('[FOLLOW] RPC get_follow_stats params=$params');
    try {
      final response = await _client.rpc('get_follow_stats', params: params);
      if (response is Map) {
        final result = Map<String, dynamic>.from(response);
        debugPrint('[FOLLOW] RPC get_follow_stats response=$result');
        return result;
      }
      throw StateError('Réponse get_follow_stats invalide');
    } catch (e, stack) {
      debugPrint('[FOLLOW] RPC get_follow_stats exception=$e\n$stack');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getFollowList(
    String kind, {
    String? userId,
    int limit = 30,
    int offset = 0,
    String? query,
  }) async {
    final rpc = switch (kind) {
      'followers' => 'get_followers',
      'following' => 'get_following',
      'friends' => 'get_friends',
      _ => throw ArgumentError.value(kind, 'kind', 'Direction invalide'),
    };
    final params = <String, dynamic>{
      'p_user_id': userId,
      'p_limit': limit,
      'p_offset': offset,
      'p_query': query,
    };
    debugPrint('[FOLLOW] RPC $rpc params=$params');
    try {
      final response = await _client.rpc(rpc, params: params);
      if (response is Map) {
        final result = Map<String, dynamic>.from(response);
        debugPrint('[FOLLOW] RPC $rpc response=$result');
        return result;
      }
      throw StateError('Réponse $rpc invalide');
    } catch (e, stack) {
      debugPrint('[FOLLOW] RPC $rpc exception=$e\n$stack');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getMyFollowRequests({
    required String direction,
    int limit = 30,
    int offset = 0,
  }) async {
    if (direction != 'received' && direction != 'sent') {
      throw ArgumentError.value(direction, 'direction', 'Direction invalide');
    }
    final params = {'p_direction': direction, 'p_limit': limit, 'p_offset': offset};
    debugPrint('[FOLLOW] RPC get_my_follow_requests params=$params');
    try {
      final response = await _client.rpc('get_my_follow_requests', params: params);
      if (response is Map) {
        final result = Map<String, dynamic>.from(response);
        debugPrint('[FOLLOW] RPC get_my_follow_requests response=$result');
        return result;
      }
      throw StateError('Réponse get_my_follow_requests invalide');
    } catch (e, stack) {
      debugPrint('[FOLLOW] RPC get_my_follow_requests exception=$e\n$stack');
      rethrow;
    }
  }

  /// Compatibilité locale : l'état dérivé vient maintenant de get_relationship.
  Future<RelationState> getRelationState(String targetUserId) async {
    final relation = await getRelationship(targetUserId);
    switch ((relation['state'] ?? 'none').toString()) {
      case 'self': return RelationState.self;
      case 'friends': return RelationState.friend;
      case 'requested': return RelationState.requestSent;
      case 'request_received': return RelationState.requestReceived;
      case 'blocked': return RelationState.blockedByMe;
      default: return RelationState.none;
    }
  }

  /// Récupère les amis (suivis mutuels) depuis la RPC, sans accès direct à friendships.
  Future<List<Map<String, dynamic>>> getAcceptedConnections() async {
    final response = await getFollowList('friends');
    final rawItems = response['items'];
    if (rawItems is! List) return [];
    final profiles = rawItems.whereType<Map>().map((item) {
      final row = Map<String, dynamic>.from(item);
      return <String, dynamic>{
        'user_id': row['user_id'],
        'username': row['username'],
        'first_name': row['first_name'],
        'last_name': row['last_name'],
        'photo_url': row['photo_url'],
        'is_verified': row['is_certified'] ?? false,
        'is_certified': row['is_certified'] ?? false,
        'account_status': 'active',
        'deleted_at': null,
      };
    }).toList();
    await _dao.savePeople(profiles);
    return profiles;
  }

  /// Retourne le QR actif depuis le cache local ou en crée un à synchroniser via l'outbox.
  Future<Map<String, dynamic>> getOrGenerateUserQrCode() async {
    final userId = currentUserId;
    if (userId == null || userId.isEmpty) {
      throw StateError('Utilisateur non connecté');
    }

    final cached = await _dao.getActiveUserQrCode(userId);
    if (cached != null && (cached['id'] ?? '').toString().isNotEmpty) {
      debugPrint('[FOLLOW] QR active local cache user_id=$userId id=${cached['id']}');
      return Map<String, dynamic>.from(cached);
    }

    final id = generateLocalUuid();
    final qr = <String, dynamic>{
      'id': id,
      'user_id': userId,
      'uses_remaining': 3,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'sync_status': 'pending_push',
    };
    await _dao.saveUserQrCodes([qr]);
    await _dao.enqueueOutbox(
      userId: userId,
      operation: 'generate_user_qr_code',
      payload: {'id': id},
    );
    debugPrint('[FOLLOW] queued generate_user_qr_code params={p_id: $id}');
    return qr;
  }

  /// Réessaie immédiatement l'envoi d'un QR local au backend.
  /// En cas de timeout après création serveur, une violation d'unicité signifie
  /// que le QR existe déjà : on peut donc marquer la copie locale comme synchronisée.
  Future<void> syncUserQrCode(Map<String, dynamic> qr) async {
    final userId = currentUserId;
    final qrId = (qr['id'] ?? '').toString();
    if (userId == null || userId.isEmpty) {
      throw StateError('Utilisateur non connecté');
    }
    if (qrId.isEmpty) throw StateError('Identifiant du QR code manquant');
    if ((qr['user_id'] ?? '').toString() != userId) {
      throw StateError('Ce QR code ne correspond pas à l’utilisateur connecté');
    }

    try {
      await _client.rpc('generate_user_qr_code', params: {'p_id': qrId});
    } on PostgrestException catch (e) {
      // La requête a pu aboutir côté serveur avant une coupure réseau.
      if (e.code != '23505') rethrow;
    }

    await _dao.updateUserQrCodeSyncStatus(qrId, 'synced');
    debugPrint('[FOLLOW] QR synchronisé user_id=$userId id=$qrId');
  }

  /// Scanner un QR personnel : une seule action crée la relation mutuelle.
  Future<Map<String, dynamic>?> scanQrCode(String qrId, [String? mode]) async {
    final userId = currentUserId;
    if (userId == null) throw StateError('Utilisateur non connecté');
    await _dao.enqueueOutbox(
      userId: userId,
      operation: 'scan_qr_code',
      payload: {'qr_id': qrId},
    );
    debugPrint('[FOLLOW] RPC scan_qr_code params={p_qr_id: $qrId, p_mode: null}');
    try {
      final res = await _client.rpc('scan_qr_code', params: {
        'p_qr_id': qrId,
        'p_mode': null,
      });
      if (res is Map) {
        final result = Map<String, dynamic>.from(res);
        final relation = result['relationship'];
        if (relation is Map && relation['user_id'] != null) {
          _relationshipCache[_relationshipCacheKey(relation['user_id'].toString())] = Map<String, dynamic>.from(relation);
        }
        debugPrint('[FOLLOW] RPC scan_qr_code response=$result');
        return result;
      }
      return null;
    } catch (e, stack) {
      debugPrint('[FOLLOW] RPC scan_qr_code exception=$e\\n$stack');
      rethrow;
    }
  }

  String generateLocalUuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int b) => b.toRadixString(16).padLeft(2, '0');
    final chars = bytes.map(hex).join();
    return '${chars.substring(0, 8)}-${chars.substring(8, 12)}-${chars.substring(12, 16)}-${chars.substring(16, 20)}-${chars.substring(20, 32)}';
  }

  /// Adaptateur temporaire pour les anciens écrans ; les données viennent des RPC de suivi.

}
