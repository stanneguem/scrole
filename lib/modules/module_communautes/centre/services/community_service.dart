import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/widgets.dart';
import 'package:sqflite/sqflite.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import '../../../../app/local_storage/structured/app_cache_database.dart';
import '../../../../app/repository_global/storage_repository.dart';
import '../../../module_authentification/centre/services/auth_service.dart';
import '../models/community_model.dart';
import '../persistence/community_local_dao.dart';
import '../../externe/repositories/community_repository.dart';
import 'community_outbox_processor.dart';
import '../models/news/community_hashtag.dart';
import '../../interne/controllers/community/community_feed_controller.dart';
import '../../interne/controllers/community/community_controller.dart';
import '../../../../shared/constants/post_media_limits.dart';

class CommunityService extends GetxService with WidgetsBindingObserver {
  final CommunityRepository _repo;
  final StorageRepository? _storageRepo;
  late final CommunityLocalDao _dao = CommunityLocalDao(Get.find<AppDatabase>());
  final AuthService _authService = Get.find<AuthService>();

  RealtimeChannel? _userChannel;

  CommunityService([CommunityRepository? repo, this._storageRepo])
      : _repo = repo ?? CommunityRepository();

  Future<CommunityService> init() async {
    WidgetsBinding.instance.addObserver(this);
    if (!Get.isRegistered<CommunityOutboxProcessor>()) {
      Get.put(CommunityOutboxProcessor());
    }
    final userId = _authService.userId;
    if (userId != null) {
      listenRealtime(userId);
      await reconcileMyCommunities();
    }
    return this;
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _userChannel?.unsubscribe();
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(reconcileMyCommunities());
    }
  }

  void listenRealtime(String userId) {
    if (_userChannel != null) return;
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null || session.isExpired) return;

    _userChannel = Supabase.instance.client
        .channel('user:$userId', opts: const RealtimeChannelConfig(private: true))
        .onBroadcast(
          event: 'community_membership_removed',
          callback: (payload) async {
            final communityId = payload['community_id']?.toString();
            if (communityId != null && communityId.isNotEmpty) {
              await handleCommunityMembershipRemoved(communityId);
            }
          },
        )
        .subscribe((status, [error]) {
          if (status == RealtimeSubscribeStatus.subscribed) {
            unawaited(reconcileMyCommunities());
          }
        });
  }

  Future<void> handleCommunityMembershipRemoved(String communityId) async {
    await _dao.deleteCommunity(communityId);
    try {
      if (Get.isRegistered<CommunityFeedController>()) {
        final feedCtrl = Get.find<CommunityFeedController>();
        if (feedCtrl.communityId == communityId) {
          Get.back();
        }
      } else if (Get.currentRoute.contains(communityId) || Get.currentRoute.contains('community_feed')) {
        Get.back();
      }
    } catch (_) {}

    Get.snackbar(
      'community_membership_removed_title'.tr,
      'community_membership_removed_msg'.tr,
      snackPosition: SnackPosition.BOTTOM,
    );

    await reconcileMyCommunities();
  }

  bool _isReconciling = false;

  Future<void> reconcileMyCommunities() async {
    if (_isReconciling) return;
    _isReconciling = true;

    try {
      List<Map<String, dynamic>> remoteList = [];
      try {
        remoteList = await _repo.getMyCommunities();
      } catch (e) {
        return;
      }

      final remoteIds = remoteList.map((m) => m['id']?.toString()).where((id) => id != null && id.isNotEmpty).toSet();
      final now = DateTime.now().millisecondsSinceEpoch;
      final userId = _authService.userId ?? 'local_user';

      for (final map in remoteList) {
        final id = map['id']?.toString();
        if (id == null || id.isEmpty) continue;
        try {
          final existing = await _dao.getCommunity(id);
          final createdAt = existing?.createdAt ?? now;
          final rawSlug = map['slug']?.toString();
          final slug = (rawSlug != null && rawSlug.trim().isNotEmpty) ? rawSlug.trim() : id;

          final community = CommunityModel(
            id: id,
            name: map['name']?.toString() ?? '',
            slug: slug,
            description: map['description']?.toString(),
            avatarUrl: map['avatar_url']?.toString() ?? map['photo_profile']?.toString() ?? map['imageUrl']?.toString(),
            bannerUrl: map['banner_url']?.toString() ?? map['photo_cover']?.toString(),
            visibility: map['visibility']?.toString() ?? 'public',
            status: 'confirmed',
            memberCount: (map['member_count'] as num?)?.toInt() ?? 1,
            cachedAt: now,
            createdAt: createdAt,
          );
          await _dao.saveCommunity(community);
          await _dao.ensureCommunityMember(userId, id);
        } catch (_) {}
      }

      final localCommunities = await _dao.getAllCommunities();
      for (final local in localCommunities) {
        if (local.status != 'pending' && !remoteIds.contains(local.id)) {
          await _dao.deleteCommunity(local.id);
        }
      }
    } catch (e) {
      debugPrint('[COMMUNITY_SYNC] Reconciliation error: $e');
    } finally {
      _isReconciling = false;
    }
  }

  Future<CommunityModel?> getCommunityById(String id) async {
    return await _dao.getCommunity(id);
  }

  Future<List<CommunityModel>> getJoinedCommunities() async {
    final userId = _authService.userId ?? 'local_user';
    return await _dao.getCommunities(userId);
  }

  Future<List<CommunityHashtag>> searchCommunityHashtags(String query, {int limit = 20}) async {
    final rows = await _repo.searchCommunityHashtags(query, limit: limit);
    return rows.map((row) => CommunityHashtag(
      id: (row['id'] ?? '').toString(),
      name: (row['name'] ?? row['normalized_name'] ?? '').toString(),
      postCount: (row['post_count'] as num?)?.toInt() ?? 0,
    )).where((tag) => tag.name.isNotEmpty).toList();
  }

  Future<Map<String, dynamic>> getCommunityMembersRpc({
    required String communityId,
    int limit = 50,
    String? cursor,
    String? query,
  }) async {
    return await _repo.getCommunityMembersRpc(
      communityId: communityId,
      limit: limit,
      cursor: cursor,
      query: query,
    );
  }

  Future<bool> isCommunityStaffRpc(String communityId) async {
    return await _repo.isCommunityStaffRpc(communityId);
  }

  Future<List<Map<String, dynamic>>> getCommunityMembers(String communityId) async {
    return await _repo.getCommunityMembers(communityId);
  }

  Future<void> updateMemberRole(String communityId, String userId, String newRole) async {
    await _repo.updateCommunityMemberRoleRpc(
      communityId: communityId,
      userId: userId,
      newRole: newRole,
    );
  }

  /// Resolves the user's role inside this specific community, not the platform.
  /// Maps stable backend moderation errors to app-localized messages.
  /// Keep raw backend text in logs, not in user-facing UI.
  String localizedCommunityError(Object error) {
    final message = error.toString().replaceFirst('Exception: ', '').toLowerCase();
    if (message.contains('action réservée aux administrateurs') ||
        message.contains('administrateurs de la communauté')) {
      return 'community_admin_required'.tr;
    }
    if (message.contains('créateur de la communauté') ||
        message.contains('createur de la communaute')) {
      return 'community_creator_cannot_exclude'.tr;
    }
    if (message.contains('retirez d’abord') ||
        message.contains("retirez d'abord") ||
        message.contains('rôle administrateur')) {
      return 'community_remove_admin_role_first'.tr;
    }
    if (message.contains('vous ne pouvez pas vous exclure')) {
      return 'community_cannot_exclude_self'.tr;
    }
    if (message.contains('motif trop long')) {
      return 'community_exclusion_reason_too_long'.tr;
    }
    if (message.contains('âge invalide') ||
        message.contains('age invalid') ||
        message.contains('âge minimum doit être inférieur')) {
      return 'community_settings_age_invalid'.tr;
    }
    if (message.contains('visibilité invalide')) {
      return 'community_settings_visibility_invalid'.tr;
    }
    if (message.contains('au moins un pays')) {
      return 'community_settings_select_at_least_one_country'.tr;
    }
    if (message.contains('au moins une ville')) {
      return 'community_settings_select_at_least_one_city'.tr;
    }
    if (message.contains('pays sélectionné est invalide') ||
        message.contains('ville sélectionnée est invalide')) {
      return 'community_settings_location_invalid'.tr;
    }
    if (message.contains('villes sélectionnées doivent appartenir')) {
      return 'community_settings_city_country_mismatch'.tr;
    }
    if (message.contains('nom ne peut pas être vide')) {
      return 'community_settings_name_required'.tr;
    }
    if (message.contains('nom est trop long')) {
      return 'community_settings_name_too_long'.tr;
    }
    if (message.contains('slogan est trop long')) {
      return 'community_settings_slogan_too_long'.tr;
    }
    if (message.contains('description est trop longue')) {
      return 'community_settings_description_too_long'.tr;
    }
    if (message.contains('non authentifié') || message.contains('authentication required')) {
      return 'community_auth_required'.tr;
    }
    if (message.contains('introuvable') || message.contains('not found')) {
      return 'community_user_not_found'.tr;
    }
    return 'community_operation_failed'.tr;
  }

  Future<String> getCurrentUserRole(String communityId) async {
    final userId = _authService.userId;
    if (userId == null || userId.trim().isEmpty) return 'member';

    String normalizeRole(dynamic value) {
      final role = value?.toString().trim().toLowerCase() ?? '';
      if ([
        'admin',
        'administrator',
        'administrateur',
        'owner',
        'community_owner',
        'community_admin',
        'creator',
        'founder',
        'créateur',
        'createur',
        'fondateur',
        'propriétaire',
        'proprietaire',
      ].contains(role)) {
        return 'admin';
      }
      if ([
        'moderator',
        'modérateur',
        'moderateur',
        'community_moderator',
        'staff',
      ].contains(role)) {
        return 'moderator';
      }
      return 'member';
    }

    try {
      // Source of truth: this community's creator_id and membership role.
      // Do not use platform-wide staff permissions for community settings.
      final communityRole = await _repo.getCurrentUserCommunityRole(communityId);
      if (communityRole != null && communityRole.trim().isNotEmpty) {
        return normalizeRole(communityRole);
      }
    } catch (e) {
      debugPrint('[CommunityService] Direct community role lookup failed: $e');
    }

    // Compatibility fallback for installations where direct table reads are
    // restricted by RLS or where the role is exposed by a community RPC.
    try {
      final myCommunities = await _repo.getMyCommunities();
      for (final community in myCommunities) {
        final id = (community['id'] ?? community['community_id'])?.toString();
        if (id != communityId) continue;

        final creatorId = (community['creator_id'] ??
                community['created_by'] ??
                community['owner_id'])
            ?.toString();
        if (creatorId == userId) return 'admin';

        for (final key in [
          'role',
          'user_role',
          'member_role',
          'community_role',
          'staff_role',
          'role_name',
        ]) {
          final value = community[key];
          if (value != null && value.toString().trim().isNotEmpty) {
            return normalizeRole(value);
          }
        }
      }
    } catch (e) {
      debugPrint('[CommunityService] get_my_communities role lookup failed: $e');
    }

    try {
      final response = await _repo.getCommunityMembersRpc(communityId: communityId);
      final rawItems = response['items'] ?? response['members'] ?? response['data'] ?? [];
      if (rawItems is List) {
        for (final item in rawItems.whereType<Map>()) {
          final member = Map<String, dynamic>.from(item);
          final memberId = (member['user_id'] ?? member['profile_id'])?.toString();
          if (memberId != userId) continue;

          final role = member['role'] ?? member['community_role'] ?? member['role_name'];
          if (role != null) return normalizeRole(role);
          if (member['is_admin'] == true || member['is_creator'] == true) return 'admin';
          if (member['is_moderator'] == true || member['is_staff'] == true) return 'moderator';
        }
      }
    } catch (e) {
      debugPrint('[CommunityService] Community member role lookup failed: $e');
    }

    // is_community_staff is scoped to this community. It does not distinguish
    // admin from moderator, so use the least-privileged staff role only if the
    // exact role could not be retrieved.
    try {
      if (await _repo.isCommunityStaffRpc(communityId)) return 'moderator';
    } catch (e) {
      debugPrint('[CommunityService] Community staff check failed: $e');
    }

    return 'member';
  }

  Future<void> excludeCommunityMember(String communityId, String userId, {String? reason, bool deleteContent = false}) async {
    await _repo.excludeCommunityMember(communityId, userId, reason: reason, deleteContent: deleteContent);
  }

  Future<void> unexcludeCommunityMember(String communityId, String userId) async {
    await _repo.unexcludeCommunityMember(communityId, userId);
  }

  Future<Map<String, dynamic>> getCommunityExclusions(String communityId, {int limit = 30, int offset = 0}) async {
    return await _repo.getCommunityExclusions(communityId, limit: limit, offset: offset);
  }

  Future<List<Map<String, dynamic>>> getSignalementRaisons() async {
    return await _repo.getSignalementRaisons();
  }

  Future<void> reportCommunity({
    required String communityId,
    required String reasonId,
    String? description,
  }) async {
    try {
      final trimmedDesc = (description != null && description.trim().isNotEmpty) ? description.trim() : null;
      await _repo.reportContent(
        targetType: 'community',
        targetId: communityId,
        reasonId: reasonId,
        description: trimmedDesc,
      );
    } catch (e) {
      debugPrint('[CommunityService] reportCommunity error: $e');
      rethrow;
    }
  }

  Future<CommunityOpenResult> openCommunity(String communityId) async {
    final resMap = await _repo.openCommunityRpc(communityId);
    return CommunityOpenResult.fromJson(resMap);
  }

  Future<Map<String, dynamic>> joinCommunity(String communityId) async {
    final userId = _authService.userId ?? 'local_user';
    final res = await _repo.joinCommunityRpc(communityId);
    final status = (res['status'] ?? res['membership_status'] ?? res['request_status'] ?? '').toString().toLowerCase();

    if (status == 'active' || status == 'approved' || status == 'joined' || status == 'confirmed') {
      await _dao.ensureCommunityMember(userId, communityId);
    }

    await reconcileMyCommunities();
    return res;
  }

  Future<Map<String, dynamic>> leaveCommunity(String communityId) async {
    final result = await _repo.leaveCommunityRpc(communityId);
    await _dao.deleteCommunity(communityId);
    await reconcileMyCommunities();
    return result;
  }

  Future<CommunityModel> createCommunity({
    required String name,
    required String slug,
    required String description,
    required String visibility,
    File? avatarFile,
    File? bannerFile,
  }) async {
    final userId = _authService.userId ?? 'local_user';
    final communityId = _generateUuidV4();
    final operationId = _generateUuidV4();
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    String? avatarLocalPath;
    String? bannerLocalPath;

    try {
      final appDir = await getApplicationDocumentsDirectory();
      if (avatarFile != null && avatarFile.existsSync()) {
        final targetPath = p.join(appDir.path, 'communities', communityId, 'profile.jpg');
        await Directory(p.dirname(targetPath)).create(recursive: true);
        final compressed = await FlutterImageCompress.compressAndGetFile(
          avatarFile.absolute.path,
          targetPath,
          minWidth: 1280,
          minHeight: 1280,
          quality: 80,
        );
        avatarLocalPath = compressed?.path ?? avatarFile.path;
      }

      if (bannerFile != null && bannerFile.existsSync()) {
        final targetPath = p.join(appDir.path, 'communities', communityId, 'cover.jpg');
        await Directory(p.dirname(targetPath)).create(recursive: true);
        final compressed = await FlutterImageCompress.compressAndGetFile(
          bannerFile.absolute.path,
          targetPath,
          minWidth: 1280,
          minHeight: 1280,
          quality: 80,
        );
        bannerLocalPath = compressed?.path ?? bannerFile.path;
      }
    } catch (_) {}

    final community = CommunityModel(
      id: communityId,
      name: name,
      slug: slug,
      description: description,
      avatarUrl: avatarLocalPath,
      bannerUrl: bannerLocalPath,
      visibility: visibility,
      status: 'pending',
      memberCount: 1,
      cachedAt: nowMs,
      createdAt: nowMs,
    );

    await _dao.saveCommunity(community);

    final payload = {
      'name': name,
      'slug': slug,
      'description': description,
      'visibility': visibility,
      'avatar_local_path': avatarLocalPath,
      'banner_local_path': bannerLocalPath,
      'require_manual_approval': visibility == 'prive',
    };

    await _dao.insertCommunityOutbox(
      operationId: operationId,
      userId: userId,
      communityId: communityId,
      operationType: 'create_community',
      payload: jsonEncode(payload),
    );

    try {
      if (!Get.isRegistered<CommunityOutboxProcessor>()) {
        Get.put(CommunityOutboxProcessor());
      }
      await Get.find<CommunityOutboxProcessor>().processPendingOperations();
    } catch (_) {}

    return community;
  }

  Future<void> _refreshLocalCommunityFromSnapshot(
    String communityId,
    Map<String, dynamic> snapshot,
  ) async {
    try {
      final rawCommunity = snapshot['community'];
      if (rawCommunity is! Map) return;
      final data = Map<String, dynamic>.from(rawCommunity);
      final existing = await _dao.getCommunity(communityId);
      if (existing == null) return;
      await _dao.saveCommunity(existing.copyWith(
        name: data['name']?.toString() ?? existing.name,
        description: data['description']?.toString() ?? existing.description,
        avatarUrl: data['photo_profile']?.toString() ?? existing.avatarUrl,
        bannerUrl: data['photo_cover']?.toString() ?? existing.bannerUrl,
        visibility: data['visibility']?.toString() ?? existing.visibility,
        cachedAt: DateTime.now().millisecondsSinceEpoch,
      ));
    } catch (e) {
      debugPrint('[CommunityService] Local community cache refresh failed: $e');
    }
  }

  Future<void> updateCommunityInfo({
    required String id,
    required String name,
    String? slogan,
    required String description,
    String? photoProfile,
    String? photoCover,
  }) async {
    await _repo.updateCommunityInfo(
      p_id: id,
      p_name: name,
      p_slogan: slogan,
      p_description: description,
      p_photo_profile: photoProfile,
      p_photo_cover: photoCover,
    );
    try {
      final snapshot = await _repo.getCommunityManagementSettings(id);
      await _refreshLocalCommunityFromSnapshot(id, snapshot);
    } catch (e) {
      debugPrint('[CommunityService] Community info saved, but snapshot refresh failed: $e');
    }
  }

  Future<Map<String, dynamic>> getCommunityModerationCounts(String communityId) async {
    return await _repo.getCommunityModerationCounts(communityId);
  }

  Future<Map<String, dynamic>> getCommunityReports(String communityId, {String status = 'open', int limit = 20, int offset = 0}) async {
    return await _repo.getCommunityReports(communityId, status: status, limit: limit, offset: offset);
  }

  Future<Map<String, dynamic>> resolveCommunityReport(String reportId, String action, {String? note}) async {
    return await _repo.resolveCommunityReport(reportId, action, note: note);
  }

  Future<Map<String, dynamic>> getCommunityPendingPosts(String communityId, {int limit = 20, int offset = 0}) async {
    return await _repo.getCommunityPendingPosts(communityId, limit: limit, offset: offset);
  }

  Future<Map<String, dynamic>> getCommunityAlerts(String communityId) async {
    return _repo.getCommunityAlerts(communityId);
  }

  Future<Map<String, dynamic>> getCommunitySpamQueue(
    String communityId, {
    int limit = 20,
    int offset = 0,
  }) async {
    return _repo.getCommunitySpamQueue(
      communityId,
      limit: limit,
      offset: offset,
    );
  }

  Future<void> moderateCommunityPost(String postId, String action, {String? reason}) async {
    await _repo.moderateCommunityPost(postId, action, reason: reason);
  }

  Future<Map<String, dynamic>> getCommunityJoinRequests(String communityId, {int limit = 20, String? cursor}) async {
    return await _repo.getCommunityJoinRequests(communityId, limit: limit, cursor: cursor);
  }

  Future<void> respondCommunityJoinRequest(String requestId, bool accepted) async {
    await _repo.respondCommunityJoinRequest(requestId, accepted);
  }

  Future<Map<String, dynamic>> getCommunityAccessRules(String communityId) async {
    return await _repo.getCommunityAccessRules(communityId);
  }

  Future<Map<String, dynamic>> getCommunityManagementSettings(String communityId) {
    return _repo.getCommunityManagementSettings(communityId);
  }

  Future<Map<String, dynamic>> updateCommunityManagementSettings({
    required String communityId,
    String? visibility,
    bool? requireManualApproval,
    bool? membersListVisible,
    bool? certificationRequired,
    bool? countriesEnabled,
    List<String>? allowedCountries,
    bool? citiesEnabled,
    List<String>? allowedCities,
    String? genderRestriction,
    int? ageMin,
    int? ageMax,
    bool clearAge = false,
    bool clearAgeMin = false,
    bool clearAgeMax = false,
    bool clearGender = false,
    bool? allowReports,
    bool? allowComments,
    bool? allowReactions,
    bool? allowPostPromotion,
  }) async {
    final snapshot = await _repo.updateCommunityManagementSettings(
      communityId: communityId,
      visibility: visibility,
      requireManualApproval: requireManualApproval,
      membersListVisible: membersListVisible,
      certificationRequired: certificationRequired,
      countriesEnabled: countriesEnabled,
      allowedCountries: allowedCountries,
      citiesEnabled: citiesEnabled,
      allowedCities: allowedCities,
      genderRestriction: genderRestriction,
      ageMin: ageMin,
      ageMax: ageMax,
      clearAge: clearAge,
      clearAgeMin: clearAgeMin,
      clearAgeMax: clearAgeMax,
      clearGender: clearGender,
      allowReports: allowReports,
      allowComments: allowComments,
      allowReactions: allowReactions,
      allowPostPromotion: allowPostPromotion,
    );
    await _refreshLocalCommunityFromSnapshot(communityId, snapshot);
    return snapshot;
  }

  Future<void> updateCommunityAccessRules({
    required String communityId,
    required bool countriesEnabled,
    required List<String> allowedCountries,
    required bool citiesEnabled,
    required List<String> allowedCities,
    required bool certificationRequired,
    String? genderRestriction,
    int? ageMin,
    int? ageMax,
  }) async {
    await _repo.updateCommunityAccessRules(
      p_id: communityId,
      p_countries_enabled: countriesEnabled,
      p_allowed_countries: allowedCountries,
      p_cities_enabled: citiesEnabled,
      p_allowed_cities: allowedCities,
      p_certification_required: certificationRequired,
      p_gender_restriction: genderRestriction,
      p_age_min: ageMin,
      p_age_max: ageMax,
    );
  }

  Future<void> updateCommunitySettings({
    required String communityId,
    required String visibility,
    required bool requireManualApproval,
  }) async {
    await _repo.updateCommunitySettings(
      p_id: communityId,
      p_visibility: visibility,
      p_require_manual_approval: requireManualApproval,
    );
  }

  Future<void> updateCommunityPostSettings({
    required String communityId,
    required String postPermission,
    required bool postsRequireApproval,
  }) async {
    await _repo.updateCommunityPostSettings(
      communityId: communityId,
      postPermission: postPermission,
      postsRequireApproval: postsRequireApproval,
    );
  }

  Future<void> updateCommunityFeatures(
    String communityId, {
    bool? membersListVisible,
    bool? allowReports,
    bool? allowComments,
    bool? allowReactions,
  }) async {
    await _repo.updateCommunityFeatures(
      communityId: communityId,
      membersListVisible: membersListVisible,
      allowReports: allowReports,
      allowComments: allowComments,
      allowReactions: allowReactions,
    );
  }

  Future<List<Map<String, dynamic>>> getCommunityRules(String communityId) async {
    return await _repo.getCommunityRules(communityId);
  }

  Future<void> setCommunityRule({
    required String p_id,
    required String p_community_id,
    required String p_text,
    required int p_order_index,
  }) async {
    await _repo.setCommunityRule(
      p_id: p_id,
      p_community_id: p_community_id,
      p_text: p_text,
      p_order_index: p_order_index,
    );
  }

  Future<void> deleteCommunityRule(String p_id) async {
    await _repo.deleteCommunityRule(p_id);
  }

  Future<void> transferCommunityOwnership({
    required String communityId,
    required String toUserId,
  }) async {
    await _repo.transferCommunityOwnership(
      communityId: communityId,
      toUserId: toUserId,
    );
  }

  Future<void> deleteCommunity(String communityId) async {
    // Delete on the server first; preserve local data if the RPC fails.
    await _repo.deleteCommunity(communityId);
    await _dao.deleteCommunity(communityId);
    await reconcileMyCommunities();
  }

  Future<void> leaveCommunityAndReport({
    required String communityId,
    required String reasonId,
    required String description,
  }) async {
    await _repo.leaveCommunityAndReport(
      communityId: communityId,
      reasonId: reasonId,
      description: description,
    );
    await _dao.deleteCommunity(communityId);
    await reconcileMyCommunities();
  }

  Future<void> updateCommunityMemberVisibility(String communityId, bool membersListVisible) async {
    await _repo.updateCommunityMemberVisibility(communityId, membersListVisible);
  }

  Future<Map<String, dynamic>> getCommunityUserReports(String communityId, {String status = 'open', int limit = 20, int offset = 0}) async {
    return await _repo.getCommunityUserReports(communityId, status: status, limit: limit, offset: offset);
  }

  Future<Map<String, dynamic>> resolveCommunityUserReport(String reportId, String action, {String? note, bool deleteContent = false}) async {
    return await _repo.resolveCommunityUserReport(reportId, action, note: note, deleteContent: deleteContent);
  }

  Future<List<Map<String, dynamic>>> getAvailableCountries() {
    return _repo.getAvailableCountries();
  }

  Future<List<Map<String, dynamic>>> getAvailableCities() {
    return _repo.getAvailableCities();
  }

  Future<List<Map<String, dynamic>>> getAvailableInterests() async {
    return await _repo.getAvailableInterests();
  }

  Future<List<Map<String, dynamic>>> getCommunityInterests(String communityId) async {
    return await _repo.getCommunityInterests(communityId);
  }

  Future<void> updateCommunityInterests(String communityId, List<String> interestIds) async {
    await _repo.updateCommunityInterests(communityId, interestIds);
  }

  Future<void> checkPendingExpirations() async {
    try {
      final localCommunities = await _dao.getAllCommunities();
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final twoMinutesMs = 2 * 60 * 1000;

      final pendingCommunities = localCommunities.where((c) => c.status == 'pending').toList();
      if (pendingCommunities.isEmpty) return;

      List<Map<String, dynamic>> remoteList = [];
      try {
        remoteList = await _repo.getMyCommunities();
      } catch (e) {
        debugPrint('[COMMUNITY_SYNC] Failed to fetch remote communities during expiration check: $e');
      }
      final remoteIds = remoteList.map((m) => m['id']?.toString()).where((id) => id != null && id.isNotEmpty).toSet();

      for (final community in pendingCommunities) {
        final age = nowMs - community.createdAt;
        final expired = age > twoMinutesMs;
        if (expired) {
          if (remoteIds.contains(community.id)) {
            await _dao.updateCommunityStatus(community.id, 'confirmed');
          } else {
            await _dao.deleteCommunity(community.id);
          }
        }
      }
    } catch (e) {
      debugPrint('[COMMUNITY_SYNC] checkPendingExpirations error: $e');
    }
  }

  Future<void> createCommunityPost({
    required String communityId,
    String? requestedPostId,
    String? content,
    List<File>? imageFiles,
    List<File>? videoFiles,
    List<File>? orderedMediaFiles,
    List<String>? orderedMediaTypes,
    String? audience,
    bool commentsEnabled = true,
    bool sharingEnabled = true,
    bool reactionsEnabled = true,
    List<String>? hashtags,
    List<String>? mentions,
    Map<String, dynamic>? poll,
    bool allowPromotion = true,
  }) async {
    final startedAt = DateTime.now();
    debugPrint('[POST_CREATE][COMPOSER] START communityId=$communityId requestedPostId=$requestedPostId audience=$audience contentLength=${content?.length ?? 0} imageCount=${imageFiles?.length ?? 0} videoCount=${videoFiles?.length ?? 0} orderedCount=${orderedMediaFiles?.length ?? 0} pollPresent=${poll != null}');
    final totalMediaCount = orderedMediaFiles?.length ?? ((imageFiles?.length ?? 0) + (videoFiles?.length ?? 0));
    if (totalMediaCount > maxPostMedia) {
      throw Exception('Une publication peut contenir au maximum $maxPostMedia médias.');
    }

    final userId = _authService.userId ?? 'local_user';
    final postId = requestedPostId ?? _generateUuidV4();
    final operationId = postId;

    List<Map<String, String>> localMediaPaths = [];
    try {
      final appDir = await getApplicationDocumentsDirectory();
      // Copy selected files into app-owned storage quickly. Compression and
      // upload happen in the background processor after the outbox row exists.
      if (orderedMediaFiles != null && orderedMediaTypes != null &&
          orderedMediaFiles.length == orderedMediaTypes.length) {
        for (int i = 0; i < orderedMediaFiles.length; i++) {
          final file = orderedMediaFiles[i];
          if (!await file.exists()) continue;
          final type = orderedMediaTypes[i] == 'video' ? 'video' : 'photo';
          final extension = p.extension(file.path).isEmpty
              ? (type == 'video' ? '.mp4' : '.img')
              : p.extension(file.path);
          final targetPath = p.join(
            appDir.path, 'posts', postId,
            '${type}_$i$extension',
          );
          await Directory(p.dirname(targetPath)).create(recursive: true);
          final stableFile = await file.copy(targetPath);
          if (await stableFile.length() <= 0) {
            throw StateError('Le média sélectionné ${i + 1} est vide.');
          }
          localMediaPaths.add({'path': stableFile.path, 'type': type});
        }
      } else {
        // Backward compatibility for callers that still provide separate lists.
        if (imageFiles != null) {
          for (int i = 0; i < imageFiles.length; i++) {
            final file = imageFiles[i];
            if (!await file.exists()) continue;
            final extension = p.extension(file.path).isEmpty ? '.img' : p.extension(file.path);
            final targetPath = p.join(appDir.path, 'posts', postId, 'photo_$i$extension');
            await Directory(p.dirname(targetPath)).create(recursive: true);
            final stableFile = await file.copy(targetPath);
            localMediaPaths.add({'path': stableFile.path, 'type': 'photo'});
          }
        }
        if (videoFiles != null) {
          for (int i = 0; i < videoFiles.length; i++) {
            final video = videoFiles[i];
            if (!await video.exists()) continue;
            final extension = p.extension(video.path).isEmpty ? '.mp4' : p.extension(video.path);
            final targetPath = p.join(appDir.path, 'posts', postId, 'video_$i$extension');
            await Directory(p.dirname(targetPath)).create(recursive: true);
            final stableFile = await video.copy(targetPath);
            localMediaPaths.add({'path': stableFile.path, 'type': 'video'});
          }
        }
      }
    } catch (e, st) {
      debugPrint('[POST_CREATE][COMPOSER] MEDIA_PREPARE_FAILED postId=$postId error=$e\n$st');
      rethrow;
    }

    debugPrint('[POST_CREATE][COMPOSER] MEDIA_PREPARED postId=$postId communityId=$communityId mediaCount=${localMediaPaths.length} types=${localMediaPaths.map((m) => m['type']).toList()} elapsedMs=${DateTime.now().difference(startedAt).inMilliseconds}');

    Map<String, dynamic>? pollPayload = poll == null ? null : Map<String, dynamic>.from(poll);
    if (pollPayload != null) {
      final appDir = await getApplicationDocumentsDirectory();
      Future<String?> persistPollImage(dynamic rawPath, String filename) async {
        final localPath = rawPath?.toString();
        if (localPath == null || localPath.isEmpty) return null;
        final source = File(localPath);
        if (!await source.exists()) throw FileSystemException('Image de sondage introuvable.', localPath);
        final targetPath = p.join(appDir.path, 'posts', postId, 'poll', filename + (p.extension(localPath).isEmpty ? '.jpg' : p.extension(localPath)));
        await Directory(p.dirname(targetPath)).create(recursive: true);
        final stableFile = await source.copy(targetPath);
        if (await stableFile.length() <= 0) throw StateError('Une image du sondage est vide.');
        return stableFile.path;
      }

      final questionImagePath = await persistPollImage(pollPayload['image_file_path'], 'question');
      if (questionImagePath != null) {
        pollPayload['image_file_path'] = questionImagePath;
      } else {
        pollPayload.remove('image_file_path');
      }
      final rawOptions = pollPayload['options'];
      if (rawOptions is List) {
        final options = <Map<String, dynamic>>[];
        for (var i = 0; i < rawOptions.length; i++) {
          if (rawOptions[i] is! Map) continue;
          final option = Map<String, dynamic>.from(rawOptions[i] as Map);
          final imagePath = await persistPollImage(option['image_file_path'], 'option_${i + 1}');
          if (imagePath != null) {
            option['image_file_path'] = imagePath;
          } else {
            option.remove('image_file_path');
          }
          options.add(option);
        }
        pollPayload['options'] = options;
      }
    }

    final payload = {
      'p_id': postId,
      'p_content': content ?? '',
      'p_community_id': communityId.isEmpty ? null : communityId,
      'p_audience': audience ?? 'public',
      'p_local_media': localMediaPaths,
      // Versioned payload lets the processor quarantine legacy/stale queue rows safely.
      'p_outbox_version': 2,
      'p_hashtags': hashtags ?? [],
      'p_mentions': mentions ?? [],
      'p_comments_enabled': commentsEnabled,
      'p_sharing_enabled': sharingEnabled,
      'p_reactions_enabled': reactionsEnabled,
      'p_poll': pollPayload,
      'p_allow_promotion': allowPromotion,
    };

    final db = await Get.find<AppDatabase>().database;
    final now = DateTime.now().toIso8601String();

    // Some installed app_local.db versions have a NOT NULL operation_type
    // column in post_outbox, while older versions do not. Inspect the actual
    // local schema so publishing works on both without forcing data deletion.
    final postOutboxColumns = await db.rawQuery('PRAGMA table_info(post_outbox)');
    final hasOperationType = postOutboxColumns.any(
      (column) => column['name']?.toString() == 'operation_type',
    );
    final outboxRow = <String, Object?>{
      'operation_id': operationId,
      'user_id': userId,
      'community_id': communityId.isEmpty ? null : communityId,
      'payload': jsonEncode(payload),
      'status': 'pending',
      'attempt_count': 0,
      'next_retry_at': 0,
      'created_at': now,
      'updated_at': now,
    };
    if (hasOperationType) {
      outboxRow['operation_type'] = 'create';
    }

    debugPrint('[POST_CREATE][COMPOSER] OUTBOX_INSERT_START operationId=$operationId postId=$postId communityId=$communityId userId=$userId payloadMediaCount=${localMediaPaths.length} payloadBytes=${jsonEncode(payload).length} hasOperationType=$hasOperationType');
    await db.insert(
      'post_outbox',
      outboxRow,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    debugPrint('[POST_CREATE][COMPOSER] OUTBOX_INSERT_SUCCESS operationId=$operationId elapsedMs=${DateTime.now().difference(startedAt).inMilliseconds}');

    // Start the durable outbox processor in the background. The composer only
    // waits until the payload is safely stored locally, never for media uploads
    // or the remote RPC to finish.
    try {
      if (!Get.isRegistered<CommunityOutboxProcessor>()) {
        Get.put(CommunityOutboxProcessor());
      }
      unawaited(Get.find<CommunityOutboxProcessor>().processPendingPosts());
    } catch (e) {
      debugPrint('[POST_CREATE][COMPOSER] BACKGROUND_PROCESS_START_FAILED operationId=$operationId postId=$postId error=$e');
    }

  }

  String _generateUuidV4() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final chars = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${chars.substring(0, 8)}-${chars.substring(8, 12)}-${chars.substring(12, 16)}-${chars.substring(16, 20)}-${chars.substring(20, 32)}';
  }
}
