import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';
import 'package:scrole/modules/module_principale/centre/models/community_post.dart';
import 'package:scrole/modules/module_principale/interne/enums/community_role_enum.dart';
import 'package:scrole/modules/module_principale/externe/repositories/home_feed_repository.dart';
import 'package:scrole/modules/module_evenement/centre/repositories/event_repository.dart';
import 'package:scrole/modules/module_evenement/centre/models/event_model.dart';
import 'package:scrole/modules/module_authentification/centre/services/auth_service.dart';
import 'package:scrole/modules/module_communautes/centre/services/community_outbox_processor.dart';
import 'package:scrole/app/local_storage/structured/app_cache_database.dart';
import 'package:scrole/app/routes/app_pages.dart';
import 'package:scrole/app/utils/supabase_error_mapper.dart';
import 'package:uuid/uuid.dart';

enum HomeFeedState { initial, loading, loaded, empty, error, loadingMore }

class HomeFeedController extends GetxController {
  late final HomeFeedRepository _feedRepo;
  late final EventRepository _eventRepo;
  final AuthService _authService = Get.find<AuthService>();
  final AppDatabase _db = Get.find<AppDatabase>();

  final Rx<HomeFeedState> state = HomeFeedState.initial.obs;
  final RxList<CommunityPost> posts = <CommunityPost>[].obs;
  final RxList<SuggestedProfileModel> suggestedProfiles = <SuggestedProfileModel>[].obs;
  final RxList<EventModel> suggestedEvents = <EventModel>[].obs;
  final RxString errorMessage = ''.obs;
  final RxBool hasMore = true.obs;
  final RxBool isRefreshing = false.obs;
  final RxBool isLoadingMore = false.obs;
  final RxString nextCursor = ''.obs;

  final Map<String, DateTime> _activeDwellStartedAt = {};
  final List<Map<String, dynamic>> _pendingDwellItems = [];
  Timer? _dwellBatchTimer;

  final Set<String> _sentViewIds = {};
  final List<String> _pendingViewIds = [];
  Timer? _viewBatchTimer;
  Timer? _counterRefreshTimer;
  bool _refreshingVisibleCounters = false;

  // Protect against duplicate HomeFeedController instances issuing the same
  // periodic counters RPC at the same time.
  static bool _postCountersRequestInFlight = false;
  static DateTime? _lastPostCountersRequestAt;

  Future<List<Map<String, dynamic>>> _requestPostCounters(List<String> ids) async {
    if (ids.isEmpty || _postCountersRequestInFlight) return const [];
    final now = DateTime.now();
    final lastRequest = _lastPostCountersRequestAt;
    // Multiple feed controllers can exist briefly during route transitions.
    // Coalesce their identical refreshes instead of flooding Supabase.
    if (lastRequest != null && now.difference(lastRequest) < const Duration(seconds: 8)) {
      return const [];
    }
    _postCountersRequestInFlight = true;
    _lastPostCountersRequestAt = now;
    try {
      return await _feedRepo.getPostCounters(ids);
    } finally {
      _postCountersRequestInFlight = false;
    }
  }

  void startPostDwell(CommunityPost post) {
    if (post.isPublishing || post.id.isEmpty) return;
    final myId = _authService.userId;
    if (myId != null && post.authorId == myId) return;
    _activeDwellStartedAt.putIfAbsent(post.id, DateTime.now);
  }

  void stopPostDwell(String postId) {
    final startedAt = _activeDwellStartedAt.remove(postId);
    if (startedAt == null) return;
    final dwellMs = DateTime.now().difference(startedAt).inMilliseconds;
    if (dwellMs <= 0) return;
    _pendingDwellItems.add({'post_id': postId, 'dwell_ms': dwellMs});
    if (_pendingDwellItems.length >= 100) {
      unawaited(_flushPostDwell());
    } else {
      _dwellBatchTimer ??= Timer(const Duration(seconds: 5), _flushPostDwell);
    }
  }

  Future<void> _flushPostDwell() async {
    _dwellBatchTimer?.cancel();
    _dwellBatchTimer = null;
    while (_pendingDwellItems.isNotEmpty) {
      final count = _pendingDwellItems.length > 100 ? 100 : _pendingDwellItems.length;
      final batch = _pendingDwellItems.take(count).toList();
      _pendingDwellItems.removeRange(0, count);
      try {
        final recorded = await _feedRepo.recordPostDwell(batch);
        debugPrint('[POST_DWELL] Recorded dwell for $recorded/${batch.length} posts');
      } catch (e) {
        debugPrint('[POST_DWELL] Batch failed and was dropped: $e');
      }
    }
  }

  void queuePostView(CommunityPost post) {
    if (post.isPublishing) return;
    final myId = _authService.userId;
    if (myId != null && post.authorId == myId) return;
    if (_sentViewIds.contains(post.id)) return;
    if (_pendingViewIds.contains(post.id)) return;

    _pendingViewIds.add(post.id);
    _sentViewIds.add(post.id);

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
      debugPrint('[POST_ACTIONS] Sending view batch of ${batch.length} posts');
      await _feedRepo.recordPostViews(batch);

      final counters = await _requestPostCounters(batch);
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
      debugPrint('[POST_ACTIONS] Error recording view batch or fetching counters: $e');
    }
  }

  Future<void> _refreshVisibleCounters() async {
    if (_refreshingVisibleCounters || posts.isEmpty || state.value != HomeFeedState.loaded) return;
    final ids = posts.take(50).map((p) => p.id).toSet().toList();
    if (ids.isEmpty) return;
    _refreshingVisibleCounters = true;
    try {
      final counters = await _requestPostCounters(ids);
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
      debugPrint('[POST_ACTIONS] Counter refresh failed; will retry on next interval: $e');
    } finally {
      _refreshingVisibleCounters = false;
    }
  }

  @override
  void onInit() {
    super.onInit();
    _feedRepo = HomeFeedRepository();
    try {
      _eventRepo = Get.find<EventRepository>();
    } catch (_) {
      _eventRepo = EventRepository(Get.find(), Get.find());
    }
    fetchFeed();
    _counterRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) => _refreshVisibleCounters());
  }

  @override
  void onClose() {
    _dwellBatchTimer?.cancel();
    for (final postId in _activeDwellStartedAt.keys.toList()) {
      stopPostDwell(postId);
    }
    unawaited(_flushPostDwell());
    _viewBatchTimer?.cancel();
    _counterRefreshTimer?.cancel();
    _flushViewBatch();
    for (final t in _reactionDebouncers.values) {
      t.cancel();
    }
    _reactionDebouncers.clear();
    super.onClose();
  }

  Future<void> fetchFeed({bool refresh = false}) async {
    if (refresh) {
      isRefreshing.value = true;
    } else if (posts.isEmpty) {
      state.value = HomeFeedState.loading;
    }

    try {
      final userId = _authService.userId;
      if (userId == null) {
        state.value = HomeFeedState.empty;
        isRefreshing.value = false;
        return;
      }

      // 1. Cache-first loading (load cached posts + outbox pending posts)
      if (!refresh) {
        await _loadCachedFeedAndOutbox(userId);
      }

      debugPrint('[HOME_FEED] fetchFeed started with refresh=$refresh');

      // 2. Show queued personal posts before waiting on the network.
      final pendingPosts = await _getPendingOutboxPosts(userId);
      if (pendingPosts.isNotEmpty) {
        final existingRemote = posts.where((post) => !post.isPublishing).toList();
        final previewById = <String, CommunityPost>{};
        for (final post in [...pendingPosts, ...existingRemote]) {
          previewById[post.id] = post;
        }
        posts.assignAll(previewById.values);
        state.value = HomeFeedState.loaded;
      }

      // 3. Remote fetch via get_home_feed RPC
      final result = await _feedRepo.getHomeFeed(limit: 20, cursor: null);
      final remoteItems = result['items'] as List<CommunityPost>;
      nextCursor.value = result['next_cursor']?.toString() ?? '';
      hasMore.value = result['has_more'] == true;

      debugPrint('[HOME_FEED] Fetched remote items count: ${remoteItems.length}, next_cursor=${nextCursor.value}, has_more=${hasMore.value}');

      // Count item types for logs
      int postTypeCount = remoteItems.where((p) => p.communityId == null).length;
      int communityPostCount = remoteItems.where((p) => p.communityId != null).length;
      debugPrint('[HOME_FEED] Item counts per type -> Standard Posts: $postTypeCount, Community Posts: $communityPostCount');

      if (remoteItems.isNotEmpty) {
        unawaited(_feedRepo.recordPostViews(remoteItems.map((p) => p.id).toList()));
      }

      // Combine pending outbox posts (at top, grayed out) + remote items
      final combined = <CommunityPost>[...pendingPosts, ...remoteItems];

      // Deduplicate by id
      final Map<String, CommunityPost> uniqueMap = {};
      for (final p in combined) {
        uniqueMap[p.id] = p;
      }
      posts.value = uniqueMap.values.toList();

      // Cache fetched items locally
      await _cacheFeedItems(userId, remoteItems);

      // Fetch suggested profiles and suggested events
      try {
        final profiles = await _feedRepo.getSuggestedProfiles(limit: 10);
        suggestedProfiles.assignAll(profiles);
        debugPrint('[HOME_FEED] Suggested profiles count: ${profiles.length}');
      } catch (e) {
        debugPrint('[HOME_FEED] Error fetching suggested profiles: $e');
      }

      try {
        final events = await _eventRepo.getSuggestedEvents(forceRefresh: refresh);
        suggestedEvents.assignAll(events);
        debugPrint('[HOME_FEED] Suggested events count: ${events.length}');
      } catch (e) {
        debugPrint('[HOME_FEED] Error fetching suggested events: $e');
      }

      state.value = posts.isEmpty ? HomeFeedState.empty : HomeFeedState.loaded;
    } catch (e, st) {
      debugPrint('[HOME_FEED] Error in fetchFeed: $e\n$st');
      if (posts.isNotEmpty) {
        state.value = HomeFeedState.loaded;
      } else {
        final appError = mapSupabaseError(e);
        errorMessage.value = appError.message;
        state.value = HomeFeedState.error;
      }
    } finally {
      isRefreshing.value = false;
    }
  }

  Future<void> loadMore() async {
    if (isLoadingMore.value || !hasMore.value || nextCursor.value.isEmpty) return;
    isLoadingMore.value = true;

    try {
      debugPrint('[HOME_FEED] Loading more feed with cursor: ${nextCursor.value}');
      final result = await _feedRepo.getHomeFeed(limit: 20, cursor: nextCursor.value);
      final moreItems = result['items'] as List<CommunityPost>;
      nextCursor.value = result['next_cursor']?.toString() ?? '';
      hasMore.value = result['has_more'] == true;

      debugPrint('[HOME_FEED] Loaded more items count: ${moreItems.length}, next_cursor=${nextCursor.value}, has_more=${hasMore.value}');

      if (moreItems.isNotEmpty) {
        final existingIds = posts.map((p) => p.id).toSet();
        final newItems = moreItems.where((p) => !existingIds.contains(p.id)).toList();
        posts.addAll(newItems);
      }
    } catch (e) {
      debugPrint('[HOME_FEED] Error in loadMore: $e');
    } finally {
      isLoadingMore.value = false;
    }
  }

  Future<void> hidePost(String postId) async {
    try {
      debugPrint('[HOME_FEED] Hiding post $postId locally and calling RPC hide_post');
      posts.removeWhere((p) => p.id == postId);
      await _feedRepo.hidePost(postId);
      Get.snackbar('Succès', 'Publication masquée', snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      debugPrint('[HOME_FEED] Error hiding post $postId: $e');
      final appError = mapSupabaseError(e);
      showAppErrorDialog(Get.context!, appError.message);
    }
  }

  Future<void> _loadCachedFeedAndOutbox(String userId) async {
    try {
      final db = await _db.database;
      final cachedRows = await db.query(
        'home_feed_cache',
        where: 'user_id = ?',
        whereArgs: [userId],
        orderBy: 'cached_at DESC',
        limit: 30,
      );

      final List<CommunityPost> cachedPosts = [];
      for (final row in cachedRows) {
        try {
          final dataMap = jsonDecode(row['data'].toString()) as Map<String, dynamic>;
          cachedPosts.add(CommunityPost(
            id: dataMap['id']?.toString() ?? '',
            authorName: dataMap['author_name']?.toString() ?? 'Utilisateur',
            authorId: dataMap['author_id']?.toString() ?? '',
            authorColor: Colors.deepPurple,
            authorRole: CommunityRole.member,
            timeAgo: dataMap['time_ago']?.toString() ?? 'Récemment',
            content: dataMap['content']?.toString() ?? '',
            communityId: dataMap['community_id']?.toString(),
            communityName: dataMap['community_name']?.toString(),
            isSuggested: dataMap['is_suggested'] == true,
            reasonSubtitle: dataMap['reason_subtitle']?.toString(),
            likeCount: (dataMap['like_count'] as num?)?.toInt() ?? 0,
            commentCount: (dataMap['comment_count'] as num?)?.toInt() ?? 0,
          ));
        } catch (_) {}
      }

      final pendingPosts = await _getPendingOutboxPosts(userId);
      if (pendingPosts.isNotEmpty || cachedPosts.isNotEmpty) {
        final combined = <CommunityPost>[...pendingPosts, ...cachedPosts];
        posts.assignAll(combined);
        state.value = HomeFeedState.loaded;
        debugPrint('[HOME_FEED] Loaded ${cachedPosts.length} cached posts and ${pendingPosts.length} outbox posts.');
      }
    } catch (e) {
      debugPrint('[HOME_FEED] Error loading cached feed: $e');
    }
  }

  Future<List<CommunityPost>> _getPendingOutboxPosts(String userId) async {
    try {
      final db = await _db.database;
      final rows = await db.query(
        'post_outbox',
        where: 'user_id = ? AND status IN (?, ?) AND community_id IS NULL',
        whereArgs: [userId, 'pending', 'failed'],
        orderBy: 'created_at DESC',
      );

      final List<CommunityPost> pending = [];
      for (final row in rows) {
        try {
          final payload = jsonDecode(row['payload'].toString()) as Map<String, dynamic>;
          final id = payload['p_id']?.toString() ?? row['operation_id']?.toString() ?? 'pending_${row['id']}';
          final content = payload['p_content']?.toString() ?? '';
          final communityId = payload['p_community_id']?.toString();

          pending.add(CommunityPost(
            id: id,
            authorName: 'Moi (en attente)',
            authorId: userId,
            authorColor: Colors.grey,
            authorRole: CommunityRole.member,
            timeAgo: row['status'] == 'failed' ? 'Échec de publication' : 'Publication en cours…',
            content: content,
            communityId: communityId,
            isPublishing: true,
            reactionsEnabled: false,
            commentsEnabled: false,
            sharingEnabled: false,
            reasonSubtitle: row['status'] == 'failed'
                ? (payload['p_last_error']?.toString() ?? 'Publication non confirmée')
                : 'Publication en cours…',
          ));
        } catch (_) {}
      }
      return pending;
    } catch (e) {
      debugPrint('[HOME_FEED] Error reading post_outbox: $e');
      return [];
    }
  }

  Future<void> _cacheFeedItems(String userId, List<CommunityPost> items) async {
    try {
      final db = await _db.database;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      for (final p in items) {
        await db.insert(
          'home_feed_cache',
          {
            'id': p.id,
            'user_id': userId,
            'data': jsonEncode({
              'id': p.id,
              'content': p.content,
              'author_name': p.authorName,
              'author_id': p.authorId,
              'time_ago': p.timeAgo,
              'community_id': p.communityId,
              'community_name': p.communityName,
              'is_suggested': p.isSuggested,
              'reason_subtitle': p.reasonSubtitle,
              'like_count': p.likeCount,
              'comment_count': p.commentCount,
            }),
            'cached_at': nowMs,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    } catch (e) {
      debugPrint('[HOME_FEED] Error caching feed items: $e');
    }
  }

  final Map<String, Timer> _reactionDebouncers = {};

  Future<void> retryQueuedPost(String postId) async {
    final userId = _authService.userId;
    if (userId == null) return;
    try {
      final db = await _db.database;
      final rows = await db.query(
        'post_outbox',
        columns: ['id'],
        where: 'user_id = ? AND operation_id = ? AND status = ?',
        whereArgs: [userId, postId, 'failed'],
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
      await fetchFeed(refresh: true);
    } catch (e) {
      debugPrint('[HOME_FEED] Retry queued post failed postId=$postId error=$e');
      Get.snackbar('Réessai impossible', e.toString().replaceFirst('Exception: ', ''), snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> handleReaction(String postId, PostReaction reaction) async {
    final index = posts.indexWhere((p) => p.id == postId);
    if (index == -1) return;

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

    _reactionDebouncers[postId]?.cancel();

    _reactionDebouncers[postId] = Timer(const Duration(milliseconds: 600), () async {
      _reactionDebouncers.remove(postId);
      try {
        final reactionStr = newReaction == PostReaction.like ? 'like' : (newReaction == PostReaction.dislike ? 'dislike' : null);
        await _feedRepo.setCommunityPostReaction(postId, reactionStr);
      } catch (e) {
        debugPrint('[POST_ACTIONS] Error reacting to post: $e');
        if (!isClosed) {
          final curIdx = posts.indexWhere((p) => p.id == postId);
          if (curIdx != -1) {
            posts[curIdx] = post;
            posts.refresh();
          }
          Get.snackbar('Erreur', e.toString().replaceFirst('Exception: ', '').tr, snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white);
        }
      }
    });
  }

  Future<void> sharePost({
    required String originalPostId,
    String? communityId,
    String audience = 'public',
    String? comment,
  }) async {
    final pId = const Uuid().v4();
    debugPrint('[POST_ACTIONS] Sharing post original=$originalPostId, community=$communityId, audience=$audience');

    try {
      await _feedRepo.sharePost(
        p_id: pId,
        p_original_post_id: originalPostId,
        p_community_id: communityId,
        p_audience: audience,
        p_comment: comment,
      );
      await fetchFeed(refresh: true);
      Get.snackbar('Succès', 'Publication partagée avec succès !', snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      debugPrint('[POST_ACTIONS] Error sharing post: $e');
      Get.snackbar('Erreur', e.toString().replaceFirst('Exception: ', '').tr, snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white);
    }
  }

  Future<void> deletePost(String postId, {String? reason}) async {
    debugPrint('[DELETE] [Controller] Deleting post postId=$postId');
    final oldPosts = List<CommunityPost>.from(posts);
    posts.removeWhere((p) => p.id == postId);
    posts.refresh();

    try {
      await _feedRepo.deletePost(postId, reason: reason);
      Get.snackbar('Succès', 'Publication supprimée', snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      debugPrint('[DELETE] [Controller] Error deleting post: $e');
      posts.value = oldPosts;
      posts.refresh();
      Get.snackbar('Erreur', e.toString().replaceFirst('Exception: ', '').tr, snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white);
    }
  }
}
