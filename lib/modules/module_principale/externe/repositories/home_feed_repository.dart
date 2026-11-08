import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:scrole/modules/module_principale/centre/models/community_post.dart';
import 'package:scrole/shared/models/post_media.dart';

class SuggestedProfileModel {
  final String id;
  final String name;
  final String username;
  final String? photoUrl;
  final String reasonSubtitle;
  final bool isCertified;
  bool isAdded;
  bool isRequestSent;

  SuggestedProfileModel({
    required this.id,
    required this.name,
    required this.username,
    this.photoUrl,
    required this.reasonSubtitle,
    this.isCertified = false,
    this.isAdded = false,
    this.isRequestSent = false,
  });

  factory SuggestedProfileModel.fromJson(Map<String, dynamic> json) {
    final username = (json['username'] ?? '').toString();
    final fullName = (json['full_name'] ?? json['name'] ?? json['display_name'] ?? '').toString().trim();
    final mutual = (json['mutual_friends_count'] as num?)?.toInt() ?? 0;
    final String reasonKey;
    final Map<String, String> reasonParams;
    if (mutual > 0) {
      reasonKey = 'home_feed_profile_reason_mutual_friends';
      reasonParams = {'count': mutual.toString()};
    } else if (json['same_city'] == true) {
      reasonKey = 'home_feed_profile_reason_same_city';
      reasonParams = const {};
    } else if (json['common_community'] == true) {
      reasonKey = 'home_feed_profile_reason_common_community';
      reasonParams = const {};
    } else if (((json['common_interests_count'] as num?)?.toInt() ?? 0) > 0) {
      reasonKey = 'home_feed_profile_reason_common_interests';
      reasonParams = const {};
    } else {
      reasonKey = 'home_feed_profile_reason_discover';
      reasonParams = const {};
    }
    return SuggestedProfileModel(
      id: (json['user_id'] ?? json['id'] ?? '').toString(),
      name: fullName.isNotEmpty ? fullName : username,
      username: username,
      photoUrl: (json['photo_url'] ?? json['avatar_url'])?.toString(),
      reasonSubtitle: reasonKey.trParams(reasonParams),
      isCertified: json['is_certified'] == true || json['is_verified'] == true,
      isAdded: json['is_added'] == true || json['is_following'] == true,
      isRequestSent: json['request_sent'] == true,
    );
  }
}

class HomeFeedRepository {
  final SupabaseClient client;

  HomeFeedRepository([SupabaseClient? client])
      : client = client ?? _getOrCreateClient();

  static SupabaseClient _getOrCreateClient() {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return SupabaseClient('https://example.supabase.co', 'dummyKey');
    }
  }

  Future<Map<String, dynamic>> getHomeFeed({int limit = 20, String? cursor}) async {
    try {
      debugPrint('[HOME_FEED] Calling RPC get_home_feed with p_limit=$limit, p_cursor=$cursor');
      final params = <String, dynamic>{
        'p_limit': limit,
      };
      if (cursor != null && cursor.isNotEmpty) {
        params['p_cursor'] = cursor;
      }

      final response = await client.rpc('get_home_feed', params: params);
      debugPrint('[HOME_FEED] RPC get_home_feed raw response type: ${response.runtimeType}');

      List rawItems = [];
      String? nextCursor;
      bool hasMore = false;

      if (response is Map) {
        rawItems = response['items'] as List? ?? response['data'] as List? ?? [];
        nextCursor = response['next_cursor']?.toString() ?? response['nextCursor']?.toString();
        hasMore = response['has_more'] == true || response['hasMore'] == true || nextCursor != null;
      } else if (response is List) {
        rawItems = response;
      }

      final List<CommunityPost> items = [];
      final Set<String> seenIds = {};
      int postCount = 0;

      for (final row in rawItems) {
        if (row is Map) {
          final map = Map<String, dynamic>.from(row);
          final id = map['id']?.toString() ?? map['post_id']?.toString() ?? '';
          if (id.isEmpty || seenIds.contains(id)) continue;
          seenIds.add(id);

          final post = _parsePost(map);
          items.add(post);
          postCount++;
        }
      }

      debugPrint('[HOME_FEED] get_home_feed success: items_count=$postCount, next_cursor=$nextCursor, has_more=$hasMore');
      return {
        'items': items,
        'next_cursor': nextCursor,
        'has_more': hasMore,
      };
    } on PostgrestException catch (e) {
      debugPrint('[HOME_FEED] PostgrestException in get_home_feed: code=${e.code}, message=${e.message}');
      rethrow;
    } catch (e, st) {
      debugPrint('[HOME_FEED] Unexpected error in get_home_feed: $e\n$st');
      rethrow;
    }
  }

  /// Returns only active campaigns whose targeting matches the current user.
  /// The database RPC enforces status, dates and audience filters server-side.
  Future<List<CommunityPost>> getTargetedPromotionCampaigns({int limit = 10}) async {
    try {
      final response = await client.rpc('get_targeted_promotion_campaigns');
      if (response is! List) return const [];
      final campaigns = <CommunityPost>[];
      for (final entry in response) {
        if (entry is! Map) continue;
        final row = Map<String, dynamic>.from(entry);
        final campaignId = (row['id'] ?? '').toString();
        if (campaignId.isEmpty) continue;
        final mediaUrls = row['media_urls'] is List
            ? (row['media_urls'] as List).map((value) => value.toString()).where((value) => value.trim().isNotEmpty).toList()
            : <String>[];
        final postType = (row['post_type'] ?? 'text').toString().toLowerCase();
        final media = mediaUrls.map((url) => PostMedia(
          type: postType == 'video' ? 'video' : 'photo',
          url: url,
        )).toList();
        final rawOptions = row['poll_options'];
        final options = rawOptions is List
            ? rawOptions.map((option) {
                if (option is Map) {
                  final item = Map<String, dynamic>.from(option);
                  return <String, dynamic>{'label': (item['label'] ?? item['text'] ?? '').toString()};
                }
                return <String, dynamic>{'label': option.toString()};
              }).where((item) => (item['label'] as String).trim().isNotEmpty).toList()
            : <Map<String, dynamic>>[];
        campaigns.add(CommunityPost(
          id: 'promotion_$campaignId',
          authorName: 'Scrole',
          authorId: 'scrole_promotion',
          authorObj: const CommunityPostAuthor(
            userId: 'scrole_promotion',
            username: 'Scrole',
          ),
          timeAgo: (row['created_at'] ?? DateTime.now().toIso8601String()).toString(),
          content: (row['content'] ?? '').toString(),
          media: media,
          poll: postType == 'poll' && options.isNotEmpty
              ? <String, dynamic>{'question': (row['title'] ?? '').toString(), 'options': options}
              : null,
          reactionsEnabled: false,
          commentsEnabled: false,
          sharingEnabled: false,
        ));
      }
      return campaigns.take(limit).toList(growable: false);
    } on PostgrestException catch (e) {
      debugPrint('[PROMOTIONS] Unable to load targeted campaigns: ${e.code} ${e.message}');
      return const [];
    } catch (e, st) {
      debugPrint('[PROMOTIONS] Unexpected campaign loading error: $e\\n$st');
      return const [];
    }
  }

  Future<void> hidePost(String postId) async {
    try {
      debugPrint('[HOME_FEED] Calling RPC hide_post with p_post_id=$postId');
      try {
        await client.rpc('hide_post', params: {'p_post_id': postId});
      } catch (_) {
        await client.rpc('hide_post', params: {'p_id': postId});
      }
      debugPrint('[HOME_FEED] RPC hide_post successful for postId=$postId');
    } on PostgrestException catch (e) {
      debugPrint('[HOME_FEED] PostgrestException in hide_post: code=${e.code}, message=${e.message}');
      rethrow;
    } catch (e, st) {
      debugPrint('[HOME_FEED] Unexpected error in hide_post: $e\n$st');
      rethrow;
    }
  }

  Future<int> recordPostDwell(List<Map<String, dynamic>> items) async {
    if (items.isEmpty) return 0;
    if (items.length > 100) {
      throw ArgumentError('record_post_dwell accepts at most 100 items');
    }
    try {
      final response = await client.rpc(
        'record_post_dwell',
        params: {'p_items': items},
      );
      return response is num ? response.toInt() : 0;
    } catch (e, st) {
      debugPrint('[POST_DWELL] Error recording dwell batch: $e\\n$st');
      rethrow;
    }
  }

  Future<void> recordPostViews(List<String> postIds) async {
    if (postIds.isEmpty) return;
    try {
      debugPrint('[POST_ACTIONS] Calling RPC record_post_views with ${postIds.length} IDs');
      await client.rpc('record_post_views', params: {'p_post_ids': postIds});
    } catch (e, st) {
      debugPrint('[POST_ACTIONS] Error in record_post_views (ignored): $e\n$st');
    }
  }

  Future<void> reactToCommunityPost(String postId, String reaction) async {
    try {
      debugPrint('[POST_ACTIONS] Calling RPC react_to_community_post with p_post_id=$postId, p_reaction=$reaction');
      await client.rpc('react_to_community_post', params: {
        'p_post_id': postId,
        'p_reaction': reaction,
      });
      debugPrint('[POST_ACTIONS] RPC react_to_community_post successful for postId=$postId');
    } catch (e, st) {
      debugPrint('[POST_ACTIONS] Error in react_to_community_post: $e\n$st');
      rethrow;
    }
  }

  Future<void> removeCommunityPostReaction(String postId) async {
    try {
      debugPrint('[POST_ACTIONS] Calling RPC remove_community_post_reaction with p_post_id=$postId');
      await client.rpc('remove_community_post_reaction', params: {
        'p_post_id': postId,
      });
      debugPrint('[POST_ACTIONS] RPC remove_community_post_reaction successful for postId=$postId');
    } catch (e, st) {
      debugPrint('[POST_ACTIONS] Error in remove_community_post_reaction: $e\n$st');
      rethrow;
    }
  }

  Future<CommunityPost> getPost(String postId) async {
    try {
      debugPrint('[POST_ACTIONS] Calling RPC get_post with p_post_id=$postId');
      final response = await client.rpc('get_post', params: {'p_post_id': postId});
      if (response is Map) {
        return _parsePost(Map<String, dynamic>.from(response));
      }
      throw Exception('Publication indisponible');
    } on PostgrestException catch (e) {
      debugPrint('[POST_ACTIONS] PostgrestException in get_post: ${e.message}');
      throw Exception('Publication indisponible');
    } catch (e) {
      debugPrint('[POST_ACTIONS] Error in get_post: $e');
      throw Exception('Publication indisponible');
    }
  }

  Future<Map<String, dynamic>> sharePost({
    required String p_id,
    required String p_original_post_id,
    String? p_community_id,
    String p_audience = 'public',
    String? p_comment,
  }) async {
    try {
      debugPrint('[POST_ACTIONS] Calling RPC share_post with p_id=$p_id, original=$p_original_post_id, community=$p_community_id, audience=$p_audience');
      final params = <String, dynamic>{
        'p_id': p_id,
        'p_original_post_id': p_original_post_id,
        'p_audience': p_audience,
      };
      if (p_community_id != null && p_community_id.isNotEmpty) {
        params['p_community_id'] = p_community_id;
      }
      if (p_comment != null && p_comment.isNotEmpty) {
        params['p_comment'] = p_comment;
      }

      final response = await client.rpc('share_post', params: params);
      debugPrint('[POST_ACTIONS] RPC share_post successful: $response');
      if (response is Map) return Map<String, dynamic>.from(response);
      return {'id': p_id, 'success': true};
    } on PostgrestException catch (e) {
      debugPrint('[POST_ACTIONS] PostgrestException in share_post: code=${e.code}, message=${e.message}');
      final msg = e.message.toLowerCase();
      if (msg.contains('désactivé') || msg.contains('disabled')) {
        throw Exception('share_disabled_error');
      }
      if (msg.contains('déjà partagé') || msg.contains('already shared')) {
        throw Exception('already_shared_error');
      }
      rethrow;
    } catch (e, st) {
      debugPrint('[POST_ACTIONS] Unexpected error in share_post: $e\n$st');
      rethrow;
    }
  }

  Future<List<SuggestedProfileModel>> getSuggestedProfiles({int limit = 10, int offset = 0}) async {
    try {
      debugPrint('[HOME_FEED] Calling RPC get_suggested_profiles with p_limit=$limit, p_offset=$offset');
      final response = await client.rpc('get_suggested_profiles', params: {
        'p_limit': limit,
        'p_offset': offset,
      });
      debugPrint('[HOME_FEED] RPC get_suggested_profiles response count: ${response is List ? response.length : 1}');
      final rawItems = response is List
          ? response
          : response is Map
              ? (response['items'] as List? ?? const [])
              : const [];
      return rawItems
          .whereType<Map>()
          .map((e) => SuggestedProfileModel.fromJson(Map<String, dynamic>.from(e)))
          .where((profile) => profile.id.isNotEmpty)
          .toList(growable: false);
    } catch (e) {
      debugPrint('[HOME_FEED] get_suggested_profiles error: $e');
      return [];
    }
  }

  Future<void> dismissSuggestedProfile(String userId) async {
    await client.rpc('dismiss_suggested_profile', params: {'p_user_id': userId});
  }

  /// Returns live hashtag trends calculated from visible posts in the last 30 minutes and 24 hours.
  Future<List<Map<String, dynamic>>> getTrendingHashtags({int limit = 20}) async {
    final response = await client.rpc('get_trending_hashtags', params: {
      'p_limit': limit,
    });
    if (response is! List) return <Map<String, dynamic>>[];
    return response
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> getPostsByHashtag(
    String hashtag, {
    int limit = 20,
    String? cursor,
  }) async {
    final normalized = hashtag.trim().replaceFirst(RegExp(r'^#+'), '').toLowerCase();
    if (normalized.isEmpty) {
      return {'items': <CommunityPost>[], 'next_cursor': null, 'has_more': false};
    }

    final params = <String, dynamic>{
      'p_hashtag': normalized,
      'p_limit': limit,
      if (cursor != null && cursor.isNotEmpty) 'p_cursor': cursor,
    };
    final response = await client.rpc('get_posts_by_hashtag', params: params);
    List rawItems = [];
    String? nextCursor;
    bool hasMore = false;
    if (response is Map) {
      rawItems = response['items'] as List? ?? [];
      nextCursor = response['next_cursor']?.toString();
      hasMore = response['has_more'] == true || nextCursor != null;
    } else if (response is List) {
      rawItems = response;
    }

    final items = <CommunityPost>[];
    final seen = <String>{};
    for (final row in rawItems) {
      if (row is! Map) continue;
      final map = Map<String, dynamic>.from(row);
      final id = (map['id'] ?? map['post_id'] ?? '').toString();
      if (id.isEmpty || !seen.add(id)) continue;
      items.add(_parsePost(map));
    }
    return {
      'items': items,
      'next_cursor': nextCursor,
      'has_more': hasMore,
      'total_posts': response is Map ? (response['total_posts'] as num?)?.toInt() ?? items.length : items.length,
      'total_views': response is Map ? (response['total_views'] as num?)?.toInt() ?? 0 : 0,
      'total_likes': response is Map ? (response['total_likes'] as num?)?.toInt() ?? 0 : 0,
    };
  }

  CommunityPost _parsePost(Map<String, dynamic> map) {
    return CommunityPost.fromMap(map);
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
      debugPrint('[DELETE] [Repository] delete-community-post failed: $e\\n$st');
      rethrow;
    }
  }

  Future<String?> setCommunityPostReaction(String postId, String? reaction) async {
    try {
      debugPrint('[POST_ACTIONS] Calling RPC set_community_post_reaction postId=$postId, reaction=$reaction');
      final response = await client.rpc('set_community_post_reaction', params: {
        'p_post_id': postId,
        'p_reaction': reaction,
      });
      debugPrint('[POST_ACTIONS] RPC set_community_post_reaction result: $response');
      return response?.toString();
    } catch (e, st) {
      debugPrint('[POST_ACTIONS] Error in set_community_post_reaction: $e\n$st');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getCommunityPostComments(String postId, {int limit = 20, String? cursor}) async {
    try {
      debugPrint('[POST_ACTIONS] Calling RPC get_community_post_comments postId=$postId, limit=$limit, cursor=$cursor');
      final params = <String, dynamic>{
        'p_post_id': postId,
        'p_limit': limit,
      };
      if (cursor != null && cursor.isNotEmpty) params['p_cursor'] = cursor;
      final response = await client.rpc('get_community_post_comments', params: params);
      if (response is Map) return Map<String, dynamic>.from(response);
      return {'items': [], 'has_more': false};
    } catch (e, st) {
      debugPrint('[POST_ACTIONS] Error in get_community_post_comments: $e\n$st');
      return {'items': [], 'has_more': false};
    }
  }

  Future<Map<String, dynamic>> getCommunityCommentReplies(String commentId, {int limit = 20, String? cursor}) async {
    try {
      debugPrint('[POST_ACTIONS] Calling RPC get_community_comment_replies commentId=$commentId, limit=$limit, cursor=$cursor');
      final params = <String, dynamic>{
        'p_comment_id': commentId,
        'p_limit': limit,
      };
      if (cursor != null && cursor.isNotEmpty) params['p_cursor'] = cursor;
      final response = await client.rpc('get_community_comment_replies', params: params);
      if (response is Map) return Map<String, dynamic>.from(response);
      return {'items': [], 'has_more': false};
    } catch (e, st) {
      debugPrint('[POST_ACTIONS] Error in get_community_comment_replies: $e\n$st');
      return {'items': [], 'has_more': false};
    }
  }

  Future<List<Map<String, dynamic>>> getPostCounters(List<String> postIds) async {
    if (postIds.isEmpty) return [];
    try {
      debugPrint('[POST_ACTIONS] Calling RPC get_post_counters with ${postIds.length} IDs');
      final response = await client.rpc('get_post_counters', params: {'p_post_ids': postIds});
      if (response is List) {
        return response.map((e) => Map<String, dynamic>.from(e)).toList();
      }
      return [];
    } catch (e) {
      // Counter refresh is best-effort; keep transient network failures concise.
      debugPrint('[POST_ACTIONS] get_post_counters failed (will retry later): $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> commentCommunityPost({
    required String p_id,
    required String postId,
    required String content,
    List<String>? mentions,
    String? parentCommentId,
  }) async {
    try {
      debugPrint('[POST_ACTIONS] Calling RPC comment_community_post postId=$postId, p_id=$p_id, parent_comment_id=$parentCommentId');
      final params = <String, dynamic>{
        'p_id': p_id,
        'p_post_id': postId,
        'p_content': content,
      };
      if (mentions != null && mentions.isNotEmpty) params['p_mentions'] = mentions;
      if (parentCommentId != null && parentCommentId.isNotEmpty) params['p_parent_comment_id'] = parentCommentId;
      final response = await client.rpc('comment_community_post', params: params);
      if (response is Map) return Map<String, dynamic>.from(response);
      return {'id': p_id, 'success': true};
    } catch (e, st) {
      debugPrint('[POST_ACTIONS] Error in comment_community_post: $e\n$st');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> replyToCommunityComment({
    required String p_id,
    required String commentId,
    required String content,
    List<String>? mentions,
  }) async {
    try {
      debugPrint('[POST_ACTIONS] Calling RPC reply_to_community_comment commentId=$commentId, p_id=$p_id');
      final params = <String, dynamic>{
        'p_id': p_id,
        'p_comment_id': commentId,
        'p_content': content,
      };
      if (mentions != null && mentions.isNotEmpty) params['p_mentions'] = mentions;
      final response = await client.rpc('reply_to_community_comment', params: params);
      if (response is Map) return Map<String, dynamic>.from(response);
      return {'id': p_id, 'success': true};
    } catch (e, st) {
      debugPrint('[POST_ACTIONS] Error in reply_to_community_comment: $e\n$st');
      rethrow;
    }
  }

  Future<void> deleteCommunityComment(String commentId) async {
    try {
      debugPrint('[POST_ACTIONS] Calling RPC delete_community_comment commentId=$commentId');
      await client.rpc('delete_community_comment', params: {'p_id': commentId});
    } catch (e, st) {
      debugPrint('[POST_ACTIONS] Error in delete_community_comment: $e\n$st');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> setCommentReaction(String commentId, String? reaction) async {
    try {
      debugPrint('[POST_ACTIONS] Calling RPC set_comment_reaction commentId=$commentId, reaction=$reaction');
      final response = await client.rpc('set_comment_reaction', params: {
        'p_comment_id': commentId,
        'p_reaction': reaction,
      });
      if (response is Map) return Map<String, dynamic>.from(response);
      return {'reaction': reaction};
    } catch (e, st) {
      debugPrint('[POST_ACTIONS] Error in set_comment_reaction: $e\n$st');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> shareComment({
    required String p_id,
    required String p_comment_id,
    String? p_community_id,
    String p_audience = 'public',
    String? p_comment,
  }) async {
    try {
      debugPrint('[POST_ACTIONS] Calling RPC share_comment with p_id=$p_id, commentId=$p_comment_id');
      final params = <String, dynamic>{
        'p_id': p_id,
        'p_comment_id': p_comment_id,
        'p_audience': p_audience,
      };
      if (p_community_id != null && p_community_id.isNotEmpty) params['p_community_id'] = p_community_id;
      if (p_comment != null && p_comment.isNotEmpty) params['p_comment'] = p_comment;

      final response = await client.rpc('share_comment', params: params);
      if (response is Map) return Map<String, dynamic>.from(response);
      return {'id': p_id, 'success': true};
    } catch (e, st) {
      debugPrint('[POST_ACTIONS] Error in share_comment: $e\n$st');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getCommentThread(String commentId) async {
    try {
      debugPrint('[POST_ACTIONS] Calling RPC get_comment_thread commentId=$commentId');
      final response = await client.rpc('get_comment_thread', params: {'p_comment_id': commentId});
      if (response is Map) return Map<String, dynamic>.from(response);
      return {};
    } catch (e, st) {
      debugPrint('[POST_ACTIONS] Error in get_comment_thread: $e\n$st');
      rethrow;
    }
  }

  bool isAuthorActiveAndValid(Map<String, dynamic> postMap) {
    final authorMap = postMap['author'] is Map ? Map<String, dynamic>.from(postMap['author']) : <String, dynamic>{};

    final status = (authorMap['account_status'] ?? authorMap['status'] ?? postMap['author_status'] ?? 'active').toString().toLowerCase();
    if (status != 'active' || status == 'suspended' || status == 'banned' || status == 'deleted') {
      return false;
    }

    if (authorMap['deleted_at'] != null || authorMap['is_deleted'] == true || postMap['author_deleted_at'] != null) {
      return false;
    }

    if (postMap['shared_post'] is Map) {
      final spMap = Map<String, dynamic>.from(postMap['shared_post']);
      final spAuthorMap = spMap['author'] is Map ? Map<String, dynamic>.from(spMap['author']) : <String, dynamic>{};
      final spStatus = (spAuthorMap['account_status'] ?? spAuthorMap['status'] ?? spMap['author_status'] ?? 'active').toString().toLowerCase();
      if (spStatus != 'active' || spAuthorMap['deleted_at'] != null || spAuthorMap['is_deleted'] == true) {
        postMap['shared_post'] = null;
      }
    }

    return true;
  }

  Future<Map<String, dynamic>> getCommunityFeed(String communityId, {int limit = 20, String? cursor}) async {
    try {
      debugPrint('[COMMUNITY_FEED] Calling RPC get_community_feed communityId=$communityId, limit=$limit, cursor=$cursor');
      final params = <String, dynamic>{
        'p_community_id': communityId,
        'p_limit': limit,
      };
      if (cursor != null && cursor.isNotEmpty) params['p_cursor'] = cursor;
      final response = await client.rpc('get_community_feed', params: params);
      if (response is Map) {
        final rawItems = response['items'] is List ? response['items'] as List : [];
        final items = rawItems
            .where((e) => e is Map && isAuthorActiveAndValid(Map<String, dynamic>.from(e)))
            .map((e) => CommunityPost.fromMap(Map<String, dynamic>.from(e)))
            .toList();
        return {
          'items': items,
          'next_cursor': response['next_cursor']?.toString(),
          'has_more': response['has_more'] == true,
        };
      }
      return {'items': [], 'has_more': false};
    } catch (e, st) {
      debugPrint('[COMMUNITY_FEED] Error in get_community_feed: $e\n$st');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getCommunitiesFeed({int limit = 20, String? cursor, String? communityId}) async {
    try {
      debugPrint('[COMMUNITY_FEED] Calling RPC get_communities_feed limit=$limit, communityId=$communityId');
      final params = <String, dynamic>{
        'p_limit': limit,
      };
      if (cursor != null && cursor.isNotEmpty) params['p_cursor'] = cursor;
      if (communityId != null && communityId.isNotEmpty) params['p_community_id'] = communityId;

      final response = await client.rpc('get_communities_feed', params: params);
      if (response is Map) {
        final rawItems = response['items'] is List ? response['items'] as List : [];
        final items = rawItems
            .where((e) => e is Map && isAuthorActiveAndValid(Map<String, dynamic>.from(e)))
            .map((e) => CommunityPost.fromMap(Map<String, dynamic>.from(e)))
            .toList();
        return {
          'items': items,
          'next_cursor': response['next_cursor']?.toString(),
          'has_more': response['has_more'] == true,
        };
      }
      return {'items': [], 'has_more': false};
    } catch (e, st) {
      debugPrint('[COMMUNITY_FEED] Error in get_communities_feed: $e\n$st');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> sharePostToStory({
    required String p_id,
    required String p_original_post_id,
    String? p_caption,
    String? p_background,
    String p_audience = 'public',
  }) async {
    try {
      debugPrint('[STORY] Calling RPC share_post_to_story original=$p_original_post_id');
      final params = <String, dynamic>{
        'p_id': p_id,
        'p_original_post_id': p_original_post_id,
        'p_audience': p_audience,
      };
      if (p_caption != null && p_caption.isNotEmpty) params['p_caption'] = p_caption;
      if (p_background != null && p_background.isNotEmpty) params['p_background'] = p_background;

      final response = await client.rpc('share_post_to_story', params: params);
      if (response is Map) return Map<String, dynamic>.from(response);
      return {'id': p_id, 'success': true};
    } catch (e, st) {
      debugPrint('[STORY] Error in share_post_to_story: $e\n$st');
      rethrow;
    }
  }
}
