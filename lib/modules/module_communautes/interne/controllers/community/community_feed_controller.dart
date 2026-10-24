import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:scrole/app/local_storage/structured/app_cache_database.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:scrole/modules/module_principale/centre/models/community_post.dart';
import 'package:scrole/modules/module_principale/centre/models/post_comment.dart';
import 'package:scrole/modules/module_principale/interne/enums/community_role_enum.dart';
import 'package:scrole/shared/models/post_media.dart';
import 'package:scrole/modules/module_communautes/centre/services/community_service.dart';
import 'package:scrole/modules/module_communautes/centre/services/community_outbox_processor.dart';
import 'package:scrole/modules/module_principale/externe/repositories/home_feed_repository.dart';
import 'package:scrole/modules/module_authentification/centre/services/auth_service.dart';

enum CommunityFeedState { initialLoading, loaded, empty, error, refreshing }

class CommunityFeedController extends GetxController {
  final dynamic service;
  final String? communityId;
  final HomeFeedRepository _feedRepo = HomeFeedRepository();

  String? get currentUserId {
    try {
      if (Get.isRegistered<AuthService>()) {
        return Get.find<AuthService>().userId;
      }
    } catch (_) {}
    return null;
  }

  static final Set<String> _globalSentViewIds = {};
  final List<String> _pendingViewIds = [];
  Timer? _viewBatchTimer;

  CommunityFeedController([this.service, this.communityId]);

  final RxString communityName = 'evenement'.obs;
  final RxList<CommunityPost> posts = <CommunityPost>[].obs;
  final Rx<CommunityFeedState> feedState = CommunityFeedState.initialLoading.obs;
  final RxString errorMessage = ''.obs;
  String? nextCursor;
  bool hasMore = false;
  bool isLoadingMore = false;

  final RxMap<String, bool> commentsLoading = <String, bool>{}.obs;
  final RxMap<String, List<PostComment>> commentsByPostId = <String, List<PostComment>>{}.obs;
  final RxMap<String, List<PostComment>> repliesByCommentId = <String, List<PostComment>>{}.obs;
  final RxMap<String, bool> loadingRepliesByCommentId = <String, bool>{}.obs;

  @override
  void onInit() {
    super.onInit();
    fetchCommunityFeed();
  }

  @override
  void onClose() {
    _viewBatchTimer?.cancel();
    super.onClose();
  }

  void queuePostView(CommunityPost post) {
    if (post.isPublishing) return;
    final myId = currentUserId;
    if (myId != null && post.authorId == myId) return;
    if (_globalSentViewIds.contains(post.id)) return;
    if (_pendingViewIds.contains(post.id)) return;

    _pendingViewIds.add(post.id);
    _globalSentViewIds.add(post.id);

    if (_pendingViewIds.length >= 20) {
      _flushViewBatch();
    } else {
      _viewBatchTimer ??= Timer(const Duration(seconds: 3), _flushViewBatch);
    }
  }

  Future<void> _flushViewBatch() async {
    _viewBatchTimer?.cancel();
    _viewBatchTimer = null;

    if (_pendingViewIds.isEmpty) return;
    final batch = List<String>.from(_pendingViewIds);
    _pendingViewIds.clear();

    try {
      debugPrint('[POST_ACTIONS] [CommunityFeed] Sending view batch of ${batch.length} posts');
      await _feedRepo.recordPostViews(batch);

      final counters = await _feedRepo.getPostCounters(batch);
      if (counters.isNotEmpty) {
        for (final c in counters) {
          final id = c['id']?.toString();
          if (id == null) continue;
          final idx = posts.indexWhere((p) => p.id == id);
          if (idx != -1) {
            final p = posts[idx];
            posts[idx] = p.copyWith(
              viewCount: (c['views_count'] as num?)?.toInt() ?? p.viewCount,
              likeCount: (c['likes_count'] as num?)?.toInt() ?? p.likeCount,
              dislikeCount: (c['dislikes_count'] as num?)?.toInt() ?? p.dislikeCount,
              commentCount: (c['comments_count'] as num?)?.toInt() ?? p.commentCount,
              shareCount: (c['shares_count'] as num?)?.toInt() ?? p.shareCount,
            );
          }
        }
        posts.refresh();
      }
    } catch (e) {
      debugPrint('[POST_ACTIONS] [CommunityFeed] Error flushing view batch: $e');
    }
  }

  Future<List<CommunityPost>> _getPendingOutboxPosts(String userId) async {
    try {
      final db = await Get.find<AppDatabase>().database;
      final rows = await db.query(
        'post_outbox',
        where: 'user_id = ? AND status IN (?, ?) AND community_id = ?',
        whereArgs: [userId, 'pending', 'failed', communityId],
        orderBy: 'created_at DESC',
      );
      final pending = <CommunityPost>[];
      for (final row in rows) {
        try {
          final raw = jsonDecode(row['payload']?.toString() ?? '{}');
          if (raw is! Map) continue;
          final payload = Map<String, dynamic>.from(raw);
          final id = (payload['p_id'] ?? row['operation_id'] ?? '').toString();
          if (id.isEmpty) continue;
          pending.add(CommunityPost(
            id: id,
            authorName: 'Moi',
            authorId: userId,
            authorColor: Colors.grey,
            authorRole: CommunityRole.member,
            timeAgo: row['status'] == 'failed' ? 'Échec de publication' : 'Publication en cours…',
            content: payload['p_content']?.toString() ?? '',
            communityId: communityId,
            isPublishing: true,
            reactionsEnabled: false,
            commentsEnabled: false,
            sharingEnabled: false,
            reasonSubtitle: row['status'] == 'failed'
                ? (payload['p_last_error']?.toString() ?? 'Publication à réessayer')
                : 'Publication en cours…',
          ));
        } catch (e) {
          debugPrint('[COMMUNITY_FEED] Ignoring malformed pending post row: $e');
        }
      }
      return pending;
    } catch (e) {
      debugPrint('[COMMUNITY_FEED] Could not load pending outbox posts: $e');
      return [];
    }
  }

  Future<void> retryQueuedPost(String postId) async {
    final userId = currentUserId;
    if (userId == null || communityId == null) return;
    try {
      final db = await Get.find<AppDatabase>().database;
      final rows = await db.query(
        'post_outbox',
        columns: ['id'],
        where: 'user_id = ? AND operation_id = ? AND community_id = ? AND status = ?',
        whereArgs: [userId, postId, communityId, 'failed'],
        limit: 1,
      );
      if (rows.isEmpty) return;
      await db.update(
        'post_outbox',
        {'status': 'pending', 'attempt_count': 0, 'next_retry_at': 0, 'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [rows.first['id']],
      );
      if (!Get.isRegistered<CommunityOutboxProcessor>()) {
        Get.put(CommunityOutboxProcessor());
      }
      unawaited(Get.find<CommunityOutboxProcessor>().processPendingPosts());
      await fetchCommunityFeed(isRefresh: true);
    } catch (e) {
      debugPrint('[COMMUNITY_FEED] Retry queued post failed postId=$postId error=$e');
      Get.snackbar('Réessai impossible', e.toString().replaceFirst('Exception: ', ''), snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> fetchCommunityFeed({bool isRefresh = false}) async {
    if (communityId == null || communityId!.isEmpty) {
      feedState.value = CommunityFeedState.empty;
      return;
    }

    if (isRefresh) {
      if (posts.isEmpty) {
        feedState.value = CommunityFeedState.initialLoading;
      } else {
        feedState.value = CommunityFeedState.refreshing;
      }
      nextCursor = null;
      hasMore = false;
    } else {
      if (posts.isEmpty) {
        feedState.value = CommunityFeedState.initialLoading;
      }
    }

    try {
      debugPrint('[COMMUNITY_FEED] Fetching posts via get_community_feed for communityId=$communityId, isRefresh=$isRefresh');
      // Publish the local outbox placeholder before waiting on the network.
      final userId = currentUserId;
      final pending = userId == null ? <CommunityPost>[] : await _getPendingOutboxPosts(userId);
      if (pending.isNotEmpty) {
        final existingRemote = posts.where((post) => !post.isPublishing).toList();
        final previewById = <String, CommunityPost>{};
        for (final post in [...pending, ...existingRemote]) {
          previewById[post.id] = post;
        }
        posts.assignAll(previewById.values);
        feedState.value = CommunityFeedState.loaded;
      }
      final result = await _feedRepo.getCommunityFeed(communityId!);
      final items = result['items'] as List<CommunityPost>;
      nextCursor = result['next_cursor']?.toString();
      hasMore = result['has_more'] == true;

      // Keep the local outbox representation visible until the server confirms
      // the same post ID. Deduplicate by ID so confirmation never creates twins.
      final byId = <String, CommunityPost>{};
      for (final post in [...pending, ...items]) {
        byId[post.id] = post.isPublishing ? post : post;
      }
      posts.assignAll(byId.values);
      errorMessage.value = '';

      if (posts.isEmpty) {
        feedState.value = CommunityFeedState.empty;
      } else {
        feedState.value = CommunityFeedState.loaded;
      }
    } catch (e, st) {
      debugPrint('[COMMUNITY_FEED] Error fetching community feed: $e\n$st');
      String msg = e.toString().replaceFirst('Exception: ', '').tr;
      if (e is PostgrestException) {
        msg = e.message;
      }
      errorMessage.value = msg;

      if (posts.isNotEmpty) {
        feedState.value = CommunityFeedState.loaded;
        Get.snackbar(
          'error'.tr,
          msg,
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      } else {
        feedState.value = CommunityFeedState.error;
      }
    }
  }

  Future<void> loadMorePosts() async {
    if (isLoadingMore || !hasMore || nextCursor == null || communityId == null) return;
    isLoadingMore = true;

    try {
      debugPrint('[COMMUNITY_FEED] Loading more posts for communityId=$communityId, cursor=$nextCursor');
      final result = await _feedRepo.getCommunityFeed(communityId!, cursor: nextCursor);
      final items = result['items'] as List<CommunityPost>;
      nextCursor = result['next_cursor']?.toString();
      hasMore = result['has_more'] == true;

      final existingIds = posts.map((p) => p.id).toSet();
      final uniqueNew = items.where((p) => !existingIds.contains(p.id)).toList();
      posts.addAll(uniqueNew);
    } catch (e) {
      debugPrint('[COMMUNITY_FEED] Error loading more posts: $e');
    } finally {
      isLoadingMore = false;
    }
  }

  List<PostComment> getCommentsForPost(String postId) => commentsByPostId[postId] ?? [];

  Future<void> createPost({
    String? content,
    List<File>? imageFiles,
    String? audience,
    bool commentsEnabled = true,
    bool sharingEnabled = true,
    bool reactionsEnabled = true,
    List<String>? hashtags,
    List<String>? mentions,
    Map<String, dynamic>? poll,
    bool allowPromotion = true,
  }) async {
    final tempId = 'new_${DateTime.now().millisecondsSinceEpoch}';
    final newPost = CommunityPost(
      id: tempId,
      authorName: 'Moi',
      authorId: 'me',
      authorColor: Colors.purple,
      authorRole: CommunityRole.member,
      timeAgo: 'publication_in_progress'.tr,
      content: content ?? '',
      media: imageFiles != null ? imageFiles.map((f) => PostMedia(type: 'photo', url: f.path)).toList() : [],
      likeCount: 0,
      commentCount: 0,
      shareCount: 0,
      isPublishing: true,
      poll: poll,
    );
    posts.insert(0, newPost);

    try {
      final service = Get.isRegistered<CommunityService>() ? Get.find<CommunityService>() : Get.put(CommunityService(Get.find(), Get.find()));
      await service.createCommunityPost(
        communityId: communityId ?? '',
        content: content,
        imageFiles: imageFiles,
        audience: audience,
        commentsEnabled: commentsEnabled,
        sharingEnabled: sharingEnabled,
        reactionsEnabled: reactionsEnabled,
        hashtags: hashtags,
        mentions: mentions,
        poll: poll,
        allowPromotion: allowPromotion,
      );
    } catch (e) {
      debugPrint('[POST] [Controller] createPost error: $e');
    }
  }

  Future<void> loadCommentsForPost(String postId) async {
    commentsLoading[postId] = true;
    await Future.delayed(const Duration(milliseconds: 400));
    commentsByPostId[postId] = [
      PostComment(
        id: 'c1',
        authorName: 'Alexandre',
        authorId: 'u_10',
        authorColor: Colors.blue,
        timeAgo: '1h',
        content: 'Superbe publication ! Hâte d\'y participer.',
        likesCount: 5,
        isOp: true,
      ),
    ];
    commentsLoading[postId] = false;
  }

  Future<void> addCommentToPost(String postId, String text) async {
    final list = commentsByPostId[postId] ?? [];
    final newComment = PostComment(
      id: 'c_${DateTime.now().millisecondsSinceEpoch}',
      authorName: 'Moi',
      authorId: 'me',
      authorColor: Colors.purple,
      timeAgo: 'À l\'instant',
      content: text,
    );
    commentsByPostId[postId] = [newComment, ...list];
  }

  Future<void> addReplyToComment(String postId, String commentId, String text) async {
    final list = repliesByCommentId[commentId] ?? [];
    final newReply = PostComment(
      id: 'r_${DateTime.now().millisecondsSinceEpoch}',
      authorName: 'Moi',
      authorId: 'me',
      authorColor: Colors.purple,
      timeAgo: 'À l\'instant',
      content: text,
    );
    repliesByCommentId[commentId] = [...list, newReply];
  }

  Future<void> toggleCommentReaction(String postId, String commentId, PostReaction reaction) async {}

  Future<void> loadRepliesForComment(String commentId) async {
    loadingRepliesByCommentId[commentId] = true;
    await Future.delayed(const Duration(milliseconds: 300));
    loadingRepliesByCommentId[commentId] = false;
  }

  void deleteComment(String postId, String commentId) {
    final list = commentsByPostId[postId];
    if (list != null) {
      list.removeWhere((c) => c.id == commentId);
      commentsByPostId.refresh();
    }
  }

  void sharePost(CommunityPost post) {
    Get.snackbar('Partage', 'Publication partagée avec succès', snackPosition: SnackPosition.BOTTOM);
  }

  Future<void> deletePost(String postId, {String? reason}) async {
    debugPrint('[DELETE] [Controller] Deleting community post postId=$postId');
    final oldPosts = List<CommunityPost>.from(posts);
    posts.removeWhere((p) => p.id == postId);
    posts.refresh();

    try {
      await _feedRepo.deletePost(postId, reason: reason);
      Get.snackbar('Succès', 'Publication supprimée', snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      debugPrint('[DELETE] [Controller] Error deleting community post: $e');
      posts.value = oldPosts;
      posts.refresh();
      Get.snackbar('Erreur', e.toString().replaceFirst('Exception: ', '').tr, snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white);
    }
  }

  Future<void> handleReaction(String postId, PostReaction reaction) async {
    final index = posts.indexWhere((p) => p.id == postId);
    if (index != -1) {
      final post = posts[index];
      if (post.isPublishing) return;
      final newReaction = post.userReaction == reaction ? PostReaction.none : reaction;
      int likes = post.likeCount;
      int dislikes = post.dislikeCount;

      if (post.userReaction == PostReaction.like) likes--;
      if (post.userReaction == PostReaction.dislike) dislikes--;
      if (newReaction == PostReaction.like) likes++;
      if (newReaction == PostReaction.dislike) dislikes++;

      posts[index] = post.copyWith(
        userReaction: newReaction,
        likeCount: likes,
        dislikeCount: dislikes,
      );
      posts.refresh();

      try {
        final reactionStr = newReaction == PostReaction.like ? 'like' : (newReaction == PostReaction.dislike ? 'dislike' : null);
        await _feedRepo.setCommunityPostReaction(postId, reactionStr);
      } catch (e) {
        debugPrint('[POST_ACTIONS] Error reacting to community post: $e');
        posts[index] = post;
        posts.refresh();
        Get.snackbar('Erreur', e.toString().replaceFirst('Exception: ', '').tr, snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white);
      }
    }
  }
}
