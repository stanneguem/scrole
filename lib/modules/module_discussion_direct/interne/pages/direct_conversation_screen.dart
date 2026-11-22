import 'dart:async';
import 'dart:io';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:scrole/shared/models/chat_message.dart'
    as legacy;
import '../widgets/direct_voice_message_player.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';
import '../../../../shared/widgets/app_cached_image.dart';
import '../../../../shared/widgets/linkified_text.dart';
import '../../../../shared/widgets/user_certified_badge.dart';
import '../../../../shared/widgets/image_source_sheet.dart';
import 'chat_media_viewer_screen.dart';
import '../../centre/models/message_model.dart';
import '../widgets/chat_cached_media.dart';
import '../controllers/direct_conversation_controller.dart';
import '../widgets/direct_voice_recorder_panel.dart';
import 'direct_conversation_details_screen.dart';

class DirectConversationScreen extends GetView<DirectConversationController> {
  const DirectConversationScreen({super.key});

  Widget? _buildChatBackground() {
    final wp = controller.selectedWallpaper.value;
    if (wp == 'none') return null;

    if (wp.startsWith('custom:')) {
      final path = wp.substring(7);
      final file = File(path);
      if (file.existsSync()) {
        return Image.file(
          file,
          key: ValueKey('${file.path}_${file.lastModifiedSync().millisecondsSinceEpoch}'),
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Image.asset(
            'assets/message_fond/messsage_fond1.png',
            fit: BoxFit.cover,
          ),
        );
      }
      return Image.asset('assets/message_fond/messsage_fond1.png', fit: BoxFit.cover);
    }

    if (wp == 'fond2') return Image.asset('assets/message_fond/messsage_fond2.png', fit: BoxFit.cover);
    if (wp == 'fond3') return Image.asset('assets/message_fond/messsage_fond3.png', fit: BoxFit.cover);
    return Image.asset('assets/message_fond/messsage_fond1.png', fit: BoxFit.cover);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        backgroundColor: colors.surface,
        elevation: .5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: controller.onBack,
        ),
        title: Obx(() => _buildTitle()),
        actions: const [],
      ),
      body: Stack(
        children: [
          // 1. Image de fond d'écran (Asset ou Personnalisé Bac à sable) + Calque d'assombrissement
          Obx(() {
            final bgWidget = _buildChatBackground();
            if (bgWidget == null) return const SizedBox.shrink();
            return Stack(
              children: [
                Positioned.fill(
                  child: bgWidget,
                ),
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withValues(
                      alpha: Get.isDarkMode ? 0.60 : 0.45,
                    ),
                  ),
                ),
              ],
            );
          }),

          // 2. Contenu protégé des zones système (navigation Android/iOS).
          // SafeArea conserve le fond derrière la barre système, mais maintient
          // les messages et surtout le composeur au-dessus de celle-ci.
          SafeArea(
            top: false,
            child: Column(
              children: [
                Expanded(child: _messages(colors)),
                Obx(() {
                  if (controller.blockedByOtherUser.value) {
                    return Container(
                      width: double.infinity,
                      margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: colors.errorContainer.withValues(alpha: .65),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: colors.error.withValues(alpha: .25), width: 0.7),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.block_rounded, color: colors.onErrorContainer, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Cet utilisateur vous a bloqué. Vous ne pouvez plus lui envoyer de messages.',
                              style: TextStyle(color: colors.onErrorContainer, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  if (controller.blockedByMe.value) {
                    return Container(
                      width: double.infinity,
                      margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        'Vous avez bloqué cet utilisateur. Débloquez-le depuis les paramètres de discussion pour lui envoyer des messages.',
                        style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    );
                  }
                  return controller.recordingState.value != RecordingState.idle
                      ? DirectVoiceRecorderPanel(controller: controller)
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _reply(colors),
                            _composer(context, colors),
                            _emoji(),
                          ],
                        );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openDetails() {
    Get.to(
      () => DirectConversationDetailsScreen(
        userId: controller.otherUserId,
        userName: controller.otherUserName.value,
        userColor: controller.otherUserColor,
        userAvatar: controller.otherUserAvatar.value,
      ),
    );
  }

  Widget _buildTitle() {
    return GestureDetector(
      onTap: _openDetails,
      child: Row(
        children: [
          ClipOval(
            child: SizedBox(
              width: 32,
              height: 32,
              child:
                  controller.otherUserAvatar.value != null &&
                      controller.otherUserAvatar.value!.isNotEmpty
                  ? AppCachedImage(
                      imageUrl: controller.otherUserAvatar.value!,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      color: controller.otherUserColor.withValues(alpha: .1),
                      alignment: Alignment.center,
                      child: Text(
                        controller.otherUserName.value.characters.first.toUpperCase(),
                        style: TextStyle(
                          color: controller.otherUserColor,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 10),
          Obx(
            () => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        controller.otherUserName.value.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.h6.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    UserCertifiedBadge(
                      userId: controller.otherUserId,
                      size: 16,
                    ),
                  ],
                ),
                if (controller.isOtherUserTyping.value)
                  const Text(
                    "En train d'écrire...",
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyChatState(ColorScheme colors) {
    final hasWallpaper = controller.selectedWallpaper.value != 'none';
    final isDark = Get.isDarkMode;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30),
        child: Container(
          width: 360,
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 26),
          decoration: BoxDecoration(
            color: hasWallpaper
                ? Colors.black.withValues(alpha: .28)
                : colors.surface.withValues(alpha: isDark ? .72 : .92),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: hasWallpaper
                  ? Colors.white.withValues(alpha: .18)
                  : colors.outlineVariant.withValues(alpha: .35),
              width: .7,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? .10 : .035),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: hasWallpaper
                      ? Colors.white.withValues(alpha: .14)
                      : colors.primary.withValues(alpha: .10),
                ),
                child: Icon(
                  CupertinoIcons.chat_bubble_text_fill,
                  size: 29,
                  color: hasWallpaper ? Colors.white : colors.primary,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'chats_empty_title'.tr,
                textAlign: TextAlign.center,
                style: AppTextStyles.h4.copyWith(
                  fontSize: 19,
                  height: 1.2,
                  letterSpacing: -.35,
                  fontWeight: FontWeight.w700,
                  color: hasWallpaper ? Colors.white : colors.onSurface,
                ),
              ),
              const SizedBox(height: 9),
              Text(
                'chats_empty_subtitle'.tr,
                textAlign: TextAlign.center,
                style: AppTextStyles.body.copyWith(
                  fontSize: 14,
                  height: 1.5,
                  color: hasWallpaper
                      ? Colors.white.withValues(alpha: .86)
                      : colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              Container(
                height: 3,
                width: 34,
                decoration: BoxDecoration(
                  color: hasWallpaper
                      ? Colors.white.withValues(alpha: .55)
                      : colors.primary.withValues(alpha: .45),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _messages(ColorScheme colors) {
    return Obx(() {
      if (controller.isLoading.value && controller.messages.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }

      if (controller.messages.isEmpty) {
        return _buildEmptyChatState(colors);
      }

      return _MessagesList(
        controller: controller,
        colors: colors,
        bubbleBuilder: _bubble,
      );
    });
  }

  Widget _bubble(
    BuildContext context,
    ColorScheme colors,
    MessageModel m,
    bool header,
  ) {
    final isMe = m.senderId == controller.currentUserId;
    final hasWallpaper = controller.selectedWallpaper.value != 'none';

    if (m.deletedSilently) return const SizedBox.shrink();
    if (m.isDeleted) {
      return const Padding(
        padding: EdgeInsets.only(top: 10),
        child: Text(
          'Ce message a été supprimé',
          style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.white70),
        ),
      );
    }

    final content = <Widget>[];
    if (header) {
      content.add(
        Text(
          (isMe ? 'Moi' : controller.otherUserName.value).toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w900,
            color: isMe
                ? (hasWallpaper ? Colors.white70 : Colors.grey)
                : controller.otherUserColor,
          ),
        ),
      );
    }
    if (m.repliedToId != null) content.add(_quoted(colors, m.repliedToId!));
    if (m.type == MessageType.audio && m.audioUrl != null) {
      content.add(
        DirectVoiceMessagePlayer(
          voiceMessage: legacy.VoiceMessage(
            fileName: 'audio.m4a',
            sizeLabel: '',
            durationLabel: '${m.audioDuration?.inSeconds ?? 0}',
            url: m.audioUrl,
          ),
          audioPath: m.audioUrl,
          messageId: m.id,
          isMine: isMe,
        ),
      );
    }
    if (m.mediaUrls?.isNotEmpty == true) content.add(_media(m.mediaUrls!));
    if (m.text != null) {
      content.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: LinkifiedText(
                text: m.text!,
                style: AppTextStyles.bodyLarge.copyWith(
                  color: hasWallpaper
                      ? Colors.white.withValues(alpha: .95)
                      : colors.onSurface.withValues(alpha: .9),
                ),
                linkColor: hasWallpaper ? Colors.lightBlueAccent : colors.primary,
              ),
            ),
            if (m.isEdited && !m.editedSilently)
              Padding(
                padding: const EdgeInsets.only(left: 5, bottom: 2),
                child: Icon(
                  Icons.edit_outlined,
                  size: 11,
                  color: hasWallpaper
                      ? Colors.white.withValues(alpha: .7)
                      : colors.onSurfaceVariant.withValues(alpha: .65),
                ),
              ),
          ],
        ),
      );
    }
    if (m.status == MessageStatus.sending) {
      content.add(
        Text(
          'Envoi...',
          style: TextStyle(
            fontSize: 10,
            fontStyle: FontStyle.italic,
            color: hasWallpaper ? Colors.white70 : Colors.grey,
          ),
        ),
      );
    }

    return GestureDetector(
      onDoubleTap: () => _options(context, m),
      child: Padding(
        padding: EdgeInsets.only(top: header ? 16 : 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 4,
              height: 50,
              decoration: BoxDecoration(
                color: (isMe ? Colors.grey : controller.otherUserColor)
                    .withValues(alpha: .5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: content,
              ),
            ),
            if (header || isMe)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    DateFormat.Hm().format(m.createdAt),
                    style: TextStyle(
                      fontSize: 9,
                      color: hasWallpaper
                          ? Colors.white70
                          : colors.onSurfaceVariant.withValues(alpha: .5),
                    ),
                  ),
                  if (isMe) ...[
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _status(m.status),
                        const SizedBox(width: 3),
                        Text(
                          _receiptLabel(m.status),
                          style: TextStyle(
                            fontSize: 9,
                            color: m.status == MessageStatus.read
                                ? Colors.blue
                                : hasWallpaper
                                    ? Colors.white70
                                    : colors.onSurfaceVariant.withValues(alpha: .65),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _status(MessageStatus s) {
    final icon = switch (s) {
      MessageStatus.pending || MessageStatus.sending => Icons.schedule_rounded,
      MessageStatus.sent => Icons.check_rounded,
      MessageStatus.delivered || MessageStatus.received || MessageStatus.read => Icons.done_all_rounded,
      MessageStatus.failed || MessageStatus.error => Icons.error_outline_rounded,
    };
    final color = s == MessageStatus.read
        ? Colors.blue
        : s == MessageStatus.error || s == MessageStatus.failed
            ? AppColors.error
            : null;
    return Icon(icon, size: 13, color: color);
  }

  String _receiptLabel(MessageStatus s) => switch (s) {
    MessageStatus.pending || MessageStatus.sending => 'Envoi…',
    MessageStatus.sent => 'Envoyé',
    MessageStatus.delivered || MessageStatus.received => 'Reçu',
    MessageStatus.read => 'Lu',
    MessageStatus.failed || MessageStatus.error => 'Échec',
  };

  Widget _media(List<String> urls) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      child: urls.length == 1
          ? _one(urls.first, urls)
          : Wrap(
              spacing: 8,
              runSpacing: 8,
              children: urls
                  .asMap()
                  .entries
                  .map((entry) => _thumb(entry.value, entry.key, urls))
                  .toList(),
            ),
    );
  }

  Widget _one(String path, List<String> all) {
    return GestureDetector(
      onTap: () =>
          Get.to(() => ChatMediaViewerScreen(mediaUrls: all, initialIndex: 0)),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: ChatCachedMedia(
          remoteUrl: path,
          fit: BoxFit.cover,
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Widget _thumb(String path, int index, List<String> all) {
    return GestureDetector(
      onTap: () => Get.to(
        () => ChatMediaViewerScreen(mediaUrls: all, initialIndex: index),
      ),
      child: ChatCachedMedia(
        remoteUrl: path,
        width: 100,
        height: 100,
        fit: BoxFit.cover,
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }

  Widget _quoted(ColorScheme colors, String id) {
    final q = controller.messages.firstWhereOrNull((m) => m.id == id);
    if (q == null || q.deletedSilently) return const SizedBox.shrink();
    final me = q.senderId == controller.currentUserId;
    final hasWallpaper = controller.selectedWallpaper.value != 'none';

    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: hasWallpaper
            ? Colors.white.withValues(alpha: .1)
            : colors.onSurface.withValues(alpha: .05),
        borderRadius: BorderRadius.circular(4),
        border: Border(
          left: BorderSide(
            color: me ? Colors.grey : controller.otherUserColor,
            width: 3,
          ),
        ),
      ),
      child: Text(
        q.type == MessageType.audio ? '🎤 Message vocal' : (q.text ?? 'Média'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          color: hasWallpaper ? Colors.white70 : colors.onSurface,
        ),
      ),
    );
  }

  bool _interactionAllowed(MessageModel m) {
    return DateTime.now().difference(m.createdAt) < const Duration(minutes: 5);
  }

  void _options(BuildContext context, MessageModel m) {
    final me = m.senderId == controller.currentUserId;
    final canInteractGlobally = me && _interactionAllowed(m);

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (m.status == MessageStatus.failed)
                ListTile(
                  leading: const Icon(Icons.refresh_rounded, color: AppColors.primary),
                  title: const Text('Réessayer l’envoi'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    controller.retryMessage(m.localId);
                  },
                ),
              if (m.text != null)
                ListTile(
                  leading: const Icon(Icons.copy_outlined),
                  title: Text('chats_copy'.tr),
                  onTap: () => Navigator.of(sheetContext).pop(),
                ),
              if (canInteractGlobally && m.type == MessageType.text)
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Modifier'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    controller.beginEditing(m);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.reply_outlined),
                title: Text('chats_reply'.tr),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  controller.setReply(m);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_sweep_outlined),
                title: const Text('Supprimer pour moi'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  controller.deleteMessageForMe(m.id);
                },
              ),
              if (canInteractGlobally)
                ListTile(
                  leading: const Icon(
                    Icons.delete_outline,
                    color: AppColors.error,
                  ),
                  title: Text(
                    'chats_delete_everyone'.tr,
                    style: const TextStyle(color: AppColors.error),
                  ),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    controller.deleteMessageForEveryone(m.id);
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _reply(ColorScheme colors) {
    return Obx(() {
      final message = controller.repliedMessage.value;
      if (message == null) return const SizedBox.shrink();
      final hasWallpaper = controller.selectedWallpaper.value != 'none';

      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: hasWallpaper
              ? Colors.black54
              : colors.surfaceContainerHighest.withValues(alpha: .5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 34,
              color: message.senderId == controller.currentUserId
                  ? Colors.grey
                  : controller.otherUserColor,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message.type == MessageType.audio
                    ? '🎤 Message vocal'
                    : (message.text ?? 'Média'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: hasWallpaper ? Colors.white : colors.onSurface,
                ),
              ),
            ),
            IconButton(
              icon: Icon(
                Icons.close,
                color: hasWallpaper ? Colors.white : colors.onSurface,
              ),
              onPressed: controller.clearReply,
            ),
          ],
        ),
      );
    });
  }

  Widget _composer(BuildContext context, ColorScheme colors) {
    return Obx(() {
      final editing = controller.editingMessage.value;
      final editingMode = editing != null;
      final canSendText = editingMode || controller.isTyping.value;
      final hasWallpaper = controller.selectedWallpaper.value != 'none';

      return Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        decoration: BoxDecoration(
          color: hasWallpaper
              ? Colors.black.withValues(alpha: .16)
              : colors.surface.withValues(alpha: .96),
          border: Border(
            top: BorderSide(
              color: hasWallpaper
                  ? Colors.white.withValues(alpha: .12)
                  : colors.outlineVariant.withValues(alpha: .35),
              width: .6,
            ),
          ),
        ),
        child: Column(
          children: [
            if (editingMode)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: hasWallpaper
                      ? Colors.black54
                      : colors.surfaceContainerHighest.withValues(alpha: .45),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.edit_outlined,
                      size: 18,
                      color: hasWallpaper ? Colors.white : colors.onSurface,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Modification du message',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: hasWallpaper ? Colors.white : colors.onSurface,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.close,
                        color: hasWallpaper ? Colors.white : colors.onSurface,
                      ),
                      onPressed: controller.cancelEditing,
                    ),
                  ],
                ),
              ),
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 360;
                final iconSize = compact ? 38.0 : 42.0;
                final gap = compact ? 5.0 : 8.0;
                return Row(
                  children: [
                    if (!editingMode)
                      _CircleIcon(
                        icon: null,
                        assetPath: 'assets/svg_icons/pictures2-svgrepo-com.svg',
                        size: iconSize,
                        color: hasWallpaper ? Colors.white : null,
                        onTap: () => showImageSourceSheet(
                          context,
                          onCamera: controller.pickCameraMedia,
                          onGallery: controller.pickGalleryMedia,
                        ),
                      ),
                    if (!editingMode) SizedBox(width: gap),
                    Expanded(
                      child: TextField(
                        controller: controller.messageController,
                        onTap: () => controller.showEmojiPicker.value = false,
                        minLines: 1,
                        maxLines: 5,
                        textCapitalization: TextCapitalization.sentences,
                        keyboardAppearance: hasWallpaper || Get.isDarkMode
                            ? Brightness.dark
                            : Brightness.light,
                        style: TextStyle(
                          color: hasWallpaper ? Colors.white : colors.onSurface,
                          fontSize: 15,
                          height: 1.35,
                        ),
                        decoration: InputDecoration(
                          hintText: editingMode
                              ? 'Modifier le message...'
                              : 'chats_message_hint'.tr,
                          hintStyle: TextStyle(
                            color: hasWallpaper ? Colors.white60 : colors.onSurfaceVariant,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: BorderSide(
                              color: colors.outlineVariant.withValues(alpha: .35),
                              width: 0.5,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide(
                              color: colors.outlineVariant.withValues(alpha: .35),
                              width: 0.5,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide(
                              color: colors.outline.withValues(alpha: .55),
                              width: 0.7,
                            ),
                          ),
                          filled: true,
                          fillColor: hasWallpaper
                              ? Colors.black.withValues(alpha: .45)
                              : colors.surfaceContainerHighest.withValues(alpha: .3),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: compact ? 12 : 16,
                            vertical: 11,
                          ),
                          isDense: true,
                        ),
                        onSubmitted: (_) => controller.sendMessage(),
                      ),
                    ),
                    SizedBox(width: gap),
                    _CircleIcon(
                      size: iconSize,
                      icon: editingMode
                          ? Icons.check_rounded
                          : controller.isTyping.value
                          ? Icons.send
                          : Icons.mic_none,
                      color: canSendText ? AppColors.primary : (hasWallpaper ? Colors.white : null),
                      onTap: canSendText
                          ? controller.sendMessage
                          : controller.startRecording,
                      onLongPress: editingMode ? null : controller.startRecording,
                      onLongPressUp: editingMode ? null : controller.stopRecording,
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      );
    });
  }

  Widget _emoji() {
    return Obx(
      () => controller.showEmojiPicker.value
          ? SizedBox(
              height: 280,
              child: EmojiPicker(
                textEditingController: controller.messageController,
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}

class _CircleIcon extends StatelessWidget {
  const _CircleIcon({
    this.icon,
    this.assetPath,
    this.color,
    this.onTap,
    this.onLongPress,
    this.onLongPressUp,
    this.size = 44,
  }) : assert(icon != null || assetPath != null);

  final IconData? icon;
  final String? assetPath;
  final Color? color;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onLongPressUp;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.onSurface;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      onLongPressUp: onLongPressUp,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: c.withValues(alpha: .15),
        ),
        alignment: Alignment.center,
        child: assetPath != null
            ? SvgPicture.asset(
                assetPath!,
                width: 21,
                height: 21,
                colorFilter: ColorFilter.mode(c, BlendMode.srcIn),
              )
            : Icon(icon, color: c, size: 21),
      ),
    );
  }
}

class _MessagesList extends StatefulWidget {
  const _MessagesList({
    required this.controller,
    required this.colors,
    required this.bubbleBuilder,
  });

  final DirectConversationController controller;
  final ColorScheme colors;
  final Widget Function(BuildContext, ColorScheme, MessageModel, bool)
  bubbleBuilder;

  @override
  State<_MessagesList> createState() => _MessagesListState();
}

class _MessagesListState extends State<_MessagesList> {
  final ScrollController _scrollController = ScrollController();
  final Map<String, Timer> _visibilityTimers = <String, Timer>{};
  bool _showJumpButton = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
  }

  void _onScroll() {
    final show = _scrollController.hasClients && _scrollController.offset > 280;
    if (show != _showJumpButton && mounted) {
      setState(() => _showJumpButton = show);
    }
  }

  bool _isUnreadMessage(MessageModel message) {
    final cursor = widget.controller.lastReadAt.value;
    return message.senderId != widget.controller.currentUserId &&
        !message.isDeleted &&
        (cursor == null || message.createdAt.isAfter(cursor));
  }

  void _markVisibleAsRead(MessageModel message) {
    if (!_isUnreadMessage(message) ||
        _visibilityTimers.containsKey(message.id)) {
      return;
    }

    _visibilityTimers[message.id] = Timer(
      const Duration(milliseconds: 300),
      () {
        _visibilityTimers.remove(message.id);
        if (mounted && _isUnreadMessage(message)) {
          widget.controller.queueVisibleMessageAsRead(message);
        }
      },
    );
  }

  void _jumpToFirstUnread() {
    final count = widget.controller.unreadCount.value;
    if (count == 0) {
      _jumpToLatest();
      return;
    }

    final id = widget.controller.firstUnreadMessageId.value;
    final index = widget.controller.messages.indexWhere((m) => m.id == id);
    final target = index >= 0 ? index : count;
    final maxExtent = _scrollController.hasClients
        ? _scrollController.position.maxScrollExtent
        : 0.0;
    final offset = (target * 92.0).clamp(0.0, maxExtent);

    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        offset,
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _jumpToLatest() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    for (final timer in _visibilityTimers.values) {
      timer.cancel();
    }
    _visibilityTimers.clear();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => Stack(
        children: [
          ListView.builder(
            controller: _scrollController,
            reverse: true,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            itemCount: widget.controller.messages.length,
            itemBuilder: (context, index) {
              final messages = widget.controller.messages.toList(
                growable: false,
              );
              if (index >= messages.length) return const SizedBox.shrink();

              final message = messages[index];
              final next = index < messages.length - 1
                  ? messages[index + 1]
                  : null;
              final header = next == null || next.senderId != message.senderId;

              if (index < 5) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _markVisibleAsRead(message);
                });
              }

              return widget.bubbleBuilder(
                context,
                widget.colors,
                message,
                header,
              );
            },
          ),
          IgnorePointer(
            ignoring:
                !(_showJumpButton || widget.controller.unreadCount.value > 0),
            child: AnimatedOpacity(
              opacity:
                  _showJumpButton || widget.controller.unreadCount.value > 0
                  ? 1
                  : 0,
              duration: const Duration(milliseconds: 180),
              child: Align(
                alignment: Alignment.bottomRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 14, bottom: 14),
                  child: _buildJumpButton(context),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJumpButton(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final unread = widget.controller.unreadCount.value;

    return Material(
      color: Colors.transparent,
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: .25),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: _jumpToFirstUnread,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          height: 46,
          decoration: BoxDecoration(
            color: colors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: colors.outline.withValues(alpha: .15)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.keyboard_arrow_down_rounded, size: 24),
              if (unread > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 3),
                  child: Text(
                    '$unread',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
