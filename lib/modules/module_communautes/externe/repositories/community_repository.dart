import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CommunityRepository {
  final SupabaseClient client;

  CommunityRepository([SupabaseClient? client]) : client = client ?? Supabase.instance.client;

  Future<Map<String, dynamic>> createCommunityRpc({
    required String p_id,
    required String p_name,
    required String p_slug,
    required String p_description,
    required String p_visibility,
    String? p_photo_profile,
    String? p_photo_cover,
    bool? p_require_manual_approval,
  }) async {
    try {
      final requireApproval = p_require_manual_approval ?? (p_visibility == 'prive');
      debugPrint('[CREATE_COMMUNITY] [Repository] Calling RPC create_community with p_id=$p_id, p_name=$p_name, p_slug=$p_slug, p_visibility=$p_visibility, p_require_manual_approval=$requireApproval, p_photo_profile=$p_photo_profile, p_photo_cover=$p_photo_cover');
      
      final params = <String, dynamic>{
        'p_id': p_id,
        'p_name': p_name,
        'p_slug': p_slug,
        'p_description': p_description,
        'p_visibility': p_visibility,
        'p_require_manual_approval': requireApproval,
      };
      if (p_photo_profile != null && p_photo_profile.isNotEmpty) {
        params['p_photo_profile'] = p_photo_profile;
      }
      if (p_photo_cover != null && p_photo_cover.isNotEmpty) {
        params['p_photo_cover'] = p_photo_cover;
      }

      final response = await client.rpc('create_community', params: params);

      debugPrint('[CREATE_COMMUNITY] [Repository] RPC create_community successful for p_id=$p_id, response=$response');
      if (response is Map) {
        return Map<String, dynamic>.from(response);
      }
      return {'id': p_id, 'success': true};
    } on PostgrestException catch (e) {
      debugPrint('[CREATE_COMMUNITY] [Repository] PostgrestException during create_community: code=${e.code}, message=${e.message}, details=${e.details}');
      final msg = e.message;
      final msgLower = msg.toLowerCase();

      // 1. "Ce slug de communauté est déjà utilisé"
      if (msgLower.contains('slug') || msgLower.contains('déjà utilisé')) {
        throw Exception('slug_already_used');
      }

      // 2. "Cet identifiant de communauté existe déjà" -> Check if community exists via getMyCommunities()
      if (msgLower.contains('identifiant') || msgLower.contains('existe déjà') || e.code == '23505' || e.code == '409') {
        if (msgLower.contains('cette communauté existe déjà')) {
          throw Exception('community_already_exists');
        }
        try {
          final myComms = await getMyCommunities();
          final exists = myComms.any((c) => c['id']?.toString() == p_id);
          if (exists) {
            debugPrint('[CREATE_COMMUNITY] [Repository] Community id $p_id already exists and user is member. Treating as success.');
            return {'id': p_id, 'success': true};
          }
        } catch (verifyErr) {
          debugPrint('[CREATE_COMMUNITY] [Repository] Failed to verify existing community id: $verifyErr');
        }
      }

      // 3. "Cette communauté existe déjà"
      if (msgLower.contains('cette communauté existe déjà')) {
        throw Exception('community_already_exists');
      }

      // 4. "Utilisateur non authentifié"
      if (msgLower.contains('non authentifié') || msgLower.contains('unauthenticated') || e.code == '401') {
        throw Exception('user_unauthenticated');
      }

      // 5. Validation errors ("... est obligatoire", "... est invalide")
      if (msgLower.contains('obligatoire') || msgLower.contains('invalide') || msgLower.contains('required') || msgLower.contains('invalid')) {
        throw Exception('validation');
      }

      // 6. PGRST codes (PGRST202, PGRST301...), network errors, timeouts, 5xx -> Transient error
      if ((e.code != null && e.code!.startsWith('PGRST')) || (e.code != null && e.code!.startsWith('5')) || msgLower.contains('timeout') || msgLower.contains('socket')) {
        debugPrint('[CREATE_COMMUNITY] [Repository] Transient Postgrest error encountered (code=${e.code}, msg=$msg). Keeping in outbox for retry.');
        rethrow;
      }

      rethrow;
    } catch (e, st) {
      debugPrint('[CREATE_COMMUNITY] [Repository] Unexpected error during create_community: $e\n$st');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getMyCommunities() async {
    try {
      debugPrint('[COMMUNITY_SYNC] [Repository] Calling RPC get_my_communities');
      final response = await client.rpc('get_my_communities');
      debugPrint('[COMMUNITY_SYNC] [Repository] RPC get_my_communities response: $response');
      if (response is List) {
        return response.map((e) => Map<String, dynamic>.from(e)).toList();
      } else if (response is Map) {
        return [Map<String, dynamic>.from(response)];
      }
      return [];
    } catch (e, st) {
      debugPrint('[COMMUNITY_SYNC] [Repository] Error in getMyCommunities: $e\n$st');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> leaveCommunityRpc(String communityId) async {
    try {
      debugPrint('[COMMUNITY_SYNC] [Repository] Calling RPC leave_community with p_community_id=$communityId');
      final response = await client.rpc('leave_community', params: {
        'p_community_id': communityId,
      });
      debugPrint('[COMMUNITY_SYNC] [Repository] RPC leave_community successful for p_community_id=$communityId');
      if (response is Map) {
        return Map<String, dynamic>.from(response);
      }
      return {'success': true};
    } on PostgrestException catch (e) {
      debugPrint('[COMMUNITY_SYNC] [Repository] PostgrestException during leave_community: code=${e.code}, message=${e.message}');
      final msg = e.message.toLowerCase();
      if (msg.contains('dernier administrateur') || msg.contains('last admin') || msg.contains('administrator') || msg.contains('transférez')) {
        throw Exception('community_last_admin_error');
      }
      rethrow;
    } catch (e, st) {
      debugPrint('[COMMUNITY_SYNC] [Repository] Unexpected error during leave_community: $e\n$st');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> openCommunityRpc(String communityId) async {
    try {
      debugPrint('[CommunityRepository] Calling RPC open_community for communityId=$communityId');
      final response = await client.rpc('open_community', params: {
        'p_community_id': communityId,
      });
      if (response is Map) {
        return Map<String, dynamic>.from(response);
      } else if (response is String) {
        final decoded = jsonDecode(response);
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      }
      return {'destination': 'unavailable', 'reasons': ['COMMUNITY_UNAVAILABLE']};
    } catch (e, st) {
      debugPrint('[CommunityRepository] Error in open_community RPC: $e\n$st');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> joinCommunityRpc(String communityId) async {
    try {
      debugPrint('[CommunityRepository] Calling RPC join_community for communityId=$communityId');
      final response = await client.rpc('join_community', params: {
        'p_community_id': communityId,
      });
      if (response is Map) {
        return Map<String, dynamic>.from(response);
      } else if (response is String) {
        final decoded = jsonDecode(response);
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      }
      return {'success': true};
    } catch (e, st) {
      debugPrint('[CommunityRepository] Error in join_community RPC: $e\n$st');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> searchCommunityHashtags(String query, {int limit = 20}) async {
    try {
      final response = await client.rpc('search_community_hashtags', params: {
        'p_query': query.trim(),
        'p_limit': limit,
      });
      dynamic decoded = response;
      if (decoded is String) decoded = jsonDecode(decoded);
      if (decoded is Map) {
        decoded = decoded['items'] ?? decoded['results'] ?? decoded['data'] ?? [];
      }
      if (decoded is! List) return <Map<String, dynamic>>[];
      return decoded.whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } catch (e) {
      debugPrint('[CommunityRepository] search_community_hashtags failed: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getCommunityMembersRpc({
    required String communityId,
    int limit = 50,
    String? cursor,
    String? query,
  }) async {
    try {
      debugPrint('[CommunityRepository] Calling RPC get_community_members for communityId=$communityId, limit=$limit, cursor=$cursor, query=$query');
      final params = <String, dynamic>{
        'p_community_id': communityId,
        'p_limit': limit,
        'p_cursor': (cursor != null && cursor.isNotEmpty) ? cursor : null,
        'p_query': (query != null && query.isNotEmpty) ? query : null,
      };

      final response = await client.rpc('get_community_members', params: params);
      if (response is Map) {
        return Map<String, dynamic>.from(response);
      } else if (response is String) {
        final decoded = jsonDecode(response);
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      }
      return {'items': [], 'has_more': false};
    } on PostgrestException catch (e) {
      if (e.code == 'P0001' || e.message.toLowerCase().contains('masquée') || e.message.toLowerCase().contains('masque')) {
        debugPrint('[CommunityRepository] get_community_members: Members list is hidden for communityId=$communityId');
      } else {
        debugPrint('[CommunityRepository] PostgrestException in get_community_members: ${e.code} ${e.message}');
      }
      rethrow;
    } catch (e, st) {
      debugPrint('[CommunityRepository] Error in get_community_members RPC: $e\n$st');
      rethrow;
    }
  }

  /// Resolves the authenticated user's role within one specific community.
  ///
  /// Creator ownership is checked against communities.creator_id first. If the
  /// creator lookup is hidden by RLS, community_members.role remains the
  /// authoritative fallback (the creator is inserted there as admin).
  Future<String?> getCurrentUserCommunityRole(String communityId) async {
    final userId = client.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) return null;

    try {
      final community = await client
          .from('communities')
          .select('creator_id')
          .eq('id', communityId)
          .maybeSingle();
      if (community?['creator_id']?.toString() == userId) {
        return 'admin';
      }
    } catch (e) {
      debugPrint('[CommunityRepository] Creator lookup failed for $communityId: $e');
    }

    try {
      final membership = await client
          .from('community_members')
          .select('role')
          .eq('community_id', communityId)
          .eq('user_id', userId)
          .maybeSingle();
      final role = membership?['role']?.toString().trim().toLowerCase();
      if (role != null && role.isNotEmpty) return role;
    } catch (e) {
      debugPrint('[CommunityRepository] Membership role lookup failed for $communityId: $e');
    }

    return null;
  }

  Future<bool> isCommunityStaffRpc(String communityId) async {
    try {
      final response = await client.rpc('is_community_staff', params: {'p_community_id': communityId});
      return response == true || response == 1;
    } catch (e) {
      debugPrint('[CommunityRepository] Error in is_community_staff: $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getCommunityMembers(String communityId) async {
    try {
      final res = await getCommunityMembersRpc(communityId: communityId);
      final rawItems = res['items'] is List ? res['items'] as List : [];
      return rawItems.map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (e) {
      debugPrint('[CommunityRepository] getCommunityMembers error: $e');
      rethrow;
    }
  }

  Future<void> updateCommunityMemberRoleRpc({
    required String communityId,
    required String userId,
    required String newRole,
  }) async {
    try {
      debugPrint('[CommunityRepository] Calling RPC update_community_member_role communityId=$communityId, userId=$userId, newRole=$newRole');
      await client.rpc('update_community_member_role', params: {
        'p_community_id': communityId,
        'p_user_id': userId,
        'p_role': newRole,
      });
    } catch (e, st) {
      debugPrint('[CommunityRepository] Error in update_community_member_role RPC: $e\n$st');
      rethrow;
    }
  }

  Future<void> updateMemberRole(String communityId, String userId, String newRole) async {
    await updateCommunityMemberRoleRpc(
      communityId: communityId,
      userId: userId,
      newRole: newRole,
    );
  }

  Future<void> deletePost(String postId, {String? reason}) async {
    try {
      debugPrint('[DELETE] [Repository] Calling delete-community-post Edge Function for postId=$postId');
      final response = await client.functions.invoke(
        'delete-community-post',
        body: {
          'post_id': postId,
          if (reason != null && reason.isNotEmpty) 'reason': reason,
        },
      );

      final responseData = response.data;
      if (response.status < 200 || response.status >= 300) {
        final message = responseData is Map
            ? (responseData['error']?.toString() ?? 'delete_post_failed')
            : 'delete_post_failed';
        if (response.status == 401 || response.status == 403) {
          throw Exception('delete_unauthorized_error');
        }
        throw Exception(message);
      }
      if (responseData is Map && responseData['success'] != true) {
        throw Exception(responseData['error']?.toString() ?? 'delete_post_failed');
      }
      debugPrint('[DELETE] [Repository] Post and media cleanup completed for postId=$postId');
    } catch (e, st) {
      final message = e.toString().toLowerCase();
      if (message.contains('delete_unauthorized_error') ||
          message.contains('action non autorisée') ||
          message.contains('unauthorized') ||
          message.contains('status: 403') ||
          message.contains('status: 401')) {
        throw Exception('delete_unauthorized_error');
      }
      if (message.contains('post introuvable') ||
          message.contains('post not found') ||
          message.contains('status: 404')) {
        return;
      }
      debugPrint('[DELETE] [Repository] delete-community-post failed: $e\n$st');
      rethrow;
    }
  }

  Future<void> excludeCommunityMember(String communityId, String userId, {String? reason, bool deleteContent = false}) async {
    try {
      debugPrint('[MODERATION] [Repository] Calling RPC exclude_community_member communityId=$communityId, userId=$userId');
      await client.rpc('exclude_community_member', params: {
        'p_community_id': communityId,
        'p_user_id': userId,
        if (reason != null && reason.isNotEmpty) 'p_reason': reason,
        'p_delete_content': deleteContent,
      });
      debugPrint('[MODERATION] [Repository] RPC exclude_community_member successful.');
    } catch (e, st) {
      debugPrint('[MODERATION] [Repository] Error exclude_community_member: $e\n$st');
      rethrow;
    }
  }

  Future<void> unexcludeCommunityMember(String communityId, String userId) async {
    try {
      debugPrint('[MODERATION] [Repository] Calling RPC unexclude_community_member communityId=$communityId, userId=$userId');
      await client.rpc('unexclude_community_member', params: {
        'p_community_id': communityId,
        'p_user_id': userId,
      });
      debugPrint('[MODERATION] [Repository] RPC unexclude_community_member successful.');
    } catch (e, st) {
      debugPrint('[MODERATION] [Repository] Error unexclude_community_member: $e\n$st');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getCommunityExclusions(String communityId, {int limit = 30, int offset = 0}) async {
    try {
      final response = await client.rpc('get_community_exclusions', params: {
        'p_community_id': communityId,
        'p_limit': limit,
        'p_offset': offset,
      });
      if (response is Map) return Map<String, dynamic>.from(response);
      if (response == null) return {'items': [], 'total': 0, 'has_more': false};
      throw const FormatException('Réponse invalide du serveur pour les exclusions.');
    } catch (e) {
      debugPrint('[MODERATION] [Repository] Error get_community_exclusions: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getSignalementRaisons() async {
    try {
      final response = await client.from('signalement_raison').select().eq('est_actif', true);
      if (response is List) {
        return response.map((e) => Map<String, dynamic>.from(e)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('[MODERATION] [Repository] Error getSignalementRaisons: $e');
      return [];
    }
  }

  Future<void> reportContent({
    required String targetType,
    required String targetId,
    required String reasonId,
    String? description,
  }) async {
    try {
      debugPrint('[MODERATION] [Repository] Calling RPC report_content type=$targetType, targetId=$targetId, reasonId=$reasonId');
      await client.rpc('report_content', params: {
        'p_target_type': targetType,
        'p_target_id': targetId,
        'p_reason_id': reasonId,
        if (description != null && description.isNotEmpty) 'p_description': description,
      });
      debugPrint('[MODERATION] [Repository] RPC report_content successful.');
    } catch (e) {
      debugPrint('[MODERATION] [Repository] Error report_content: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getPlatformReports(String status, int limit, int offset) async {
    try {
      final response = await client.rpc('get_platform_reports', params: {
        'p_status': status,
        'p_limit': limit,
        'p_offset': offset,
      });
      if (response is Map) return Map<String, dynamic>.from(response);
      return {'items': [], 'has_more': false};
    } catch (e) {
      debugPrint('[MODERATION] [Repository] Error get_platform_reports: $e');
      return {'items': [], 'has_more': false};
    }
  }

  Future<Map<String, dynamic>> resolvePlatformReport(String reportId, String action, {String? note}) async {
    try {
      final response = await client.rpc('resolve_platform_report', params: {
        'p_report_id': reportId,
        'p_action': action,
        if (note != null && note.isNotEmpty) 'p_note': note,
      });
      if (response is Map) return Map<String, dynamic>.from(response);
      return {'updated': true, 'status': action};
    } catch (e) {
      debugPrint('[MODERATION] [Repository] Error resolve_platform_report: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> createPostRpc({
    required String p_id,
    required String p_content,
    String? p_community_id,
    String? p_audience,
    required List<Map<String, dynamic>> p_media,
    required List<String> p_hashtags,
    required List<String> p_mentions,
    required bool p_comments_enabled,
    required bool p_sharing_enabled,
    required bool p_reactions_enabled,
    Map<String, dynamic>? p_poll,
    bool? p_allow_promotion,
  }) async {
    Map<String, dynamic>? params;
    try {
      debugPrint('[POST] [Repository] Calling RPC create_post with p_id=$p_id, p_community_id=$p_community_id, p_audience=$p_audience, mediaCount=${p_media.length}');
      
      params = <String, dynamic>{
        'p_id': p_id,
        'p_content': p_content,
        'p_media': p_media,
        'p_hashtags': p_hashtags,
        'p_mentions': p_mentions,
        'p_comments_enabled': p_comments_enabled,
        'p_sharing_enabled': p_sharing_enabled,
        'p_reactions_enabled': p_reactions_enabled,
      };

      if (p_community_id != null && p_community_id.isNotEmpty) {
        params['p_community_id'] = p_community_id;
        if (p_allow_promotion != null) {
          params['p_allow_promotion'] = p_allow_promotion;
        }
      } else {
        if (p_audience != null && p_audience.isNotEmpty) {
          params['p_audience'] = p_audience;
        }
      }

      if (p_poll != null) {
        params['p_poll'] = p_poll;
      }

      final response = await client.rpc('create_post', params: params);

      debugPrint('[POST] [Repository] RPC create_post successful for p_id=$p_id, response=$response');
      if (response is Map) {
        return Map<String, dynamic>.from(response);
      }
      return {'id': p_id, 'success': true};
    } on PostgrestException catch (e) {
      debugPrint('[POST] [Repository] PostgrestException during create_post: code=${e.code}, message=${e.message}');
      
      if (e.code == '23505' || e.message.toLowerCase().contains('community_posts_pkey') || e.message.toLowerCase().contains('already exists')) {
        debugPrint('[POST] [Repository] Post p_id=$p_id already exists on server (idempotency success). Treating as success.');
        return {'id': p_id, 'success': true};
      }

      if (params != null && (e.code == 'PGRST202' || e.message.toLowerCase().contains('function create_post') || e.message.toLowerCase().contains('does not exist'))) {
        debugPrint('[POST] [Repository] Fallback to alias create_community_post');
        try {
          final response = await client.rpc('create_community_post', params: params);
          if (response is Map) return Map<String, dynamic>.from(response);
          return {'id': p_id, 'success': true};
        } on PostgrestException catch (fallbackE) {
          if (fallbackE.code == '23505' || fallbackE.message.toLowerCase().contains('community_posts_pkey') || fallbackE.message.toLowerCase().contains('already exists')) {
            debugPrint('[POST] [Repository] Fallback post p_id=$p_id already exists on server (idempotency success).');
            return {'id': p_id, 'success': true};
          }
          rethrow;
        }
      }
      rethrow;
    } catch (e, st) {
      debugPrint('[POST] [Repository] Unexpected error during create_post: $e\n$st');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> createCommunityPost({
    required String p_id,
    required String p_community_id,
    required String p_content,
    required List<Map<String, dynamic>> p_media,
    required List<String> p_hashtags,
    required List<String> p_mentions,
    required bool p_comments_enabled,
    required bool p_sharing_enabled,
    required bool p_reactions_enabled,
    Map<String, dynamic>? p_poll,
    bool? p_allow_promotion,
  }) async {
    return createPostRpc(
      p_id: p_id,
      p_content: p_content,
      p_community_id: p_community_id,
      p_media: p_media,
      p_hashtags: p_hashtags,
      p_mentions: p_mentions,
      p_comments_enabled: p_comments_enabled,
      p_sharing_enabled: p_sharing_enabled,
      p_reactions_enabled: p_reactions_enabled,
      p_poll: p_poll,
      p_allow_promotion: p_allow_promotion,
    );
  }

  Future<Map<String, dynamic>> getCommunityAccessRules(String communityId) async {
    try {
      final response = await client.rpc('get_community_access_rules', params: {'p_community_id': communityId});
      if (response is Map) return Map<String, dynamic>.from(response);
      return {};
    } catch (e) {
      debugPrint('[CommunityRepository] Error in getCommunityAccessRules: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getAvailableCountries() async {
    try {
      final response = await client
          .from('countries')
          .select('id, nom, code_iso')
          .eq('is_active', true)
          .order('nom');
      return (response as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
    } catch (e) {
      debugPrint('[CommunityRepository] Error in getAvailableCountries: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getAvailableCities() async {
    try {
      final response = await client
          .from('cities')
          .select('id, country_id, nom')
          .eq('is_active', true)
          .order('nom');
      return (response as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
    } catch (e) {
      debugPrint('[CommunityRepository] Error in getAvailableCities: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getCommunityManagementSettings(String communityId) async {
    final response = await client.rpc(
      'get_community_management_settings',
      params: {'p_community_id': communityId},
    );
    if (response is! Map) {
      throw const FormatException('Réponse invalide des paramètres de communauté.');
    }
    return Map<String, dynamic>.from(response);
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
    final params = <String, dynamic>{'p_community_id': communityId};
    if (visibility != null) params['p_visibility'] = visibility;
    if (requireManualApproval != null) params['p_require_manual_approval'] = requireManualApproval;
    if (membersListVisible != null) params['p_members_list_visible'] = membersListVisible;
    if (certificationRequired != null) params['p_certification_required'] = certificationRequired;
    if (countriesEnabled != null) params['p_countries_enabled'] = countriesEnabled;
    if (allowedCountries != null) params['p_allowed_countries'] = allowedCountries;
    if (citiesEnabled != null) params['p_cities_enabled'] = citiesEnabled;
    if (allowedCities != null) params['p_allowed_cities'] = allowedCities;
    if (genderRestriction != null) params['p_gender_restriction'] = genderRestriction;
    if (ageMin != null) params['p_age_min'] = ageMin;
    if (ageMax != null) params['p_age_max'] = ageMax;
    params['p_clear_age'] = clearAge;
    params['p_clear_age_min'] = clearAgeMin;
    params['p_clear_age_max'] = clearAgeMax;
    params['p_clear_gender'] = clearGender;
    if (allowReports != null) params['p_allow_reports'] = allowReports;
    if (allowComments != null) params['p_allow_comments'] = allowComments;
    if (allowReactions != null) params['p_allow_reactions'] = allowReactions;
    if (allowPostPromotion != null) params['p_allow_post_promotion'] = allowPostPromotion;
    final response = await client.rpc('update_community_management_settings', params: params);
    if (response is! Map) {
      throw const FormatException('Réponse invalide après sauvegarde des paramètres de communauté.');
    }
    return Map<String, dynamic>.from(response);
  }

  Future<void> updateCommunityAccessRules({
    required String p_id,
    bool? p_countries_enabled,
    List<String>? p_allowed_countries,
    bool? p_cities_enabled,
    List<String>? p_allowed_cities,
    bool? p_certification_required,
    String? p_gender_restriction,
    int? p_age_min,
    int? p_age_max,
    bool? p_clear_age,
    bool? p_clear_gender,
  }) async {
    try {
      final params = <String, dynamic>{'p_id': p_id};
      if (p_countries_enabled != null) params['p_countries_enabled'] = p_countries_enabled;
      if (p_allowed_countries != null) params['p_allowed_countries'] = p_allowed_countries;
      if (p_cities_enabled != null) params['p_cities_enabled'] = p_cities_enabled;
      if (p_allowed_cities != null) params['p_allowed_cities'] = p_allowed_cities;
      if (p_certification_required != null) params['p_certification_required'] = p_certification_required;
      if (p_gender_restriction != null) params['p_gender_restriction'] = p_gender_restriction;
      if (p_age_min != null) params['p_age_min'] = p_age_min;
      if (p_age_max != null) params['p_age_max'] = p_age_max;
      if (p_clear_age != null) params['p_clear_age'] = p_clear_age;
      if (p_clear_gender != null) params['p_clear_gender'] = p_clear_gender;

      await client.rpc('update_community_access_rules', params: params);
    } catch (e) {
      debugPrint('[CommunityRepository] Error in updateCommunityAccessRules: $e');
      rethrow;
    }
  }

  Future<void> updateCommunitySettings({
    required String p_id,
    required String p_visibility,
    required bool p_require_manual_approval,
  }) async {
    try {
      await client.rpc('update_community_settings', params: {
        'p_id': p_id,
        'p_visibility': p_visibility,
        'p_require_manual_approval': p_require_manual_approval,
      });
    } catch (e) {
      debugPrint('[CommunityRepository] Error in updateCommunitySettings: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getCommunityRules(String communityId) async {
    try {
      final response = await client
          .from('community_rules')
          .select()
          .eq('community_id', communityId)
          .order('order_index');
      return (response as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
    } catch (e) {
      debugPrint('[CommunityRepository] Error in getCommunityRules: $e');
      rethrow;
    }
  }

  Future<void> setCommunityRule({
    required String p_id,
    required String p_community_id,
    required String p_text,
    required int p_order_index,
  }) async {
    try {
      await client.rpc('set_community_rule', params: {
        'p_id': p_id,
        'p_community_id': p_community_id,
        'p_text': p_text,
        'p_order_index': p_order_index,
      });
    } catch (e) {
      debugPrint('[CommunityRepository] Error in setCommunityRule: $e');
      rethrow;
    }
  }

  Future<void> deleteCommunityRule(String p_id) async {
    try {
      await client.rpc('delete_community_rule', params: {'p_id': p_id});
    } catch (e) {
      debugPrint('[CommunityRepository] Error in deleteCommunityRule: $e');
      rethrow;
    }
  }


  Future<void> setCommunityPostSharingEnabled({
    required String communityId,
    required bool enabled,
  }) async {
    await client.rpc('set_community_post_sharing_enabled', params: {
      'p_community_id': communityId,
      'p_enabled': enabled,
    });
  }

  Future<void> updateCommunityPostSettings({
    required String communityId,
    required String postPermission,
    required bool postsRequireApproval,
  }) async {
    try {
      await client.rpc('update_community_post_settings', params: {
        'p_community_id': communityId,
        'p_post_permission': postPermission,
        'p_posts_require_approval': postsRequireApproval,
      });
    } catch (e) {
      debugPrint('[CommunityRepository] Error in updateCommunityPostSettings: $e');
      rethrow;
    }
  }

  Future<void> updateCommunityFeatures({
    required String communityId,
    bool? membersListVisible,
    bool? allowReports,
    bool? allowComments,
    bool? allowReactions,
  }) async {
    final params = <String, dynamic>{'p_community_id': communityId};
    if (membersListVisible != null) params['p_members_list_visible'] = membersListVisible;
    if (allowReports != null) params['p_allow_reports'] = allowReports;
    if (allowComments != null) params['p_allow_comments'] = allowComments;
    if (allowReactions != null) params['p_allow_reactions'] = allowReactions;
    if (params.length == 1) return;
    try {
      await client.rpc('update_community_features', params: params);
    } catch (e) {
      debugPrint('[CommunityRepository] Error in updateCommunityFeatures: $e');
      rethrow;
    }
  }

  Future<void> updateCommunityInfo({
    required String p_id,
    required String p_name,
    String? p_slogan,
    required String p_description,
    String? p_photo_profile,
    String? p_photo_cover,
  }) async {
    try {
      final params = <String, dynamic>{
        'p_id': p_id,
        'p_name': p_name,
        'p_description': p_description,
      };
      if (p_slogan != null) params['p_slogan'] = p_slogan;
      if (p_photo_profile != null) params['p_photo_profile'] = p_photo_profile;
      if (p_photo_cover != null) params['p_photo_cover'] = p_photo_cover;

      await client.rpc('update_community_info', params: params);
    } catch (e) {
      debugPrint('[CommunityRepository] Error in updateCommunityInfo: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getCommunityModerationCounts(String communityId) async {
    try {
      final response = await client.rpc('get_community_moderation_counts', params: {'p_community_id': communityId});
      if (response is! Map) {
        throw const FormatException('Réponse invalide des compteurs de modération.');
      }
      final data = Map<String, dynamic>.from(response);
      return {
        ...data,
        'pending_reports': (data['reports'] as num?)?.toInt() ?? 0,
        'pending_join_requests': (data['join_requests'] as num?)?.toInt() ?? 0,
        'pending_posts': (data['pending_posts'] as num?)?.toInt() ?? 0,
      };
    } catch (e) {
      debugPrint('[CommunityRepository] Error in getCommunityModerationCounts: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getCommunityReports(String communityId, {String status = 'open', int limit = 20, int offset = 0}) async {
    try {
      final response = await client.rpc('get_community_reports', params: {
        'p_community_id': communityId,
        'p_status': status,
        'p_limit': limit,
        'p_offset': offset,
      });
      if (response is Map) return Map<String, dynamic>.from(response);
      return {'items': [], 'has_more': false};
    } catch (e) {
      debugPrint('[CommunityRepository] Error in getCommunityReports: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> resolveCommunityReport(String reportId, String action, {String? note}) async {
    try {
      final params = <String, dynamic>{
        'p_report_id': reportId,
        'p_action': action,
      };
      if (note != null && note.isNotEmpty) params['p_note'] = note;
      final response = await client.rpc('resolve_community_report', params: params);
      if (response is Map) return Map<String, dynamic>.from(response);
      return {'success': true};
    } catch (e) {
      debugPrint('[CommunityRepository] Error in resolveCommunityReport: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getCommunityPendingPosts(String communityId, {int limit = 20, int offset = 0}) async {
    try {
      final response = await client.rpc('get_community_pending_posts', params: {
        'p_community_id': communityId,
        'p_limit': limit,
        'p_offset': offset,
      });
      if (response is! Map) {
        throw const FormatException('Réponse invalide des publications en attente.');
      }
      return Map<String, dynamic>.from(response);
    } catch (e) {
      debugPrint('[CommunityRepository] Error in getCommunityPendingPosts: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getCommunityAlerts(String communityId) async {
    try {
      final response = await client.rpc('get_community_alerts', params: {
        'p_community_id': communityId,
      });
      if (response is Map) return Map<String, dynamic>.from(response);
      return {'items': [], 'count': 0};
    } catch (e) {
      debugPrint('[CommunityRepository] Error in getCommunityAlerts: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getCommunitySpamQueue(
    String communityId, {
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final response = await client.rpc('get_community_spam_queue', params: {
        'p_community_id': communityId,
        'p_limit': limit,
        'p_offset': offset,
      });
      if (response is Map) return Map<String, dynamic>.from(response);
      return {'items': [], 'has_more': false};
    } catch (e) {
      debugPrint('[CommunityRepository] Error in getCommunitySpamQueue: $e');
      rethrow;
    }
  }

  Future<void> moderateCommunityPost(String postId, String action, {String? reason}) async {
    try {
      final params = <String, dynamic>{
        'p_post_id': postId,
        'p_action': action,
      };
      if (reason != null && reason.isNotEmpty) params['p_reason'] = reason;
      await client.rpc('moderate_community_post', params: params);
    } catch (e) {
      debugPrint('[CommunityRepository] Error in moderateCommunityPost: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getCommunityJoinRequests(String communityId, {int limit = 20, String? cursor}) async {
    try {
      final params = <String, dynamic>{
        'p_community_id': communityId,
        'p_limit': limit,
      };
      if (cursor != null && cursor.isNotEmpty) params['p_cursor'] = cursor;
      final response = await client.rpc('get_community_join_requests', params: params);
      if (response is! Map) {
        throw const FormatException('Réponse invalide des demandes d’adhésion.');
      }
      return Map<String, dynamic>.from(response);
    } catch (e) {
      debugPrint('[CommunityRepository] Error in getCommunityJoinRequests: $e');
      rethrow;
    }
  }

  Future<void> respondCommunityJoinRequest(String requestId, bool accepted) async {
    try {
      await client.rpc('respond_community_join_request', params: {
        'p_request_id': requestId,
        'p_accepted': accepted,
      });
    } catch (e) {
      debugPrint('[CommunityRepository] Error in respondCommunityJoinRequest: $e');
      rethrow;
    }
  }

  Future<void> transferCommunityOwnership({
    required String communityId,
    required String toUserId,
  }) async {
    try {
      await client.rpc('transfer_community_ownership', params: {
        'p_community_id': communityId,
        'p_to_user_id': toUserId,
      });
    } catch (e) {
      debugPrint('[CommunityRepository] Error in transferCommunityOwnership: $e');
      rethrow;
    }
  }

  Future<void> deleteCommunity(String communityId) async {
    try {
      await client.rpc('delete_community', params: {'p_id': communityId});
    } catch (e) {
      debugPrint('[CommunityRepository] Error in deleteCommunity: $e');
      rethrow;
    }
  }

  Future<void> leaveCommunityAndReport({
    required String communityId,
    required String reasonId,
    required String description,
  }) async {
    try {
      await client.rpc('leave_community_and_report', params: {
        'p_community_id': communityId,
        'p_reason_id': reasonId,
        'p_description': description,
      });
    } catch (e) {
      debugPrint('[CommunityRepository] Error in leaveCommunityAndReport: $e');
      rethrow;
    }
  }

  Future<void> updateCommunityMemberVisibility(String communityId, bool membersListVisible) async {
    try {
      await client.rpc('update_community_member_visibility', params: {
        'p_community_id': communityId,
        'p_members_list_visible': membersListVisible,
      });
    } catch (e) {
      debugPrint('[CommunityRepository] Error in updateCommunityMemberVisibility: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getCommunityUserReports(String communityId, {String status = 'open', int limit = 20, int offset = 0}) async {
    try {
      final response = await client.rpc('get_community_user_reports', params: {
        'p_community_id': communityId,
        'p_status': status,
        'p_limit': limit,
        'p_offset': offset,
      });
      if (response is Map) return Map<String, dynamic>.from(response);
      return {'items': [], 'has_more': false};
    } catch (e) {
      debugPrint('[CommunityRepository] Error in getCommunityUserReports: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> resolveCommunityUserReport(String reportId, String action, {String? note, bool deleteContent = false}) async {
    try {
      final params = <String, dynamic>{
        'p_report_id': reportId,
        'p_action': action,
        'p_delete_content': deleteContent,
      };
      if (note != null && note.isNotEmpty) params['p_note'] = note;
      final response = await client.rpc('resolve_community_user_report', params: params);
      if (response is Map) return Map<String, dynamic>.from(response);
      return {'success': true};
    } catch (e) {
      debugPrint('[CommunityRepository] Error in resolveCommunityUserReport: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getAvailableInterests() async {
    try {
      final response = await client.from('interests').select().order('name');
      return (response as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
    } catch (e) {
      debugPrint('[CommunityRepository] Error in getAvailableInterests: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getCommunityInterests(String communityId) async {
    try {
      final response = await client.rpc('get_community_interests', params: {'p_community_id': communityId});
      if (response is List) {
        return response.map((e) => Map<String, dynamic>.from(e)).toList();
      }
      if (response is Map && response['items'] is List) {
        return (response['items'] as List)
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      throw const FormatException('Réponse invalide des centres d’intérêt de la communauté.');
    } catch (rpcError) {
      // Older deployments expose the relation but do not have the optional read RPC.
      try {
        final response = await client
            .from('community_interests')
            .select('interests(id, name, category, icon_url)')
            .eq('community_id', communityId);
        return (response as List).map((entry) {
          final item = Map<String, dynamic>.from(entry as Map);
          final interest = item['interests'];
          if (interest is! Map) {
            throw const FormatException('Centre d’intérêt associé introuvable.');
          }
          return Map<String, dynamic>.from(interest);
        }).toList();
      } catch (fallbackError) {
        debugPrint('[CommunityRepository] RPC getCommunityInterests failed: $rpcError');
        debugPrint('[CommunityRepository] Relation fallback failed: $fallbackError');
        rethrow;
      }
    }
  }

  Future<void> updateCommunityInterests(String communityId, List<String> interestIds) async {
    try {
      await client.rpc('update_community_interests', params: {
        'p_community_id': communityId,
        'p_interest_ids': interestIds,
      });
    } catch (e) {
      debugPrint('[CommunityRepository] Error in updateCommunityInterests: $e');
      rethrow;
    }
  }
}
