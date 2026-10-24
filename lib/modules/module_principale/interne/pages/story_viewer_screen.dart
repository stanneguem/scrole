import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:lottie/lottie.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../../../shared/widgets/app_cached_image.dart';
import '../../../../shared/widgets/user_certified_badge.dart';
import '../../../../shared/widgets/user_identity_row.dart';
import '../../../../shared/utils/number_formatter.dart';
import '../controllers/stories_controller.dart';
import '../widgets/feed_post_card.dart';
import 'package:scrole/modules/module_principale/externe/repositories/stories_repository.dart';
import 'package:scrole/modules/module_principale/externe/repositories/home_feed_repository.dart';

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
            _animController.forward();
          }
        }
      }
    });

    // Wait until the first frame so inherited widgets (MediaQuery/Theme)
    // are available before starting story image precaching.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _startStory();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _precacheNextStory();
  }

  void _precacheNextStory() {
    if (_storyIndex < _currentGroup.stories.length - 1) {
      final url = _currentGroup.stories[_storyIndex + 1].imageUrl;
      if (url != null && url.isNotEmpty) {
        precacheImage(NetworkImage(url), context);
      }
    } else if (_groupIndex < widget.groups.length - 1) {
      final nextGroup = widget.groups[_groupIndex + 1];
      if (nextGroup.stories.isNotEmpty) {
        final url = nextGroup.stories.first.imageUrl;
        if (url != null && url.isNotEmpty) {
          precacheImage(NetworkImage(url), context).catchError((Object _) {});
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
    if (!_isPaused && !_commentFocusNode.hasFocus) {
      if (_currentStoryHasVideo) {
        // A video repost advances only when the actual video reaches its end.
        _animController.stop();
        _animController.value = 0;
      } else {
        _animController.forward(from: 0.0);
      }
      _markCurrentViewed();
      _precacheNextStory();
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

  String _formatStoryAge(DateTime createdAt) {
    final elapsed = DateTime.now().difference(createdAt);
    if (elapsed.isNegative || elapsed.inSeconds < 60) return 'À l’instant';
    if (elapsed.inMinutes < 60) return 'Il y a ${elapsed.inMinutes} min';
    if (elapsed.inHours < 24) return 'Il y a ${elapsed.inHours} h';
    if (elapsed.inDays == 1) return 'Il y a 1 jour';
    if (elapsed.inDays < 7) return 'Il y a ${elapsed.inDays} jours';
    return '${createdAt.day.toString().padLeft(2, '0')}/${createdAt.month.toString().padLeft(2, '0')}/${createdAt.year}';
  }

  void _nextStory() {
    if (_storyIndex < _currentGroup.stories.length - 1) {
      setState(() => _storyIndex++);
      _startStory();
    } else if (_groupIndex < widget.groups.length - 1) {
      setState(() {
        _groupIndex++;
        _storyIndex = 0;
      });
      _startStory();
    } else {
      Navigator.of(context).pop();
    }
  }

  void _prevStory() {
    if (_storyIndex > 0) {
      setState(() => _storyIndex--);
      _startStory();
    } else if (_groupIndex > 0) {
      setState(() {
        _groupIndex--;
        _storyIndex = widget.groups[_groupIndex].stories.length - 1;
      });
      _startStory();
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

  Future<void> _shareCurrentStory() async {
    final story = _currentStory;
    final author = _currentGroup.author.displayName;
    final parts = <String>[
      'Story de $author sur Scrole',
      if ((story.content ?? '').trim().isNotEmpty) story.content!.trim(),
      if ((story.imageUrl ?? '').trim().isNotEmpty) story.imageUrl!.trim(),
    ];
    try {
      await SharePlus.instance.share(ShareParams(text: parts.join('\n\n')));
    } catch (e) {
      if (mounted) {
        Get.snackbar(
          'Erreur',
          'Impossible de partager cette story.',
          snackPosition: SnackPosition.BOTTOM,
        );
      }
      debugPrint('[STORY] Error sharing story: $e');
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
      _nextStory();
    } else {
      _animController.forward();
    }
  }

  void _onCancel() {
    if (_commentFocusNode.hasFocus || _isPaused) return;
    _animController.forward();
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
      _animController.forward();
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
      _animController.forward();
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
              ListTile(
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
            const SizedBox(height: 8),
            ListTile(
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
          ],
        ),
      ),
    );

    if (mounted) {
      setState(() => _isPaused = false);
      _animController.forward();
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
            onTapDown: _onTapDown,
            onTapUp: _onTapUp,
            onTapCancel: _onCancel,
            onDoubleTap: _isOwnStory ? null : _toggleStoryLike,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // --- Media / Background ---
                if (_currentStory.kind == 'video' &&
                    _currentStory.imageUrl != null &&
                    _currentStory.imageUrl!.isNotEmpty)
                  _StoryVideoPlayer(
                    objectKey: _currentStory.imageUrl!,
                    onCompleted: _nextStory,
                  )
                else if (_currentStory.kind == 'image' &&
                    _currentStory.imageUrl != null)
                  Center(
                    child: AppCachedImage(
                      imageUrl: _currentStory.imageUrl!,
                      fit: BoxFit.cover,
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
                            Text(
                              _currentStory.content!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
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
                            GestureDetector(
                              onTap: () {
                                if (_currentStory.sharedPostId != null && _currentStory.sharedPostCanOpenOriginal) {
                                  _openOriginalPost(
                                    _currentStory.sharedPostId!,
                                  );
                                }
                              },
                              child: Container(
                                constraints: const BoxConstraints(
                                  maxWidth: 400,
                                ),
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
                                child: _currentStory.sharedPost!.media.any(
                                  (media) => media.isVideo && (media.url ?? '').trim().isNotEmpty,
                                )
                                    ? _StorySharedVideoPost(
                                        post: _currentStory.sharedPost!,
                                        onCompleted: _nextStory,
                                      )
                                    : FeedPostCard(
                                        post: _currentStory.sharedPost!,
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
                                          ? _animController.value
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

                // --- Bottom Interactive Bar ---
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: () {},
                    child: AnimatedOpacity(
                      opacity: _isDragging ? 0.0 : 1.0,
                      duration: const Duration(milliseconds: 200),
                      child: Container(
                        padding: EdgeInsets.fromLTRB(
                          16,
                          12,
                          16,
                          MediaQuery.of(context).padding.bottom + 12,
                        ),
                        color: Colors.black.withValues(alpha: 0.3),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            // 1. Views icon & count (Only for own story)
                            if (_isOwnStory)
                              InkWell(
                                onTap: _showViewersSheet,
                                borderRadius: BorderRadius.circular(16),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.remove_red_eye_outlined,
                                        color: Colors.white,
                                        size: 22,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        NumberFormatter.formatCount(
                                          _currentStory.viewersCount,
                                        ),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                            // Share story with the device share sheet.
                            InkWell(
                              onTap: _shareCurrentStory,
                              borderRadius: BorderRadius.circular(16),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                child: Icon(
                                  Icons.ios_share_rounded,
                                  color: Colors.white,
                                  size: 22,
                                ),
                              ),
                            ),

                            // 2. Comments icon & count (Both own & other stories)
                            InkWell(
                              onTap: _openStoryCommentsModal,
                              borderRadius: BorderRadius.circular(16),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SvgPicture.asset(
                                      'assets/svg_icons/chat-round-svgrepo-com.svg',
                                      width: 22,
                                      height: 22,
                                      colorFilter: const ColorFilter.mode(
                                        Colors.white,
                                        BlendMode.srcIn,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      NumberFormatter.formatCount(
                                        _currentStory.commentsCount,
                                      ),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            // 3. Like icon only (Only for other users' stories, NO count)
                            if (!_isOwnStory)
                              InkWell(
                                onTap: _toggleStoryLike,
                                borderRadius: BorderRadius.circular(16),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  child: Icon(
                                    _currentStory.isLiked
                                        ? Icons.favorite_rounded
                                        : Icons.favorite_border_rounded,
                                    color: _currentStory.isLiked
                                        ? Colors.red
                                        : Colors.white,
                                    size: 26,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
      _animController.forward();
    }
  }

  Future<void> _openOriginalPost(String postId) async {
    try {
      final repo = HomeFeedRepository();
      final originalPost = await repo.getPost(postId);
      Get.to(
        () => Scaffold(
          appBar: AppBar(title: const Text('Publication originale')),
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
        : (author['first_name']?.toString() ?? 'Utilisateur');
    final content = comment['content']?.toString() ?? '';
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: 'Commentaire de $authorName sur une story Scrole :\n\n$content',
        ),
      );
    } catch (e) {
      if (mounted) {
        Get.snackbar(
          'Erreur',
          'Impossible de partager ce commentaire.',
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
                            'Utilisateur',
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
      if (elapsed.inSeconds < 60) return 'À l’instant';
      if (elapsed.inMinutes < 60) return 'Il y a ${elapsed.inMinutes} min';
      if (elapsed.inHours < 24) return 'Il y a ${elapsed.inHours} h';
      if (elapsed.inDays == 1) return 'Il y a 1 jour';
      if (elapsed.inDays < 7) return 'Il y a ${elapsed.inDays} jours';
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
                      Text(
                        content,
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
                                ? 'Chargement des réponses…'
                                : repliesExpanded
                                    ? 'Masquer les réponses'
                                    : 'Afficher les réponses ($repliesCount)',
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
                      'Aucune réponse pour le moment.',
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
class _StorySharedVideoPost extends StatefulWidget {
  final CommunityPost post;
  final VoidCallback onCompleted;

  const _StorySharedVideoPost({
    required this.post,
    required this.onCompleted,
  });

  @override
  State<_StorySharedVideoPost> createState() => _StorySharedVideoPostState();
}

class _StorySharedVideoPostState extends State<_StorySharedVideoPost> {
  VideoPlayerController? _controller;
  bool _failed = false;
  bool _completionHandled = false;

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
      if (!mounted) return;
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
    if (controller.value.position >= controller.value.duration &&
        controller.value.duration > Duration.zero &&
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
          Text(
            widget.post.authorName,
            style: TextStyle(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
          AspectRatio(
            aspectRatio: controller?.value.isInitialized == true
                ? controller!.value.aspectRatio
                : 9 / 16,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ColoredBox(
                color: Colors.black,
                child: controller?.value.isInitialized == true && !_failed
                    ? VideoPlayer(controller!)
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
          if (controller?.value.isInitialized == true && !_failed)
            VideoProgressIndicator(
              controller!,
              allowScrubbing: false,
              colors: const VideoProgressColors(
                playedColor: Colors.white,
                bufferedColor: Colors.white38,
                backgroundColor: Colors.white12,
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
  final VoidCallback onCompleted;

  const _StoryVideoPlayer({required this.objectKey, required this.onCompleted});

  @override
  State<_StoryVideoPlayer> createState() => _StoryVideoPlayerState();
}

class _StoryVideoPlayerState extends State<_StoryVideoPlayer> {
  VideoPlayerController? _controller;
  bool _failed = false;
  bool _completionHandled = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      String url = widget.objectKey;
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
      final controller = VideoPlayerController.networkUrl(Uri.parse(url));
      _controller = controller;
      controller.addListener(_onVideoChanged);
      await controller.initialize();
      if (!mounted) return;
      await controller.setLooping(false);
      await controller.setVolume(1);
      setState(() {});
      await controller.play();
    } catch (e) {
      debugPrint('[STORY] Standalone video initialization failed: $e');
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

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_failed) {
      return const Center(child: Icon(Icons.error_outline_rounded, color: Colors.white, size: 48));
    }
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    return GestureDetector(
      onTap: () {
        if (controller.value.isPlaying) {
          controller.pause();
        } else {
          controller.play();
        }
      },
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
