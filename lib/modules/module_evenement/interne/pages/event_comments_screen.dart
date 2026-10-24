import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:scrole/app/theme/app_colors.dart';
import 'package:scrole/app/theme/text_styles.dart';
import 'package:scrole/shared/widgets/app_cached_image.dart';
import 'package:scrole/shared/widgets/entity_certified_badge.dart';
import '../../centre/models/event_comment.dart';
import '../controllers/event_comments_controller.dart';

String _commentTranslation(String key, String fallback) {
  final translated = key.tr.trim();
  return translated.isEmpty || translated == key ? fallback : translated;
}

/// Écran complet dédié à la consultation et discussion par commentaires d'un événement.
class EventCommentsScreen extends StatefulWidget {
  final String eventId;
  final String? eventName;

  const EventCommentsScreen({
    super.key,
    required this.eventId,
    this.eventName,
  });

  @override
  State<EventCommentsScreen> createState() => _EventCommentsScreenState();
}

class _EventCommentsScreenState extends State<EventCommentsScreen> {
  late final EventCommentsController _controller;
  final ScrollController _scrollController = ScrollController();

  final List<String> _quickReactions = [
    '🔥 Trop hâte !',
    '❤️ J\'adore !',
    '🎉 J\'y serai !',
    '👏 Bravo !',
    '❓ Question',
  ];

  @override
  void initState() {
    super.initState();
    _controller = Get.put(EventCommentsController(), tag: widget.eventId);
    _controller.init(widget.eventId);

    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
        _controller.loadMoreComments(widget.eventId);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _insertQuickReaction(String text) {
    final current = _controller.commentTextController.text;
    if (current.isEmpty) {
      _controller.commentTextController.text = '$text ';
    } else {
      _controller.commentTextController.text = '$current $text ';
    }
    _controller.commentTextController.selection = TextSelection.fromPosition(
      TextPosition(offset: _controller.commentTextController.text.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Get.back(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  _commentTranslation('comments_title', 'Commentaires'),
                  style: GoogleFonts.spaceGrotesk(
                    color: colorScheme.onSurface,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Obx(() => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${_controller.comments.length}',
                        style: GoogleFonts.spaceGrotesk(
                          color: AppColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    )),
              ],
            ),
            if (widget.eventName != null && widget.eventName!.isNotEmpty)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      widget.eventName!,
                      style: AppTextStyles.caption.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  EntityCertifiedBadge(entityType: 'event', entityId: widget.eventId, size: 14),
                ],
              ),
          ],
        ),
      ),
      body: Column(
        children: [
          // ─── LISTE DES COMMENTAIRES ───
          Expanded(
            child: Obx(() {
              final currentState = _controller.state.value;

              if (currentState == EventCommentsState.loading) {
                return const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                );
              }

              if (currentState == EventCommentsState.error) {
                return _CommentsErrorState(
                  errorMessage: _controller.errorMessage.value,
                  onRetry: () => _controller.fetchComments(widget.eventId),
                  colorScheme: colorScheme,
                );
              }

              if (currentState == EventCommentsState.empty || _controller.comments.isEmpty) {
                return _EmptyCommentsState(colorScheme: colorScheme);
              }

              return RefreshIndicator(
                onRefresh: () => _controller.fetchComments(widget.eventId),
                color: AppColors.primary,
                child: ListView.separated(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: _controller.comments.length + (_controller.hasMoreComments.value ? 1 : 0),
                  separatorBuilder: (_, __) => const SizedBox(height: 18),
                  itemBuilder: (context, index) {
                    if (index == _controller.comments.length) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                        ),
                      );
                    }

                    final comment = _controller.comments[index];
                    return _CommentThreadTile(
                      comment: comment,
                      controller: _controller,
                    );
                  },
                ),
              );
            }),
          ),

          // ─── CHIPS DE RÉACTIONS RAPIDES ───
          Container(
            height: 38,
            margin: const EdgeInsets.only(bottom: 6),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _quickReactions.length,
              itemBuilder: (context, index) {
                final reaction = _quickReactions[index];
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    label: Text(
                      reaction,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    backgroundColor: colorScheme.surfaceContainerLow,
                    side: BorderSide(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    onPressed: () => _insertQuickReaction(reaction),
                  ),
                );
              },
            ),
          ),

          // ─── DOCK DE SAISIE ET RÉPONSE ───
          Container(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 10,
              bottom: MediaQuery.of(context).padding.bottom + 12,
            ),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, -4),
                ),
              ],
              border: Border(
                top: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                ),
              ),
            ),
            child: Obx(() {
              final replyingTo = _controller.replyingToComment.value;
              final isSending = _controller.isSending.value;

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (replyingTo != null) ...[
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.reply_rounded, size: 16, color: AppColors.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'En réponse à ${replyingTo.author.displayName}',
                              style: GoogleFonts.spaceGrotesk(
                                color: AppColors.primary,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          InkWell(
                            onTap: _controller.cancelReply,
                            borderRadius: BorderRadius.circular(12),
                            child: const Padding(
                              padding: EdgeInsets.all(4),
                              child: Icon(Icons.close_rounded, size: 16, color: AppColors.primary),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller.commentTextController,
                          focusNode: _controller.commentFocusNode,
                          enabled: !isSending,
                          maxLines: null,
                          textCapitalization: TextCapitalization.sentences,
                          style: GoogleFonts.spaceGrotesk(
                            color: colorScheme.onSurface,
                            fontSize: 14,
                          ),
                          decoration: InputDecoration(
                            hintText: replyingTo != null
                                ? 'Votre réponse...'
                                : _commentTranslation('comments_add_hint', 'Écrire un commentaire…'),
                            hintStyle: GoogleFonts.spaceGrotesk(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 13,
                            ),
                            filled: true,
                            fillColor: colorScheme.surfaceContainerLow,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide(
                                color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: const BorderSide(
                                color: AppColors.primary,
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      isSending
                          ? const SizedBox(
                              width: 42,
                              height: 42,
                              child: Padding(
                                padding: EdgeInsets.all(8),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: AppColors.primary,
                                ),
                              ),
                            )
                          : Container(
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: [
                                    Color(0xFF3B82F6),
                                    AppColors.primary,
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                              child: IconButton(
                                onPressed: () => _controller.sendComment(widget.eventId),
                                icon: const Icon(Icons.send_rounded, size: 20, color: Colors.white),
                                tooltip: 'Envoyer',
                              ),
                            ),
                    ],
                  ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }
}

// =========================================
// ÉTAT VIDE ET ERREUR
// =========================================
class _EmptyCommentsState extends StatelessWidget {
  final ColorScheme colorScheme;

  const _EmptyCommentsState({required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primary.withValues(alpha: 0.18),
                    AppColors.primary.withValues(alpha: 0.05),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.forum_rounded,
                size: 56,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Inaugurez la discussion !',
              style: GoogleFonts.spaceGrotesk(
                color: colorScheme.onSurface,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              _commentTranslation('comments_empty', 'Soyez la première personne à lancer la discussion autour de cet événement.'),
              style: AppTextStyles.body.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _CommentsErrorState extends StatelessWidget {
  final String errorMessage;
  final VoidCallback onRetry;
  final ColorScheme colorScheme;

  const _CommentsErrorState({
    required this.errorMessage,
    required this.onRetry,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wifi_off_rounded, size: 52, color: colorScheme.error),
            const SizedBox(height: 18),
            Text(
              errorMessage.isNotEmpty ? errorMessage : 'Une erreur de connexion est survenue',
              style: GoogleFonts.spaceGrotesk(
                color: colorScheme.onSurface,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Réessayer'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommentThreadTile extends StatelessWidget {
  final EventComment comment;
  final EventCommentsController controller;

  const _CommentThreadTile({
    required this.comment,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final hasReplies = comment.replies.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Commentaire principal
        _CommentBodyCard(
          comment: comment,
          isMain: true,
          onReply: () => controller.setReplyTo(comment),
          onLike: () => controller.toggleCommentLike(comment, isMainComment: true),
        ),

        // Fil de réponses à la demande
        if (comment.areRepliesLoaded && hasReplies) ...[
          Padding(
            padding: const EdgeInsets.only(left: 22, top: 12),
            child: Container(
              padding: const EdgeInsets.only(left: 14),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: AppColors.primary.withValues(alpha: 0.35),
                    width: 2,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...comment.replies.map((reply) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _CommentBodyCard(
                        comment: reply,
                        isMain: false,
                        onReply: () => controller.setReplyTo(comment),
                        onLike: () => controller.toggleCommentLike(
                          reply,
                          isMainComment: false,
                          parentCommentId: comment.id,
                        ),
                      ),
                    );
                  }),
                  if (comment.hasMoreReplies) ...[
                    const SizedBox(height: 4),
                    InkWell(
                      onTap: () => controller.loadMoreCommentReplies(comment),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.add_circle_outline_rounded, size: 14, color: AppColors.primary),
                            const SizedBox(width: 6),
                            Text(
                              'Afficher plus de réponses',
                              style: GoogleFonts.spaceGrotesk(
                                color: AppColors.primary,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],

        // Indicator or Button for loading replies
        Padding(
          padding: const EdgeInsets.only(left: 48, top: 6),
          child: comment.isLoadingReplies
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                )
              : (!comment.areRepliesLoaded && comment.repliesCount > 0)
                  ? InkWell(
                      onTap: () => controller.loadCommentReplies(comment),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.subdirectory_arrow_right_rounded, size: 16, color: AppColors.primary),
                            const SizedBox(width: 6),
                            Text(
                              'Afficher les ${comment.repliesCount} réponse${comment.repliesCount > 1 ? 's' : ''}',
                              style: GoogleFonts.spaceGrotesk(
                                color: AppColors.primary,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _CommentBodyCard extends StatelessWidget {
  final EventComment comment;
  final bool isMain;
  final VoidCallback onReply;
  final VoidCallback onLike;

  const _CommentBodyCard({
    required this.comment,
    required this.isMain,
    required this.onReply,
    required this.onLike,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final avatarSize = isMain ? 40.0 : 32.0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Avatar Auteur
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: isMain
                  ? AppColors.primary.withValues(alpha: 0.4)
                  : colorScheme.outlineVariant.withValues(alpha: 0.3),
              width: 1.5,
            ),
          ),
          child: ClipOval(
            child: SizedBox(
              width: avatarSize,
              height: avatarSize,
              child: comment.author.photoUrl != null && comment.author.photoUrl!.isNotEmpty
                  ? AppCachedImage(imageUrl: comment.author.photoUrl!, fit: BoxFit.cover)
                  : Container(
                      color: colorScheme.surfaceContainerHighest,
                      child: Icon(
                        Icons.person_rounded,
                        size: avatarSize * 0.6,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
            ),
          ),
        ),
        const SizedBox(width: 10),

        // Bulle de commentaire
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isMain
                      ? colorScheme.surfaceContainerLow
                      : colorScheme.surfaceContainerHigh.withValues(alpha: 0.5),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    topRight: Radius.circular(18),
                    bottomLeft: Radius.circular(18),
                    bottomRight: Radius.circular(18),
                  ),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  comment.author.displayName,
                                  style: GoogleFonts.spaceGrotesk(
                                    color: colorScheme.onSurface,
                                    fontWeight: FontWeight.bold,
                                    fontSize: isMain ? 14 : 13,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (comment.eventRole != null) ...[
                                const SizedBox(width: 6),
                                _RoleBadge(role: comment.eventRole!),
                              ],
                            ],
                          ),
                        ),
                        Text(
                          _formatTimeAgo(comment.createdAt),
                          style: GoogleFonts.spaceGrotesk(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      comment.content,
                      style: AppTextStyles.body.copyWith(
                        color: colorScheme.onSurface,
                        fontSize: isMain ? 14 : 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 6),

              // Barre d'actions du commentaire (Like + Répondre)
              Row(
                children: [
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: onLike,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: Row(
                        children: [
                          Icon(
                            comment.isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                            size: 14,
                            color: comment.isLiked ? AppColors.error : colorScheme.onSurfaceVariant,
                          ),
                          if (comment.likesCount > 0) ...[
                            const SizedBox(width: 4),
                            Text(
                              '${comment.likesCount}',
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: comment.isLiked ? AppColors.error : colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  InkWell(
                    onTap: onReply,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: Row(
                        children: [
                          const Icon(Icons.reply_rounded, size: 14, color: AppColors.primary),
                          const SizedBox(width: 4),
                          Text(
                            _commentTranslation('comments_reply_button', 'Répondre'),
                            style: GoogleFonts.spaceGrotesk(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatTimeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'À l\'instant';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}j';
    return DateFormat('dd/MM/yyyy').format(date);
  }
}

class _RoleBadge extends StatelessWidget {
  final String role;

  const _RoleBadge({required this.role});

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    String labelKey;

    switch (role) {
      case 'founder':
        bg = AppColors.primary.withValues(alpha: 0.15);
        fg = AppColors.primary;
        labelKey = 'comment_role_founder';
        break;
      case 'co_founder':
        bg = Colors.purple.withValues(alpha: 0.15);
        fg = Colors.purple;
        labelKey = 'comment_role_co_founder';
        break;
      case 'staff':
        bg = Colors.orange.withValues(alpha: 0.15);
        fg = Colors.orange;
        labelKey = 'comment_role_staff';
        break;
      default:
        return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        labelKey.tr,
        style: GoogleFonts.spaceGrotesk(
          color: fg,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
