import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StoriesRepository {
  final SupabaseClient client;

  StoriesRepository([SupabaseClient? client]) : client = client ?? Supabase.instance.client;

  Future<Map<String, dynamic>> createStoryRpc({
    required String p_id,
    required String p_kind,
    String? p_content,
    String? p_image_url,
    String? p_background,
    String p_audience = 'public',
    Map<String, dynamic>? p_poll,
    bool p_allow_reshare = false,
  }) async {
    try {
      debugPrint('[STORY] [Repository] Calling RPC create_story with p_id=$p_id, kind=$p_kind, audience=$p_audience');
      final params = <String, dynamic>{
        'p_id': p_id,
        'p_kind': p_kind,
        'p_audience': p_audience,
        'p_allow_reshare': p_allow_reshare,
      };
      if (p_content != null && p_content.isNotEmpty) params['p_content'] = p_content;
      if (p_image_url != null && p_image_url.isNotEmpty) params['p_image_url'] = p_image_url;
      if (p_background != null && p_background.isNotEmpty) params['p_background'] = p_background;
      if (p_poll != null) params['p_poll'] = p_poll;

      final response = await client.rpc('create_story', params: params);
      debugPrint('[STORY] [Repository] RPC create_story successful for p_id=$p_id, response=$response');
      if (response is Map) return Map<String, dynamic>.from(response);
      return {'id': p_id, 'success': true};
    } on PostgrestException catch (e) {
      debugPrint('[STORY] [Repository] PostgrestException in create_story: code=${e.code}, message=${e.message}');
      if (e.code == '23505' || e.message.toLowerCase().contains('already exists') || e.message.toLowerCase().contains('pkey')) {
        return {'id': p_id, 'success': true};
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getStoriesTray({int followingLimit = 30, int suggestedLimit = 15}) async {
    try {
      final response = await client.rpc('get_stories_tray', params: {
        'p_following_limit': followingLimit,
        'p_suggested_limit': suggestedLimit,
      });
      if (response is Map) return Map<String, dynamic>.from(response);
      return {'own': null, 'following': [], 'suggested': []};
    } catch (e) {
      debugPrint('[STORY] [Repository] Error in getStoriesTray: $e');
      return {'own': null, 'following': [], 'suggested': []};
    }
  }

  Future<Map<String, dynamic>> getSuggestedStories(int limit, int offset) async {
    try {
      final response = await client.rpc('get_suggested_stories', params: {
        'p_limit': limit,
        'p_offset': offset,
      });
      if (response is Map) return Map<String, dynamic>.from(response);
      return {'items': [], 'has_more': false};
    } catch (e) {
      debugPrint('[STORY] [Repository] Error in getSuggestedStories: $e');
      return {'items': [], 'has_more': false};
    }
  }

  Future<Map<String, dynamic>?> getUserStories(String userId) async {
    try {
      final response = await client.rpc('get_user_stories', params: {'p_user_id': userId});
      if (response is Map) return Map<String, dynamic>.from(response);
      return null;
    } catch (e) {
      debugPrint('[STORY] [Repository] Error in getUserStories: $e');
      return null;
    }
  }

  Future<int> markStoriesViewed(List<String> storyIds) async {
    try {
      final response = await client.rpc('mark_stories_viewed', params: {'p_story_ids': storyIds});
      return (response as num?)?.toInt() ?? 0;
    } catch (e) {
      debugPrint('[STORY] [Repository] Error in markStoriesViewed: $e');
      return 0;
    }
  }

  Future<Map<String, dynamic>> getStoryViewers(String storyId, int limit, int offset) async {
    try {
      final response = await client.rpc('get_story_viewers', params: {
        'p_story_id': storyId,
        'p_limit': limit,
        'p_offset': offset,
      });
      if (response is Map) return Map<String, dynamic>.from(response);
      return {'viewers_count': 0, 'items': [], 'has_more': false};
    } catch (e) {
      debugPrint('[STORY] [Repository] Error in getStoryViewers: $e');
      return {'viewers_count': 0, 'items': [], 'has_more': false};
    }
  }

  Future<Map<String, dynamic>> voteStoryPoll(String storyId, List<String> optionIds) async {
    try {
      final response = await client.rpc('vote_story_poll', params: {
        'p_story_id': storyId,
        'p_option_ids': optionIds,
      });
      if (response is Map) return Map<String, dynamic>.from(response);
      return {};
    } catch (e) {
      debugPrint('[STORY] [Repository] Error in voteStoryPoll: $e');
      rethrow;
    }
  }

  Future<bool> setStoryLike(String storyId, bool liked) async {
    try {
      debugPrint('[POST_ACTIONS] Calling RPC set_story_like storyId=$storyId, liked=$liked');
      final response = await client.rpc('set_story_like', params: {
        'p_story_id': storyId,
        'p_liked': liked,
      });
      return response == true || response == 1;
    } catch (e, st) {
      debugPrint('[POST_ACTIONS] Error in set_story_like: $e\n$st');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getStoryComments(String storyId, {int limit = 50, int offset = 0}) async {
    try {
      debugPrint('[STORY] [Repository] Calling RPC get_story_comments for storyId=$storyId');
      final response = await client.rpc('get_story_comments', params: {
        'p_story_id': storyId,
        'p_limit': limit,
        'p_offset': offset,
      });
      if (response is Map) return Map<String, dynamic>.from(response);
      return {'items': [], 'total': 0, 'has_more': false};
    } catch (e) {
      debugPrint('[STORY] [Repository] Error in getStoryComments: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getStoryCommentReplies(
    String storyId,
    String commentId, {
    int limit = 30,
    int offset = 0,
  }) async {
    final response = await client.rpc('get_story_comment_replies', params: {
      'p_story_id': storyId,
      'p_comment_id': commentId,
      'p_limit': limit,
      'p_offset': offset,
    });
    if (response is Map) return Map<String, dynamic>.from(response);
    return {'items': [], 'total': 0, 'has_more': false};
  }
  Future<String?> setStoryCommentReaction(String commentId, String? reaction) async {
    try {
      final normalized = reaction == null || reaction == 'none' ? 'none' : reaction;
      final response = await client.rpc('set_story_comment_reaction', params: {
        'p_comment_id': commentId,
        'p_reaction': normalized,
      });
      return response?.toString();
    } catch (e, st) {
      debugPrint('[STORY] Error setting story comment reaction: $e\n$st');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> createStoryComment({
    required String p_id,
    required String p_story_id,
    required String p_content,
    String? p_parent_comment_id,
  }) async {
    try {
      debugPrint('[STORY] [Repository] Calling RPC create_story_comment for storyId=$p_story_id, parent=$p_parent_comment_id');
      final params = <String, dynamic>{
        'p_id': p_id,
        'p_story_id': p_story_id,
        'p_content': p_content,
      };
      if (p_parent_comment_id != null && p_parent_comment_id.isNotEmpty) {
        params['p_parent_comment_id'] = p_parent_comment_id;
      }
      final response = await client.rpc('create_story_comment', params: params);
      debugPrint('[STORY] [Repository] RPC create_story_comment successful: $response');
      if (response is Map) return Map<String, dynamic>.from(response);
      return {'id': p_id, 'success': true};
    } catch (e) {
      debugPrint('[STORY] [Repository] Error in createStoryComment: $e');
      rethrow;
    }
  }

  Future<void> deleteStory(String storyId, {String? reason}) async {
    try {
      debugPrint('[DELETE] [Repository] Calling RPC delete_story with p_story_id=$storyId, p_reason=$reason');
      await client.rpc('delete_story', params: {
        'p_story_id': storyId,
        if (reason != null && reason.isNotEmpty) 'p_reason': reason,
      });
      debugPrint('[DELETE] [Repository] RPC delete_story successful for storyId=$storyId');
    } on PostgrestException catch (e) {
      debugPrint('[DELETE] [Repository] PostgrestException in delete_story: code=${e.code}, message=${e.message}');
      final msg = e.message.toLowerCase();
      if (msg.contains('non autorisée') || msg.contains('unauthorized')) {
        throw Exception('delete_unauthorized_error');
      }
      if (e.code == 'PGRST116' || msg.contains('not found') || msg.contains('does not exist')) {
        return;
      }
      rethrow;
    } catch (e, st) {
      debugPrint('[DELETE] [Repository] Unexpected error in delete_story: $e\n$st');
      rethrow;
    }
  }
}
