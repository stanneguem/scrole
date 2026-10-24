import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/local_storage/fast/fast_cache_key.dart';
import '../../../../app/local_storage/fast/fast_cache_service.dart';
import '../../../../app/service_global/supabse_service.dart';
import '../../../module_discussion_direct/centre/persistence/social_local_dao.dart';
import '../../../module_discussion_direct/externe/repositories/social_repository.dart';
import '../../centre/models/external_profile_model.dart';

enum ProfileResultStatus {
  loaded,
  deleted,
  notFound,
  suspended,
  banned,
  error,
}

class ExternalProfileResult {
  final ProfileResultStatus status;
  final ExternalProfileModel? profile;
  final String? errorMessage;

  const ExternalProfileResult({
    required this.status,
    this.profile,
    this.errorMessage,
  });
}

class ExternalProfileRepository {
  final _client = Get.find<SupabaseService>().client;
  final SocialRepository _socialRepo = SocialRepository();

  FastCacheService? get _cache =>
      Get.isRegistered<FastCacheService>() ? Get.find<FastCacheService>() : null;


  Future<ExternalProfileResult> getProfileResult(String userId) async {
    final cacheKey = FastCacheKey.externalProfile(userId);

    // Privacy and relationship fields depend on the current viewer and can change
    // immediately. Never serve a cached external profile before rechecking the RPC.
    Map<String, dynamic>? rawJson;
    ProfileResultStatus? explicitStatus;

    try {
      final response = await _client.rpc('get_external_profile', params: {'p_user_id': userId});

      if (response is Map) {
        final errStr = (response['error'] ?? response['code'] ?? response['message'] ?? '').toString().toLowerCase();
        if (errStr.contains('profile_deleted') || response['status'] == 'deleted') {
          explicitStatus = ProfileResultStatus.deleted;
        } else if (errStr.contains('profile_suspended') || response['status'] == 'suspended') {
          explicitStatus = ProfileResultStatus.suspended;
          if (response['user_id'] != null) rawJson = Map<String, dynamic>.from(response);
        } else if (errStr.contains('profile_banned') || response['status'] == 'banned') {
          explicitStatus = ProfileResultStatus.banned;
          if (response['user_id'] != null) rawJson = Map<String, dynamic>.from(response);
        } else if (errStr.contains('profile_not_found') || response['status'] == 'not_found') {
          explicitStatus = ProfileResultStatus.notFound;
        } else if (response['user_id'] != null) {
          rawJson = Map<String, dynamic>.from(response);
          explicitStatus = ProfileResultStatus.loaded;
        }
      }
    } on PostgrestException catch (e) {
      debugPrint('[ExternalProfileRepository] PostgrestException in get_external_profile for $userId: code=${e.code}, msg=${e.message}, details=${e.details}');
      final fullMsg = '${e.message} ${e.details} ${e.code}'.toLowerCase();
      if (fullMsg.contains('profile_deleted') || fullMsg.contains('account_deleted')) {
        explicitStatus = ProfileResultStatus.deleted;
      } else if (fullMsg.contains('profile_suspended') || fullMsg.contains('account_suspended')) {
        explicitStatus = ProfileResultStatus.suspended;
      } else if (fullMsg.contains('profile_banned') || fullMsg.contains('account_banned')) {
        explicitStatus = ProfileResultStatus.banned;
      } else if (fullMsg.contains('profile_not_found') || fullMsg.contains('pgrst116') || e.code == 'PGRST116') {
        explicitStatus = ProfileResultStatus.notFound;
      }
    } catch (e) {
      debugPrint('[ExternalProfileRepository] RPC get_external_profile error for $userId: $e');
      final fullMsg = e.toString().toLowerCase();
      if (fullMsg.contains('profile_deleted') || fullMsg.contains('account_deleted')) {
        explicitStatus = ProfileResultStatus.deleted;
      } else if (fullMsg.contains('profile_suspended') || fullMsg.contains('account_suspended')) {
        explicitStatus = ProfileResultStatus.suspended;
      } else if (fullMsg.contains('profile_banned') || fullMsg.contains('account_banned')) {
        explicitStatus = ProfileResultStatus.banned;
      } else if (fullMsg.contains('profile_not_found')) {
        explicitStatus = ProfileResultStatus.notFound;
      }
    }

    // 3. Handle explicit deleted / notFound / suspended / banned statuses
    if (explicitStatus == ProfileResultStatus.deleted) {
      debugPrint('[ExternalProfileRepository] Profile $userId is DELETED. Invalidating cache.');
      await _cache?.remove(cacheKey);
      return const ExternalProfileResult(status: ProfileResultStatus.deleted);
    }

    if (explicitStatus == ProfileResultStatus.notFound) {
      debugPrint('[ExternalProfileRepository] Profile $userId is NOT FOUND. Invalidating cache.');
      await _cache?.remove(cacheKey);
      return const ExternalProfileResult(status: ProfileResultStatus.notFound);
    }

    if (explicitStatus == ProfileResultStatus.suspended) {
      debugPrint('[ExternalProfileRepository] Profile $userId is SUSPENDED.');
      await _cache?.remove(cacheKey);
      final model = rawJson != null ? ExternalProfileModel.fromJson(rawJson) : null;
      return ExternalProfileResult(status: ProfileResultStatus.suspended, profile: model);
    }

    if (explicitStatus == ProfileResultStatus.banned) {
      debugPrint('[ExternalProfileRepository] Profile $userId is BANNED.');
      await _cache?.remove(cacheKey);
      final model = rawJson != null ? ExternalProfileModel.fromJson(rawJson) : null;
      return ExternalProfileResult(status: ProfileResultStatus.banned, profile: model);
    }

    // 4. If RPC returned valid profile json, populate user activities and save to cache
    if (rawJson != null) {
      final modelTmp = ExternalProfileModel.fromJson(rawJson);
      final rawRelationship = rawJson['relationship'];
      final relationship = rawRelationship is Map ? Map<String, dynamic>.from(rawRelationship) : <String, dynamic>{};
      final hasApprovedPrivateAccess = rawJson['is_following'] == true ||
          rawJson['is_friend'] == true ||
          relationship['is_following'] == true ||
          relationship['is_friend'] == true;
      if (!modelTmp.isBlocked && (!modelTmp.isPrivate || hasApprovedPrivateAccess)) {
        final acts = await fetchUserActivities(userId);
        if (acts.isNotEmpty) {
          rawJson['activities'] = acts;
        }
      }

      await _cache?.set(cacheKey, rawJson);
      return ExternalProfileResult(
        status: ProfileResultStatus.loaded,
        profile: ExternalProfileModel.fromJson(rawJson),
      );
    }

    // Do not fall back to a direct user_profiles query or stale cache here:
    // that could bypass profile privacy after an RPC/network failure.
    return const ExternalProfileResult(
      status: ProfileResultStatus.error,
      errorMessage: 'Impossible de charger ce profil.',
    );
  }

  Future<ExternalProfileModel?> getProfile(String userId) async {
    final res = await getProfileResult(userId);
    return res.profile;
  }

  /// Updates local cached profile map when a relationship action is performed.
  Future<void> updateCachedProfile(ExternalProfileModel model) async {
    final cacheKey = FastCacheKey.externalProfile(model.userId);
    await _cache?.set(cacheKey, model.toJson());
  }

  Future<List<Map<String, dynamic>>> fetchUserActivities(String userId) async {
    try {
      final response = await _client
          .from('activities')
          .select('id, name, base_price, currency_code, photo_url')
          .eq('user_id', userId)
          .limit(10);

      if (response is List) {
        return response
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (e) {
      debugPrint('[ExternalProfileRepository] fetchUserActivities error: $e');
    }
    return [];
  }


  /// Loads one of the sections of an external profile through the server RPC.
  Future<List<Map<String, dynamic>>> fetchProfileTab({
    required String userId,
    required String tab,
    int limit = 24,
    int offset = 0,
  }) async {
    final response = await _client.rpc('get_external_profile_tab', params: {
      'p_user_id': userId,
      'p_tab': tab,
      'p_limit': limit,
      'p_offset': offset,
    });
    if (response is List) {
      return response
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
    }
    return const <Map<String, dynamic>>[];
  }

  Future<Map<String, dynamic>> getRelationship(String userId, {bool forceRefresh = false}) =>
      _socialRepo.getRelationship(userId, forceRefresh: forceRefresh);

  Future<Map<String, dynamic>> getFollowStats({String? userId}) =>
      _socialRepo.getFollowStats(userId: userId);

  Future<void> sendConnectionRequest(String userId) async {
    await _socialRepo.followUser(userId);
  }

  Future<void> cancelConnection(String userId) async {
    await _socialRepo.unfollowUser(userId);
  }

  Future<void> respondConnectionRequest(String requestId, bool accept, {String? targetUserId}) async {
    var target = targetUserId;
    if (target == null || target.isEmpty) {
      final requests = await _socialRepo.getMyFollowRequests(direction: 'received', limit: 100, offset: 0);
      final items = requests['items'];
      if (items is List) {
        for (final item in items.whereType<Map>()) {
          if ((item['request_id'] ?? '').toString() == requestId) {
            final user = item['user'];
            if (user is Map) target = (user['user_id'] ?? user['id'])?.toString();
            break;
          }
        }
      }
    }
    if (target == null || target.isEmpty) throw ArgumentError('Utilisateur cible introuvable');
    await _socialRepo.respondFollowRequest(requestId, accept, targetUserId: target);
  }

  Future<Map<String, dynamic>> removeFriend(String userId) =>
      _socialRepo.removeFriend(userId);

  Future<bool> follow(String userId) async {
    await _socialRepo.followUser(userId);
    return true;
  }

  Future<bool> unfollow(String userId) async {
    await _socialRepo.unfollowUser(userId);
    return true;
  }
}
