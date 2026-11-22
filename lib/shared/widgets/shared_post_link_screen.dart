import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../modules/module_principale/centre/models/community_post.dart';
import '../../modules/module_principale/externe/repositories/home_feed_repository.dart';
import '../../modules/module_principale/interne/widgets/feed_post_card.dart';
import '../../modules/module_principale/interne/widgets/community_comments_sheet.dart';
import '../../modules/module_communautes/interne/controllers/community/community_feed_controller.dart';

/// Opens a shared post using the same FeedPostCard and width constraints as
/// HomeFeedScreen so its appearance matches the original feed card.
class SharedPostLinkScreen extends StatefulWidget {
  const SharedPostLinkScreen({super.key, required this.postId, this.commentId});

  final String postId;
  final String? commentId;

  @override
  State<SharedPostLinkScreen> createState() => _SharedPostLinkScreenState();
}

class _SharedPostLinkScreenState extends State<SharedPostLinkScreen> {
  late final Future<CommunityPost> _postFuture =
      HomeFeedRepository().getPost(widget.postId);
  bool _targetCommentOpened = false;

  CommunityFeedController _commentsController(CommunityPost post) {
    final tag = 'mention_post_${post.id}';
    if (!Get.isRegistered<CommunityFeedController>(tag: tag)) {
      Get.put(CommunityFeedController(null, post.communityId), tag: tag);
    }
    return Get.find<CommunityFeedController>(tag: tag);
  }

  Future<void> _openComments(CommunityPost post, {String? targetCommentId}) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CommunityCommentsSheet(
        post: post,
        controller: _commentsController(post),
        targetCommentId: targetCommentId,
      ),
    );
  }

  void _openTargetCommentAfterBuild(CommunityPost post) {
    final commentId = widget.commentId?.trim();
    if (_targetCommentOpened || commentId == null || commentId.isEmpty) return;
    _targetCommentOpened = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openComments(post, targetCommentId: commentId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return FutureBuilder<CommunityPost>(
      future: _postFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Scaffold(
            backgroundColor: colorScheme.surface,
            appBar: AppBar(
              title: const Text('Publication'),
              centerTitle: true,
              scrolledUnderElevation: 0,
            ),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return Scaffold(
            backgroundColor: colorScheme.surface,
            appBar: AppBar(
              title: const Text('Publication'),
              centerTitle: true,
              scrolledUnderElevation: 0,
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.link_off_rounded,
                      size: 44,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Cette publication est indisponible ou tu n’as pas accès à son contenu.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => Get.back(),
                      child: const Text('Retour'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final post = snapshot.data!;
        _openTargetCommentAfterBuild(post);

        return Scaffold(
          backgroundColor: colorScheme.surface,
          appBar: AppBar(
            title: const Text('Publication'),
            centerTitle: true,
            scrolledUnderElevation: 0,
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 120),
            children: [
              // Same Center + maxWidth constraints as the home feed.
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: FeedPostCard(
                    post: post,
                    onReactionTap: (reaction) async {
                      try {
                        await HomeFeedRepository().setCommunityPostReaction(
                          post.id,
                          reaction == PostReaction.like
                              ? 'like'
                              : reaction == PostReaction.dislike
                                  ? 'dislike'
                                  : null,
                        );
                      } catch (error) {
                        if (context.mounted) {
                          Get.snackbar(
                            'Réaction impossible',
                            'Connecte-toi ou réessaie dans un instant.',
                            snackPosition: SnackPosition.BOTTOM,
                          );
                        }
                      }
                    },
                    onCommentTap: () => _openComments(post),
                    onShareTap: () {
                      Get.snackbar(
                        'Partager',
                        'Le partage sera disponible depuis cette page prochainement.',
                        snackPosition: SnackPosition.BOTTOM,
                      );
                    },
                    onMoreTap: () {},
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
