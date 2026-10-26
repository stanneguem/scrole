import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:scrole/modules/module_principale/centre/models/community_post.dart';
import 'package:scrole/modules/module_principale/externe/repositories/home_feed_repository.dart';
import 'package:scrole/modules/module_principale/interne/widgets/feed_post_card.dart';
import 'package:scrole/modules/module_principale/interne/widgets/community_comments_sheet.dart';

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
    final next = post.userReaction == reaction ? null : reaction.name;
    try {
      await _repository.setCommunityPostReaction(post.id, next);
      if (mounted) await _loadPosts();
    } catch (_) {
      if (!mounted) return;
      Get.snackbar('hashtag_feed_error_title'.tr, 'hashtag_feed_error'.tr);
    }
  }

  void _openComments(CommunityPost post) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CommunityCommentsSheet(post: post, controller: null),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('hashtag_feed_title'.trParams({'tag': _hashtag})),
        centerTitle: false,
      ),
      body: _loading && _posts.isEmpty
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
    );
  }
}
