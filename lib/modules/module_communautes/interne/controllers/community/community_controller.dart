import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../centre/models/community_model.dart';
import '../../../centre/services/community_service.dart';
import 'package:scrole/modules/module_principale/centre/models/community_post.dart';
import 'package:scrole/modules/module_principale/externe/repositories/home_feed_repository.dart';

class CommunityController extends GetxController {
  final CommunityService _service = Get.isRegistered<CommunityService>()
      ? Get.find<CommunityService>()
      : Get.put(CommunityService());

  final RxList<CommunityModel> communities = <CommunityModel>[].obs;
  final RxBool isLoading = false.obs;
  final RxMap<String, int> unreadSalonCounts = <String, int>{}.obs;

  final RxList<CommunityPost> globalFeedPosts = <CommunityPost>[].obs;
  final RxBool isFeedLoading = false.obs;
  final RxnString selectedCommunityId = RxnString();
  final HomeFeedRepository _feedRepo = HomeFeedRepository();

  @override
  void onInit() {
    super.onInit();
    loadCommunities().then((_) {
      loadCommunitiesFeed();
    });
  }

  Future<void> loadCommunitiesFeed({String? communityId}) async {
    selectedCommunityId.value = communityId;
    isFeedLoading.value = true;
    try {
      final res = await _feedRepo.getCommunitiesFeed(limit: 20, communityId: communityId);
      globalFeedPosts.assignAll(res['items'] as List<CommunityPost>);
    } catch (e) {
      debugPrint('[COMMUNITY_FEED] Error loading communities feed: $e');
    } finally {
      isFeedLoading.value = false;
    }
  }

  Future<void> hidePost(String postId) async {
    globalFeedPosts.removeWhere((p) => p.id == postId);
    try {
      await _feedRepo.hidePost(postId);
    } catch (_) {}
  }

  Future<void> handleReaction(String postId, PostReaction reaction) async {
    final index = globalFeedPosts.indexWhere((p) => p.id == postId);
    if (index != -1) {
      final post = globalFeedPosts[index];
      if (post.isPublishing) return;
      final newReaction = post.userReaction == reaction ? PostReaction.none : reaction;
      int likes = post.likeCount;
      int dislikes = post.dislikeCount;

      if (post.userReaction == PostReaction.like) likes--;
      if (post.userReaction == PostReaction.dislike) dislikes--;
      if (newReaction == PostReaction.like) likes++;
      if (newReaction == PostReaction.dislike) dislikes++;

      globalFeedPosts[index] = post.copyWith(
        userReaction: newReaction,
        likeCount: likes,
        dislikeCount: dislikes,
      );
      globalFeedPosts.refresh();

      try {
        final reactionStr = newReaction == PostReaction.like ? 'like' : (newReaction == PostReaction.dislike ? 'dislike' : null);
        await _feedRepo.setCommunityPostReaction(postId, reactionStr);
      } catch (e) {
        debugPrint('[POST_ACTIONS] Error reacting to post: $e');
        globalFeedPosts[index] = post;
        globalFeedPosts.refresh();
      }
    }
  }

  Future<void> reloadCommunitiesFromCache() async {
    final list = await _service.getJoinedCommunities();
    communities.assignAll(list);
    await loadUnreadSalonCounts();
    debugPrint('[COMMUNITY_SYNC] Local cache dump updated from cache: ${communities.map((c) => '${c.id}:${c.name}:${c.status}').toList()}');
  }

  Future<void> loadUnreadSalonCounts() async {
    try {
      final response = await Supabase.instance.client.rpc('get_my_community_salon_unread_counts');
      final counts = <String, int>{};
      if (response is List) {
        for (final row in response) {
          if (row is! Map) continue;
          final communityId = row['community_id']?.toString() ?? '';
          final count = (row['unread_count'] as num?)?.toInt() ?? 0;
          if (communityId.isNotEmpty && count > 0) counts[communityId] = count;
        }
      }
      unreadSalonCounts.assignAll(counts);
    } catch (error) {
      debugPrint('[COMMUNITY_UNREAD] Could not load salon unread counts: $error');
    }
  }

  Future<void> loadCommunities({bool forceRemoteSync = true}) async {
    isLoading.value = true;
    try {
      if (forceRemoteSync) {
        await _service.checkPendingExpirations();
        await _service.reconcileMyCommunities();
      }
      await reloadCommunitiesFromCache();
    } finally {
      isLoading.value = false;
    }
  }

  Future<bool> leaveCommunity(String communityId) async {
    try {
      await _service.leaveCommunity(communityId);
      await reloadCommunitiesFromCache();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> createCommunity({
    required String name,
    required String slug,
    required String description,
    required String visibility,
    File? avatarFile,
    File? bannerFile,
  }) async {
    try {
      debugPrint('[CREATE_COMMUNITY] [Controller] createCommunity called for name=$name, slug=$slug, visibility=$visibility');
      await _service.createCommunity(
        name: name,
        slug: slug,
        description: description,
        visibility: visibility,
        avatarFile: avatarFile,
        bannerFile: bannerFile,
      );
      await loadCommunities();
      debugPrint('[CREATE_COMMUNITY] [Controller] createCommunity completed and communities reloaded');
      return true;
    } catch (e) {
      debugPrint('[CREATE_COMMUNITY] [Controller] createCommunity error: $e');
      return false;
    }
  }
}
