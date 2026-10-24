import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';
import '../../app/service_global/preferences_service.dart';
import '../../shared/models/post_media.dart';
import '../../shared/widgets/app_cached_image.dart';
import 'media_full_screen_page.dart';

class PostMediaSlider extends StatefulWidget {
  /// Parent feed post ID; autoplay requires at least half of that card to be visible.
  final String? autoplayPostId;
  /// Forces inline playback for contexts such as a shared-post story card.
  final bool forceAutoplayVideos;
  final List<PostMedia> media;
  final String? heroTagPrefix;
  final int likesCount;
  final int dislikesCount;
  final int viewsCount;
  final int commentsCount;
  final int sharesCount;

  const PostMediaSlider({
    super.key,
    this.autoplayPostId,
    this.forceAutoplayVideos = false,
    required this.media,
    this.heroTagPrefix,
    this.likesCount = 0,
    this.dislikesCount = 0,
    this.viewsCount = 0,
    this.commentsCount = 0,
    this.sharesCount = 0,
  });

  @override
  State<PostMediaSlider> createState() => _PostMediaSliderState();
}

class _PostMediaSliderState extends State<PostMediaSlider> {
  int _currentIndex = 0;
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  String get _computedPrefix => widget.heroTagPrefix ?? 'media_${identityHashCode(widget)}';

  String _getHeroTag(int index) {
    final url = (index < widget.media.length) ? (widget.media[index].url ?? '') : '';
    return '${_computedPrefix}_${url}_$index';
  }

  void _openFullScreen(BuildContext context, int index) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black.withValues(alpha: 0.95),
        pageBuilder: (context, animation, secondaryAnimation) => MediaFullScreenPage(
          media: widget.media,
          heroTagPrefix: _computedPrefix,
          initialIndex: index,
          likesCount: widget.likesCount,
          dislikesCount: widget.dislikesCount,
          viewsCount: widget.viewsCount,
          commentsCount: widget.commentsCount,
          sharesCount: widget.sharesCount,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 250),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.media.isEmpty) return const SizedBox.shrink();

    final len = widget.media.length;

    // Mixed-media posts use one consistent horizontal viewer so video items
    // render as playable tiles instead of being passed to the image cache.
    if (widget.media.any((item) => item.isVideo)) {
      return SizedBox(
        height: 280,
        child: Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              itemCount: len,
              onPageChanged: (index) => setState(() => _currentIndex = index),
              itemBuilder: (context, index) {
                final item = widget.media[index];
                return GestureDetector(
                  onTap: item.isVideo ? null : () => _openFullScreen(context, index),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: item.isVideo
                        ? _InlineFeedVideo(
                            key: ValueKey('feed_video_${_getHeroTag(index)}'),
                            autoplayPostId: widget.autoplayPostId,
                            forceAutoplay: widget.forceAutoplayVideos,
                            url: item.url ?? '',
                            thumbnailUrl: item.thumbnailUrl,
                            onOpenFullScreen: () => _openFullScreen(context, index),
                          )
                        : AppCachedImage(
                            imageUrl: item.url,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: 280,
                          ),
                  ),
                );
              },
            ),
            Positioned(
              right: 12,
              top: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                child: Text(
                  '${_currentIndex + 1}/$len',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // --- Cas 1 : Une seule image ---
    if (len == 1) {
      return GestureDetector(
        onTap: () => _openFullScreen(context, 0),
        child: Hero(
          tag: _getHeroTag(0),
          child: Container(
            height: 280,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: Colors.black12,
            ),
            clipBehavior: Clip.antiAlias,
            child: AppCachedImage(
              imageUrl: widget.media[0].url ?? '',
              fit: BoxFit.cover,
              progressive: true,
              lowResolutionWidth: 400,
              highResolutionWidth: 1080,
            ),
          ),
        ),
      );
    }

    // --- Cas 2 : Deux images (50% / 50% côte à côte, ratio 1:1) ---
    if (len == 2) {
      return SizedBox(
        height: 220,
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => _openFullScreen(context, 0),
                child: Hero(
                  tag: _getHeroTag(0),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.horizontal(left: Radius.circular(14)),
                    child: AppCachedImage(
                      imageUrl: widget.media[0].url ?? '',
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: 220,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 2),
            Expanded(
              child: GestureDetector(
                onTap: () => _openFullScreen(context, 1),
                child: Hero(
                  tag: _getHeroTag(1),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.horizontal(right: Radius.circular(14)),
                    child: AppCachedImage(
                      imageUrl: widget.media[1].url ?? '',
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: 220,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // --- Cas 3 : Trois images (asymétrique : 50% gauche, 2x 25% empilées droite) ---
    if (len == 3) {
      return SizedBox(
        height: 260,
        child: Row(
          children: [
            Expanded(
              flex: 1,
              child: GestureDetector(
                onTap: () => _openFullScreen(context, 0),
                child: Hero(
                  tag: _getHeroTag(0),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.horizontal(left: Radius.circular(14)),
                    child: AppCachedImage(
                      imageUrl: widget.media[0].url ?? '',
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 2),
            Expanded(
              flex: 1,
              child: Column(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _openFullScreen(context, 1),
                      child: Hero(
                        tag: _getHeroTag(1),
                        child: ClipRRect(
                          borderRadius: const BorderRadius.only(topRight: Radius.circular(14)),
                          child: AppCachedImage(
                            imageUrl: widget.media[1].url ?? '',
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _openFullScreen(context, 2),
                      child: Hero(
                        tag: _getHeroTag(2),
                        child: ClipRRect(
                          borderRadius: const BorderRadius.only(bottomRight: Radius.circular(14)),
                          child: AppCachedImage(
                            imageUrl: widget.media[2].url ?? '',
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                          ),
                        ),
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

    // --- Cas 4 : Plus de trois images (> 3) -> Slider horizontal avec indicateur 1/N ---
    return SizedBox(
      height: 280,
      child: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: len,
            onPageChanged: (idx) => setState(() => _currentIndex = idx),
            itemBuilder: (context, index) {
              return GestureDetector(
                onTap: () => _openFullScreen(context, index),
                child: Hero(
                  tag: _getHeroTag(index),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: AppCachedImage(
                      imageUrl: widget.media[index].url ?? '',
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                    ),
                  ),
                ),
              );
            },
          ),
          Positioned(
            top: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                '${_currentIndex + 1} / $len',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


/// Autoplay gate driven by visibility of the complete feed post card.
class FeedVideoAutoplayGate {
  static final Map<String, bool> _eligiblePosts = {};
  static final Map<String, Set<VoidCallback>> _listeners = {};
  static bool isEligible(String postId) => _eligiblePosts[postId] == true;
  static void updatePostVisibility(String postId, bool eligible) {
    if (_eligiblePosts[postId] == eligible) return;
    _eligiblePosts[postId] = eligible;
    for (final listener in List<VoidCallback>.from(_listeners[postId] ?? <VoidCallback>{})) { listener(); }
  }
  static void register(String postId, VoidCallback listener) {
    (_listeners[postId] ??= <VoidCallback>{}).add(listener);
    listener();
  }
  static void unregister(String postId, VoidCallback listener) {
    _listeners[postId]?.remove(listener);
    if (_listeners[postId]?.isEmpty == true) _listeners.remove(postId);
  }
}

class _InlineFeedVideo extends StatefulWidget {
  final String? autoplayPostId;
  final bool forceAutoplay;
  final String url;
  final String? thumbnailUrl;
  final VoidCallback onOpenFullScreen;

  const _InlineFeedVideo({
    super.key,
    this.autoplayPostId,
    this.forceAutoplay = false,
    required this.url,
    required this.thumbnailUrl,
    required this.onOpenFullScreen,
  });

  @override
  State<_InlineFeedVideo> createState() => _InlineFeedVideoState();
}

class _InlineFeedVideoState extends State<_InlineFeedVideo> {
  VideoPlayerController? _controller;
  bool _initializing = false;
  bool _autoPlay = true;
  bool _visible = false;
  bool _cardEligible = false;
  bool _failed = false;
  bool _isMuted = false;
  Worker? _preferencesWorker;

  @override
  void initState() {
    super.initState();
    final postId = widget.autoplayPostId;
    if (postId != null) {
      _cardEligible = FeedVideoAutoplayGate.isEligible(postId);
      FeedVideoAutoplayGate.register(postId, _onCardVisibilityChanged);
    } else {
      _cardEligible = true;
    }
    _autoPlay = widget.forceAutoplay;
    try {
      if (Get.isRegistered<PreferencesService>()) {
        final service = Get.find<PreferencesService>();
        _autoPlay = widget.forceAutoplay || service.preferences.value.autoPlayVideos;
        _preferencesWorker = ever(service.preferences, (prefs) {
          if (!mounted || widget.forceAutoplay || _autoPlay == prefs.autoPlayVideos) return;
          setState(() => _autoPlay = prefs.autoPlayVideos);
          if (!_autoPlay) {
            _controller?.pause();
          } else if (_visible && _cardEligible) {
            _initializeIfNeeded();
            _controller?.play();
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _initializeIfNeeded() async {
    if (!_autoPlay || !_visible || !_cardEligible || _initializing || _controller != null ||
        widget.url.trim().isEmpty || _failed) return;
    _initializing = true;
    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    try {
      await controller.initialize();
      if (!mounted || !_visible || !_cardEligible || !_autoPlay) {
        await controller.dispose();
        return;
      }
      await controller.setLooping(true);
      // Feed autoplay starts with sound enabled. The in-card control lets
      // the viewer mute/unmute without opening the fullscreen player.
      await controller.setVolume(_isMuted ? 0 : 1);
      _controller = controller;
      setState(() {});
      await controller.play();
    } catch (error) {
      debugPrint('[POST_MEDIA] inline video initialization failed: $error');
      await controller.dispose();
      if (mounted) setState(() => _failed = true);
    } finally {
      _initializing = false;
    }
  }

  void _onCardVisibilityChanged() {
    final postId = widget.autoplayPostId;
    if (postId == null) return;
    final eligible = FeedVideoAutoplayGate.isEligible(postId);
    if (_cardEligible == eligible) return;
    _cardEligible = eligible;
    if (!eligible) {
      _controller?.pause();
    } else if (_visible && _autoPlay) {
      _initializeIfNeeded();
      final controller = _controller;
      if (controller != null && controller.value.isInitialized) controller.play();
    }
    if (mounted) setState(() {});
  }

  void _onVisibilityChanged(VisibilityInfo info) {
    final visible = info.visibleFraction >= 0.50;
    if (_visible == visible) return;
    _visible = visible;
    final controller = _controller;
    if (!visible || !_cardEligible) {
      controller?.pause();
    } else {
      _initializeIfNeeded();
      if (_autoPlay && controller != null && controller.value.isInitialized) controller.play();
    }
  }

  @override
  void dispose() {
    _preferencesWorker?.dispose();
    final postId = widget.autoplayPostId;
    if (postId != null) FeedVideoAutoplayGate.unregister(postId, _onCardVisibilityChanged);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: ValueKey('visibility_${widget.key ?? widget.url}'),
      onVisibilityChanged: _onVisibilityChanged,
      child: GestureDetector(
        onTap: () {
          _controller?.pause();
          widget.onOpenFullScreen();
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
          if (_controller != null && _controller!.value.isInitialized)
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _controller!.value.size.width,
                height: _controller!.value.size.height,
                child: VideoPlayer(_controller!),
              ),
            )
          else if (widget.thumbnailUrl != null && widget.thumbnailUrl!.trim().isNotEmpty)
            AppCachedImage(
              imageUrl: widget.thumbnailUrl!,
              fit: BoxFit.cover,
              width: double.infinity,
              height: 280,
              progressive: true,
              lowResolutionWidth: 400,
              highResolutionWidth: 1080,
            )
          else
            const ColoredBox(color: Colors.black),
          if (_controller == null || !_controller!.value.isInitialized || !_controller!.value.isPlaying)
            Center(
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.48),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 1.5),
                ),
                child: Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 46,
                ),
              ),
            ),
          if (_controller != null && _controller!.value.isInitialized)
            Positioned(
              right: 10,
              bottom: 10,
              child: Material(
                color: Colors.black.withValues(alpha: 0.62),
                shape: const CircleBorder(),
                child: IconButton(
                  tooltip: _isMuted ? 'Activer le son' : 'Couper le son',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(minWidth: 42, minHeight: 42),
                  padding: const EdgeInsets.all(9),
                  onPressed: () async {
                    final controller = _controller;
                    if (controller == null || !controller.value.isInitialized) return;
                    final mute = !_isMuted;
                    try {
                      await controller.setVolume(mute ? 0 : 1);
                      if (mounted) setState(() => _isMuted = mute);
                    } catch (error) {
                      debugPrint('[POST_MEDIA] unable to change inline video volume: $error');
                    }
                  },
                  icon: Icon(
                    _isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
