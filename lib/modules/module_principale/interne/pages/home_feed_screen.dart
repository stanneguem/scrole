import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lottie/lottie.dart';
import 'package:visibility_detector/visibility_detector.dart';
import '../controllers/home_feed_controller.dart';
import '../controllers/main_layout_controller.dart';
import '../controllers/stories_controller.dart';
import '../widgets/feed_post_card.dart';
import '../../../../shared/widgets/post_media_slider.dart';
import '../widgets/community_comments_sheet.dart';
import 'package:scrole/modules/module_communautes/interne/controllers/community/community_feed_controller.dart';
import 'package:scrole/modules/module_evenement/centre/models/event_model.dart';
import 'package:scrole/modules/module_principale/externe/repositories/home_feed_repository.dart';
import 'story_viewer_screen.dart';
import 'create_story_screen.dart';
import 'package:scrole/app/routes/app_pages.dart';
import 'package:scrole/shared/widgets/app_cached_image.dart';
import 'package:scrole/shared/widgets/user_certified_badge.dart';
import 'package:scrole/shared/widgets/entity_certified_badge.dart';

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
    if (!Get.isRegistered<HomeFeedController>()) {
      Get.put(HomeFeedController());
    }
    if (!Get.isRegistered<StoriesController>()) {
      Get.put(StoriesController());
    }

    final feedController = Get.find<HomeFeedController>();
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
                    const _SuggestedProfilesCarousel(),
                    const _SuggestedEventsCarousel(),
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
                    return const _SuggestedProfilesCarousel();
                  }
                  if (index == insertIndex + 1) {
                    return const _SuggestedEventsCarousel();
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
                      }
                    },
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: FeedPostCard(
                          post: post,
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
                            padding: EdgeInsets.all(hasOwnStory ? 2.5 : 0),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: hasOwnStory
                                  ? Border.all(color: own.hasUnseen ? Colors.blue : Colors.grey.shade500, width: 2.5)
                                  : null,
                            ),
                            child: CircleAvatar(
                              radius: 28,
                              backgroundImage: own?.author.photoUrl != null && own!.author.photoUrl!.isNotEmpty
                                  ? NetworkImage(own.author.photoUrl!)
                                  : null,
                              child: own?.author.photoUrl == null || own!.author.photoUrl!.isEmpty
                                  ? Icon(Icons.person, color: colorScheme.onSurfaceVariant)
                                  : null,
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
                      child: CircleAvatar(
                        radius: 28,
                        backgroundImage: group.author.photoUrl != null && group.author.photoUrl!.isNotEmpty
                            ? NetworkImage(group.author.photoUrl!)
                            : null,
                        child: group.author.photoUrl == null || group.author.photoUrl!.isEmpty
                            ? Text(group.author.displayName.isNotEmpty ? group.author.displayName[0] : 'U')
                            : null,
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

class _SuggestedProfilesCarousel extends GetView<HomeFeedController> {
  const _SuggestedProfilesCarousel();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Obx(() {
      final profiles = controller.suggestedProfiles;
      if (profiles.isEmpty) return const SizedBox.shrink();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Suggestions de profils',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: colorScheme.onSurface),
                ),
                TextButton(
                  onPressed: () {},
                  child: Text('home_feed_see_more'.tr, style: TextStyle(fontWeight: FontWeight.w600, color: colorScheme.primary)),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 195,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: profiles.length,
              itemBuilder: (context, index) {
                final p = profiles[index];
                return Container(
                  width: 135,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: p.photoUrl != null && p.photoUrl!.isNotEmpty
                              ? AppCachedImage(imageUrl: p.photoUrl!, width: 60, height: 60, fit: BoxFit.cover)
                              : Container(width: 60, height: 60, color: colorScheme.primary, alignment: Alignment.center, child: Text(p.name.isNotEmpty ? p.name[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20))),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(p.name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: colorScheme.onSurface), maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 3),
                      Text(p.reasonSubtitle, style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
                      const Spacer(),
                      SizedBox(
                        width: double.infinity,
                        height: 32,
                        child: ElevatedButton(
                          onPressed: () {
                            p.isAdded = !p.isAdded;
                            controller.suggestedProfiles.refresh();
                          },
                          style: ElevatedButton.styleFrom(
                            padding: EdgeInsets.zero,
                            elevation: 0,
                            backgroundColor: p.isAdded ? colorScheme.surfaceContainerHighest : colorScheme.primary,
                            foregroundColor: p.isAdded ? colorScheme.onSurface : colorScheme.onPrimary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: Text(p.isAdded ? 'Ajouté' : 'home_feed_add_profile'.tr, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      );
    });
  }
}

class _SuggestedEventsCarousel extends GetView<HomeFeedController> {
  const _SuggestedEventsCarousel();

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
                Text(
                  'Événements suggérés',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: colorScheme.onSurface),
                ),
                TextButton(
                  onPressed: () {
                    try {
                      if (Get.isRegistered<MainLayoutController>()) {
                        Get.find<MainLayoutController>().goToEventSuggestionsTab();
                      }
                    } catch (e) {
                      debugPrint('[EVENTS] Error navigating to event suggestions: $e');
                    }
                  },
                  child: Text('see_more'.tr, style: TextStyle(fontWeight: FontWeight.w600, color: colorScheme.primary)),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 165,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: events.length,
              itemBuilder: (context, index) {
                final ev = events[index];
                return GestureDetector(
                  onTap: () {
                    Get.toNamed(AppPages.eventPreviewPath(ev.id));
                  },
                  child: Container(
                    width: 155,
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ev.coverImageUrl != null && ev.coverImageUrl!.isNotEmpty
                            ? AppCachedImage(imageUrl: ev.coverImageUrl!, width: 155, height: 85, fit: BoxFit.cover)
                            : Container(width: 155, height: 85, color: colorScheme.primaryContainer, child: const Icon(Icons.event, size: 28)),
                        Padding(
                          padding: const EdgeInsets.all(10.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Expanded(child: Text(ev.name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: colorScheme.onSurface), maxLines: 1, overflow: TextOverflow.ellipsis)),
                                EntityCertifiedBadge(entityType: 'event', entityId: ev.id, size: 15),
                              ]),
                              const SizedBox(height: 3),
                              Row(
                                children: [
                                  Icon(Icons.location_on_rounded, size: 12, color: colorScheme.primary),
                                  const SizedBox(width: 3),
                                  Expanded(
                                    child: Text(
                                      ev.city?.toString() ?? 'Virtuel',
                                      style: TextStyle(fontSize: 11.5, color: colorScheme.onSurfaceVariant),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      );
    });
  }
}
