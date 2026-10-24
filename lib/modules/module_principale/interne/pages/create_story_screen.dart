import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:video_player/video_player.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
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

  bool _commentsEnabled = true;
  bool _sharingEnabled = true;
  String _background = 'sunset';
  String _audience = 'public';
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
        onSelected: (files) {
          if (files.isNotEmpty) {
            setState(() {
              _selectedFiles
                ..clear()
                ..addAll(files.take(1).map((f) => File(f.path)));
            });
          }
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

  Future<void> _openSettings() async {
    final result = await Get.to<Map<String, dynamic>>(
      () => CommunityPostSettingsScreen(
        initialCommentsEnabled: _commentsEnabled,
        initialSharingEnabled: _sharingEnabled,
      ),
    );
    if (result != null) {
      setState(() {
        _commentsEnabled = result['commentsEnabled'] ?? true;
        _sharingEnabled = result['sharingEnabled'] ?? true;
      });
    }
  }

  Future<void> _publish() async {
    if (!_canPublish || _isPublishing) return;
    setState(() => _isPublishing = true);

    try {
      final sharedPost = widget.sharedPost;
      if (sharedPost != null) {
        // Keep the original post linked in the story instead of copying its
        // media file. This preserves video playback and the original post card.
        await HomeFeedRepository().sharePostToStory(
          p_id: const Uuid().v4(),
          p_original_post_id: sharedPost.sharedPostId ?? sharedPost.id,
          p_caption: _textController.text.trim().isNotEmpty
              ? _textController.text.trim()
              : null,
          p_background: _background,
          p_audience: _audience,
        );
        if (!mounted) return;
        Get.back();
        Get.snackbar(
          'Succès',
          'Publication ajoutée à votre story avec succès !',
          snackPosition: SnackPosition.BOTTOM,
        );
        return;
      }

      final storiesController = Get.isRegistered<StoriesController>()
          ? Get.find<StoriesController>()
          : Get.put(StoriesController());
      final selectedFile = _selectedFiles.isNotEmpty ? _selectedFiles.first : null;
      final extension = selectedFile == null ? '' : p.extension(selectedFile.path).toLowerCase();
      final kind = selectedFile == null ? 'text' : ({'.mp4', '.mov'}.contains(extension) ? 'video' : 'image');
      await storiesController.createStory(
        kind: kind,
        content: _textController.text.trim().isNotEmpty ? _textController.text.trim() : null,
        imageFile: selectedFile,
        mentions: _selectedMentionIds,
        allowReshare: _sharingEnabled,
      );
      if (mounted) Get.back();
    } catch (e) {
      Get.snackbar(
        'Erreur',
        e.toString().replaceFirst('Exception: ', ''),
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    } finally {
      if (mounted) setState(() => _isPublishing = false);
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
                                      const UserCertifiedBadge(size: 15),
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

                    // Media preview grid
                    if (widget.sharedPost == null && _selectedFiles.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: SizedBox(
                          height: 120,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: _selectedFiles.length,
                            itemBuilder: (context, index) {
                              final file = _selectedFiles[index];
                              return Stack(
                                children: [
                                  Container(
                                    width: 100,
                                    margin: const EdgeInsets.only(right: 8),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: colorScheme.outlineVariant),
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: _isVideoFile(file)
                                      ? const ColoredBox(
                                          color: Colors.black,
                                          child: Center(
                                            child: Icon(
                                              Icons.play_circle_fill_rounded,
                                              color: Colors.white,
                                              size: 38,
                                            ),
                                          ),
                                        )
                                      : Image.file(file, fit: BoxFit.cover),
                                  ),
                                  Positioned(
                                    top: 4,
                                    right: 12,
                                    child: GestureDetector(
                                      onTap: () => setState(() => _selectedFiles.removeAt(index)),
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: const BoxDecoration(
                                          color: Colors.black54,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(Icons.close, size: 14, color: Colors.white),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
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
                  if (widget.sharedPost != null) ...[
                    const SizedBox(width: 4),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _audience,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Audience',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'public', child: Text('Public')),
                          DropdownMenuItem(value: 'followers', child: Text('Abonnés')),
                          DropdownMenuItem(value: 'friends', child: Text('Amis')),
                        ],
                        onChanged: (value) => setState(() => _audience = value ?? 'public'),
                      ),
                    ),
                  ],
                  IconButton(
                    onPressed: _openSettings,
                    icon: Icon(Icons.settings_outlined, color: colorScheme.primary),
                    tooltip: 'Paramètres',
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


class _SharedPostStoryPreview extends StatelessWidget {
  final CommunityPost post;
  final ColorScheme colorScheme;

  const _SharedPostStoryPreview({
    required this.post,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    final original = post.sharedPost ?? post;
    final media = original.media.isNotEmpty ? original.media.first : null;
    final isVideo = media?.isVideo == true;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.55)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 17,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  child: Icon(Icons.person_outline, size: 19, color: colorScheme.onSurfaceVariant),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    original.authorName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colorScheme.onSurface, fontWeight: FontWeight.w700),
                  ),
                ),
                Icon(Icons.repeat_rounded, size: 18, color: colorScheme.primary),
              ],
            ),
          ),
          if (original.content.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Text(
                original.content,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colorScheme.onSurface, height: 1.35),
              ),
            ),
          if (media != null)
            SizedBox(
              height: 190,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (media.thumbnailUrl != null && media.thumbnailUrl!.isNotEmpty)
                    AppCachedImage(imageUrl: media.thumbnailUrl!, fit: BoxFit.cover)
                  else if (!isVideo && media.url.isNotEmpty)
                    AppCachedImage(imageUrl: media.url, fit: BoxFit.cover)
                  else
                    ColoredBox(color: Colors.black87),
                  if (isVideo)
                    const Center(
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 32),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(isVideo ? Icons.videocam_outlined : Icons.article_outlined, size: 16, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  isVideo ? 'Publication vidéo' : 'Publication partagée',
                  style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
