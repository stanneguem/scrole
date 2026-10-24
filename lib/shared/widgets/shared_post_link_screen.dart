import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../modules/module_principale/centre/models/community_post.dart';
import '../../modules/module_principale/externe/repositories/home_feed_repository.dart';
import 'profile_post_detail_screen.dart';

/// Resolves a shared post link using the same access rules as the backend RPC.
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
    final colors = Theme.of(context).colorScheme;
    return FutureBuilder<CommunityPost>(
      future: _postFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Scaffold(
            backgroundColor: colors.surface,
            appBar: AppBar(title: const Text('Publication Scrole'), centerTitle: true),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Scaffold(
            backgroundColor: colors.surface,
            appBar: AppBar(title: const Text('Publication Scrole'), centerTitle: true),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.link_off_rounded, size: 44, color: colors.onSurfaceVariant),
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
        return ProfilePostDetailScreen(post: snapshot.data!);
      },
    );
  }
}
