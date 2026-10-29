import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:scrole/shared/widgets/video_trim_screen.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:scrole/app/theme/app_colors.dart';
import 'package:scrole/app/theme/text_styles.dart';
import 'package:scrole/app_controller.dart';
import 'package:scrole/shared/widgets/app_cached_image.dart';
import 'package:scrole/shared/widgets/user_certified_badge.dart';
import 'package:scrole/shared/widgets/media_gallery_sheet.dart';
import 'package:scrole/modules/module_communautes/interne/pages/community_post_mentions_screen.dart';
import 'package:scrole/modules/module_communautes/interne/pages/community_post_settings_screen.dart';
import 'package:scrole/modules/module_principale/interne/controllers/stories_controller.dart';
import 'package:scrole/modules/module_principale/centre/models/community_post.dart';
import 'package:scrole/modules/module_principale/externe/repositories/home_feed_repository.dart';
import 'package:scrole/modules/module_principale/interne/widgets/feed_post_card.dart';

class CreateStoryScreen extends StatefulWidget {
  final String? prefilledText;
  final String? prefilledMediaUrl;
  final CommunityPost? sharedPost;

  const CreateStoryScreen({
    super.key,
    this.prefilledText,
    this.prefilledMediaUrl,
    this.sharedPost,
  });

  @override
  State<CreateStoryScreen> createState() => _CreateStoryScreenState();
}

class _CreateStoryScreenState extends State<CreateStoryScreen> {
  final TextEditingController _textController = TextEditingController();
  final List<File> _selectedFiles = [];
  bool _isPublishing = false;
  static const Duration _maxVideoDuration = Duration(seconds: 30);

  bool _commentsEnabled = true;
  bool _sharingEnabled = true;
  String _background = 'sunset';
  List<Map<String, dynamic>> _selectedMentions = [];
  List<String> _selectedMentionIds = [];

  @override
  void initState() {
    super.initState();
    if (widget.prefilledText != null && widget.prefilledText!.isNotEmpty) {
      _textController.text = widget.prefilledText!;
    }
    if (widget.prefilledMediaUrl != null && widget.prefilledMediaUrl!.isNotEmpty) {
      if (!widget.prefilledMediaUrl!.startsWith('http')) {
        final file = File(widget.prefilledMediaUrl!);
        if (file.existsSync()) {
          _selectedFiles.add(file);
        }
      }
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  bool get _canPublish =>
      widget.sharedPost != null ||
      _textController.text.trim().isNotEmpty ||
      _selectedFiles.isNotEmpty;

  bool _isVideoFile(File file) =>
      const {'.mp4', '.mov'}.contains(p.extension(file.path).toLowerCase());

  Future<void> _openMediaPicker() async {
    final maxAllowed = 1;
    if (maxAllowed <= 0) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MediaGallerySheet(
        maxSelection: maxAllowed,
        onSelected: (files) async {
          if (files.isEmpty) return;

          final file = File(files.first.path);
          var selectedFile = file;
          if (_isVideoFile(selectedFile)) {
            try {
              final controller = VideoPlayerController.file(selectedFile);
              Duration duration;
              try {
                await controller.initialize();
                duration = controller.value.duration;
                if (duration <= Duration.zero) {
                  throw StateError('Impossible de déterminer la durée de cette vidéo.');
                }
              } finally {
                await controller.dispose();
              }

              // Same trimming flow as post creation: long videos are not
              // rejected outright; the user chooses a segment of <= 29 sec.
              const maxStoryVideoDuration = Duration(seconds: 29);
              if (duration > maxStoryVideoDuration) {
                final trimmed = await Get.to<File>(
                  () => VideoTrimScreen(
                    videoFile: selectedFile,
                    maxDuration: maxStoryVideoDuration,
                  ),
                );
                if (trimmed == null || !mounted) return;
                selectedFile = trimmed;

                final verify = VideoPlayerController.file(selectedFile);
                try {
                  await verify.initialize();
                  if (verify.value.duration <= Duration.zero ||
                      verify.value.duration > maxStoryVideoDuration) {
                    Get.snackbar(
                      'post_composer_attention'.tr,
                      'post_composer_trim_invalid'.tr,
                      snackPosition: SnackPosition.BOTTOM,
                      backgroundColor: Colors.black87,
                      colorText: Colors.white,
                    );
                    return;
                  }
                } finally {
                  await verify.dispose();
                }
              }
            } catch (e) {
              Get.snackbar(
                'post_composer_video_invalid_title'.tr,
                'post_composer_video_invalid_message'.tr,
                snackPosition: SnackPosition.BOTTOM,
                backgroundColor: Colors.black87,
                colorText: Colors.white,
              );
              debugPrint('[STORY] Invalid selected video: $e');
              return;
            }
          }

          if (!mounted) return;
          setState(() {
            _selectedFiles
              ..clear()
              ..add(selectedFile);
          });
        },
      ),
    );
  }

  Future<void> _openMentions() async {
    final result = await Get.to<List<Map<String, dynamic>>>(
      () => const CommunityPostMentionsScreen(),
      arguments: {'initialSelected': _selectedMentionIds},
    );
    if (result != null) {
      setState(() {
        _selectedMentions = result;
        _selectedMentionIds = result.map((m) => (m['user_id'] ?? m['id'] ?? '').toString()).toList();
      });
    }
  }


  Future<void> _publish() async {
    if (!_canPublish || _isPublishing) return;

    final sharedPost = widget.sharedPost;
    final caption = _textController.text.trim();
    final selectedFile = _selectedFiles.isNotEmpty ? _selectedFiles.first : null;
    final mentions = List<String>.from(_selectedMentionIds);
    final allowReshare = _sharingEnabled;
    final background = _background;
    final storiesController = Get.isRegistered<StoriesController>()
        ? Get.find<StoriesController>()
        : Get.put(StoriesController());

    if (storiesController.isPublishingStory.value) return;

    setState(() => _isPublishing = true);
    storiesController.isPublishingStory.value = true;

    // Close the composer immediately. The upload continues in the controller
    // while the user's own story avatar displays a rotating progress ring.
    Get.back();
    unawaited(_publishInBackground(
      storiesController: storiesController,
      sharedPost: sharedPost,
      caption: caption,
      selectedFile: selectedFile,
      mentions: mentions,
      allowReshare: allowReshare,
      background: background,
    ));
  }

  Future<void> _publishInBackground({
    required StoriesController storiesController,
    required CommunityPost? sharedPost,
    required String caption,
    required File? selectedFile,
    required List<String> mentions,
    required bool allowReshare,
    required String background,
  }) async {
    try {
      if (sharedPost != null) {
        await HomeFeedRepository().sharePostToStory(
          p_id: const Uuid().v4(),
          p_original_post_id: sharedPost.sharedPostId ?? sharedPost.id,
          p_caption: caption.isNotEmpty ? caption : null,
          p_background: background,
          p_audience: 'followers',
        );
        await storiesController.fetchStories();
        Get.snackbar(
          'Succès',
          'Publication ajoutée à votre story avec succès !',
          snackPosition: SnackPosition.BOTTOM,
        );
        return;
      }

      final extension = selectedFile == null
          ? ''
          : p.extension(selectedFile.path).toLowerCase();
      final kind = selectedFile == null
          ? 'text'
          : ({'.mp4', '.mov'}.contains(extension) ? 'video' : 'image');

      await storiesController.createStory(
        kind: kind,
        content: caption.isNotEmpty ? caption : null,
        imageFile: selectedFile,
        mentions: mentions,
        allowReshare: allowReshare,
      );
    } catch (e) {
      Get.snackbar(
        'Erreur',
        e.toString().replaceFirst('Exception: ', ''),
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    } finally {
      storiesController.isPublishingStory.value = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final appController = Get.find<AppController>();
    final profileRaw = appController.profile.value ?? {};
    final profile = (profileRaw['profile'] is Map)
        ? Map<String, dynamic>.from(profileRaw['profile'] as Map)
        : profileRaw;
    final firstName = profile['first_name']?.toString() ?? profile['prenom']?.toString() ?? '';
    final lastName = profile['last_name']?.toString() ?? profile['nom']?.toString() ?? '';
    final fullName = "$firstName $lastName".trim();
    final username = profile['username']?.toString() ?? '';
    final displayName = fullName.isEmpty ? (username.isEmpty ? 'profile_default_username'.tr : username) : fullName;
    final avatarUrl = profile['photo_url']?.toString() ?? '';
    final isCertified = profile['is_certified'] == true || profile['is_verified'] == true || profile['is_certified'] == 1 || profile['is_verified'] == 1;
    final certificationUserId = Supabase.instance.client.auth.currentUser?.id
        ?? profile['user_id']?.toString()
        ?? profile['id']?.toString();

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        centerTitle: false,
        title: Text(widget.sharedPost == null ? 'Créer une story' : 'Partager en story'),
        titleTextStyle: AppTextStyles.h5.copyWith(color: colorScheme.onSurface),
        leading: IconButton(
          onPressed: () => Get.back(),
          icon: const Icon(Icons.close_rounded, size: 28),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: TextButton(
              onPressed: _canPublish && !_isPublishing ? _publish : null,
              style: TextButton.styleFrom(
                foregroundColor: _canPublish ? colorScheme.primary : colorScheme.outline,
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: _isPublishing
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(
                      'Partager',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: _canPublish ? colorScheme.primary : colorScheme.outline.withValues(alpha: 0.6),
                      ),
                    ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Profil Header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(shape: BoxShape.circle, color: colorScheme.surfaceContainerHighest),
                            child: ClipOval(
                              child: avatarUrl.isNotEmpty
                                  ? AppCachedImage(imageUrl: avatarUrl, width: 44, height: 44, fit: BoxFit.cover)
                                  : Icon(Icons.person, color: colorScheme.onSurfaceVariant),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: RichText(
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        text: TextSpan(
                                          style: AppTextStyles.h6.copyWith(fontWeight: FontWeight.bold, fontSize: 15, color: colorScheme.onSurface),
                                          children: [
                                            TextSpan(text: displayName),
                                            if (username.isNotEmpty)
                                              TextSpan(
                                                text: ' @$username',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.normal,
                                                  fontSize: 13.5,
                                                  color: colorScheme.onSurfaceVariant,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    if (isCertified) ...[
                                      const SizedBox(width: 4),
                                      UserCertifiedBadge(
                                        size: 15,
                                        userId: certificationUserId,
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'Votre Story',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    if (widget.sharedPost != null)
                      _SharedPostStoryPreview(post: widget.sharedPost!, colorScheme: colorScheme),

                    // Champ de texte
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        controller: _textController,
                        autofocus: true,
                        maxLines: null,
                        style: AppTextStyles.bodyXL.copyWith(fontSize: 18, height: 1.4, color: colorScheme.onSurface),
                        decoration: InputDecoration(
                          hintText: 'Ajouter du texte à votre story...',
                          hintStyle: AppTextStyles.bodyXL.copyWith(fontSize: 18, color: colorScheme.outline.withValues(alpha: 0.5)),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          errorBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),

                    // Large media preview: videos can be played before publishing.
                    if (widget.sharedPost == null && _selectedFiles.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        child: Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child: _isVideoFile(_selectedFiles.first)
                                  ? _StoryVideoPreview(file: _selectedFiles.first)
                                  : Image.file(
                                      _selectedFiles.first,
                                      width: double.infinity,
                                      height: 300,
                                      fit: BoxFit.contain,
                                    ),
                            ),
                            Positioned(
                              top: 10,
                              right: 10,
                              child: Material(
                                color: Colors.black54,
                                shape: const CircleBorder(),
                                child: IconButton(
                                  tooltip: 'Retirer le média',
                                  onPressed: () => setState(() => _selectedFiles.clear()),
                                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Bottom action toolbar (Gallery, Mentions, Settings) - NO HASHTAGS
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3))),
                color: colorScheme.surface,
              ),
              child: Row(
                children: [
                  if (widget.sharedPost == null)
                    IconButton(
                    onPressed: _openMediaPicker,
                    icon: Icon(Icons.photo_library_outlined, color: colorScheme.primary),
                    tooltip: 'Ajouter des médias',
                  ),
                  IconButton(
                    onPressed: _openMentions,
                    icon: Icon(Icons.alternate_email_rounded, color: colorScheme.primary),
                    tooltip: 'Mentionner',
                  ),

                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class _StoryVideoPreview extends StatefulWidget {
  final File file;

  const _StoryVideoPreview({required this.file});

  @override
  State<_StoryVideoPreview> createState() => _StoryVideoPreviewState();
}

class _StoryVideoPreviewState extends State<_StoryVideoPreview> {
  late final VideoPlayerController _controller;
  late final Future<void> _initialized;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(widget.file);
    _initialized = _initialize();
  }

  Future<void> _initialize() async {
    await _controller.initialize();
    await _controller.setLooping(true);
    await _controller.setVolume(1);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initialized,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Container(
            height: 280,
            width: double.infinity,
            color: Colors.black,
            alignment: Alignment.center,
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline_rounded, color: Colors.white, size: 32),
                SizedBox(height: 8),
                Text('Impossible de prévisualiser cette vidéo', style: TextStyle(color: Colors.white)),
              ],
            ),
          );
        }
        if (snapshot.connectionState != ConnectionState.done ||
            !_controller.value.isInitialized) {
          return const SizedBox(
            height: 280,
            width: double.infinity,
            child: ColoredBox(
              color: Colors.black,
              child: Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
          );
        }

        final ratio = _controller.value.aspectRatio;
        return GestureDetector(
          onTap: () {
            if (_controller.value.isPlaying) {
              _controller.pause();
            } else {
              _controller.play();
            }
            setState(() {});
          },
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 380),
            color: Colors.black,
            child: AspectRatio(
              aspectRatio: ratio > 0 ? ratio : 9 / 16,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  VideoPlayer(_controller),
                  if (!_controller.value.isPlaying)
                    Container(
                      decoration: const BoxDecoration(
                        color: Colors.black38,
                        shape: BoxShape.circle,
                      ),
                      padding: const EdgeInsets.all(12),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 42,
                      ),
                    ),
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 10,
                    child: VideoProgressIndicator(
                      _controller,
                      allowScrubbing: true,
                      colors: const VideoProgressColors(
                        playedColor: Colors.white,
                        bufferedColor: Colors.white38,
                        backgroundColor: Colors.white24,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SharedPostStoryPreview extends StatelessWidget {
  final CommunityPost post;
  final ColorScheme colorScheme;

  const _SharedPostStoryPreview({
    required this.post,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    // Reuse the exact feed card instead of maintaining a second, divergent
    // design for story reshares. The card is displayed as a preview only:
    // its actions and media are not tappable on the story-creation screen.
    final originalPost = post;

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: IgnorePointer(
          child: FeedPostCard(
            post: originalPost,
            onReactionTap: (_) {},
            onCommentTap: () {},
          ),
        ),
      ),
    );
  }
}
