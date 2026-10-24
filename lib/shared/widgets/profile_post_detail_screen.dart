import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:scrole/modules/module_principale/externe/repositories/home_feed_repository.dart';
import 'package:video_player/video_player.dart';
import 'package:scrole/modules/module_principale/centre/models/community_post.dart';
import 'package:scrole/shared/widgets/app_cached_image.dart';

class ProfilePostDetailScreen extends StatefulWidget {
  const ProfilePostDetailScreen({super.key, required this.post});
  final CommunityPost post;

  @override
  State<ProfilePostDetailScreen> createState() => _ProfilePostDetailScreenState();
}

class _ProfilePostDetailScreenState extends State<ProfilePostDetailScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _deleting = false;

  bool get _isOwnPost {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    return currentUserId != null && currentUserId.isNotEmpty && widget.post.authorId == currentUserId;
  }

  Future<void> _confirmAndDeletePost() async {
    if (!_isOwnPost || _deleting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(Icons.delete_outline_rounded, color: Theme.of(dialogContext).colorScheme.error, size: 30),
        title: const Text('Supprimer la publication ?'),
        content: const Text('Cette action est définitive. La publication et ses médias associés seront supprimés.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Annuler')),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(dialogContext).colorScheme.error),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      await HomeFeedRepository().deletePost(widget.post.id);
      if (!mounted) return;
      Get.snackbar('Succès', 'Publication supprimée', snackPosition: SnackPosition.BOTTOM);
      Get.back(result: true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _deleting = false);
      Get.snackbar(
        'Suppression impossible',
        error.toString().replaceFirst('Exception: ', '').replaceAll('delete_unauthorized_error', 'Tu ne peux pas supprimer cette publication.'),
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  void _goToPage(int delta) {
    final target = (_currentPage + delta).clamp(0, widget.post.media.length - 1);
    if (target == _currentPage) return;
    _pageController.animateToPage(
      target,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final media = post.media;
    final rawDate = post.timeAgo.trim();
    final formattedDate = rawDate.isEmpty ? '' : _formatPublicationDate(rawDate);

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        title: const Text('Publication', style: TextStyle(fontWeight: FontWeight.w700)),
        centerTitle: true,
        leading: IconButton(
          tooltip: 'Retour',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Get.back(),
        ),
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          if (_isOwnPost)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _deleting
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : IconButton(
                      tooltip: 'Supprimer la publication',
                      onPressed: _confirmAndDeletePost,
                      icon: Icon(Icons.delete_outline_rounded, color: colors.error),
                    ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (media.isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: AspectRatio(
                aspectRatio: 0.92,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    PageView.builder(
                      controller: _pageController,
                      itemCount: media.length,
                      physics: const BouncingScrollPhysics(),
                      onPageChanged: (index) => setState(() => _currentPage = index),
                      itemBuilder: (context, index) => _PostMediaPage(
                        key: ValueKey('${post.id}:$index'),
                        media: media[index],
                      ),
                    ),
                    if (media.length > 1) ...[
                      Positioned(
                        left: 12,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: _CarouselArrow(
                            icon: Icons.chevron_left_rounded,
                            enabled: _currentPage > 0,
                            onTap: () => _goToPage(-1),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 12,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: _CarouselArrow(
                            icon: Icons.chevron_right_rounded,
                            enabled: _currentPage < media.length - 1,
                            onTap: () => _goToPage(1),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 12,
                        right: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.68),
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.collections_rounded, color: Colors.white, size: 14),
                              const SizedBox(width: 6),
                              Text(
                                '${_currentPage + 1} / ${media.length}',
                                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 14,
                        left: 0,
                        right: 0,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(media.length, (index) {
                            final selected = index == _currentPage;
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              width: selected ? 20 : 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: selected ? Colors.white : Colors.white.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(8),
                              ),
                            );
                          }),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
          ],
          if (formattedDate.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.schedule_rounded, size: 15, color: colors.onSurfaceVariant),
                    const SizedBox(width: 7),
                    Text(
                      formattedDate,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (post.content.trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              post.content,
              style: theme.textTheme.bodyLarge?.copyWith(height: 1.55, fontSize: 15.5),
            ),
          ],
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.45)),
            ),
            child: Row(
              children: [
                Expanded(child: _Metric(icon: Icons.favorite_rounded, value: post.likeCount, color: colors.error)),
                _metricDivider(colors),
                Expanded(child: _Metric(icon: Icons.chat_bubble_rounded, value: post.commentCount, color: colors.primary)),
                _metricDivider(colors),
                Expanded(child: _Metric(icon: Icons.visibility_rounded, value: post.viewCount, color: colors.tertiary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricDivider(ColorScheme colors) => Container(
        width: 1,
        height: 28,
        color: colors.outlineVariant.withValues(alpha: 0.6),
      );

}

String _formatPublicationDate(String rawDate) {
  final parsed = DateTime.tryParse(rawDate.trim());
  if (parsed == null) return rawDate;
  final localDate = parsed.toLocal();
  return DateFormat('dd/MM/yyyy HH:mm').format(localDate);
}

class _PostMediaPage extends StatefulWidget {
  const _PostMediaPage({super.key, required this.media});
  final dynamic media;

  @override
  State<_PostMediaPage> createState() => _PostMediaPageState();
}

class _PostMediaPageState extends State<_PostMediaPage> {
  VideoPlayerController? _videoController;
  bool _videoFailed = false;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  @override
  void didUpdateWidget(covariant _PostMediaPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.media.url != widget.media.url || oldWidget.media.type != widget.media.type) {
      _disposeVideo();
      _initializeVideo();
    }
  }

  void _initializeVideo() {
    if (!widget.media.isVideo || widget.media.url.toString().trim().isEmpty) return;
    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.media.url));
    _videoController = controller;
    controller.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
    }).catchError((_) {
      if (mounted) setState(() => _videoFailed = true);
    });
  }

  void _disposeVideo() {
    final controller = _videoController;
    _videoController = null;
    if (controller != null) controller.dispose();
  }

  @override
  void dispose() {
    _disposeVideo();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final url = widget.media.url.toString().trim();
    if (widget.media.isVideo) {
      final controller = _videoController;
      if (_videoFailed) {
        return Center(child: Icon(Icons.videocam_off_outlined, size: 48, color: colors.onSurfaceVariant));
      }
      if (controller == null || !controller.value.isInitialized) {
        return const Center(child: CircularProgressIndicator());
      }
      return GestureDetector(
        onTap: () {
          if (controller.value.isPlaying) {
            controller.pause();
          } else {
            controller.play();
          }
          setState(() {});
        },
        child: Stack(alignment: Alignment.center, children: [
          Center(child: AspectRatio(aspectRatio: controller.value.aspectRatio, child: VideoPlayer(controller))),
          if (!controller.value.isPlaying)
            const CircleAvatar(backgroundColor: Colors.black54, radius: 28, child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 36)),
        ]),
      );
    }
    if (url.isEmpty) return Center(child: Icon(Icons.image_not_supported_outlined, size: 48, color: colors.onSurfaceVariant));
    return InteractiveViewer(minScale: 1, maxScale: 4, child: AppCachedImage(imageUrl: url, fit: BoxFit.contain));
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.value, required this.color});
  final IconData icon;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 19, color: color),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            _compactCount(value),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }

  String _compactCount(int value) {
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(value % 1000000 == 0 ? 0 : 1)}M';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(value % 1000 == 0 ? 0 : 1)}k';
    return value.toString();
  }
}

class _CarouselArrow extends StatelessWidget {
  const _CarouselArrow({required this.icon, required this.enabled, required this.onTap});
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: enabled ? 0.58 : 0.24),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: enabled ? onTap : null,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(icon, color: Colors.white.withValues(alpha: enabled ? 1 : 0.55), size: 30),
        ),
      ),
    );
  }
}
