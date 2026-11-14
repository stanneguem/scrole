import 'dart:async';
import 'dart:ui' as ui;
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
  final VoidCallback? onVideoQualifiedView;
  final ValueChanged<int>? onPageChanged;
  final double qualifiedViewPercent;

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
    this.onVideoQualifiedView,
    this.onPageChanged,
    this.qualifiedViewPercent = 0.5,
  });

  @override
  State<PostMediaSlider> createState() => _PostMediaSliderState();
}

class _PostMediaSliderState extends State<PostMediaSlider> {
  int _currentIndex = 0;
  double _videoOverlayOpacity = 1;
  late final PageController _pageController;
  final Map<int, double> _mediaAspectRatios = {};
  int _ratioLoadGeneration = 0;

  // Load intrinsic dimensions from photos and video thumbnails. The feed
  // uses one shared viewport ratio for a carousel, so swiping never changes
  // the card height.
  void _loadMediaAspectRatios() {
    final generation = ++_ratioLoadGeneration;
    _mediaAspectRatios.clear();

    for (var index = 0; index < widget.media.length; index++) {
      final media = widget.media[index];
      // A video URL is not an image stream. Use its poster only; when no
      // poster exists, the conservative video fallback ratio is used below.
      if (media.isVideo &&
          (media.thumbnailUrl == null || media.thumbnailUrl!.trim().isEmpty)) {
        continue;
      }
      final source = media.isVideo ? media.thumbnailUrl! : media.url;
      if (source.trim().isEmpty) continue;

      final provider = NetworkImage(source);
      final stream = provider.resolve(ImageConfiguration.empty);
      late final ImageStreamListener listener;
      listener = ImageStreamListener(
        (ImageInfo info, bool synchronousCall) {
          stream.removeListener(listener);
          final ratio = info.image.width / info.image.height;
          info.dispose();
          if (!mounted || generation != _ratioLoadGeneration ||
              !ratio.isFinite || ratio <= 0) return;
          setState(() => _mediaAspectRatios[index] = ratio);
        },
        onError: (Object error, StackTrace? stackTrace) {
          stream.removeListener(listener);
        },
      );
      stream.addListener(listener);
    }
  }

  double _getSharedAspectRatio() {
    if (widget.media.isEmpty) return 1;
    final ratios = List<double>.generate(
      widget.media.length,
      (index) => _mediaAspectRatios[index] ??
          (widget.media[index].isVideo ? 0.8 : 1.0),
    )..sort();

    // Median is robust against one extremely tall or wide item. For an even
    // number of items, the arithmetic mean balances portrait and landscape.
    final middle = ratios.length ~/ 2;
    final ratio = ratios.length.isOdd
        ? ratios[middle]
        : (ratios[middle - 1] + ratios[middle]) / 2;
    return ratio.clamp(0.45, 1.91).toDouble();
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _loadMediaAspectRatios();
  }

  @override
  void didUpdateWidget(covariant PostMediaSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.media != widget.media) {
      _currentIndex = 0;
      if (_pageController.hasClients) {
        _pageController.jumpToPage(0);
      }
      _loadMediaAspectRatios();
    }
  }

  @override
  void dispose() {
    _ratioLoadGeneration++;
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
    return LayoutBuilder(
      builder: (context, constraints) =>
          _buildForWidth(context, constraints.maxWidth),
    );
  }

  Widget _buildForWidth(BuildContext context, double availableWidth) {
    if (widget.media.isEmpty || availableWidth <= 0) {
      return const SizedBox.shrink();
    }

    final len = widget.media.length;
    final sharedAspectRatio = _getSharedAspectRatio();
    // Keep a consistent viewport for every item in a carousel. The media
    // itself fills this viewport; only excess edges are cropped.
    final mediaHeight = (availableWidth / sharedAspectRatio)
        .clamp(availableWidth / 1.91, availableWidth * 1.25)
        .toDouble();

    Widget buildMedia(int index, {required BorderRadius radius}) {
      final item = widget.media[index];
      return ClipRRect(
        borderRadius: radius,
        child: SizedBox.expand(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final tileWidth = constraints.maxWidth;
              final tileHeight = constraints.maxHeight;

              // Give every tile its own explicit, finite dimensions. This is
              // important for the second/third cells in a Row/Column: relying
              // on the image's intrinsic dimensions can leave letterboxed
              // gaps even when the first tile happens to fill correctly.
              final mediaView = item.isVideo
                  ? _InlineFeedVideo(
                      key: ValueKey('feed_video_${_getHeroTag(index)}'),
                      autoplayPostId: widget.autoplayPostId,
                      forceAutoplay: widget.forceAutoplayVideos,
                      onQualifiedView: widget.onVideoQualifiedView,
                      qualifiedViewPercent: widget.qualifiedViewPercent,
                      onPlaybackOverlayOpacityChanged: (opacity) {
                        if (!mounted || (_videoOverlayOpacity - opacity).abs() < 0.03) return;
                        setState(() => _videoOverlayOpacity = opacity);
                      },
                      url: item.url,
                      thumbnailUrl: item.thumbnailUrl,
                      onOpenFullScreen: () => _openFullScreen(context, index),
                    )
                  : GestureDetector(
                      onTap: () => _openFullScreen(context, index),
                      child: Hero(
                        tag: _getHeroTag(index),
                        child: AppCachedImage(
                          imageUrl: item.url,
                          width: tileWidth,
                          height: tileHeight,
                          fit: BoxFit.cover,
                        ),
                      ),
                    );

              return SizedBox(
                width: tileWidth,
                height: tileHeight,
                child: ClipRect(
                  child: mediaView,
                ),
              );
            },
          ),
        ),
      );
    }

    if (len == 1) {
      return SizedBox(
        width: double.infinity,
        height: mediaHeight,
        child: buildMedia(0, radius: BorderRadius.zero),
      );
    }

    // Two items share the full media area side by side.
    if (len == 2) {
      return SizedBox(
        width: double.infinity,
        height: mediaHeight,
        child: Row(
          children: [
            Expanded(
              child: buildMedia(
                0,
                radius: BorderRadius.zero,
              ),
            ),
            const SizedBox(width: 2),
            Expanded(
              child: buildMedia(
                1,
                radius: BorderRadius.zero,
              ),
            ),
          ],
        ),
      );
    }

    // Three items: one large tile and two stacked tiles.
    if (len == 3) {
      return SizedBox(
        width: double.infinity,
        height: mediaHeight,
        child: Row(
          children: [
            Expanded(
              child: buildMedia(
                0,
                radius: BorderRadius.zero,
              ),
            ),
            const SizedBox(width: 2),
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    child: buildMedia(
                      1,
                      radius: BorderRadius.zero,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Expanded(
                    child: buildMedia(
                      2,
                      radius: BorderRadius.zero,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Four or more items use a swipeable full-bleed carousel.
    return SizedBox(
      width: double.infinity,
      height: mediaHeight,
      child: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: len,
            onPageChanged: (index) {
              setState(() => _currentIndex = index);
              widget.onPageChanged?.call(index);
            },
            itemBuilder: (context, index) => buildMedia(
              index,
              radius: BorderRadius.zero,
            ),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _videoOverlayOpacity,
                duration: const Duration(milliseconds: 180),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.30),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.24),
                          width: 0.8,
                        ),
                      ),
                      child: Text(
                        '${_currentIndex + 1} / $len',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ),
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
  final ValueChanged<double>? onPlaybackOverlayOpacityChanged;
  final VoidCallback? onQualifiedView;
  final double qualifiedViewPercent;
  final String url;
  final String? thumbnailUrl;
  final VoidCallback onOpenFullScreen;

  const _InlineFeedVideo({
    super.key,
    this.autoplayPostId,
    this.forceAutoplay = false,
    this.onPlaybackOverlayOpacityChanged,
    this.onQualifiedView,
    this.qualifiedViewPercent = 0.5,
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
  bool _playbackOverlaysDismissed = false;
  double _playbackOverlayOpacity = 1;
  Worker? _preferencesWorker;
  Duration _lastPlaybackPosition = Duration.zero;
  Duration _accumulatedPlayback = Duration.zero;
  bool _qualifiedViewSent = false;

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
      controller.addListener(_onVideoValueChanged);
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

  void _onVideoValueChanged() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final value = controller.value;
    final position = value.position;
    if (value.isPlaying && !value.isBuffering && _visible && _cardEligible && !_qualifiedViewSent) {
      final delta = position - _lastPlaybackPosition;
      // Listener updates are frequent; discard discontinuities caused by seeks,
      // buffering stalls or lifecycle jumps rather than counting them as watch time.
      if (delta > Duration.zero && delta <= const Duration(milliseconds: 900)) {
        _accumulatedPlayback += delta;
      }
      final duration = value.duration;
      if (duration > Duration.zero &&
          _accumulatedPlayback >= Duration(microseconds: (duration.inMicroseconds * widget.qualifiedViewPercent).round())) {
        _qualifiedViewSent = true;
        widget.onQualifiedView?.call();
      }
    }
    _lastPlaybackPosition = position;
    _updatePlaybackOverlayOpacity();
  }

  void _updatePlaybackOverlayOpacity() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized ||
        !controller.value.isPlaying || _playbackOverlaysDismissed) {
      return;
    }

    // Fade the media counter and speaker control away during the first
    // 2.5 seconds of playback, then keep them hidden for the rest of the clip.
    final elapsedMs = controller.value.position.inMilliseconds;
    const fadeDurationMs = 2500;
    final opacity = (1 - (elapsedMs / fadeDurationMs)).clamp(0.0, 1.0);
    if ((_playbackOverlayOpacity - opacity).abs() >= 0.03 || elapsedMs >= fadeDurationMs) {
      _playbackOverlayOpacity = opacity;
      widget.onPlaybackOverlayOpacityChanged?.call(opacity);
      if (mounted) setState(() {});
    }
    if (elapsedMs >= fadeDurationMs) {
      _playbackOverlaysDismissed = true;
      widget.onPlaybackOverlayOpacityChanged?.call(0);
    }
  }

  void _onCardVisibilityChanged() {
    if (!mounted) return;
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
    // VisibilityDetector may deliver a queued callback after this widget starts
    // disposing. Never touch a controller once the State is no longer mounted.
    if (!mounted) return;
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
    // Clear the field before disposing so any queued visibility callback sees
    // no controller to pause or play.
    final controller = _controller;
    _controller = null;
    controller?.removeListener(_onVideoValueChanged);
    if (controller != null) unawaited(controller.dispose());
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
              height: double.infinity,
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
              child: IgnorePointer(
                ignoring: _playbackOverlaysDismissed,
                child: AnimatedOpacity(
                  opacity: _playbackOverlayOpacity,
                  duration: const Duration(milliseconds: 180),
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
              ),
            ),
          ],
        ),
      ),
    );
  }
}
