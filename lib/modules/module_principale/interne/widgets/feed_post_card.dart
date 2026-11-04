import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:scrole/app/theme/app_colors.dart';
import 'package:share_plus/share_plus.dart';
import 'package:scrole/modules/module_communautes/externe/repositories/community_repository.dart';
import 'package:scrole/shared/utils/number_formatter.dart';
import 'package:scrole/shared/widgets/app_cached_image.dart';
import 'package:scrole/shared/widgets/linkified_text.dart';
import 'package:scrole/shared/widgets/user_certified_badge.dart';
import 'package:scrole/shared/widgets/entity_certified_badge.dart';
import 'package:scrole/modules/module_authentification/centre/services/auth_service.dart';
import 'package:scrole/app/routes/app_pages.dart';
import '../../centre/models/community_post.dart';
import '../../../../modules/module_communautes/interne/controllers/community/community_feed_controller.dart';
import '../../../../shared/widgets/post_media_slider.dart';
import '../../../../modules/module_communautes/interne/widgets/community/poll_card_widget.dart';
import '../controllers/home_feed_controller.dart';
import '../../externe/repositories/home_feed_repository.dart';
import '../pages/create_story_screen.dart';
import '../../../module_communautes/interne/pages/create_community_post_screen.dart';

/// Composant de texte extensible avec bouton "Voir plus" / "Voir moins"
class ExpandableTextWidget extends StatefulWidget {
  final String text;
  final int maxLines;
  final TextStyle? style;
  final ValueChanged<String>? onHashtagTap;

  const ExpandableTextWidget({
    super.key,
    required this.text,
    this.maxLines = 2,
    this.style,
    this.onHashtagTap,
  });

  @override
  State<ExpandableTextWidget> createState() => _ExpandableTextWidgetState();
}

class _ExpandableTextWidgetState extends State<ExpandableTextWidget> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final defaultStyle =
        widget.style ??
        TextStyle(fontSize: 14, color: colorScheme.onSurface, height: 1.4);

    return LayoutBuilder(
      builder: (context, constraints) {
        final textSpan = TextSpan(text: widget.text, style: defaultStyle);
        final tp = TextPainter(
          text: textSpan,
          maxLines: widget.maxLines,
          textDirection: TextDirection.ltr,
        );
        tp.layout(maxWidth: constraints.maxWidth);

        final isOverflowing = tp.didExceedMaxLines;

        if (!isOverflowing) {
          return LinkifiedText(text: widget.text, style: defaultStyle, onHashtagTap: widget.onHashtagTap);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () => setState(() => _isExpanded = !_isExpanded),
              child: LinkifiedText(
                text: widget.text,
                maxLines: _isExpanded ? null : widget.maxLines,
                overflow: _isExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                style: defaultStyle,
                onHashtagTap: widget.onHashtagTap,
              ),
            ),
            const SizedBox(height: 4),
            GestureDetector(
              onTap: () => setState(() => _isExpanded = !_isExpanded),
              child: Text(
                _isExpanded ? 'post_see_less'.tr : 'post_see_more'.tr,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class FeedPostCard extends StatelessWidget {
  final CommunityPost post;
  final ValueChanged<PostReaction> onReactionTap;
  final VoidCallback onCommentTap;
  final VoidCallback? onShareTap;
  final VoidCallback? onMoreTap;
  final VoidCallback? onHidePost;
  final VoidCallback? onJoinCommunity;
  final VoidCallback? onRetryPublishing;
  final String? currentCommunityId;
  /// Enables inline video autoplay when this card is embedded in a story.
  final bool autoplayVideos;

  const FeedPostCard({
    super.key,
    required this.post,
    required this.onReactionTap,
    required this.onCommentTap,
    this.onShareTap,
    this.onMoreTap,
    this.onHidePost,
    this.onJoinCommunity,
    this.onRetryPublishing,
    this.currentCommunityId,
    this.autoplayVideos = false,
  });

  @override
  Widget build(BuildContext context) {
    if (post.sharedPostId != null || post.sharedPost != null) {
      return _RepublicationPostCard(
        post: post,
        onReactionTap: onReactionTap,
        onCommentTap: onCommentTap,
        onShareTap: onShareTap,
        onMoreTap: onMoreTap,
        onHidePost: onHidePost,
        currentCommunityId: currentCommunityId,
        autoplayVideos: autoplayVideos,
      );
    }

    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final username = post.authorObj?.username ?? '';
    final screenWidth = MediaQuery.sizeOf(context).width;
    final cardHorizontalPadding = screenWidth < 360 ? 10.0 : (screenWidth < 600 ? 14.0 : 18.0);
    final hasCommunity =
        post.communityId != null && post.communityId!.isNotEmpty;
    final isInsideOwnCommunityFeed =
        currentCommunityId != null && currentCommunityId == post.communityId;
    final showCommunityHeader = hasCommunity && !isInsideOwnCommunityFeed;

    return Opacity(
      opacity: post.isPublishing ? 0.65 : 1.0,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.32),
            width: 0.8,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: Theme.of(context).brightness == Brightness.dark ? 0.12 : 0.035,
              ),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
              padding: EdgeInsets.symmetric(horizontal: cardHorizontalPadding, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. En-tête de la communauté si présente et hors du fil propre de cette communauté
                  if (showCommunityHeader) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                            ClipOval(
                              child:
                                  post.communityLogoUrl != null &&
                                      post.communityLogoUrl!.isNotEmpty
                                  ? AppCachedImage(
                                      imageUrl: post.communityLogoUrl!,
                                      width: 22,
                                      height: 22,
                                      fit: BoxFit.cover,
                                    )
                                  : Container(
                                      width: 22,
                                      height: 22,
                                      decoration: BoxDecoration(
                                        color: colorScheme.primary.withValues(
                                          alpha: 0.15,
                                        ),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        Icons.groups_rounded,
                                        size: 14,
                                        color: colorScheme.primary,
                                      ),
                                    ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      post.communityName ?? 'Communauté',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.onSurface,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (post.communityId != null && post.communityId!.isNotEmpty)
                                    EntityCertifiedBadge(
                                      entityType: 'community',
                                      entityId: post.communityId!,
                                      size: 15,
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],

                  // 2. Ligne Auteur + Contenu de la carte
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Avatar de l'auteur
                      GestureDetector(
                        onTap: () => _onAuthorTap(post),
                        child: ClipOval(
                          child:
                              (post.authorObj?.photoUrl != null &&
                                  post.authorObj!.photoUrl!.isNotEmpty)
                              ? AppCachedImage(
                                  imageUrl: post.authorObj!.photoUrl!,
                                  width: 40,
                                  height: 40,
                                  fit: BoxFit.cover,
                                )
                              : Container(
                                  width: 40,
                                  height: 40,
                                  color: post.authorColor.withValues(
                                    alpha: 0.2,
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    post.authorName.isNotEmpty
                                        ? post.authorName[0].toUpperCase()
                                        : '?',
                                    style: TextStyle(
                                      color: post.authorColor,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Colonne de droite
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // --- En-tête : Auteur, Pseudo, Badge & Temps ---
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => _onAuthorTap(post),
                                    child: Wrap(
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      spacing: 4,                                      runSpacing: 2,
                                      children: [
                                        Text(
                                          post.authorName,
                                          style: textTheme.bodyLarge?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14.5,
                                            color: colorScheme.onSurface,
                                          ),
                                        ),
                                        if (username.isNotEmpty)
                                          Text(
                                            '@$username',
                                            style: TextStyle(
                                              fontWeight: FontWeight.normal,
                                              fontSize: 13,
                                              color:
                                                  colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                        if (post.authorObj?.isCertified == true)
                                          UserCertifiedBadge(size: 14, userId: post.authorObj?.userId),
                                        Text(
                                          '· ${_formatShortTime(post.timeAgo)}',
                                          style: TextStyle(
                                            fontWeight: FontWeight.normal,
                                            fontSize: 12.5,
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                InkWell(
                                  borderRadius: BorderRadius.circular(20),
                                  onTap: post.isPublishing
                                      ? null
                                      : (onMoreTap ??
                                            () => _showPostOptions(
                                              context,
                                              post,
                                            )),
                                  child: Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: Icon(
                                      Icons.more_vert_rounded,
                                      size: 20,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            // --- Suggéré badge & Rejoindre button si isSuggested ---
                            if (post.isSuggested) ...[
                              const SizedBox(height: 6),
                              Wrap(
                                alignment: WrapAlignment.spaceBetween,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                runSpacing: 4,
                                spacing: 8,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: colorScheme.primary.withValues(
                                        alpha: 0.12,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      'home_feed_suggested'.tr,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.primary,
                                      ),
                                    ),
                                  ),
                                  if (hasCommunity)
                                    TextButton.icon(
                                      onPressed: onJoinCommunity ??
                                          () => _onCommunityTap(post.communityId!),
                                      icon: const Icon(
                                        Icons.group_add_rounded,
                                        size: 16,
                                      ),
                                      label: Text(
                                        'home_feed_join_community'.tr,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      style: TextButton.styleFrom(
                                        visualDensity: VisualDensity.compact,
                                        foregroundColor: colorScheme.primary,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 6,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],

                            // --- Texte de la publication ---
                            if (post.content.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              ExpandableTextWidget(
                                text: post.content,
                                maxLines: 2,
                                onHashtagTap: (tag) => Get.toNamed(AppPages.hashtagFeedPath(tag)),
                                style: textTheme.bodyMedium?.copyWith(
                                  fontSize: 14.5,
                                  height: 1.45,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                            ],

                            // --- Hashtags en bleu ---
                            if (post.hashtags.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: post.hashtags
                                    .map(
                                      (h) => InkWell(
                                        onTap: () => Get.toNamed(AppPages.hashtagFeedPath(h.name)),
                                        borderRadius: BorderRadius.circular(4),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 2),
                                          child: Text(
                                            '#${h.name}',
                                            style: TextStyle(
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.w600,
                                              color: colorScheme.primary,
                                            ),
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ],

                            // --- Zone Médias avec indicateur 1/3 et badge influenceurs ---
                            if (post.media.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(14),
                                    child: PostMediaSlider(
                                      heroTagPrefix: 'post_${post.id}',
                                      forceAutoplayVideos: autoplayVideos,
                                      media: post.media,
                                      likesCount: post.likeCount,
                                      dislikesCount: post.dislikeCount,
                                      viewsCount: post.viewCount,
                                      commentsCount: post.commentCount,
                                      sharesCount: post.shareCount,
                                    ),
                                  ),
                                  if (post.influencerReactions != null &&
                                      post.influencerReactions!.isNotEmpty)
                                    Positioned(
                                      bottom: 10,
                                      left: 10,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(
                                            alpha: 0.75,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                        ),
                                        child: _OverlappingAvatars(
                                          users: post.influencerReactions!,
                                          onTap: () =>
                                              _showUsersListBottomSheet(
                                                context,
                                                'Personnes ayant réagi',
                                                post.influencerReactions!,
                                              ),
                                          size: 22,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],

                            // --- Personnes mentionnées avant les boutons de réaction ---
                            if (post.mentionedUsers != null &&
                                post.mentionedUsers!.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              GestureDetector(
                                onTap: () => _showUsersListBottomSheet(
                                  context,
                                  'Personnes mentionnées',
                                  post.mentionedUsers!,
                                ),
                                child: Row(
                                  children: [
                                    _OverlappingAvatars(
                                      users: post.mentionedUsers!,
                                      onTap: () => _showUsersListBottomSheet(
                                        context,
                                        'Personnes mentionnées',
                                        post.mentionedUsers!,
                                      ),
                                      size: 24,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Avec ${post.mentionedUsers!.map((m) => '@${m.username}').join(', ')}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],

                            // --- Zone Poll / Sondage ---
                            if (post.poll != null) ...[
                              const SizedBox(height: 10),
                              PollCardWidget(
                                poll: post.poll!,
                                postId: post.id,
                                controller: null,
                              ),
                            ],

                            const SizedBox(height: 12),

                            // --- Barre de boutons d'action / interactions ---
                            _ReactionButtonsBar(
                              post: post,
                              onReactionTap: onReactionTap,
                              onCommentTap: onCommentTap,
                              onShareTap:
                                  onShareTap ??
                                  () => _showShareSheet(context, post),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ),
    );
  }

  void _showPostOptions(BuildContext context, CommunityPost post) {
    debugPrint(
      '[COMMUNITY_POST_DELETE][UI] Options menu opened for post=${post.id}',
    );
    final currentUserId = Get.isRegistered<AuthService>()
        ? Get.find<AuthService>().userId
        : null;
    final isAuthor =
        currentUserId != null && currentUserId == post.authorObj?.userId;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.visibility_off_rounded),
              title: Text('wall_hide_post'.tr),              onTap: () {
                Navigator.of(context).pop();
                if (onHidePost != null) {
                  onHidePost!();
                } else {
                  try {
                    Get.find<HomeFeedController>().hidePost(post.id);
                  } catch (_) {}
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: Text('home_feed_report_post'.tr),
              onTap: () {
                Navigator.of(context).pop();
                _showReportPostSheet(context, post);
              },
            ),
            if (isAuthor)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text(
                  'Supprimer la publication',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  _confirmDeletePost(context, post);
                },
              ),
          ],
        ),
      ),
    );
  }

  String _reportReasonLabel(Map<String, dynamic> reason) {
    final code = (reason['code'] ?? '').toString().toLowerCase();
    final key = switch (code) {
      'arnaque_fraude' => 'report_post_reason_scam',
      'dangereux_risqué' || 'dangereux_risque' => 'report_post_reason_dangerous',
      'copie_contrefacon' => 'report_post_reason_copyright',
      'harcelement' => 'report_post_reason_harassment',
      'spam' || 'spam_publicite' => 'report_post_reason_spam',
      'faux_profil' || 'usurpation' => 'report_post_reason_fake',
      'contenu_inapproprie' => 'report_post_reason_inappropriate',
      'autre' => 'report_post_reason_other',
      _ => '',
    };
    return key.isEmpty ? (reason['nom'] ?? '').toString() : key.tr;
  }

  Future<void> _showReportPostSheet(BuildContext context, CommunityPost post) async {
    final messenger = ScaffoldMessenger.of(context);
    List<Map<String, dynamic>> reasons;
    try {
      final response = await Supabase.instance.client
          .from('signalement_raison')
          .select('id, nom, code, description')
          .eq('est_actif', true)
          .order('nom');
      reasons = (response as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      if (reasons.isEmpty) throw Exception('no_report_reasons');
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('report_post_error'.tr)));
      debugPrint('[REPORT_POST] Failed to load reasons: $e');
      return;
    }
    if (!context.mounted) return;

    String? selectedReasonId;
    final detailsController = TextEditingController();
    bool submitting = false;
    String? inlineError;
    final colorScheme = Theme.of(context).colorScheme;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          Future<void> submit() async {
            if (submitting) return;
            if (selectedReasonId == null) {
              setSheetState(() => inlineError = 'report_post_reason_required'.tr);
              return;
            }
            setSheetState(() {
              submitting = true;
              inlineError = null;
            });
            try {
              await Supabase.instance.client.rpc('report_content', params: {
                'p_target_type': 'post',
                'p_target_id': post.id,
                'p_reason_id': selectedReasonId,
                'p_description': detailsController.text.trim().isEmpty
                    ? null
                    : detailsController.text.trim(),
              });
              if (!sheetContext.mounted) return;
              Navigator.of(sheetContext).pop();
              messenger.showSnackBar(
                SnackBar(content: Text('report_post_success'.tr)),
              );
            } catch (e) {
              debugPrint('[REPORT_POST] Failed to submit post=${post.id}: $e');
              if (sheetContext.mounted) {
                setSheetState(() {
                  submitting = false;
                  inlineError = 'report_post_error'.tr;
                });
              }
            }
          }

          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 12,
              bottom: MediaQuery.viewInsetsOf(sheetContext).bottom + 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'report_post_title'.tr,
                          style: TextStyle(
                            color: colorScheme.onSurface,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: submitting ? null : submit,
                        child: Text(
                          'report_post_submit'.tr,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: submitting
                                ? colorScheme.onSurfaceVariant
                                : colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    'report_post_hint'.tr,
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...reasons.map((reason) {
                    final id = reason['id']?.toString() ?? '';
                    final selected = selectedReasonId == id;
                    return RadioListTile<String>(
                      value: id,
                      groupValue: selectedReasonId,
                      onChanged: submitting
                          ? null
                          : (value) => setSheetState(() {
                                selectedReasonId = value;
                                inlineError = null;
                              }),
                      title: Text(
                        _reportReasonLabel(reason),
                        style: TextStyle(
                          fontSize: 14,
                          color: colorScheme.onSurface,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                      activeColor: colorScheme.primary,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    );
                  }),
                  const SizedBox(height: 8),
                  TextField(
                    controller: detailsController,
                    maxLength: 1000,
                    maxLines: 3,
                    minLines: 2,
                    enabled: !submitting,
                    decoration: InputDecoration(
                      hintText: 'report_post_description_hint'.tr,
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  if (inlineError != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      inlineError!,
                      style: TextStyle(color: colorScheme.error, fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 8),
                ],
              ),
            ),
          );
        },
      ),
    );
    // showModalBottomSheet completes as soon as pop is requested, while its
    // reverse transition may still rebuild the TextField for a few frames.
    // Disposing the controller immediately causes "used after being disposed"
    // during that closing animation. Dispose after the route transition settles.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    detailsController.dispose();
  }

  void _confirmDeletePost(BuildContext context, CommunityPost post) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer la publication'),
        content: const Text(
          'Êtes-vous sûr de vouloir supprimer cette publication ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              try {
                if (Get.isRegistered<HomeFeedController>()) {
                  Get.find<HomeFeedController>().deletePost(post.id);
                } else if (Get.isRegistered<CommunityFeedController>()) {
                  Get.find<CommunityFeedController>().deletePost(post.id);
                } else {
                  CommunityFeedController? commCtrl;
                  try {
                    commCtrl = Get.find<CommunityFeedController>(
                      tag: post.communityId,
                    );
                  } catch (_) {
                    commCtrl = Get.find<CommunityFeedController>();
                  }
                  commCtrl?.deletePost(post.id);
                }
              } catch (e) {
                debugPrint('[DELETE] Error deleting post: $e');
              }
            },
            child: const Text('Supprimer', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _onAuthorTap(CommunityPost post) {
    final authorUserId = post.authorObj?.userId;
    if (authorUserId == null || authorUserId.isEmpty) return;
    final currentUserId = Get.isRegistered<AuthService>()
        ? Get.find<AuthService>().userId
        : null;
    if (authorUserId != currentUserId) {
      Get.toNamed(AppPages.externalProfilePath(authorUserId));
    }
  }
  void _onCommunityTap(String communityId) {
    if (communityId.isNotEmpty) {
      Get.toNamed(AppPages.communityDetailPath(communityId));
    }
  }

  void _showShareSheet(BuildContext context, CommunityPost post) {
    if (!post.sharingEnabled) {
      Get.snackbar(
        'Partage',
        'Le partage est désactivé sur ce post',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ShareSheetWidget(post: post),
    );
  }

  void _showUsersListBottomSheet(
    BuildContext context,
    String title,
    List<CommunityPostMention> users,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.4,
        minChildSize: 0.3,
        maxChildSize: 0.8,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: users.length,
                itemBuilder: (context, index) {
                  final u = users[index];
                  return ListTile(
                    leading: ClipOval(
                      child: u.photoUrl != null && u.photoUrl!.isNotEmpty
                          ? AppCachedImage(
                              imageUrl: u.photoUrl!,
                              width: 44,
                              height: 44,
                              fit: BoxFit.cover,
                            )
                          : Container(
                              width: 44,
                              height: 44,
                              color: colorScheme.primary.withValues(alpha: 0.2),
                              alignment: Alignment.center,
                              child: Text(
                                u.username.isNotEmpty
                                    ? u.username[0].toUpperCase()
                                    : '?',
                                style: TextStyle(
                                  color: colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                    ),
                    title: Row(
                      children: [
                        Flexible(
                          child: Text(
                            '@${u.username}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ),
                        if (u.isCertified) ...[
                          const SizedBox(width: 6),
                          UserCertifiedBadge(size: 14, userId: u.userId),
                        ],
                      ],
                    ),
                    trailing: Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 16,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    onTap: () {
                      Navigator.of(context).pop();
                      if (u.userId.isNotEmpty) {
                        Get.toNamed(AppPages.externalProfilePath(u.userId));
                      }
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OverlappingAvatars extends StatelessWidget {
  final List<CommunityPostMention> users;
  final VoidCallback onTap;
  final double size;

  const _OverlappingAvatars({
    required this.users,
    required this.onTap,
    this.size = 24,
  });

  @override
  Widget build(BuildContext context) {
    if (users.isEmpty) return const SizedBox.shrink();

    final displayUsers = users.take(3).toList();
    final extraCount = users.length - 3;

    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: size,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(displayUsers.length, (idx) {
                final u = displayUsers[idx];
                return Align(
                  widthFactor: 0.7,
                  child: ClipOval(
                    child: Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      child: u.photoUrl != null && u.photoUrl!.isNotEmpty
                          ? AppCachedImage(
                              imageUrl: u.photoUrl!,
                              width: size,
                              height: size,
                              fit: BoxFit.cover,
                            )
                          : Container(
                              color: Colors.grey,
                              alignment: Alignment.center,
                              child: Text(
                                u.username.isNotEmpty
                                    ? u.username[0].toUpperCase()
                                    : '?',
                                style: TextStyle(
                                  fontSize: size * 0.4,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                    ),
                  ),
                );
              }),
            ),
          ),
          if (extraCount > 0) ...[
            const SizedBox(width: 4),
            Text(
              '+$extraCount',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReactionButtonsBar extends StatefulWidget {
  final CommunityPost post;
  final ValueChanged<PostReaction> onReactionTap;
  final VoidCallback onCommentTap;
  final VoidCallback onShareTap;

  const _ReactionButtonsBar({
    required this.post,
    required this.onReactionTap,
    required this.onCommentTap,
    required this.onShareTap,
  });

  @override
  State<_ReactionButtonsBar> createState() => _ReactionButtonsBarState();
}

class _ReactionButtonsBarState extends State<_ReactionButtonsBar> {
  late PostReaction _userReaction;
  late int _likeCount;
  late int _dislikeCount;

  @override
  void initState() {
    super.initState();
    _userReaction = widget.post.userReaction;
    _likeCount = widget.post.likeCount;
    _dislikeCount = widget.post.dislikeCount;
  }

  @override
  void didUpdateWidget(covariant _ReactionButtonsBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.post.userReaction != oldWidget.post.userReaction) {
      _userReaction = widget.post.userReaction;
    }
    if (widget.post.likeCount != oldWidget.post.likeCount) {
      _likeCount = widget.post.likeCount;
    }
    if (widget.post.dislikeCount != oldWidget.post.dislikeCount) {
      _dislikeCount = widget.post.dislikeCount;
    }
  }

  void _handleReaction(PostReaction reaction) {
    setState(() {
      if (_userReaction == reaction) {
        if (reaction == PostReaction.like) {
          _likeCount = (_likeCount > 0) ? _likeCount - 1 : 0;
        } else if (reaction == PostReaction.dislike) {
          _dislikeCount = (_dislikeCount > 0) ? _dislikeCount - 1 : 0;
        }
        _userReaction = PostReaction.none;
      } else {
        if (_userReaction == PostReaction.like) {
          _likeCount = (_likeCount > 0) ? _likeCount - 1 : 0;
        } else if (_userReaction == PostReaction.dislike) {
          _dislikeCount = (_dislikeCount > 0) ? _dislikeCount - 1 : 0;
        }

        if (reaction == PostReaction.like) {
          _likeCount++;
        } else if (reaction == PostReaction.dislike) {
          _dislikeCount++;
        }
        _userReaction = reaction;
      }
    });
    widget.onReactionTap(reaction);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [        // Left Block: Like, Dislike, Comment
        Expanded(
          child: Row(
            mainAxisSize: MainAxisSize.min,
          children: [
            // 1. Upvote / Like
            InkWell(
              onTap: widget.post.isPublishing
                  ? null
                  : () => _handleReaction(PostReaction.like),
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.north_rounded,
                      size: 18,
                      color: _userReaction == PostReaction.like
                          ? AppColors.primary
                          : colorScheme.onSurfaceVariant,
                    ),
                    if (_likeCount > 0) ...[
                      const SizedBox(width: 4),
                      Text(
                        NumberFormatter.formatCount(_likeCount),
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: _userReaction == PostReaction.like
                              ? FontWeight.bold
                              : FontWeight.w500,
                          color: _userReaction == PostReaction.like
                              ? AppColors.primary
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),

            // 2. Downvote / Dislike
            InkWell(
              onTap: widget.post.isPublishing
                  ? null
                  : () => _handleReaction(PostReaction.dislike),
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.south_rounded,
                      size: 18,
                      color: _userReaction == PostReaction.dislike
                          ? Colors.orangeAccent
                          : colorScheme.onSurfaceVariant,
                    ),
                    if (_dislikeCount > 0) ...[
                      const SizedBox(width: 4),
                      Text(
                        NumberFormatter.formatCount(_dislikeCount),
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: _userReaction == PostReaction.dislike
                              ? FontWeight.bold
                              : FontWeight.w500,
                          color: _userReaction == PostReaction.dislike
                              ? Colors.orangeAccent
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),

            // 3. Commenter
            InkWell(
              onTap: widget.post.isPublishing ? null : widget.onCommentTap,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 17,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    if (widget.post.commentCount > 0) ...[
                      const SizedBox(width: 4),
                      Text(
                        NumberFormatter.formatCount(widget.post.commentCount),
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
          ),
        ),

        // Right Block: Views, Share, pinned to the right edge
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 4. Vues (compteur de vues)
            InkWell(
              onTap: () {},
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.bar_chart_outlined,
                      size: 18,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    if (widget.post.viewCount > 0) ...[
                      const SizedBox(width: 4),
                      Text(
                        NumberFormatter.formatCount(widget.post.viewCount),
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),

            // 5. Partager (avec compteur)
            InkWell(
              onTap: widget.post.isPublishing ? null : widget.onShareTap,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.ios_share_rounded,
                      size: 18,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    if (widget.post.shareCount > 0) ...[
                      const SizedBox(width: 4),
                      Text(
                        NumberFormatter.formatCount(widget.post.shareCount),
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

String _formatShortTime(String raw) {
  if (raw.isEmpty) return '';
  String trCount(String key, int count) => key.trParams({'count': '$count'});
  final dt = DateTime.tryParse(raw);
  if (dt != null) {
    final difference = DateTime.now().difference(dt);
    if (difference.isNegative || difference.inSeconds < 60) return 'relative_just_now'.tr;
    if (difference.inMinutes < 60) return trCount('relative_minutes_ago', difference.inMinutes);
    if (difference.inHours < 24) return trCount('relative_hours_ago', difference.inHours);
    if (difference.inDays < 7) return difference.inDays == 1 ? 'relative_one_day_ago'.tr : trCount('relative_days_ago', difference.inDays);
    if (difference.inDays < 30) { final weeks = (difference.inDays / 7).floor(); return weeks == 1 ? 'relative_one_week_ago'.tr : trCount('relative_weeks_ago', weeks); }
    if (difference.inDays < 365) { final months = (difference.inDays / 30).floor(); return months == 1 ? 'relative_one_month_ago'.tr : trCount('relative_months_ago', months); }
    final years = (difference.inDays / 365).floor();
    return years == 1 ? 'relative_one_year_ago'.tr : trCount('relative_years_ago', years);
  }
  final lower = raw.toLowerCase().trim();
  if (lower.contains('instant') || lower.contains('maintenant') || lower.contains('now') || lower.contains('just')) return 'relative_just_now'.tr;
  final digits = lower.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isNotEmpty) {
    final val = int.tryParse(digits) ?? 1;
    if (lower.contains('min') || (lower.contains('m') && !lower.contains('mo') && !lower.contains('mai'))) return trCount('relative_minutes_ago', val);
    if (lower.contains('heure') || lower.contains('hour') || lower.contains(' h')) return trCount('relative_hours_ago', val);
    if (lower.contains('jour') || lower.contains('day') || lower.endsWith('j')) return val == 1 ? 'relative_one_day_ago'.tr : trCount('relative_days_ago', val);
    if (lower.contains('semaine') || lower.contains('week') || lower.contains('sem')) return val == 1 ? 'relative_one_week_ago'.tr : trCount('relative_weeks_ago', val);
    if (lower.contains('mois') || lower.contains('month')) return val == 1 ? 'relative_one_month_ago'.tr : trCount('relative_months_ago', val);
    if (lower.contains('an') || lower.contains('year')) return val == 1 ? 'relative_one_year_ago'.tr : trCount('relative_years_ago', val);
  }
  return raw;
}

class _ShareSheetWidget extends StatelessWidget {
  final CommunityPost post;
  const _ShareSheetWidget({required this.post});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.of(context).padding.bottom + 24,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
          const Text(
            'Partager la publication',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),

          // Compact Post Preview
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.35,
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                if (post.media.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: AppCachedImage(
                      imageUrl: post.media.first.url ?? '',
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                    ),
                  ),
                if (post.media.isNotEmpty) const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        post.authorName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        post.content.isNotEmpty
                            ? post.content
                            : 'post_media_placeholder'.tr,
                        style: TextStyle(