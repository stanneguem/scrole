import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:scrole/modules/module_communautes/interne/controllers/community/community_feed_controller.dart';
import 'package:scrole/modules/module_communautes/centre/services/community_service.dart';
import 'package:scrole/modules/module_principale/interne/widgets/feed_post_card.dart';
import 'package:scrole/shared/widgets/post_media_slider.dart';
import 'package:scrole/modules/module_principale/interne/widgets/community_comments_sheet.dart';
import 'create_community_post_screen.dart';
import 'community_settings_screen.dart';
import 'community_chat_groups_screen.dart';
import '../../../../shared/widgets/entity_certified_badge.dart';

class CommunityFeedScreen extends StatefulWidget {
  final String communityId;
  final String communityName;

  const CommunityFeedScreen({
    super.key,
    required this.communityId,
    required this.communityName,
  });

  @override
  State<CommunityFeedScreen> createState() => _CommunityFeedScreenState();
}

class _CommunityFeedScreenState extends State<CommunityFeedScreen> {
  late final CommunityFeedController controller;
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _postKeys = <String, GlobalKey>{};
  String? _targetPostId;
  String? _targetCommentId;
  bool _targetNavigationStarted = false;
  bool _targetCommentOpened = false;

  @override
  void initState() {
    super.initState();
    controller = Get.put(
      CommunityFeedController(null, widget.communityId),
      tag: widget.communityId,
    );
    controller.communityName.value = widget.communityName;
    final args = Get.arguments;
    if (args is Map) {
      _targetPostId = (args['postId'] ?? args['post_id'] ?? args['publication_id'])?.toString();
      _targetCommentId = (args['commentId'] ?? args['comment_id'] ?? args['commentaire_id'])?.toString();
    }
    if (_targetPostId != null && _targetPostId!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_navigateToNotificationTarget());
      });
    }
  }

  Future<void> _navigateToNotificationTarget() async {
    if (_targetNavigationStarted || _targetPostId == null || _targetPostId!.isEmpty) return;
    _targetNavigationStarted = true;
    try {
      await controller.fetchCommunityFeed(isRefresh: true);
      var attempts = 0;
      while (mounted &&
          !controller.posts.any((post) => post.id == _targetPostId) &&
          controller.hasMore &&
          attempts < 30) {
        final previousCount = controller.posts.length;
        await controller.loadMorePosts();
        attempts++;
        if (controller.posts.length == previousCount) break;
      }

      if (!mounted) return;
      final index = controller.posts.indexWhere((post) => post.id == _targetPostId);
      if (index < 0) {
        Get.snackbar(
          'Publication introuvable',
          'Cette publication n’est plus disponible ou tu n’as pas accès à son contenu.',
          snackPosition: SnackPosition.BOTTOM,
        );
        return;
      }

      await WidgetsBinding.instance.endOfFrame;
      // A lazy ListView may not have built the target card yet. Jump near its
      // approximate index, let Flutter build it, then align it precisely.
      for (var attempt = 0; attempt < 4; attempt++) {
        final targetContext = _postKeys[_targetPostId!]?.currentContext;
        if (targetContext != null) {
          await Scrollable.ensureVisible(
            targetContext,
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeInOut,
            alignment: 0.12,
          );
          break;
        }
        if (!_scrollController.hasClients) break;
        final estimatedOffset = (index * 420.0).clamp(
          0.0,
          _scrollController.position.maxScrollExtent,
        ).toDouble();
        _scrollController.jumpTo(estimatedOffset);
        await WidgetsBinding.instance.endOfFrame;
      }

      if (_targetCommentId != null &&
          _targetCommentId!.isNotEmpty &&
          !_targetCommentOpened &&
          mounted) {
        _targetCommentOpened = true;
        final post = controller.posts[index];
        await Future<void>.delayed(const Duration(milliseconds: 250));
        if (!mounted) return;
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => CommunityCommentsSheet(post: post, controller: controller, targetCommentId: _targetCommentId),
        );
      }
    } catch (e, st) {
      debugPrint('[CommunityFeedScreen] Notification target navigation failed: $e\\n$st');
      if (mounted) {
        Get.snackbar(
          'Navigation impossible',
          'Impossible d’ouvrir le contenu ciblé. Réessaie depuis les notifications.',
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final communityId = widget.communityId;
    final communityName = widget.communityName;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        elevation: 0,
        title: FutureBuilder(
          future: Supabase.instance.client.rpc('get_community_member_count', params: {'p_community_id': communityId}),
          builder: (context, snapshot) {
            final memberCount = snapshot.hasData ? (snapshot.data as num).toInt() : null;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                Get.to(() => CommunitySettingsScreen(
                      communityId: communityId,
                      communityName: communityName,
                    ));
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          communityName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 17,
                            height: 1.15,
                            fontWeight: FontWeight.w700,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ),
                      EntityCertifiedBadge(entityType: 'community', entityId: communityId, size: 17),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    memberCount == null
                        ? 'community_member_count_loading'.tr
                        : (memberCount == 1
                            ? 'community_member_count_one'.trParams({'count': '$memberCount'})
                            : 'community_member_count_many'.trParams({'count': '$memberCount'})),
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.1,
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.forum_outlined, color: colorScheme.primary),
            tooltip: 'Discussions de groupe',
            onPressed: () {
              Get.to(() => CommunityChatGroupsScreen(
                    communityId: communityId,
                    communityName: communityName,
                  ));
            },
          ),
          IconButton(
            icon: Icon(Icons.add_rounded, color: colorScheme.primary, size: 28),
            onPressed: () {
              Get.to(() => CreateCommunityPostScreen(
                    communityName: communityName,
                    communityId: communityId,
                  ));
            },
            tooltip: 'community_feed_create_post_tooltip'.tr,
          ),
        ],
      ),
      body: Obx(() {
        final state = controller.feedState.value;
        final posts = controller.posts;

        switch (state) {
          case CommunityFeedState.initialLoading:
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: colorScheme.primary),
                    const SizedBox(height: 16),
                    Text(
                      'community_feed_loading'.tr,
                      style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14),
                    ),
                  ],
                ),
              ),
            );

          case CommunityFeedState.error:
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline_rounded, size: 56, color: colorScheme.error),
                    const SizedBox(height: 16),
                    Text(
                      controller.errorMessage.value.isNotEmpty
                          ? controller.errorMessage.value
                          : 'community_feed_error_msg'.tr,
                      style: TextStyle(color: colorScheme.onSurface, fontSize: 15, fontWeight: FontWeight.w500),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: () => controller.fetchCommunityFeed(isRefresh: true),
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: Text('retry'.tr),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colorScheme.primary,
                        foregroundColor: colorScheme.onPrimary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ),
              ),
            );

          case CommunityFeedState.empty:
            return RefreshIndicator(
              onRefresh: () => controller.fetchCommunityFeed(isRefresh: true),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Container(
                  constraints: BoxConstraints(
                    minHeight: MediaQuery.of(context).size.height * 0.7,
                  ),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SvgPicture.asset(
                        'assets/svg_icons/chat-round-svgrepo-com.svg',
                        width: 76,
                        height: 76,
                        colorFilter: ColorFilter.mode(
                          colorScheme.primary.withValues(alpha: 0.82),
                          BlendMode.srcIn,
                        ),
                      ),
                      const SizedBox(height: 22),
                      Text(
                        'community_feed_empty_title'.tr,
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 9),
                      Text(
                        'community_feed_empty_subtitle'.tr,
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 14,
                          height: 1.45,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 14),
                      TextButton(
                        onPressed: () {
                          Get.to(() => CreateCommunityPostScreen(
                                communityName: communityName,
                                communityId: communityId,
                              ));
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: colorScheme.primary,
                          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        ),
                        child: Text('community_feed_create_first_post'.tr),
                      ),
                    ],
                  ),
                ),
              ),
            );

          case CommunityFeedState.loaded:
          case CommunityFeedState.refreshing:
            return RefreshIndicator(
              onRefresh: () => controller.fetchCommunityFeed(isRefresh: true),
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.only(bottom: 90),
                itemCount: posts.length + (controller.hasMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == posts.length) {
                    controller.loadMorePosts();
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    );
                  }

                  final post = posts[index];
                  final postKey = _postKeys.putIfAbsent(post.id, () => GlobalKey());
                  return KeyedSubtree(
                    key: postKey,
                    child: VisibilityDetector(
                    key: Key('comm_post_vis_${post.id}'),
                    onVisibilityChanged: (info) {
                      final eligible = info.visibleFraction >= 0.50;
                      FeedVideoAutoplayGate.updatePostVisibility(post.id, eligible);
                      if (eligible) {
                        controller.queuePostView(post);
                      }
                    },
                    child: FeedPostCard(
                      post: post,
                      currentCommunityId: communityId,
                      onRetryPublishing: () => controller.retryQueuedPost(post.id),
                      onReactionTap: (reaction) => controller.handleReaction(post.id, reaction),
                      onCommentTap: () {
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (_) => CommunityCommentsSheet(post: post, controller: controller),
                        );
                      },
                    ),
                    ),
                  );
                },
              ),
            );
        }
      }),
    );
  }
}
