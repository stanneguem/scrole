import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../modules/module_principale/centre/models/community_post.dart';
import '../../modules/module_principale/externe/repositories/home_feed_repository.dart';
import '../../modules/module_principale/interne/widgets/feed_post_card.dart';

/// Opens a shared post using the same FeedPostCard and width constraints as
/// HomeFeedScreen so its appearance matches the original feed card.
class SharedPostLinkScreen extends StatefulWidget {
  const SharedPostLinkScreen({super.key, required this.postId});

  final String postId;

  @override
  State<SharedPostLinkScreen> createState() => _SharedPostLinkScreenState();
}

class _SharedPostLinkScreenState extends State<SharedPostLinkScreen> {
  late final Future<CommunityPost> _postFuture =
      HomeFeedRepository().getPost(widget.postId);

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
                    onCommentTap: () {
                      Get.snackbar(
                        'Commentaires',
                        'Les commentaires de cette publication ne sont pas encore raccordés sur cette page.',
                        snackPosition: SnackPosition.BOTTOM,
                      );
                    },
                    onShareTap: () {
                      Get.snackbar(
                        'Partager',
                        'Le partage de cette publication n’est pas encore raccordé sur cette page.',
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
