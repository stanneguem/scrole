import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:scrole/modules/module_principale/centre/models/community_post.dart';
import 'package:scrole/modules/module_principale/externe/repositories/home_feed_repository.dart';
import 'package:scrole/modules/module_principale/interne/widgets/feed_post_card.dart';
import 'package:scrole/modules/module_principale/interne/widgets/community_comments_sheet.dart';
import 'package:scrole/shared/utils/number_formatter.dart';

class HashtagFeedScreen extends StatefulWidget {
  const HashtagFeedScreen({super.key});

  @override
  State<HashtagFeedScreen> createState() => _HashtagFeedScreenState();
}

class _HashtagFeedScreenState extends State<HashtagFeedScreen> {
  final HomeFeedRepository _repository = HomeFeedRepository();
  final ScrollController _scrollController = ScrollController();
  final List<CommunityPost> _posts = [];
  late final String _hashtag;
  String? _cursor;
  bool _hasMore = true;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  int _totalPosts = 0;
  int _totalViews = 0;
  int _totalLikes = 0;

  @override
  void initState() {
    super.initState();
    _hashtag = (Get.parameters['tag'] ?? '').replaceFirst(RegExp(r'^#+'), '');
    _scrollController.addListener(_onScroll);
    _loadPosts();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _loadingMore || !_hasMore) return;
    if (_scrollController.position.extentAfter < 500) _loadPosts(loadMore: true);
  }

  Future<void> _loadPosts({bool loadMore = false}) async {
    if (loadMore) {
      if (_loadingMore || !_hasMore) return;
      setState(() => _loadingMore = true);
    } else {
      setState(() {
        _loading = true;
        _error = null;
        _cursor = null;
        _hasMore = true;
        _posts.clear();
        _totalPosts = 0;
        _totalViews = 0;
        _totalLikes = 0;
      });
    }

    try {
      final result = await _repository.getPostsByHashtag(
        _hashtag,
        limit: 20,
        cursor: loadMore ? _cursor : null,
      );
      if (!mounted) return;
      setState(() {
        _posts.addAll(result['items'] as List<CommunityPost>);
        _totalPosts = (result['total_posts'] as num?)?.toInt() ?? _totalPosts;
        _totalViews = (result['total_views'] as num?)?.toInt() ?? _totalViews;
        _totalLikes = (result['total_likes'] as num?)?.toInt() ?? _totalLikes;
        _cursor = result['next_cursor'] as String?;
        _hasMore = result['has_more'] == true;
        _loading = false;
        _loadingMore = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = 'hashtag_feed_error'.tr;
      });
    }
  }

  Future<void> _onReaction(CommunityPost post, PostReaction reaction) async {
    final previousReaction = post.userReaction;
    final nextReaction = previousReaction == reaction
        ? PostReaction.none
        : reaction;
    final next = nextReaction == PostReaction.none ? null : nextReaction.name;
    final likeDelta = (nextReaction == PostReaction.like ? 1 : 0) -
        (previousReaction == PostReaction.like ? 1 : 0);
    final dislikeDelta = (nextReaction == PostReaction.dislike ? 1 : 0) -
        (previousReaction == PostReaction.dislike ? 1 : 0);
    final index = _posts.indexWhere((item) => item.id == post.id);
    if (index < 0) return;
    final previousPost = _posts[index];

    // Mise à jour optimiste : la carte et le compteur global réagissent tout de suite.
    setState(() {
      _posts[index] = previousPost.copyWith(
        userReaction: nextReaction,
        likeCount: (previousPost.likeCount + likeDelta).clamp(0, 1 << 31),
        dislikeCount: (previousPost.dislikeCount + dislikeDelta).clamp(0, 1 << 31),
      );
      _totalLikes = (_totalLikes + likeDelta).clamp(0, 1 << 31);
    });

    try {
      await _repository.setCommunityPostReaction(post.id, next);
      if (mounted) await _refreshCountersSilently();
    } catch (_) {
      if (!mounted) return;
      final currentIndex = _posts.indexWhere((item) => item.id == post.id);
      setState(() {
        if (currentIndex >= 0) _posts[currentIndex] = previousPost;
        _totalLikes = (_totalLikes - likeDelta).clamp(0, 1 << 31);
      });
      Get.snackbar('hashtag_feed_error_title'.tr, 'hashtag_feed_error'.tr);
    }
  }

  /// Recharge les statistiques sans vider la liste ni déplacer le scroll.
  Future<void> _refreshCountersSilently() async {
    try {
      final result = await _repository.getPostsByHashtag(
        _hashtag,
        limit: 20,
        cursor: null,
      );
      if (!mounted) return;
      final refreshedPosts = result['items'] as List<CommunityPost>;
      final byId = {for (final post in refreshedPosts) post.id: post};
      setState(() {
        for (var i = 0; i < _posts.length; i++) {
          final refreshed = byId[_posts[i].id];
          if (refreshed != null) {
            _posts[i] = _posts[i].copyWith(
              likeCount: refreshed.likeCount,
              dislikeCount: refreshed.dislikeCount,
              commentCount: refreshed.commentCount,
              shareCount: refreshed.shareCount,
              viewCount: refreshed.viewCount,
              userReaction: refreshed.userReaction,
              viewerHasShared: refreshed.viewerHasShared,
            );
          }
        }
        _totalPosts = (result['total_posts'] as num?)?.toInt() ?? _totalPosts;
        _totalViews = (result['total_views'] as num?)?.toInt() ?? _totalViews;
        _totalLikes = (result['total_likes'] as num?)?.toInt() ?? _totalLikes;
      });
    } catch (e) {
      debugPrint('[HashtagFeed] silent counters refresh failed: $e');
    }
  }

  Future<void> _openComments(CommunityPost post) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CommunityCommentsSheet(post: post, controller: null),
    );
    if (mounted) await _refreshCountersSilently();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('hashtag_feed_title'.trParams({'tag': _hashtag})),
        centerTitle: false,
      ),
      body: SafeArea(
        top: false,
        bottom: true,
        child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              border: Border(
                bottom: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.tag_rounded, size: 18, color: colorScheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '#$_hashtag',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w700, color: colorScheme.onSurface),
                  ),
                ),
                const SizedBox(width: 12),
                Icon(Icons.article_outlined, size: 17, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  'hashtag_posts_count'.trParams({'count': NumberFormatter.formatCount(_totalPosts)}),
                  style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                ),
                const SizedBox(width: 12),
                Icon(Icons.visibility_outlined, size: 17, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  'hashtag_views_count'.trParams({'count': NumberFormatter.formatCount(_totalViews)}),
                  style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                ),
                const SizedBox(width: 12),
                Icon(Icons.favorite_border_rounded, size: 17, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  NumberFormatter.formatCount(_totalLikes),
                  style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading && _posts.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _posts.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: () => _loadPosts(),
                          icon: const Icon(Icons.refresh),
                          label: Text('hashtag_feed_retry'.tr),
                        ),
                      ],
                    ),
                  ),
                )
              : _posts.isEmpty
                  ? RefreshIndicator(
                      onRefresh: () => _loadPosts(),
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          const SizedBox(height: 140),
                          Icon(Icons.tag, size: 48, color: colorScheme.onSurfaceVariant),
                          const SizedBox(height: 12),
                          Center(
                            child: Text(
                              'hashtag_feed_empty'.tr,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: colorScheme.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () => _loadPosts(),
                      child: ListView.separated(
                        controller: _scrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _posts.length + (_loadingMore ? 1 : 0),
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          if (index >= _posts.length) {
                            return const Padding(
                              padding: EdgeInsets.all(20),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                          final post = _posts[index];
                          return FeedPostCard(
                            post: post,
                            onReactionTap: (reaction) => _onReaction(post, reaction),
                            onCommentTap: () => _openComments(post),
                          );
                        },
                      ),
                    ),
          ),
        ],
        ),
      ),
    );
  }
}
