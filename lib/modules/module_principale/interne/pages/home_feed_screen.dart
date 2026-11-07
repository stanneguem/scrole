import 'dart:async';
import 'package:flutter/material.dart';
import 'package:scrole/app_controller.dart';
import 'package:scrole/app/theme/app_colors.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:lottie/lottie.dart';
import 'package:visibility_detector/visibility_detector.dart';
import '../controllers/home_feed_controller.dart';
import '../controllers/main_layout_controller.dart';
import '../controllers/stories_controller.dart';
import '../widgets/feed_post_card.dart';
import '../../../../shared/widgets/post_media_slider.dart';
import '../../../../shared/widgets/app_cached_image.dart';
import '../widgets/community_comments_sheet.dart';
import 'package:scrole/modules/module_communautes/interne/controllers/community/community_feed_controller.dart';
import 'package:scrole/modules/module_evenement/centre/models/event_model.dart';
import 'package:scrole/modules/module_evenement/centre/models/event_day_models.dart';
import 'package:scrole/modules/module_evenement/interne/pages/event_days_selector_screen.dart';
import 'package:scrole/modules/module_evenement/centre/repositories/event_repository.dart';
import 'package:scrole/modules/module_principale/externe/repositories/home_feed_repository.dart';
import 'story_viewer_screen.dart';
import 'create_story_screen.dart';
import 'package:scrole/app/routes/app_pages.dart';
import 'package:scrole/shared/widgets/app_cached_image.dart';
import 'package:scrole/shared/widgets/user_certified_badge.dart';
import 'package:scrole/shared/widgets/entity_certified_badge.dart';
import 'package:scrole/shared/utils/number_formatter.dart';

class HomeFeedScreen extends StatefulWidget {
  const HomeFeedScreen({super.key});

  @override
  State<HomeFeedScreen> createState() => _HomeFeedScreenState();
}

class _HomeFeedScreenState extends State<HomeFeedScreen> {
  final ScrollController _scrollController = ScrollController();
  final RxBool _showScrollToTop = false.obs;
  bool _notificationTargetHandled = false;

  Future<void> _openNotificationTarget() async {
    if (_notificationTargetHandled) return;
    final args = Get.arguments;
    if (args is! Map) return;
    final postId = (args['targetPostId'] ?? args['postId'] ?? args['post_id'])?.toString();
    if (postId == null || postId.isEmpty) return;
    _notificationTargetHandled = true;
    final commentId = (args['targetCommentId'] ?? args['commentId'] ?? args['comment_id'])?.toString();

    try {
      final post = await HomeFeedRepository().getPost(postId);
      if (!mounted) return;
      final feed = Get.find<HomeFeedController>();
      feed.posts.removeWhere((item) => item.id == post.id);
      feed.posts.insert(0, post);
      feed.posts.refresh();
      if (commentId != null && commentId.isNotEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        if (!mounted) return;
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => CommunityCommentsSheet(
            post: post,
            controller: Get.isRegistered<CommunityFeedController>()
                ? Get.find<CommunityFeedController>()
                : Get.put(CommunityFeedController(null, post.eventId)),
            targetCommentId: commentId,
          ),
        );
      }
    } catch (e, st) {
      debugPrint('[HomeFeedScreen] Failed to open notification post target: $e\\n$st');
      if (mounted) {
        Get.snackbar(
          'Contenu indisponible',
          'Cette publication ou ce commentaire n’est plus accessible.',
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (_scrollController.offset > 300 && !_showScrollToTop.value) {
        _showScrollToTop.value = true;
      } else if (_scrollController.offset <= 300 && _showScrollToTop.value) {
        _showScrollToTop.value = false;
      }

      // Infinite scroll pagination trigger
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
        if (Get.isRegistered<HomeFeedController>()) {
          Get.find<HomeFeedController>().loadMore();
        }
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Keep the feed controller owned by this screen's lifetime. A parent route
    // closing must not dispose the controller while this screen is still mounted.
    final feedController = Get.isRegistered<HomeFeedController>()
        ? Get.find<HomeFeedController>()
        : Get.put(HomeFeedController(), permanent: true);
    if (!Get.isRegistered<StoriesController>()) {
      Get.put(StoriesController(), permanent: true);
    }

    final storiesController = Get.find<StoriesController>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openNotificationTarget();
    });
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Stack(
        children: [
          RefreshIndicator(
            color: Colors.transparent,
            backgroundColor: Colors.transparent,
            elevation: 0,
            onRefresh: () async {
              await Future.wait([
                feedController.fetchFeed(refresh: true),
                storiesController.fetchStories(),
              ]);
            },
            child: Obx(() {
              final state = feedController.state.value;

              if (state == HomeFeedState.loading) {
                return Center(
                  child: Lottie.asset(
                    'assets/lotties/Animation - 1791582964132.json',
                    width: 140,
                    height: 140,
                  ),
                );
              }

              if (state == HomeFeedState.error) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(feedController.errorMessage.value, style: TextStyle(color: colorScheme.error)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => feedController.fetchFeed(),
                        child: Text('retry'.tr),
                      ),
                    ],
                  ),
                );
              }

              if (state == HomeFeedState.empty || feedController.posts.isEmpty) {
                return ListView(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    const _StoriesRow(),
                    const _TrendingHashtagsStrip(),
                    _SuggestedProfilesCarousel(controller: feedController),
                    _SuggestedEventsCarousel(controller: feedController),
                    SizedBox(
                      height: MediaQuery.of(context).size.height * 0.4,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.feed_outlined, size: 64, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                              const SizedBox(height: 16),
                              Text(
                                'home_feed_empty_invitation'.tr,
                                style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 15),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 100),
                  ],
                );
              }

              return ListView.builder(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 120),
                itemCount: feedController.posts.length + 3,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _StoriesRow(),
                        const _TrendingHashtagsStrip(),
                        // Preserve the layout boundary while making the separator
                        // visually imperceptible, as requested.
                        Container(
                          height: 1,
                          width: double.infinity,
                          color: colorScheme.outlineVariant.withValues(alpha: 0.01),
                        ),
                      ],
                    );
                  }

                  final insertIndex = feedController.posts.length >= 2 ? 3 : (feedController.posts.length == 1 ? 2 : 1);

                  if (index == insertIndex) {
                    return _SuggestedProfilesCarousel(controller: feedController);
                  }
                  if (index == insertIndex + 1) {
                    return _SuggestedEventsCarousel(controller: feedController);
                  }

                  int postIndex;
                  if (index < insertIndex) {
                    postIndex = index - 1;
                  } else {
                    postIndex = index - 3;
                  }

                  if (postIndex < 0 || postIndex >= feedController.posts.length) {
                    return const SizedBox.shrink();
                  }

                  final post = feedController.posts[postIndex];

                  return VisibilityDetector(
                    key: Key('post_vis_${post.id}'),
                    onVisibilityChanged: (info) {
                      final eligible = info.visibleFraction >= 0.50;
                      FeedVideoAutoplayGate.updatePostVisibility(post.id, eligible);
                      if (eligible) {
                        feedController.queuePostView(post);
                        feedController.startPostDwell(post);
                      } else {
                        feedController.stopPostDwell(post.id);
                      }
                    },
                    // A ListView gives each item an unbounded height.
                    // Center expands to the available height in that situation,
                    // producing an infinite-height feed item. Align with a
                    // height factor shrink-wraps to the card's natural height.
                    child: Align(
                      alignment: Alignment.topCenter,
                      heightFactor: 1,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: FeedPostCard(
                          post: post,
                          onVideoQualifiedView: (postId) => feedController.queueQualifiedVideoPostView(postId, post),
                          onRetryPublishing: () => feedController.retryQueuedPost(post.id),
                          onReactionTap: (reaction) => feedController.handleReaction(post.id, reaction),
                          onCommentTap: () {
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (_) => CommunityCommentsSheet(
                                post: post,
                                controller: Get.isRegistered<CommunityFeedController>()
                                    ? Get.find<CommunityFeedController>()
                                    : Get.put(CommunityFeedController(null, post.eventId)),
                              ),
                            );
                          },
                          onHidePost: () => feedController.hidePost(post.id),
                        ),
                      ),
                    ),
                  );
                },
              );
            }),
          ),

          // --- Custom Refresh Lottie Indicator Overlay ---
          Positioned(
            top: 12,
            left: 0,
            right: 0,
            child: Center(
              child: Obx(() {
                if (!feedController.isRefreshing.value) return const SizedBox.shrink();
                return Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Lottie.asset(
                    'assets/lotties/Animation - 1791582964132.json',
                    width: 44,
                    height: 44,
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _StoryPublishingRing extends StatefulWidget {
  const _StoryPublishingRing();

  @override
  State<_StoryPublishingRing> createState() => _StoryPublishingRingState();
}

class _StoryPublishingRingState extends State<_StoryPublishingRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotationController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 66,
      height: 66,
      child: AnimatedBuilder(
        animation: _rotationController,
        builder: (context, child) => Transform.rotate(
          angle: _rotationController.value * 2 * 3.141592653589793,
          child: CustomPaint(
            painter: _StoryPublishingRingPainter(
              trackColor: colorScheme.surface.withValues(alpha: 0.95),
              colors: [
                colorScheme.primary.withValues(alpha: 0.18),
                colorScheme.primary,
                colorScheme.tertiary,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StoryPublishingRingPainter extends CustomPainter {
  const _StoryPublishingRingPainter({
    required this.trackColor,
    required this.colors,
  });

  final Color trackColor;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 3.5;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );

    final progressPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        colors: colors,
        stops: const [0.0, 0.62, 1.0],
      ).createShader(rect);
    canvas.drawArc(rect, -1.5707963267948966, 4.55, false, progressPaint);
  }

  @override
  bool shouldRepaint(covariant _StoryPublishingRingPainter oldDelegate) =>
      oldDelegate.trackColor != trackColor || oldDelegate.colors != colors;
}

class _StoriesRow extends GetView<StoriesController> {
  const _StoriesRow();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: 116,
      child: Obx(() {
        final own = controller.ownGroup.value;
        final hasOwnStory = own != null && own.stories.isNotEmpty;
        final appController = Get.isRegistered<AppController>() ? Get.find<AppController>() : null;
        final profile = appController?.profile.value ?? const <String, dynamic>{};
        final ownProfilePhoto = (profile['photo_url'] ??
                profile['avatar_url'] ??
                profile['profile_photo_url'] ??
                appController?.authUser.value?.userMetadata?['photo_url'] ??
                appController?.authUser.value?.userMetadata?['avatar_url'])
            ?.toString();
        final ownLatestStory = hasOwnStory
            ? (own.stories.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt))).first
            : null;
        // For a story that shares a post, use the post's actual visual
        // preview (video thumbnail when available), not the profile avatar.
        final ownSharedMedia = ownLatestStory?.sharedPost?.media
            .where((media) => media.url.trim().isNotEmpty)
            .toList() ?? const [];
        final ownSharedPreviewUrl = ownSharedMedia.isEmpty
            ? null
            : (ownSharedMedia.first.isVideo &&
                    (ownSharedMedia.first.thumbnailUrl?.isNotEmpty ?? false)
                ? ownSharedMedia.first.thumbnailUrl
                : ownSharedMedia.first.url);
        final ownStoryPreviewUrl = ownLatestStory?.kind == 'video'
            ? (ownLatestStory?.thumbnailUrl?.isNotEmpty == true ? ownLatestStory!.thumbnailUrl : own?.author.photoUrl ?? ownProfilePhoto)
            : (ownLatestStory?.imageUrl?.isNotEmpty == true ? ownLatestStory!.imageUrl : ownSharedPreviewUrl);
        // Unseen stories first, then most recently active authors.
        final otherGroups = <EventStoryGroup>[
          ...controller.followingGroups,
          ...controller.suggestedGroups,
        ]..sort((a, b) {
            if (a.hasUnseen != b.hasUnseen) return a.hasUnseen ? -1 : 1;
            return b.latestAt.compareTo(a.latestAt);
          });
        final allGroupsForViewer = [
          if (hasOwnStory) own,
          ...otherGroups,
        ];

        return ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: otherGroups.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: GestureDetector(
                  onTap: () {
                    if (hasOwnStory) {
                      Get.to(() => StoryViewerScreen(groups: [own], initialGroupIndex: 0));
                    } else {
                      Get.to(() => const CreateStoryScreen());
                    }
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Stack(
                        children: [
                          Container(
                            // Keep the same outer diameter whether or not the
                            // current user has an active story.
                            padding: const EdgeInsets.all(2.5),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: hasOwnStory
                                    ? (own.hasUnseen ? Colors.blue : Colors.grey.shade500)
                                    : Colors.transparent,
                                width: 2.5,
                              ),
                            ),
                            child: ClipOval(
                              child: SizedBox(
                                width: 56,
                                height: 56,
                                child: (hasOwnStory &&
                                        ownStoryPreviewUrl != null &&
                                        ownStoryPreviewUrl.isNotEmpty)
                                    ? AppCachedImage(
                                        imageUrl: ownStoryPreviewUrl,
                                        width: 56,
                                        height: 56,
                                        fit: BoxFit.cover,
                                        cacheUntil: ownLatestStory?.expiresAt,
                                        errorWidget: Container(
                                          color: colorScheme.surfaceContainerHighest,
                                          alignment: Alignment.center,
                                          child: Icon(Icons.play_circle_outline,
                                              color: colorScheme.onSurfaceVariant, size: 25),
                                        ),
                                      )
                                    : ((own?.author.photoUrl ?? ownProfilePhoto) != null &&
                                            (own?.author.photoUrl ?? ownProfilePhoto)!.isNotEmpty)
                                        ? AppCachedImage(
                                            imageUrl: own?.author.photoUrl ?? ownProfilePhoto!,
                                            width: 56,
                                            height: 56,
                                            fit: BoxFit.cover,
                                            errorWidget: Icon(Icons.person,
                                                color: colorScheme.onSurfaceVariant),
                                          )
                                        : Container(
                                            color: colorScheme.surfaceContainerHighest,
                                            alignment: Alignment.center,
                                            child: Icon(Icons.person,
                                                color: colorScheme.onSurfaceVariant),
                                          ),
                              ),
                            ),
                          ),
                          if (controller.isPublishingStory.value)
                            const Positioned.fill(
                              child: IgnorePointer(
                                child: Center(
                                  child: _StoryPublishingRing(),
                                ),
                              ),
                            ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: GestureDetector(
                              onTap: () => Get.to(() => const CreateStoryScreen()),
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  color: colorScheme.primary,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: colorScheme.surface, width: 2),
                                ),
                                child: const Icon(Icons.add, size: 14, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        controller.isPublishingStory.value ? 'Publication…' : 'Ma story',
                        style: TextStyle(
                          fontSize: 11,
                          color: controller.isPublishingStory.value
                              ? colorScheme.primary
                              : colorScheme.onSurface,
                          fontWeight: controller.isPublishingStory.value
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            final group = otherGroups[index - 1];
            final hasUnviewed = group.hasUnseen;
            final latestStory = group.stories.isEmpty ? null : (group.stories.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt))).first;
            final storyPreviewUrl = latestStory?.kind == 'video'
                ? (latestStory?.thumbnailUrl?.isNotEmpty == true ? latestStory!.thumbnailUrl : group.author.photoUrl)
                : (latestStory?.imageUrl?.isNotEmpty == true ? latestStory!.imageUrl : group.author.photoUrl);

            return Padding(
              padding: const EdgeInsets.only(right: 12),
              child: GestureDetector(
                onTap: () {
                  final viewerIndex = hasOwnStory ? index : index - 1;
                  Get.to(() => StoryViewerScreen(groups: allGroupsForViewer, initialGroupIndex: viewerIndex));
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(2.5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: hasUnviewed ? Colors.blue : Colors.grey.shade500,
                          width: 2.5,
                        ),
                      ),
                      child: ClipOval(
                        child: SizedBox(
                          width: 56,
                          height: 56,
                          child: storyPreviewUrl != null && storyPreviewUrl.isNotEmpty
                              ? AppCachedImage(
                                  imageUrl: storyPreviewUrl,
                                  width: 56,
                                  height: 56,
                                  fit: BoxFit.cover,
                                  cacheUntil: latestStory?.expiresAt,
                                  errorWidget: Container(
                                    color: colorScheme.surfaceContainerHighest,
                                    alignment: Alignment.center,
                                    child: Text(group.author.displayName.isNotEmpty ? group.author.displayName[0] : 'U'),
                                  ),
                                )
                              : Container(
                                  color: colorScheme.surfaceContainerHighest,
                                  alignment: Alignment.center,
                                  child: Text(group.author.displayName.isNotEmpty ? group.author.displayName[0] : 'U'),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: 64,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              group.author.displayName,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: hasUnviewed ? FontWeight.w700 : FontWeight.w400,
                                color: colorScheme.onSurface,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                          ),
                          if (group.author.isCertified) ...[
                            const SizedBox(width: 3),
                            UserCertifiedBadge(size: 11, showTooltip: false, userId: group.author.userId),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      }),
    );
  }
}

class _SuggestedProfilesCarousel extends StatelessWidget {
  const _SuggestedProfilesCarousel({required this.controller});

  final HomeFeedController controller;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Obx(() {
      final profiles = controller.suggestedProfiles;
      if (profiles.isEmpty) return const SizedBox.shrink();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'home_feed_suggested_profiles_title'.tr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: colors.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 236,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: profiles.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) => _SuggestedProfileActionCard(
                profile: profiles[index],
                controller: controller,
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      );
    });
  }
}

class _SuggestedProfileActionCard extends StatefulWidget {
  const _SuggestedProfileActionCard({
    required this.profile,
    required this.controller,
  });

  final SuggestedProfileModel profile;
  final HomeFeedController controller;

  @override
  State<_SuggestedProfileActionCard> createState() => _SuggestedProfileActionCardState();
}

class _SuggestedProfileActionCardState extends State<_SuggestedProfileActionCard> {
  bool _following = false;
  bool _dismissing = false;

  Future<void> _follow() async {
    if (_following || _dismissing || widget.profile.isAdded) return;
    setState(() => _following = true);
    try {
      await widget.controller.followSuggestedProfile(widget.profile);
      if (mounted) {
        Get.snackbar(
          'home_feed_suggested_profiles_title'.tr,
          'home_feed_profile_followed'.tr,
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    } catch (error) {
      debugPrint('[SuggestedProfileCard] follow failed: $error');
      if (mounted) {
        Get.snackbar(
          'home_feed_suggested_profiles_title'.tr,
          'home_feed_profile_follow_error'.tr,
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    } finally {
      if (mounted) setState(() => _following = false);
    }
  }

  Future<void> _dismiss() async {
    if (_following || _dismissing) return;
    setState(() => _dismissing = true);
    try {
      await widget.controller.dismissSuggestedProfile(widget.profile);
    } catch (error) {
      debugPrint('[SuggestedProfileCard] dismiss failed: $error');
      if (mounted) {
        Get.snackbar(
          'home_feed_suggested_profiles_title'.tr,
          'home_feed_profile_dismiss_error'.tr,
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    } finally {
      if (mounted) setState(() => _dismissing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final profile = widget.profile;
    return Container(
      width: 218,
      height: 226,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.45)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.045),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: () => Get.toNamed(AppPages.externalProfilePath(profile.id)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ClipOval(
                  child: profile.photoUrl != null && profile.photoUrl!.isNotEmpty
                      ? AppCachedImage(imageUrl: profile.photoUrl!, width: 58, height: 58, fit: BoxFit.cover)
                      : Container(
                          width: 58,
                          height: 58,
                          color: colors.primaryContainer,
                          alignment: Alignment.center,
                          child: Text(
                            profile.name.isNotEmpty ? profile.name[0].toUpperCase() : '?',
                            style: TextStyle(color: colors.onPrimaryContainer, fontSize: 21, fontWeight: FontWeight.bold),
                          ),
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 7),
          GestureDetector(
            onTap: () => Get.toNamed(AppPages.externalProfilePath(profile.id)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    profile.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: colors.onSurface),
                  ),
                ),
                if (profile.isCertified) ...[
                  const SizedBox(width: 3),
                  UserCertifiedBadge(userId: profile.id, size: 14, showTooltip: false),
                ],
              ],
            ),
          ),
          if (profile.username.isNotEmpty)
            Text(
              '@${profile.username}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
            ),
          const SizedBox(height: 3),
          Text(
            profile.reasonSubtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10.5, color: colors.onSurfaceVariant),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: 34,
            child: ElevatedButton(
              onPressed: (_following || _dismissing || profile.isAdded || profile.isRequestSent) ? null : _follow,
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.zero,
                elevation: 0,
                backgroundColor: profile.isAdded ? colors.surfaceContainerHighest : colors.primary,
                foregroundColor: profile.isAdded ? colors.onSurface : colors.onPrimary,
                disabledBackgroundColor: colors.surfaceContainerHighest,
                disabledForegroundColor: colors.onSurface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: _following
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(
                      profile.isRequestSent
                    ? 'home_feed_profile_request_sent'.tr
                    : (profile.isAdded ? 'home_feed_profile_following'.tr : 'home_feed_add_profile'.tr),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
            ),
          ),
          const SizedBox(height: 5),
          SizedBox(
            height: 22,
            child: TextButton(
              onPressed: (_following || _dismissing) ? null : _dismiss,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'home_feed_profile_not_interested'.tr,
                maxLines: 1,
                style: TextStyle(fontSize: 10.5, color: colors.onSurfaceVariant),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestedEventsCarousel extends StatelessWidget {
  const _SuggestedEventsCarousel({required this.controller});

  final HomeFeedController controller;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Obx(() {
      final events = controller.suggestedEvents;
      if (events.isEmpty) return const SizedBox.shrink();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'home_feed_suggested_events_title'.tr,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 40),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () {
                    try {
                      if (Get.isRegistered<MainLayoutController>()) {
                        Get.find<MainLayoutController>().goToEventSuggestionsTab();
                      }
                    } catch (e) {
                      debugPrint('[EVENTS] Error navigating to event suggestions: $e');
                    }
                  },
                  child: Text(
                    'see_more'.tr,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 278,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: events.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) => _SuggestedEventActionCard(
                event: events[index],
                controller: controller,
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      );
    });
  }
}

class _SuggestedEventActionCard extends StatefulWidget {
  const _SuggestedEventActionCard({required this.event, required this.controller});

  final EventModel event;
  final HomeFeedController controller;

  @override
  State<_SuggestedEventActionCard> createState() => _SuggestedEventActionCardState();
}

class _SuggestedEventActionCardState extends State<_SuggestedEventActionCard> {
  bool _adding = false;
  bool _dismissing = false;

  bool get _isMultiDay {
    final start = DateTime(widget.event.startsAt.year, widget.event.startsAt.month, widget.event.startsAt.day);
    final endValue = widget.event.endsAt ?? widget.event.startsAt;
    final end = DateTime(endValue.year, endValue.month, endValue.day);
    return end.difference(start).inDays >= 1;
  }

  Future<void> _addToCalendar() async {
    if (_adding || _dismissing) return;
    setState(() => _adding = true);
    try {
      final repository = Get.find<EventRepository>();
      if (_isMultiDay) {
        final openDays = await repository.getEventOpenDays(widget.event.id);
        if (openDays.isEmpty || !openDays.any((day) => day.isOpen)) {
          if (mounted) Get.snackbar('Calendrier', 'home_feed_suggested_open_days_missing'.tr,
            snackPosition: SnackPosition.BOTTOM);
          return;
        }
        if (!mounted) return;
        Get.to(
          () => EventDaysSelectorScreen(
            eventId: widget.event.id,
            eventName: widget.event.name,
            openDays: openDays,
            onSuccess: () => widget.controller.removeSuggestedEvent(widget.event.id),
          ),
          transition: Transition.rightToLeft,
        );
      } else {
        final userId = Get.find<AppController>().authUser.value?.id ?? '';
        if (userId.isEmpty) throw StateError('Authentification requise');
        final suggestedCommunityId =
            await repository.addEventToCalendarOptimistic(widget.event.id, userId);
        widget.controller.removeSuggestedEvent(widget.event.id);
        if (mounted && suggestedCommunityId != null && suggestedCommunityId.isNotEmpty) {
          Get.snackbar(
            'Communauté associée',
            'Cet événement est lié à une communauté ! Souhaitez-vous la rejoindre ?',
            snackPosition: SnackPosition.BOTTOM,
            mainButton: TextButton(
              onPressed: () => Get.toNamed(AppPages.communityDetailPath(suggestedCommunityId)),
              child: const Text('Rejoindre',
                style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
            ),
            duration: const Duration(seconds: 5),
          );
        } else if (mounted) {
          Get.snackbar('Calendrier', 'home_feed_suggested_added'.tr,
            snackPosition: SnackPosition.BOTTOM);
        }
      }
    } catch (e) {
      debugPrint('[SuggestedEventCard] add to calendar failed: $e');
      if (mounted) {
        Get.snackbar('Calendrier', widget.controller.eventAgendaRestrictionMessageKey(e).tr,
          snackPosition: SnackPosition.BOTTOM, duration: const Duration(seconds: 5));
      }
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _dismiss() async {
    if (_adding || _dismissing) return;
    setState(() => _dismissing = true);
    try {
      await widget.controller.dismissSuggestedEvent(widget.event.id);
    } catch (e) {
      debugPrint('[SuggestedEventCard] dismiss failed: $e');
      if (mounted) Get.snackbar('Erreur', 'home_feed_suggested_dismiss_error'.tr,
        snackPosition: SnackPosition.BOTTOM);
    } finally {
      if (mounted) setState(() => _dismissing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final ev = widget.event;
    return Container(
      width: 238,
      height: 270,
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.035), blurRadius: 7, offset: const Offset(0, 2)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => Get.toNamed(AppPages.eventPreviewPath(ev.id)),
            child: Stack(
              children: [
                ev.coverImageUrl != null && ev.coverImageUrl!.isNotEmpty
                    ? AppCachedImage(imageUrl: ev.coverImageUrl!, width: 238, height: 128, fit: BoxFit.cover)
                    : Container(width: 238, height: 128, color: colors.primaryContainer,
                        child: Icon(Icons.event_rounded, size: 34, color: colors.onPrimaryContainer)),
                Positioned(
                  right: 8,
                  top: 8,
                  child: EntityCertifiedBadge(entityType: 'event', entityId: ev.id, size: 17),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: () => Get.toNamed(AppPages.eventPreviewPath(ev.id)),
                    child: Text(ev.name,
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: colors.onSurface),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.location_on_rounded, size: 12, color: colors.primary),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          ev.isOnline ? 'Virtuel' : (ev.city?.name ?? ev.address ?? ''),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 10.5, color: colors.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.calendar_today_rounded, size: 11, color: colors.primary),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          MaterialLocalizations.of(context).formatMediumDate(ev.startsAt),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 10.5, color: colors.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                          SizedBox(
                    width: double.infinity,
                    height: 34,
                    child: FilledButton.icon(
                      onPressed: (_adding || _dismissing) ? null : _addToCalendar,
                      icon: _adding
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.calendar_month_rounded, size: 16),
                      label: Text('home_feed_suggested_add'.tr,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 7),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 29,
                    child: Center(
                      child: TextButton(
                        onPressed: (_adding || _dismissing) ? null : _dismiss,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          minimumSize: const Size(0, 28),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          foregroundColor: colors.onSurfaceVariant,
                        ),
                        child: _dismissing
                            ? const SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 2))
                            : Text('home_feed_suggested_not_interested'.tr,
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Compact live trends row shown directly below Stories in the home feed.
class _TrendingHashtagsStrip extends StatefulWidget {
  const _TrendingHashtagsStrip();

  @override
  State<_TrendingHashtagsStrip> createState() => _TrendingHashtagsStripState();
}

class _TrendingHashtagsStripState extends State<_TrendingHashtagsStrip> {
  late Future<List<Map<String, dynamic>>> _trendsFuture;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadTrends();
    // Trends update periodically without forcing a full feed refresh.
    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) _loadTrends();
    });
  }

  void _loadTrends() {
    setState(() {
      _trendsFuture = HomeFeedRepository().getTrendingHashtags(limit: 10);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _trendsFuture,
      builder: (context, snapshot) {
        final trends = snapshot.data;
        if (trends == null || trends.isEmpty) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 0, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 14, bottom: 8),
                child: Row(
                  children: [
                    Icon(Icons.trending_up_rounded, size: 18, color: colors.primary),
                    const SizedBox(width: 6),
                    Text(
                      'hashtag_trending_title'.tr,
                      style: TextStyle(
                        color: colors.onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 58,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: trends.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final trend = trends[index];
                    final name = (trend['name'] ?? trend['normalized_name'] ?? '')
                        .toString()
                        .replaceFirst(RegExp(r'^#+'), '');
                    if (name.isEmpty) return const SizedBox.shrink();
                    final recent = (trend['posts_30m'] as num?)?.toInt() ?? 0;
                    final postCount = (trend['posts_total'] as num?)?.toInt() ?? (trend['posts_24h'] as num?)?.toInt() ?? 0;
                    return Material(
                      color: colors.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => Get.toNamed(AppPages.hashtagFeedPath(name)),
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 112, maxWidth: 156),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: colors.outlineVariant.withValues(alpha: 0.55),
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SvgPicture.asset(
                                    'assets/svg_icons/fire-svgrepo-com.svg',
                                    width: 16,
                                    height: 16,
                                    colorFilter: ColorFilter.mode(
                                      colors.primary,
                                      BlendMode.srcIn,
                                    ),
                                  ),
                                  const SizedBox(width: 3),
                                  Flexible(
                                    child: Text(
                                      '#$name',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: colors.onSurface,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'hashtag_posts_count'.trParams({'count': NumberFormatter.formatCount(postCount)}),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: colors.onSurfaceVariant,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
