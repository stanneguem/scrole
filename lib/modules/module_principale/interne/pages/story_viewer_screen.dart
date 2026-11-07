import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:lottie/lottie.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../../../shared/widgets/app_cached_image.dart';
import '../../../../shared/widgets/linkified_text.dart';
import '../../../../shared/widgets/user_certified_badge.dart';
import '../../../../shared/widgets/user_identity_row.dart';
import '../../../../shared/utils/number_formatter.dart';
import '../controllers/stories_controller.dart';
import '../widgets/feed_post_card.dart';
import 'package:scrole/modules/module_principale/externe/repositories/stories_repository.dart';
import 'package:scrole/modules/module_principale/externe/repositories/home_feed_repository.dart';
import 'package:scrole/modules/module_principale/centre/models/community_post.dart';

class StoryViewerScreen extends StatefulWidget {
  final List<EventStoryGroup> groups;
  final int initialGroupIndex;

  const StoryViewerScreen({
    super.key,
    required this.groups,
    this.initialGroupIndex = 0,
  });

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen>
    with TickerProviderStateMixin {
  late int _groupIndex;
  late int _storyIndex;
  late AnimationController _animController;
  late AnimationController _heartsAnimationController;
  bool _isPaused = false;
  bool _isSendingQuickReply = false;
  String? _imageLoadedStoryId;
  double _videoProgress = 0.0;
  final TextEditingController _replyController = TextEditingController();
  final FocusNode _commentFocusNode = FocusNode();
  final StoriesController _storiesController = Get.find<StoriesController>();
  final StoriesRepository _storiesRepo = StoriesRepository();

  final Set<String> _viewedStoryIds = {};
  double _dragOffsetY = 0.0;
  double _bgOpacity = 1.0;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _groupIndex = widget.initialGroupIndex;
    _storyIndex = 0;
    _animController =
        AnimationController(vsync: this, duration: const Duration(seconds: 5))
          ..addListener(() => setState(() {}))
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed) {
              _nextStory();
            }
          });

    _heartsAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _commentFocusNode.addListener(() {
      if (_commentFocusNode.hasFocus) {
        _animController.stop();
        setState(() => _isPaused = true);
      } else {
        setState(() => _isPaused = false);
        if (_replyController.text.trim().isEmpty) {
          if (_currentStoryHasVideo) {
            _animController.stop();
          } else {
            _resumeStoryTimer();
          }
        }
      }
    });

    // Wait until the first frame so inherited widgets (MediaQuery/Theme)
    // are available before starting story image precaching.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _startStory();
      // Render the already-fetched story/media immediately, then reconcile
      // visibility and live counters with Supabase without blocking playback.
      unawaited(_refreshCurrentGroupFromServer());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _precacheNextStory();
  }

  bool _isPrecacheableStoryImage(String? value) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) return false;
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasAuthority ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      // Story media may be stored as an R2 object key (for example
      // stories/<user>/<file>.jpg). NetworkImage cannot load that key directly.
      return false;
    }
    final path = uri.path.toLowerCase();
    return !path.endsWith('.mp4') &&
        !path.endsWith('.mov') &&
        !path.endsWith('.m3u8') &&
        !path.endsWith('.webm');
  }

  void _precacheNextStory() {
    if (_storyIndex < _currentGroup.stories.length - 1) {
      final nextStory = _currentGroup.stories[_storyIndex + 1];
      final url = nextStory.imageUrl;
      if (nextStory.kind != 'video' && _isPrecacheableStoryImage(url)) {
        precacheImage(NetworkImage(url!.trim()), context)
            .catchError((Object _) {});
      }
    } else if (_groupIndex < widget.groups.length - 1) {
      final nextGroup = widget.groups[_groupIndex + 1];
      if (nextGroup.stories.isNotEmpty) {
        final nextStory = nextGroup.stories.first;
        final url = nextStory.imageUrl;
        if (nextStory.kind != 'video' && _isPrecacheableStoryImage(url)) {
          precacheImage(NetworkImage(url!.trim()), context)
              .catchError((Object _) {});
        }
      }
    }
  }

  bool get _currentStoryHasVideo {
    if (_currentStory.kind == 'video') {
      return (_currentStory.imageUrl ?? '').trim().isNotEmpty;
    }
    if (_currentStory.kind != 'post') return false;
    final post = _currentStory.sharedPost;
    return post != null && post.media.any((media) => media.isVideo && (media.url ?? '').trim().isNotEmpty);
  }

  void _startStory() {
    if (_isPaused || _commentFocusNode.hasFocus) return;
    if (_currentStory.kind == 'image') {
      // Wait for the actual image frame, including private R2 media.
      _animController.stop();
      if (_imageLoadedStoryId == _currentStory.id) {
        _beginCurrentImageStory();
      }
      _precacheNextStory();
      return;
    }
    if (_currentStoryHasVideo) {
      _animController.stop();
      _animController.value = 0;
      _videoProgress = 0.0;
    } else {
      _animController.forward(from: 0.0);
    }
    _markCurrentViewed();
    _precacheNextStory();
  }

  void _beginCurrentImageStory() {
    if (!mounted || _isPaused || _commentFocusNode.hasFocus ||
        _currentStory.kind != 'image' ||
        _imageLoadedStoryId != _currentStory.id) return;
    _animController.forward(from: 0.0);
    _markCurrentViewed();
  }

  void _onCurrentStoryImageLoaded(String storyId) {
    if (!mounted || _currentStory.id != storyId ||
        _imageLoadedStoryId == storyId) return;
    setState(() => _imageLoadedStoryId = storyId);
    _beginCurrentImageStory();
  }

  Future<void> _refreshCurrentGroupFromServer() async {
    final groupAtRequest = _currentGroup;
    final authorId = groupAtRequest.author.userId;
    if (authorId.isEmpty) return;

    try {
      final data = await _storiesRepo.getUserStories(authorId);
      if (!mounted || _groupIndex >= widget.groups.length ||
          _currentGroup.author.userId != authorId) return;

      // A successful empty response means the author deleted the story or
      // the viewer no longer has permission to see it. A network error throws
      // from the repository and deliberately leaves the offline copy intact.
      final refreshedGroup = data == null
          ? null
          : EventStoryGroup.fromMap(Map<String, dynamic>.from(data));
      final refreshed = refreshedGroup?.stories ?? <StoryItem>[];
      final refreshedById = {for (final story in refreshed) story.id: story};
      final previousStories = List<StoryItem>.from(groupAtRequest.stories);

      for (final previous in previousStories) {
        final latest = refreshedById[previous.id];
        final wasRemoved = latest == null;
        final mediaChanged = latest != null &&
            (latest.imageUrl != previous.imageUrl ||
             latest.thumbnailUrl != previous.thumbnailUrl);
        if (!wasRemoved && !mediaChanged) continue;

        final mediaKey = previous.imageUrl;
        final thumbnailKey = previous.thumbnailUrl;
        if (mediaKey != null && mediaKey.startsWith('stories/')) {
          await AppCachedImage.clearPrivateMediaCache(mediaKey);
        }
        if (thumbnailKey != null && thumbnailKey.startsWith('stories/')) {
          await AppCachedImage.clearPrivateMediaCache(thumbnailKey);
        }
        // Video playback cache is keyed by story id. Remove it if the server
        // confirms deletion or if the underlying video object has changed.
        try {
          final directory = await getApplicationSupportDirectory();
          final cacheDirectory = Directory(p.join(directory.path, 'stories_cache'));
          final safeId = previous.id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
          for (final suffix in ['.mp4', '.mov', '.expiry']) {
            final cached = File(p.join(cacheDirectory.path, '$safeId$suffix'));
            if (await cached.exists()) await cached.delete();
          }
        } catch (cacheError) {
          debugPrint('[STORY_CACHE] Story media cleanup failed: $cacheError');
        }
        if (wasRemoved) {
          debugPrint('[STORY] Removed locally cached story no longer visible: ${previous.id}');
        } else {
          debugPrint('[STORY] Replaced stale cached media for story: ${previous.id}');
        }
      }

      final currentId = _currentStory.id;
      groupAtRequest.stories
        ..clear()
        ..addAll(refreshed);
      if (refreshedGroup != null) {
        groupAtRequest.latestAt = refreshedGroup.latestAt;
        groupAtRequest.storiesCount = refreshedGroup.storiesCount;
      } else {
        groupAtRequest.storiesCount = 0;
      }
      groupAtRequest.hasUnseen = refreshed.any((story) => !story.viewed);

      if (refreshed.isEmpty) {
        if (!mounted) return;
        // If one author deleted all their stories, continue with the next
        // available author instead of closing the entire story viewer.
        if (_groupIndex < widget.groups.length - 1) {
          setState(() {
            _groupIndex++;
            _storyIndex = 0;
            _imageLoadedStoryId = null;
            _videoProgress = 0;
          });
          _startStory();
          unawaited(_refreshCurrentGroupFromServer());
        } else if (_groupIndex > 0) {
          setState(() {
            _groupIndex--;
            _storyIndex = widget.groups[_groupIndex].stories.length - 1;
            _imageLoadedStoryId = null;
            _videoProgress = 0;
          });
          _startStory();
          unawaited(_refreshCurrentGroupFromServer());
        } else {
          Navigator.of(context).pop();
        }
        return;
      }

      final updatedIndex = refreshed.indexWhere((story) => story.id == currentId);
      if (updatedIndex < 0) {
        _storyIndex = _storyIndex.clamp(0, refreshed.length - 1).toInt();
        _imageLoadedStoryId = null;
        _videoProgress = 0;
        if (mounted) {
          setState(() {});
          _startStory();
        }
      } else {
        _storyIndex = updatedIndex;
        if (mounted) setState(() {});
      }
      _storiesController.refreshGroupViewedState(groupAtRequest);
      debugPrint('[STORY] Background sync completed for author=$authorId stories=${refreshed.length}');
    } catch (e, st) {
      // Offline or transient backend errors must not blank a valid cached story.
      debugPrint('[STORY] Background sync failed; keeping cached story: $e\\n$st');
    }
  }

  void _markCurrentViewed() {
    final story = _currentStory;
    // Opening your own story is not a view: only other authenticated viewers
    // should create a story_views row or increase the viewers counter.
    if (_isOwnStory || story.id.isEmpty) return;
    if (!story.viewed && !_viewedStoryIds.contains(story.id)) {
      _viewedStoryIds.add(story.id);
      story.viewed = true;
      story.viewersCount++;
      _storiesController.refreshGroupViewedState(_currentGroup);
      setState(() {});
      _storiesController.markStoriesViewed([story.id]);
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    _heartsAnimationController.dispose();
    _replyController.dispose();
    _commentFocusNode.dispose();
    super.dispose();
  }

  EventStoryGroup get _currentGroup => widget.groups[_groupIndex];
  StoryItem get _currentStory => _currentGroup.stories[_storyIndex];
  bool get _isOwnStory => _currentGroup.relation == 'own';

  void _resumeStoryTimer() {
    if (_currentStoryHasVideo ||
        (_currentStory.kind == 'image' &&
            _imageLoadedStoryId != _currentStory.id)) {
      _animController.stop();
    } else {
      _animController.forward();
    }
  }

  String _formatStoryAge(DateTime createdAt) {
    final elapsed = DateTime.now().difference(createdAt);
    if (elapsed.isNegative || elapsed.inSeconds < 60) return 'relative_just_now'.tr;
    if (elapsed.inMinutes < 60) return 'relative_minutes_ago'.trParams({'count': '${elapsed.inMinutes}'});
    if (elapsed.inHours < 24) return 'relative_hours_ago'.trParams({'count': '${elapsed.inHours}'});
    if (elapsed.inDays == 1) return 'relative_one_day_ago'.tr;
    if (elapsed.inDays < 7) return 'relative_days_ago'.trParams({'count': '${elapsed.inDays}'});
    return '${createdAt.day.toString().padLeft(2, '0')}/${createdAt.month.toString().padLeft(2, '0')}/${createdAt.year}';
  }

  void _nextStory() {
    _videoProgress = 0.0;
    _imageLoadedStoryId = null;
    if (_storyIndex < _currentGroup.stories.length - 1) {
      setState(() => _storyIndex++);
      _startStory();
    } else if (_groupIndex < widget.groups.length - 1) {
      setState(() {
        _groupIndex++;
        _storyIndex = 0;
      });
      _startStory();
      unawaited(_refreshCurrentGroupFromServer());
    } else {
      Navigator.of(context).pop();
    }
  }

  void _prevStory() {
    _videoProgress = 0.0;
    _imageLoadedStoryId = null;
    if (_storyIndex > 0) {
      setState(() => _storyIndex--);
      _startStory();
    } else if (_groupIndex > 0) {
      setState(() {
        _groupIndex--;
        _storyIndex = widget.groups[_groupIndex].stories.length - 1;
      });
      _startStory();
      unawaited(_refreshCurrentGroupFromServer());
    } else {
      _animController.forward(from: 0.0);
    }
  }

  Future<void> _toggleStoryLike() async {
    final newLiked = !_currentStory.isLiked;
    setState(() {
      _currentStory.isLiked = newLiked;
      if (newLiked) {
        _heartsAnimationController.forward(from: 0.0);
      } else {
        _heartsAnimationController.reverse(from: 1.0);
      }
    });

    try {
      await _storiesRepo.setStoryLike(_currentStory.id, newLiked);
    } catch (e) {
      debugPrint('[STORY] [Controller] Error setting story like: $e');
      setState(() {
        _currentStory.isLiked = !newLiked;
      });
    }
  }



  void _onTapDown(TapDownDetails details) {
    if (_commentFocusNode.hasFocus || _isPaused) return;
    _animController.stop();
  }

  void _onTapUp(TapUpDetails details) {
    if (_commentFocusNode.hasFocus || _isPaused) return;
    final screenWidth = MediaQuery.of(context).size.width;
    if (details.globalPosition.dx < screenWidth / 3) {
      _prevStory();
    } else if (details.globalPosition.dx > screenWidth * 2 / 3) {
      // Left/right zones navigate between all story types.
      _nextStory();
    } else if (!_currentStoryHasVideo) {
      _resumeStoryTimer();
    }
  }

  void _onCancel() {
    if (_commentFocusNode.hasFocus || _isPaused) return;
    _resumeStoryTimer();
  }

  Future<void> _showViewersSheet() async {
    _animController.stop();
    setState(() => _isPaused = true);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _StoryViewersSheet(storyId: _currentStory.id),
    );

    if (mounted) {
      setState(() => _isPaused = false);
      _resumeStoryTimer();
    }
  }

  Future<void> _showLikersSheet() async {
    _animController.stop();
    setState(() => _isPaused = true);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _StoryLikersSheet(storyId: _currentStory.id),
    );

    if (mounted) {
      setState(() => _isPaused = false);
      _resumeStoryTimer();
    }
  }

  Future<void> _showStoryMenu() async {
    _animController.stop();
    setState(() => _isPaused = true);

    final colorScheme = Theme.of(context).colorScheme;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          MediaQuery.of(context).padding.bottom + 20,
        ),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            if (_isOwnStory)
              Material(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  tileColor: colorScheme.errorContainer.withValues(alpha: 0.3),
                  leading: Icon(
                    Icons.delete_outline_rounded,
                    color: colorScheme.error,
                  ),
                  title: Text(
                    'Supprimer la story',
                    style: TextStyle(
                      color: colorScheme.error,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onTap: () async {
                    Navigator.of(context).pop();
                    await _storiesController.deleteStory(_currentStory.id);
                    if (mounted) Navigator.of(context).pop();
                  },
                ),
              ),
            const SizedBox(height: 8),
            Material(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                leading: Icon(
                  Icons.cancel_outlined,
                  color: colorScheme.onSurfaceVariant,
                ),
                title: Text(
                  'Annuler',
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );

    if (mounted) {
      setState(() => _isPaused = false);
      _resumeStoryTimer();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.groups.isEmpty || _currentGroup.stories.isEmpty) {
      return const Scaffold(backgroundColor: Colors.black);
    }

    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: _bgOpacity),
      body: GestureDetector(
        onVerticalDragStart: (_) => setState(() => _isDragging = true),
        onVerticalDragUpdate: (details) {
          setState(() {
            _dragOffsetY += details.delta.dy;
            if (_dragOffsetY < 0) _dragOffsetY = 0;
            final progress = (_dragOffsetY / 300).clamp(0.0, 1.0);
            _bgOpacity = (1.0 - progress * 0.7).clamp(0.3, 1.0);
          });
        },
        onVerticalDragEnd: (details) {
          if (_dragOffsetY > 120 || details.velocity.pixelsPerSecond.dy > 500) {
            Navigator.of(context).pop();
          } else {
            setState(() {
              _dragOffsetY = 0.0;
              _bgOpacity = 1.0;
              _isDragging = false;
            });
          }
        },
        child: Transform.translate(
          offset: Offset(0, _dragOffsetY),
          child: GestureDetector(
            child: Stack(
              fit: StackFit.expand,
              children: [
                // --- Media / Background ---
                if (_currentStory.kind == 'video' &&
                    _currentStory.imageUrl != null &&
                    _currentStory.imageUrl!.isNotEmpty)
                  _StoryVideoPlayer(
                    key: ValueKey(_currentStory.id),
                    objectKey: _currentStory.imageUrl!,
                    storyId: _currentStory.id,
                    expiresAt: _currentStory.expiresAt,
                    thumbnailObjectKey: _currentStory.thumbnailUrl,
                    fallbackImageUrl: _currentGroup.author.photoUrl,
                    isPaused: _isPaused || _commentFocusNode.hasFocus,
                    onProgress: (progress) {
                      if (mounted && (_videoProgress - progress).abs() >= 0.01) {
                        setState(() => _videoProgress = progress);
                      }
                    },
                    onCompleted: _nextStory,
                  )
                else if (_currentStory.kind == 'image' &&
                    _currentStory.imageUrl != null)
                  Center(
                    child: AppCachedImage(
                      key: ValueKey('story-image-${_currentStory.id}'),
                      imageUrl: _currentStory.imageUrl!,
                      fit: BoxFit.cover,
                      cacheUntil: _currentStory.expiresAt,
                      onImageLoaded: () => _onCurrentStoryImageLoaded(_currentStory.id),
                      placeholder: const Center(
                        child: SizedBox(
                          width: 34,
                          height: 34,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  )
                else if (_currentStory.kind == 'post')
                  Container(
                    color: _parseBackground(_currentStory.background),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 64,
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_currentStory.content != null &&
                              _currentStory.content!.isNotEmpty) ...[
                            LinkifiedText(
                              text: _currentStory.content!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                              linkColor: Colors.lightBlueAccent,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                          ],
                          if (_currentStory.sharedPost == null)
                            Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Text(
                                'Cette publication n\'est plus disponible',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontStyle: FontStyle.italic,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            )
                          else ...[
                            if (!_currentStory.sharedPostCanOpenOriginal)
                              const Padding(
                                padding: EdgeInsets.only(bottom: 8),
                                child: Text(
                                  'Aperçu partagé · source réservée aux membres de la communauté',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            SizedBox(
                              width: (MediaQuery.of(context).size.width - 32)
                                  .clamp(0.0, 400.0)
                                  .toDouble(),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surface,
                                  borderRadius: BorderRadius.circular(18),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Colors.black26,
                                      blurRadius: 10,
                                      offset: Offset(0, 4),
                                    ),
                                  ],
                                ),
                                clipBehavior: Clip.antiAlias,
                                // Reuse the exact feed card for every shared post,
                                // including videos. The previous custom video card
                                // omitted the feed interaction/counter bar and clipped
                                // tall cards before their actions could be seen.
                                child: FeedPostCard(
                                  post: _currentStory.sharedPost!,
                                  autoplayVideos: true,
                                  onReactionTap: (_) {},
                                  onCommentTap: () {},
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  )
                else
                  Container(
                    color: _parseBackground(_currentStory.background),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      _currentStory.content ?? '',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                // Explicit left/center/right hit zones sit above media and
                // repost cards, but below the header and footer controls.
                // This avoids VideoPlayer or a post card winning the gesture arena.
                Positioned(
                  top: 64,
                  left: 0,
                  right: 0,
                  bottom: 132,
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            if (!_commentFocusNode.hasFocus && !_isPaused) {
                              _prevStory();
                            }
                          },
                          child: const SizedBox.expand(),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          // Hold anywhere in the center zone to pause the story;
                          // releasing resumes the image timer or the video.
                          onLongPressStart: (_) {
                            if (_commentFocusNode.hasFocus || _isPaused) return;
                            _animController.stop();
                            setState(() => _isPaused = true);
                          },
                          onLongPressEnd: (_) {
                            if (_commentFocusNode.hasFocus || !_isPaused) return;
                            setState(() => _isPaused = false);
                            _resumeStoryTimer();
                          },
                          onTap: () {
                            if (!_commentFocusNode.hasFocus && !_isPaused &&
                                !_currentStoryHasVideo) {
                              _resumeStoryTimer();
                            }
                          },
                          onDoubleTap: _isOwnStory ? null : _toggleStoryLike,
                          child: const SizedBox.expand(),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            if (!_commentFocusNode.hasFocus && !_isPaused) {
                              _nextStory();
                            }
                          },
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ],
                  ),
                ),

                // --- Top Progress Bars & Header ---
                SafeArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Progress bars
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        child: Row(
                          children: List.generate(
                            _currentGroup.stories.length,
                            (idx) {
                              return Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 2,
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(2),
                                    child: LinearProgressIndicator(
                                      value: idx < _storyIndex
                                          ? 1.0
                                          : idx == _storyIndex
                                          ? (_currentStoryHasVideo
                                              ? _videoProgress
                                              : _animController.value)
                                          : 0.0,
                                      backgroundColor: Colors.white24,
                                      valueColor:
                                          const AlwaysStoppedAnimation<Color>(
                                            Colors.white,
                                          ),
                                      minHeight: 2.5,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),

                      // Header Info
                      GestureDetector(
                        onTap: () {},
                        child: AnimatedOpacity(
                          opacity: _isDragging ? 0.0 : 1.0,
                          duration: const Duration(milliseconds: 200),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      CircleAvatar(
                                        radius: 18,
                                        backgroundColor: Colors.white24,
                                        backgroundImage: _currentGroup.author.photoUrl != null &&
                                                _currentGroup.author.photoUrl!.isNotEmpty
                                            ? NetworkImage(_currentGroup.author.photoUrl!)
                                            : null,
                                        child: _currentGroup.author.photoUrl == null ||
                                                _currentGroup.author.photoUrl!.isEmpty
                                            ? Text(
                                                _currentGroup.author.displayName.isNotEmpty
                                                    ? _currentGroup.author.displayName[0].toUpperCase()
                                                    : 'U',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              )
                                            : null,
                                      ),
                                      const SizedBox(width: 8),
                                      Flexible(
                                        fit: FlexFit.loose,
                                        child: Text(
                                          _currentGroup.author.displayName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                      if (_currentGroup.author.username.isNotEmpty) ...[
                                        const SizedBox(width: 5),
                                        Flexible(
                                          fit: FlexFit.loose,
                                          child: Text(
                                            '@${_currentGroup.author.username.replaceFirst(RegExp(r'^@'), '')}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ],
                                      if (_currentGroup.author.isCertified) ...[
                                        const SizedBox(width: 4),
                                        UserCertifiedBadge(size: 14, userId: _currentGroup.author.userId),
                                      ],
                                      const SizedBox(width: 6),
                                      Flexible(
                                        fit: FlexFit.loose,
                                        child: Text(
                                          _formatStoryAge(_currentStory.createdAt),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.more_vert_rounded,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                  onPressed: _showStoryMenu,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // --- Lottie Hearts Animation Overlay ---
                Positioned(
                  bottom: 80,
                  right: 60,
                  child: IgnorePointer(
                    child: Lottie.asset(
                      'assets/lotties/head.json',
                      controller: _heartsAnimationController,
                      width: 130,
                      height: 130,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),

                // --- TikTok-style story actions on the right ---
                // Vertical action rail pinned to the extreme right, like TikTok.
                // For other people's stories: Like first, comments immediately below.
                // For own stories: viewers first, then comments.
                Positioned(
                  right: 8,
                  top: 0,
                  bottom: _isOwnStory ? 64 : 56,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Transform.translate(
                      offset: const Offset(0, 34),
                      child: AnimatedOpacity(
                        opacity: _isDragging ? 0.0 : 1.0,
                        duration: const Duration(milliseconds: 200),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_isOwnStory)
                              _buildStorySideAction(
                                icon: Icons.remove_red_eye_outlined,
                                count: _currentStory.viewersCount,
                                onTap: _showViewersSheet,
                              )
                            else
                              InkWell(
                                onTap: _toggleStoryLike,
                                borderRadius: BorderRadius.circular(24),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        _currentStory.isLiked
                                            ? Icons.favorite_rounded
                                            : Icons.favorite_border_rounded,
                                        color: _currentStory.isLiked ? Colors.red : Colors.white,
                                        size: 28,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _currentStory.isLiked ? 'Aimé' : 'J’aime',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            _buildStorySideAction(
                              assetIcon: 'assets/svg_icons/chat-round-svgrepo-com.svg',
                              count: _currentStory.commentsCount,
                              onTap: _openStoryCommentsModal,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // --- Quick reply composer for another user's story ---
                if (!_isOwnStory)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: MediaQuery.of(context).padding.bottom + 12,
                    child: AnimatedOpacity(
                      opacity: _isDragging ? 0.0 : 1.0,
                      duration: const Duration(milliseconds: 200),
                      child: _buildQuickStoryReply(),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStorySideAction({
    IconData? icon,
    String? assetIcon,
    required int count,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (assetIcon != null)
                SvgPicture.asset(
                  assetIcon,
                  width: 25,
                  height: 25,
                  colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                )
              else
                Icon(icon, color: Colors.white, size: 25),
              const SizedBox(height: 4),
              Text(
                NumberFormatter.formatCount(count),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickStoryReply() {
    final hasText = _replyController.text.trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 5, 8, 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.32)),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 12, offset: Offset(0, 3)),
        ],
      ),
      child: Row(
        children: [
          PopupMenuButton<String>(
            tooltip: 'Émojis',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            icon: const Icon(Icons.emoji_emotions_outlined, color: Colors.white, size: 25),
            color: const Color(0xFF292929),
            onSelected: (emoji) {
              final value = _replyController.value;
              final selection = value.selection;
              final start = selection.isValid ? selection.start : value.text.length;
              final end = selection.isValid ? selection.end : value.text.length;
              final nextText = value.text.replaceRange(start, end, emoji);
              _replyController.value = TextEditingValue(
                text: nextText,
                selection: TextSelection.collapsed(offset: start + emoji.length),
              );
              setState(() {});
              _commentFocusNode.requestFocus();
            },
            itemBuilder: (_) => ['❤️', '😂', '😍', '🔥', '👏', '👍']
                .map((emoji) => PopupMenuItem<String>(
                      value: emoji,
                      child: Text(emoji, style: const TextStyle(fontSize: 22)),
                    ))
                .toList(),
          ),
          Expanded(
            child: TextField(
              controller: _replyController,
              focusNode: _commentFocusNode,
              onChanged: (_) => setState(() {}),
              minLines: 1,
              maxLines: 3,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendQuickStoryReply(),
              style: const TextStyle(color: Colors.white, fontSize: 14),
              cursorColor: Colors.white,
              decoration: InputDecoration(
                hintText: 'Répondre à la story…',
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.72), fontSize: 13),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
              ),
            ),
          ),
          if (hasText)
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Envoyer',
              onPressed: _isSendingQuickReply ? null : _sendQuickStoryReply,
              icon: _isSendingQuickReply
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send_rounded, color: Colors.white, size: 22),
            )
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Future<void> _sendQuickStoryReply({String? quickEmoji}) async {
    final content = (quickEmoji ?? _replyController.text).trim();
    if (content.isEmpty || _isSendingQuickReply || _isOwnStory || DateTime.now().isAfter(_currentStory.expiresAt)) {
      return;
    }
    setState(() => _isSendingQuickReply = true);
    try {
      await _storiesRepo.createStoryComment(
        p_id: const Uuid().v4(),
        p_story_id: _currentStory.id,
        p_content: content,
        p_parent_comment_id: null,
      );
      if (!mounted) return;
      _replyController.clear();
      setState(() {
        _currentStory.commentsCount++;
        _isSendingQuickReply = false;
      });
      _commentFocusNode.unfocus();
    } catch (e, st) {
      debugPrint('[STORY] Quick reply failed: $e\\n$st');
      if (!mounted) return;
      setState(() => _isSendingQuickReply = false);
      Get.snackbar(
        'error'.tr,
        'story_error_sending_comment'.tr,
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  Future<void> _openStoryCommentsModal() async {
    _animController.stop();
    setState(() => _isPaused = true);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _StoryCommentsSheet(
        storyId: _currentStory.id,
        storyExpiresAt: _currentStory.expiresAt,
        onCommentAdded: () {
          setState(() {
            _currentStory.commentsCount++;
          });
        },
      ),
    );

    if (mounted) {
      setState(() => _isPaused = false);
      _resumeStoryTimer();
    }
  }

  Future<void> _openOriginalPost(String postId) async {
    try {
      final repo = HomeFeedRepository();
      final originalPost = await repo.getPost(postId);
      Get.to(
        () => Scaffold(
          appBar: AppBar(title: Text('comments_original_post'.tr)),
          body: SingleChildScrollView(
            child: FeedPostCard(
              post: originalPost,
              onReactionTap: (r) {},
              onCommentTap: () {},
            ),
          ),
        ),
      );
    } catch (e) {
      Get.snackbar(
        'Erreur',
        'Publication indisponible',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  Color _parseBackground(String? bg) {
    if (bg == null || bg.isEmpty) return Colors.deepPurple;
    if (bg.startsWith('#')) {
      try {
        return Color(int.parse(bg.replaceFirst('#', '0xFF')));
      } catch (_) {}
    }
    switch (bg) {
      case 'sunset':
        return Colors.orangeAccent;
      case 'ocean':
        return Colors.blue;
      case 'forest':
        return Colors.green;
      case 'dark':
        return Colors.black87;
      default:
        return Colors.deepPurple;
    }
  }
}

class _StoryViewersSheet extends StatefulWidget {
  final String storyId;
  const _StoryViewersSheet({required this.storyId});

  @override
  State<_StoryViewersSheet> createState() => _StoryViewersSheetState();
}

class _StoryViewersSheetState extends State<_StoryViewersSheet> {
  final StoriesRepository _repo = StoriesRepository();
  bool _isLoading = true;
  int _totalViewers = 0;
  List<dynamic> _viewers = [];

  @override
  void initState() {
    super.initState();
    _loadViewers();
  }

  Future<void> _loadViewers() async {
    try {
      final res = await _repo.getStoryViewers(widget.storyId, 50, 0);
      if (mounted) {
        setState(() {
          _viewers = res['items'] is List ? res['items'] : [];
          _totalViewers =
              (res['viewers_count'] as num?)?.toInt() ?? _viewers.length;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatViewedTime(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    final dt = DateTime.tryParse(raw)?.toLocal();
    if (dt == null) return raw;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(dt.year, dt.month, dt.day);
    final time =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    final days = today.difference(day).inDays;
    if (days == 0) return "Aujourd’hui à $time";
    if (days == 1) return 'Hier à $time';
    if (days < 7) return 'Il y a $days jours · $time';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} · $time';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.6,
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.of(context).padding.bottom + 20,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.remove_red_eye_rounded,
                size: 20,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Personnes ayant vu (${_totalViewers})',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 8),
          _isLoading
              ? const SizedBox(
                  height: 150,
                  child: Center(child: CircularProgressIndicator()),
                )
              : _viewers.isEmpty
              ? SizedBox(
                  height: 180,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.visibility_off_outlined,
                          size: 42,
                          color: colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Aucune vue pour le moment',
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _viewers.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final v = _viewers[index];
                      final name =
                          '${v['first_name'] ?? ''} ${v['last_name'] ?? ''}'
                              .trim();
                      final displayName = name.isEmpty
                          ? (v['username'] ?? 'Utilisateur')
                          : name;
                      final username = v['username'] != null
                          ? '@${v['username']}'
                          : '';
                      final photoUrl = v['photo_url']?.toString();
                      final liked = v['liked'] == true || v['liked'] == 1;
                      final isCertified =
                          v['is_certified'] == true ||
                          v['is_certified'] == 1 ||
                          v['certified'] == true ||
                          v['is_verified'] == true;

                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          radius: 22,
                          backgroundColor: colorScheme.surfaceContainerHighest,
                          backgroundImage:
                              photoUrl != null && photoUrl.isNotEmpty
                              ? NetworkImage(photoUrl)
                              : null,
                          child: photoUrl == null || photoUrl.isEmpty
                              ? Text(
                                  displayName.isNotEmpty
                                      ? displayName[0].toUpperCase()
                                      : 'U',
                                  style: TextStyle(
                                    color: colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                )
                              : null,
                        ),
                        title: Row(
                          children: [
                            Flexible(
                              child: Text(
                                displayName,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14.5,
                                  color: colorScheme.onSurface,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isCertified) ...[
                              const SizedBox(width: 4),
                              UserCertifiedBadge(size: 13, userId: (v['user_id'] ?? v['author_id'] ?? v['id'])?.toString()),
                            ],
                          ],
                        ),
                        subtitle: username.isNotEmpty
                            ? Text(
                                username,
                                style: TextStyle(
                                  color: colorScheme.onSurfaceVariant,
                                  fontSize: 12.5,
                                ),
                              )
                            : null,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (liked)
                              const Padding(
                                padding: EdgeInsets.only(right: 8),
                                child: Icon(
                                  Icons.favorite_rounded,
                                  color: Colors.red,
                                  size: 16,
                                ),
                              ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHighest
                                    .withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                _formatViewedTime(v['viewed_at']?.toString()),
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
        ],
      ),
    );
  }
}

class _StoryLikersSheet extends StatefulWidget {
  final String storyId;
  const _StoryLikersSheet({required this.storyId});

  @override
  State<_StoryLikersSheet> createState() => _StoryLikersSheetState();
}

class _StoryLikersSheetState extends State<_StoryLikersSheet> {
  final StoriesRepository _repo = StoriesRepository();
  bool _isLoading = true;
  List<dynamic> _likers = [];

  @override
  void initState() {
    super.initState();
    _loadLikers();
  }

  Future<void> _loadLikers() async {
    try {
      final res = await _repo.getStoryViewers(widget.storyId, 100, 0);
      if (mounted) {
        final items = res['items'] is List ? (res['items'] as List) : [];
        setState(() {
          _likers = items
              .where(
                (v) =>
                    v['liked'] == true ||
                    v['liked'] == 1 ||
                    v['user_liked'] == true ||
                    v['is_liked'] == true,
              )
              .toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.6,
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.of(context).padding.bottom + 20,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.favorite_rounded, size: 20, color: Colors.red),
              const SizedBox(width: 8),
              Text(
                'Personnes ayant aimé (${_likers.length})',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 8),
          _isLoading
              ? const SizedBox(
                  height: 150,
                  child: Center(child: CircularProgressIndicator()),
                )
              : _likers.isEmpty
              ? SizedBox(
                  height: 180,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.favorite_border_rounded,
                          size: 42,
                          color: colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Aucun j\'aime pour le moment',
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _likers.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final v = _likers[index];
                      final name =
                          '${v['first_name'] ?? ''} ${v['last_name'] ?? ''}'
                              .trim();
                      final displayName = name.isEmpty
                          ? (v['username'] ?? 'Utilisateur')
                          : name;
                      final username = v['username'] != null
                          ? '@${v['username']}'
                          : '';
                      final photoUrl = v['photo_url']?.toString();
                      final isCertified =
                          v['is_certified'] == true ||
                          v['is_certified'] == 1 ||
                          v['certified'] == true ||
                          v['is_verified'] == true;

                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          radius: 22,
                          backgroundColor: colorScheme.surfaceContainerHighest,
                          backgroundImage:
                              photoUrl != null && photoUrl.isNotEmpty
                              ? NetworkImage(photoUrl)
                              : null,
                          child: photoUrl == null || photoUrl.isEmpty
                              ? Text(
                                  displayName.isNotEmpty
                                      ? displayName[0].toUpperCase()
                                      : 'U',
                                  style: TextStyle(
                                    color: colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                )
                              : null,
                        ),
                        title: Row(
                          children: [
                            Flexible(
                              child: Text(
                                displayName,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14.5,
                                  color: colorScheme.onSurface,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isCertified) ...[
                              const SizedBox(width: 4),
                              UserCertifiedBadge(size: 13, userId: (v['user_id'] ?? v['author_id'] ?? v['id'])?.toString()),
                            ],
                          ],
                        ),
                        subtitle: username.isNotEmpty
                            ? Text(
                                username,
                                style: TextStyle(
                                  color: colorScheme.onSurfaceVariant,
                                  fontSize: 12.5,
                                ),
                              )
                            : null,
                        trailing: const Icon(
                          Icons.favorite_rounded,
                          color: Colors.red,
                          size: 20,
                        ),
                      );
                    },
                  ),
                ),
        ],
      ),
    );
  }
}

class _StoryCommentsSheet extends StatefulWidget {
  final String storyId;
  final DateTime storyExpiresAt;
  final VoidCallback? onCommentAdded;

  const _StoryCommentsSheet({
    required this.storyId,
    required this.storyExpiresAt,
    this.onCommentAdded,
  });

  @override
  State<_StoryCommentsSheet> createState() => _StoryCommentsSheetState();
}

class _StoryCommentsSheetState extends State<_StoryCommentsSheet> {
  final StoriesRepository _repo = StoriesRepository();
  final TextEditingController _commentController = TextEditingController();
  final FocusNode _commentFocusNode = FocusNode();

  bool _isLoading = true;
  bool _isSending = false;
  List<Map<String, dynamic>> _comments = [];
  final Set<String> _expandedReplyIds = <String>{};
  final Map<String, List<Map<String, dynamic>>> _repliesByCommentId = {};
  final Set<String> _loadingReplyIds = <String>{};
  Map<String, dynamic>? _replyingTo;
  String? _errorMessage;

  bool get _isExpired => DateTime.now().isAfter(widget.storyExpiresAt);

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  @override
  void dispose() {
    _commentController.dispose();
    _commentFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final res = await _repo.getStoryComments(widget.storyId);
      final items = res['items'] is List
          ? List<Map<String, dynamic>>.from(res['items'])
          : <Map<String, dynamic>>[];
      if (mounted) {
        setState(() {
          _comments = items;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[STORY] Error loading comments: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'story_error_loading_comments'.tr;
        });
      }
    }
  }

  Future<void> _toggleReplies(Map<String, dynamic> comment) async {
    final commentId = comment['id']?.toString() ?? '';
    if (commentId.isEmpty) return;

    if (_expandedReplyIds.contains(commentId)) {
      setState(() => _expandedReplyIds.remove(commentId));
      return;
    }

    setState(() {
      _expandedReplyIds.add(commentId);
      _loadingReplyIds.add(commentId);
    });

    try {
      // Charger uniquement les réponses du commentaire sélectionné.
      final res = await _repo.getStoryCommentReplies(
        widget.storyId,
        commentId,
      );
      final replies = res['items'] is List
          ? List<Map<String, dynamic>>.from(res['items'])
          : <Map<String, dynamic>>[];

      if (mounted) {
        setState(() {
          _repliesByCommentId[commentId] = replies;
          _loadingReplyIds.remove(commentId);
        });
      }
    } catch (e) {
      debugPrint('[STORY] Error loading replies for $commentId: $e');
      if (mounted) {
        setState(() {
          _loadingReplyIds.remove(commentId);
          _expandedReplyIds.remove(commentId);
        });
        Get.snackbar(
          'error'.tr,
          'story_error_loading_comments'.tr,
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    }
  }

  Future<void> _toggleStoryCommentReaction(
    Map<String, dynamic> comment,
    String reaction,
  ) async {
    final commentId = comment['id']?.toString() ?? '';
    if (commentId.isEmpty || _isExpired) return;

    final previousReaction = comment['user_reaction']?.toString();
    final previousLikes = (comment['likes_count'] as num?)?.toInt() ?? 0;
    final previousDislikes = (comment['dislikes_count'] as num?)?.toInt() ?? 0;
    final nextReaction = previousReaction == reaction ? 'none' : reaction;

    setState(() {
      comment['user_reaction'] = nextReaction == 'none' ? null : nextReaction;
      comment['likes_count'] =
          (previousLikes +
                  (nextReaction == 'like' ? 1 : 0) -
                  (previousReaction == 'like' ? 1 : 0))
              .clamp(0, 1 << 30);
      comment['dislikes_count'] =
          (previousDislikes +
                  (nextReaction == 'dislike' ? 1 : 0) -
                  (previousReaction == 'dislike' ? 1 : 0))
              .clamp(0, 1 << 30);
    });

    try {
      await _repo.setStoryCommentReaction(commentId, nextReaction);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        comment['user_reaction'] = previousReaction;
        comment['likes_count'] = previousLikes;
        comment['dislikes_count'] = previousDislikes;
      });
      Get.snackbar(
        'Erreur',
        'Impossible d’enregistrer la réaction.',
        snackPosition: SnackPosition.BOTTOM,
      );
      debugPrint('[STORY] Error reacting to comment: $e');
    }
  }

  Future<void> _shareStoryComment(Map<String, dynamic> comment) async {
    final author = comment['author'] is Map
        ? Map<String, dynamic>.from(comment['author'])
        : <String, dynamic>{};
    final username = author['username']?.toString();
    final authorName = username != null && username.isNotEmpty
        ? '@$username'
        : (author['first_name']?.toString() ?? 'story_default_user'.tr);
    final content = comment['content']?.toString() ?? '';
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: 'story_share_comment_text'.trParams({'author': authorName, 'content': content}),
        ),
      );
    } catch (e) {
      if (mounted) {
        Get.snackbar(
          'story_share_comment_error_title'.tr,
          'story_share_comment_error'.tr,
          snackPosition: SnackPosition.BOTTOM,
        );
      }
      debugPrint('[STORY] Error sharing story comment: $e');
    }
  }

  Future<void> _sendComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty || _isSending || _isExpired) return;

    setState(() => _isSending = true);
    try {
      final commentId = const Uuid().v4();
      // Les stories autorisent un seul niveau de réponses : si l'utilisateur
      // appuie sur « Répondre » sous une réponse, rattacher au commentaire
      // racine plutôt qu'à une réponse qui ne peut pas être parent.
      final parentId = _replyingTo?['parent_comment_id']?.toString() ??
          _replyingTo?['id']?.toString();

      await _repo.createStoryComment(
        p_id: commentId,
        p_story_id: widget.storyId,
        p_content: text,
        p_parent_comment_id: parentId,
      );

      _commentController.clear();
      setState(() {
        _replyingTo = null;
        _isSending = false;
      });

      await _loadComments();
      widget.onCommentAdded?.call();
    } catch (e) {
      debugPrint('[STORY] Error sending comment: $e');
      if (mounted) {
        setState(() => _isSending = false);
        Get.snackbar(
          'error'.tr,
          'story_error_sending_comment'.tr,
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'story_comment_title'.tr,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: _isLoading
                ? const SizedBox(
                    height: 150,
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _errorMessage != null
                ? SizedBox(
                    height: 150,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _errorMessage!,
                            style: TextStyle(color: colorScheme.error),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: _loadComments,
                            child: Text('retry'.tr),
                          ),
                        ],
                      ),
                    ),
                  )
                : _comments.isEmpty
                ? SizedBox(
                    height: 180,
                    child: Center(
                      child: Text(
                        'story_no_comments'.tr,
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(16),
                    itemCount: _comments.length,
                    itemBuilder: (context, index) {
                      final comment = _comments[index];
                      return _buildCommentItem(comment, colorScheme);
                    },
                  ),
          ),
          if (_replyingTo != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: colorScheme.primaryContainer.withValues(alpha: 0.4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'story_replying_to'.trParams({
                        'author':
                            _replyingTo!['author']?['username'] ??
                            _replyingTo!['author']?['first_name'] ??
                            'story_default_user'.tr,
                      }),
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _replyingTo = null),
                    child: Text(
                      'story_cancel_reply'.tr,
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Container(
            padding: EdgeInsets.fromLTRB(
              16,
              12,
              16,
              MediaQuery.of(context).padding.bottom + 12,
            ),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: _isExpired
                ? Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.errorContainer.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'story_expired_comment_disabled'.tr,
                      style: TextStyle(
                        color: colorScheme.error,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                : Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _commentController,
                          focusNode: _commentFocusNode,
                          decoration: InputDecoration(
                            hintText: 'story_write_comment_hint'.tr,
                            filled: true,
                            fillColor: colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.5),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          maxLines: null,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _sendComment(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'story_send'.tr,
                        onPressed: _isSending ? null : _sendComment,
                        icon: _isSending
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                Icons.send_rounded,
                                color: colorScheme.primary,
                              ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentItem(
    Map<String, dynamic> comment,
    ColorScheme colorScheme, {
    bool isReply = false,
  }) {
    final author = comment['author'] is Map
        ? Map<String, dynamic>.from(comment['author'])
        : <String, dynamic>{};
    final authorName =
        author['first_name'] != null || author['last_name'] != null
        ? '${author['first_name'] ?? ''} ${author['last_name'] ?? ''}'.trim()
        : (author['username']?.toString() ?? 'Utilisateur');
    final avatarUrl =
        author['photo_url']?.toString() ?? author['avatar_url']?.toString();
    final username = author['username']?.toString() ?? '';
    final isCertified =
        author['is_certified'] == true ||
        author['is_certified'] == 1 ||
        author['is_verified'] == true ||
        author['is_verified'] == 1;
    final createdAt = DateTime.tryParse(
      comment['created_at']?.toString() ?? '',
    );
    String commentAge() {
      if (createdAt == null) return '';
      final elapsed = DateTime.now().difference(createdAt);
      if (elapsed.inSeconds < 60) return 'relative_just_now'.tr;
      if (elapsed.inMinutes < 60) return 'relative_minutes_ago'.trParams({'count': '${elapsed.inMinutes}'});
      if (elapsed.inHours < 24) return 'relative_hours_ago'.trParams({'count': '${elapsed.inHours}'});
      if (elapsed.inDays == 1) return 'relative_one_day_ago'.tr;
      if (elapsed.inDays < 7) return 'relative_days_ago'.trParams({'count': '${elapsed.inDays}'});
      return '${createdAt.day.toString().padLeft(2, '0')}/${createdAt.month.toString().padLeft(2, '0')}/${createdAt.year}';
    }

    final content = comment['content']?.toString() ?? '';
    final likesCount = (comment['likes_count'] as num?)?.toInt() ?? 0;
    final dislikesCount = (comment['dislikes_count'] as num?)?.toInt() ?? 0;
    final userReaction = comment['user_reaction']?.toString();
    final commentId = comment['id']?.toString() ?? '';
    final replies = isReply
        ? <Map<String, dynamic>>[]
        : (_repliesByCommentId[commentId] ?? <Map<String, dynamic>>[]);
    final repliesExpanded = _expandedReplyIds.contains(commentId);
    final repliesLoading = _loadingReplyIds.contains(commentId);
    final repliesCount = (comment['replies_count'] as num?)?.toInt() ??
        (comment['reply_count'] as num?)?.toInt() ??
        replies.length;

    return Padding(
      padding: EdgeInsets.only(left: isReply ? 32 : 0, bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: isReply ? 14 : 18,
            backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                ? NetworkImage(avatarUrl)
                : null,
            child: avatarUrl == null || avatarUrl.isEmpty
                ? const Icon(Icons.person, size: 16)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            fit: FlexFit.loose,
                            child: Text(
                              authorName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: colorScheme.onSurface,
                              ),
                            ),
                          ),
                          if (username.isNotEmpty) ...[
                            const SizedBox(width: 4),
                            Flexible(
                              fit: FlexFit.loose,
                              child: Text(
                                '@$username',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                          if (isCertified) ...[
                            const SizedBox(width: 4),
                            UserCertifiedBadge(size: 13, userId: (author['user_id'] ?? author['id'])?.toString()),
                          ],
                          if (commentAge().isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                commentAge(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.end,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      LinkifiedText(
                        text: content,
                        style: TextStyle(
                          fontSize: 14,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 5),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      InkWell(
                        onTap: () => _shareStoryComment(comment),
                        child: Icon(
                          Icons.ios_share_rounded,
                          size: 15,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      InkWell(
                        onTap: () =>
                            _toggleStoryCommentReaction(comment, 'like'),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.north_rounded,
                              size: 16,
                              color: userReaction == 'like'
                                  ? colorScheme.primary
                                  : colorScheme.onSurfaceVariant,
                            ),
                            if (likesCount > 0) ...[
                              const SizedBox(width: 3),
                              Text(
                                '$likesCount',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: userReaction == 'like'
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: userReaction == 'like'
                                      ? colorScheme.primary
                                      : colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      InkWell(
                        onTap: () =>
                            _toggleStoryCommentReaction(comment, 'dislike'),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.south_rounded,
                              size: 16,
                              color: userReaction == 'dislike'
                                  ? Colors.orangeAccent
                                  : colorScheme.onSurfaceVariant,
                            ),
                            if (dislikesCount > 0) ...[
                              const SizedBox(width: 3),
                              Text(
                                '$dislikesCount',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: userReaction == 'dislike'
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: userReaction == 'dislike'
                                      ? Colors.orangeAccent
                                      : colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () => setState(() => _replyingTo = comment),
                        child: Text(
                          'story_reply_action'.tr,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isReply && repliesCount > 0) ...[
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: repliesLoading ? null : () => _toggleReplies(comment),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (repliesLoading)
                            const SizedBox(
                              width: 13,
                              height: 13,
                              child: CircularProgressIndicator(strokeWidth: 1.6),
                            )
                          else
                            Icon(
                              repliesExpanded
                                  ? Icons.keyboard_arrow_up_rounded
                                  : Icons.keyboard_arrow_down_rounded,
                              size: 18,
                              color: colorScheme.primary,
                            ),
                          const SizedBox(width: 4),
                          Text(
                            repliesLoading
                                ? 'comments_loading_replies'.tr
                                : repliesExpanded
                                    ? 'comments_hide_replies'.tr
                                    : 'comments_show_replies'.trParams({'count': '$repliesCount'}),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (!isReply && repliesExpanded && !repliesLoading && replies.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 8, top: 4),
                    child: Text(
                      'comments_no_replies'.tr,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                if (!isReply && repliesExpanded && !repliesLoading && replies.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ...replies.map(
                    (reply) =>
                        _buildCommentItem(reply, colorScheme, isReply: true),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Story-specific video player: unlike the feed player it never loops, and
/// the story advances only when the source video finishes.
String _formatOriginalPostDate(String raw) {
  final date = DateTime.tryParse(raw)?.toLocal();
  if (date == null) return raw;
  final now = DateTime.now();
  final sameDay = date.year == now.year && date.month == now.month && date.day == now.day;
  final clock = '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  if (sameDay) return "Aujourd’hui à $clock";
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} · $clock';
}

class _StorySharedVideoPost extends StatefulWidget {
  final CommunityPost post;
  final ValueChanged<double> onProgress;
  final VoidCallback onCompleted;

  const _StorySharedVideoPost({
    super.key,
    required this.post,
    required this.onProgress,
    required this.onCompleted,
  });

  @override
  State<_StorySharedVideoPost> createState() => _StorySharedVideoPostState();
}

class _StorySharedVideoPostState extends State<_StorySharedVideoPost> {
  VideoPlayerController? _controller;
  bool _failed = false;
  bool _isDownloading = false;
  bool _completionHandled = false;
  Timer? _expiryCleanupTimer;

  @override
  void initState() {
    super.initState();
    final video = widget.post.media.firstWhere(
      (media) => media.isVideo && (media.url ?? '').trim().isNotEmpty,
    );
    _controller = VideoPlayerController.networkUrl(Uri.parse(video.url!))
      ..addListener(_onVideoChanged);
    _initialize();
  }

  Future<void> _initialize() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      await controller.setLooping(false);
      await controller.setVolume(1);
      setState(() {});
      await controller.play();
    } catch (e) {
      debugPrint('[STORY] Shared video failed to initialize: $e');
      if (mounted) setState(() => _failed = true);
    }
  }

  void _onVideoChanged() {
    final controller = _controller;
    if (!mounted || controller == null || !controller.value.isInitialized) return;
    if (controller.value.hasError) {
      setState(() => _failed = true);
      return;
    }
    if (controller.value.duration > Duration.zero) {
      widget.onProgress(
        (controller.value.position.inMilliseconds /
                controller.value.duration.inMilliseconds)
            .clamp(0.0, 1.0),
      );
    }
    if (controller.value.position >= controller.value.duration &&
        controller.value.duration > Duration.zero &&
        !_completionHandled) {
      _completionHandled = true;
      widget.onCompleted();
    }
  }

  @override
  void dispose() {
    // Keep the expiry timer alive after leaving the viewer so cached media
    // is deleted at the story's actual expiration time.
    _controller?.removeListener(_onVideoChanged);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: colorScheme.surfaceContainerHighest,
                backgroundImage: widget.post.authorObj?.photoUrl != null &&
                        widget.post.authorObj!.photoUrl!.trim().isNotEmpty
                    ? NetworkImage(widget.post.authorObj!.photoUrl!)
                    : null,
                child: widget.post.authorObj?.photoUrl == null ||
                        widget.post.authorObj!.photoUrl!.trim().isEmpty
                    ? Text(widget.post.authorName.trim().isNotEmpty
                        ? widget.post.authorName.trim()[0].toUpperCase()
                        : 'U')
                    : null,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(
                        child: Text(widget.post.authorName,
                          style: TextStyle(color: colorScheme.onSurface,
                            fontWeight: FontWeight.w700, fontSize: 14),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      if ((widget.post.authorObj?.username ?? '').trim().isNotEmpty) ...[
                        const SizedBox(width: 4),
                        Flexible(child: Text(
                          '@${widget.post.authorObj!.username.replaceFirst(RegExp(r'^@'), '')}',
                          style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
                          maxLines: 1, overflow: TextOverflow.ellipsis)),
                      ],
                      if (widget.post.authorObj?.isCertified == true) ...[
                        const SizedBox(width: 4),
                        UserCertifiedBadge(size: 14, userId: widget.post.authorObj!.userId),
                      ],
                    ]),
                    Text(_formatOriginalPostDate(widget.post.timeAgo),
                      style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 11),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
          if (widget.post.content.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              widget.post.content,
              style: TextStyle(color: colorScheme.onSurface),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: (MediaQuery.of(context).size.height * 0.34)
                .clamp(150.0, 280.0)
                .toDouble(),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ColoredBox(
                color: Colors.black,
                child: controller?.value.isInitialized == true && !_failed
                    ? FittedBox(
                        fit: BoxFit.contain,
                        child: SizedBox(
                          width: controller!.value.size.width,
                          height: controller.value.size.height,
                          child: IgnorePointer(
                            child: VideoPlayer(controller),
                          ),
                        ),
                      )
                    : Center(
                        child: Icon(
                          _failed ? Icons.error_outline_rounded : Icons.play_circle_outline_rounded,
                          color: Colors.white,
                          size: 44,
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

/// Plays a standalone video story from its private R2 object key. Playback is
/// non-looping and the story advances only after the video reaches its end.
class _StoryVideoPlayer extends StatefulWidget {
  final String objectKey;
  final String storyId;
  final DateTime expiresAt;
  final String? thumbnailObjectKey;
  final String? fallbackImageUrl;
  final bool isPaused;
  final ValueChanged<double> onProgress;
  final VoidCallback onCompleted;

  const _StoryVideoPlayer({
    super.key,
    required this.objectKey,
    required this.storyId,
    required this.expiresAt,
    this.thumbnailObjectKey,
    this.fallbackImageUrl,
    required this.isPaused,
    required this.onProgress,
    required this.onCompleted,
  });

  @override
  State<_StoryVideoPlayer> createState() => _StoryVideoPlayerState();
}

class _StoryVideoPlayerState extends State<_StoryVideoPlayer> {
  VideoPlayerController? _controller;
  bool _failed = false;
  bool _isDownloading = false;
  bool _completionHandled = false;
  Timer? _expiryCleanupTimer;

  @override
  void initState() {
    super.initState();
    final untilExpiry = widget.expiresAt.difference(DateTime.now());
    if (untilExpiry > Duration.zero) {
      _expiryCleanupTimer = Timer(untilExpiry, _deleteExpiredLocalVideo);
    }
    _initialize();
  }

  String _storyVideoExtension() {
    final path = Uri.tryParse(widget.objectKey)?.path ?? widget.objectKey;
    final extension = p.extension(path).toLowerCase();
    return extension == '.mov' ? '.mov' : '.mp4';
  }

  Future<void> _deleteExpiredLocalVideo() async {
    try {
      final directory = await getApplicationSupportDirectory();
      final safeId = widget.storyId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final media = File(p.join(directory.path, 'stories_cache', safeId + _storyVideoExtension()));
      final expiry = File(p.join(directory.path, 'stories_cache', '$safeId.expiry'));
      if (await media.exists()) await media.delete();
      if (await expiry.exists()) await expiry.delete();
      debugPrint('[STORY_CACHE] EXPIRED story=${widget.storyId} removed');
    } catch (e) {
      debugPrint('[STORY_CACHE] Expiry cleanup failed: $e');
    }
  }

  @override
  void didUpdateWidget(covariant _StoryVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isPaused != widget.isPaused) {
      _syncPlaybackState();
    }
  }

  Future<void> _syncPlaybackState() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      if (widget.isPaused) {
        await controller.pause();
      } else {
        await controller.play();
      }
    } catch (e) {
      debugPrint('[STORY] Unable to update video pause state: $e');
    }
  }

  Future<void> _initialize() async {
    try {
      final localVideo = await _getOrDownloadStoryVideo();
      if (!mounted) return;
      final controller = VideoPlayerController.file(localVideo);
      _controller = controller;
      controller.addListener(_onVideoChanged);
      await controller.initialize();
      if (!mounted) return;
      await controller.setLooping(false);
      await controller.setVolume(1);
      setState(() {});
      if (!widget.isPaused) await controller.play();
    } catch (e) {
      debugPrint('[STORY] Standalone video initialization failed: $e');
      await _deleteExpiredLocalVideo();
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<File> _getOrDownloadStoryVideo() async {
    final directory = await getApplicationSupportDirectory();
    final cacheDirectory = Directory(p.join(directory.path, 'stories_cache'));
    if (!await cacheDirectory.exists()) {
      await cacheDirectory.create(recursive: true);
    }
    // Remove media belonging to stories that have already expired.
    final now = DateTime.now().toUtc();
    await for (final entity in cacheDirectory.list()) {
      if (entity is! File || !entity.path.endsWith('.expiry')) continue;
      try {
        final cachedExpiry = DateTime.tryParse(await entity.readAsString());
        if (cachedExpiry == null || !cachedExpiry.isAfter(now)) {
          final basePath = entity.path.substring(0, entity.path.length - '.expiry'.length);
          for (final extension in ['.mp4', '.mov']) {
            final cachedMedia = File('$basePath$extension');
            if (await cachedMedia.exists()) await cachedMedia.delete();
          }
          await entity.delete();
        }
      } catch (cleanupError) {
        debugPrint('[STORY_CACHE] Expired cache cleanup failed: $cleanupError');
      }
    }
    final safeId = widget.storyId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final videoFile = File(p.join(cacheDirectory.path, safeId + _storyVideoExtension()));
    final expiryFile = File(p.join(cacheDirectory.path, '$safeId.expiry'));
    final expiry = widget.expiresAt.toUtc();
    if (await videoFile.exists() && await expiryFile.exists()) {
      final cachedExpiry = DateTime.tryParse(await expiryFile.readAsString());
      if (cachedExpiry != null && cachedExpiry.isAfter(DateTime.now().toUtc()) &&
          cachedExpiry.isAtSameMomentAs(expiry) && await videoFile.length() > 0) {
        debugPrint('[STORY_CACHE] HIT story=${widget.storyId}');
        return videoFile;
      }
    }
    if (await videoFile.exists()) await videoFile.delete();
    if (await expiryFile.exists()) await expiryFile.delete();

    var url = widget.objectKey;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      final response = await Supabase.instance.client.functions.invoke(
        'r2-media-upload',
        body: {'action': 'create-download-url', 'object_key': widget.objectKey},
      );
      if (response.status < 200 || response.status >= 300 || response.data is! Map) {
        throw StateError('Impossible de résoudre la vidéo privée de la story.');
      }
      url = (response.data as Map)['url']?.toString() ?? '';
      if (url.isEmpty) throw StateError('URL de lecture de la vidéo absente.');
    }
    if (widget.expiresAt.isBefore(DateTime.now())) {
      throw StateError('Cette story a expiré.');
    }
    if (mounted) setState(() => _isDownloading = true);
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(url));
      final streamed = await client.send(request).timeout(const Duration(minutes: 3));
      if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
        throw HttpException('Téléchargement de la story impossible (HTTP ${streamed.statusCode}).');
      }
      final sink = videoFile.openWrite();
      try {
        await streamed.stream.pipe(sink);
      } catch (_) {
        await sink.close();
        if (await videoFile.exists()) await videoFile.delete();
        rethrow;
      }
      final size = await videoFile.length();
      if (size == 0) {
        await videoFile.delete();
        throw StateError('Le fichier vidéo téléchargé est vide.');
      }
      await expiryFile.writeAsString(expiry.toIso8601String(), flush: true);
      debugPrint('[STORY_CACHE] SAVED story=${widget.storyId} bytes=$size expires=$expiry');
      return videoFile;
    } finally {
      client.close();
      if (mounted) setState(() => _isDownloading = false);
    }
  }


  void _onVideoChanged() {
    final controller = _controller;
    if (!mounted || controller == null || !controller.value.isInitialized) return;
    if (controller.value.hasError) {
      setState(() => _failed = true);
      return;
    }
    if (controller.value.duration > Duration.zero) {
      widget.onProgress(
        (controller.value.position.inMilliseconds /
                controller.value.duration.inMilliseconds)
            .clamp(0.0, 1.0),
      );
    }
    if (controller.value.duration > Duration.zero &&
        controller.value.position >= controller.value.duration &&
        !_completionHandled) {
      _completionHandled = true;
      widget.onCompleted();
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onVideoChanged);
    _controller?.dispose();
    super.dispose();
  }

  Widget _buildFallbackBackground() {
    final fallback = widget.fallbackImageUrl?.trim() ?? '';
    if (fallback.isEmpty) return const ColoredBox(color: Colors.black);
    return AppCachedImage(
      imageUrl: fallback,
      fit: BoxFit.cover,
      errorWidget: const ColoredBox(color: Colors.black),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_failed) {
      return const Center(child: Icon(Icons.error_outline_rounded, color: Colors.white, size: 48));
    }
    if (controller == null || !controller.value.isInitialized) {
      return Stack(
        fit: StackFit.expand,
        children: [
          if (widget.thumbnailObjectKey != null && widget.thumbnailObjectKey!.isNotEmpty)
            AppCachedImage(
              imageUrl: widget.thumbnailObjectKey!,
              fit: BoxFit.cover,
              cacheUntil: widget.expiresAt,
              errorWidget: _buildFallbackBackground(),
            )
          else
            _buildFallbackBackground(),
          Center(
            child: Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.48),
                shape: BoxShape.circle,
              ),
              child: _isDownloading
                  ? const SizedBox(
                      width: 25,
                      height: 25,
                      child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                    )
                  : const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 38),
            ),
          ),
        ],
      );
    }
    // The story viewer owns navigation; the video itself is not tappable.
    return IgnorePointer(
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: controller.value.size.width,
            height: controller.value.size.height,
            child: VideoPlayer(controller),
          ),
        ),
      ),
    );
  }
}
