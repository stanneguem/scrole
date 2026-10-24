import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:lottie/lottie.dart';

import '../../../../app/routes/app_pages.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';
import '../../../../shared/widgets/app_cached_image.dart';
import '../../../../shared/widgets/user_certified_badge.dart';
import '../../../../shared/widgets/scrole_bottom_sheet.dart';
import '../../centre/models/conversation_model.dart';
import '../../centre/models/message_model.dart';
import '../../centre/repositories/messaging_repository.dart';
import '../controllers/direct_messages_controller.dart';

class DirectMessagesScreen extends GetView<DirectMessagesController> {
  const DirectMessagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;
    final bg = isDark ? AppColors.backgroundDark : AppColors.background;
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        centerTitle: false,
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
              onPressed: Get.back,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 12),
            Text(
              'chats_title'.tr,
              style: AppTextStyles.h4.copyWith(
                fontWeight: FontWeight.w900,
                color: colorScheme.onSurface,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: GestureDetector(
                onTap: () => Get.toNamed(AppPages.contacts),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.primary, width: 1.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.add,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Obx(() => _buildPinnedHorizontalList(colorScheme, isDark)),
          _buildSearchBar(colorScheme, isDark),
          Expanded(
            child: Obx(() {
              final hasCachedConversations =
                  controller.filteredConversations.isNotEmpty;
              if (controller.isLoading.value && !hasCachedConversations)
                return const _LoadingState();
              if (controller.isEmpty)
                return _EmptyState(onRefresh: controller.refreshConversations);
              return _LoadedState(
                unpinned: controller.unpinnedConversations,
                currentUserId: Get.find<MessagingRepository>().currentUserId,
                onRefresh: controller.refreshConversations,
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildPinnedHorizontalList(ColorScheme colorScheme, bool isDark) {
    if (controller.pinnedConversations.isEmpty) return const SizedBox.shrink();
    return Container(
      height: 120,
      margin: const EdgeInsets.only(top: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: controller.pinnedConversations.length,
        itemBuilder: (context, index) => _buildPinnedItem(
          controller.pinnedConversations[index],
          colorScheme,
          isDark,
        ),
      ),
    );
  }

  Widget _buildPinnedItem(
    ConversationModel chat,
    ColorScheme colorScheme,
    bool isDark,
  ) => Padding(
    padding: const EdgeInsets.only(right: 16),
    child: GestureDetector(
      onTap: () => _openConversation(chat),
      onLongPress: () =>
          _showConversationActions(context: Get.context!, conversation: chat),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.primary, width: 2),
            ),
            child: SizedBox(
              width: 68,
              height: 68,
              child: ClipOval(
                child: _Avatar(chat: chat, isDark: isDark),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: 76,
            child: Text(
              chat.name ?? 'Chat',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.caption.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w600,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  void _openConversation(ConversationModel conversation) {
    Get.toNamed(
      AppPages.conversation,
      arguments: {
        'userId': conversation.peerId(
          Get.find<MessagingRepository>().currentUserId,
        ),
        'name': conversation.name ?? 'Chat',
        'color': AppColors.primary,
        'avatar': conversation.avatarUrl,
      },
      parameters: {'chatId': conversation.id},
    );
  }

  Widget _buildSearchBar(ColorScheme colorScheme, bool isDark) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
    child: Container(
      height: 54,
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(16),
      ),
      child: TextField(
        onChanged: controller.onSearchChanged,
        style: AppTextStyles.body.copyWith(color: colorScheme.onSurface),
        decoration: InputDecoration(
          hintText: 'chats_search_hint'.tr,
          hintStyle: AppTextStyles.body.copyWith(
            color: colorScheme.onSurfaceVariant.withOpacity(.5),
            fontWeight: FontWeight.w500,
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            color: colorScheme.onSurfaceVariant.withOpacity(.5),
            size: 26,
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    ),
  );

  Future<void> _showConversationActions({
    required BuildContext context,
    required ConversationModel conversation,
  }) async {
    final action = await ScroleBottomSheet.show<String>(
      context: context,
      showCancel: true,
      child: ScroleBottomSheetGroup(
        children: [
          ScroleBottomSheetAction(
            label: conversation.isPinned ? 'Désépingler' : 'Épingler',
            icon: conversation.isPinned
                ? Icons.push_pin_outlined
                : Icons.push_pin_rounded,
            onTap: () => Navigator.of(context).pop('pin'),
          ),
          const ScroleBottomSheetDivider(),
          ScroleBottomSheetAction(
            label: 'Supprimer la discussion',
            icon: Icons.delete_outline_rounded,
            color: Theme.of(context).colorScheme.error,
            onTap: () => Navigator.of(context).pop('delete'),
          ),
        ],
      ),
    );
    if (action == 'pin') {
      await controller.togglePin(conversation.id);
    } else if (action == 'delete') {
      await _confirmConversationDelete(context, conversation.id);
    }
  }
}

Future<void> _confirmConversationDelete(
  BuildContext context,
  String conversationId,
) async {
  final colorScheme = Theme.of(context).colorScheme;
  final confirmed = await Get.dialog<bool>(
    AlertDialog(
      title: const Text('Supprimer la discussion ?'),
      content: const Text(
        'Cette action supprimera cette discussion et tous ses messages de cet appareil.',
      ),
      actions: [
        TextButton(
          onPressed: () => Get.back(result: false),
          child: const Text('Annuler'),
        ),
        TextButton(
          onPressed: () => Get.back(result: true),
          style: TextButton.styleFrom(foregroundColor: colorScheme.error),
          child: const Text('Supprimer'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  await Get.find<DirectMessagesController>().deleteConversation(conversationId);
}

class _Avatar extends StatelessWidget {
  final ConversationModel chat;
  final bool isDark;
  const _Avatar({required this.chat, required this.isDark});
  @override
  Widget build(BuildContext context) {
    final avatar = chat.avatarUrl;
    return Container(
      color: isDark ? AppColors.surfaceDark : AppColors.white1,
      alignment: Alignment.center,
      child: avatar != null && avatar.isNotEmpty
          ? AppCachedImage(imageUrl: avatar, fit: BoxFit.cover)
          : Text(
              (chat.name ?? '?').characters.first.toUpperCase(),
              style: AppTextStyles.h5.copyWith(color: AppColors.primary),
            ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();
  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator(color: AppColors.primary));
}

class _EmptyState extends StatelessWidget {
  final Future<void> Function() onRefresh;
  const _EmptyState({required this.onRefresh});
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Jouée une seule fois : évite une animation GPU permanente
            // lorsque la boîte de réception reste vide.
            Lottie.asset(
              'assets/lotties/nothing.json',
              width: 160,
              height: 160,
              repeat: false,
              animate: true,
            ),
            const SizedBox(height: 16),
            Text(
              'chats_empty_title'.tr,
              style: AppTextStyles.h5.copyWith(
                fontWeight: FontWeight.w800,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'chats_empty_subtitle'.tr,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant.withOpacity(.6),
              ),
            ),
            const SizedBox(height: 32),
            GestureDetector(
              onTap: () => Get.toNamed(AppPages.contacts),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
                child: Text(
                  'chats_start_chatting'.tr,
                  style: TextStyle(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w600,
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

class _LoadedState extends StatelessWidget {
  final List<ConversationModel> unpinned;
  final String? currentUserId;
  final Future<void> Function() onRefresh;
  const _LoadedState({
    required this.unpinned,
    required this.currentUserId,
    required this.onRefresh,
  });
  @override
  Widget build(BuildContext context) => RefreshIndicator(
    color: AppColors.primary,
    onRefresh: onRefresh,
    child: ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: unpinned.length,
      itemBuilder: (context, index) => _AnimatedConversationTile(
        conversation: unpinned[index],
        currentUserId: currentUserId,
      ),
    ),
  );
}

class _ReceiptStatusIcon extends StatelessWidget {
  const _ReceiptStatusIcon({required this.status});
  final MessageStatus status;

  @override
  Widget build(BuildContext context) {
    final icon = switch (status) {
      MessageStatus.pending || MessageStatus.sending => Icons.schedule_rounded,
      MessageStatus.sent => Icons.check_rounded,
      MessageStatus.delivered ||
      MessageStatus.received ||
      MessageStatus.read => Icons.done_all_rounded,
      MessageStatus.failed ||
      MessageStatus.error => Icons.error_outline_rounded,
    };
    final color = status == MessageStatus.read
        ? Colors.blue
        : (status == MessageStatus.failed || status == MessageStatus.error)
        ? AppColors.error
        : Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(.65);
    return Icon(icon, size: 13, color: color);
  }
}

class _AnimatedConversationTile extends StatelessWidget {
  final ConversationModel conversation;
  final String? currentUserId;
  const _AnimatedConversationTile({
    required this.conversation,
    required this.currentUserId,
  });

  Future<void> _confirmDelete(BuildContext context) =>
      _confirmConversationDelete(context, conversation.id);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasUnread = conversation.unreadCount > 0;
    final unreadColor = colorScheme.primary;
    final isDark = colorScheme.brightness == Brightness.dark;
    final tile = TweenAnimationBuilder<double>(
      key: ValueKey(
        '${conversation.id}:${conversation.unreadCount}:${conversation.updatedAt.microsecondsSinceEpoch}',
      ),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Transform.translate(
        offset: Offset((1 - Curves.easeOutCubic.transform(value)) * 28, 0),
        child: Opacity(
          opacity: Curves.easeOutCubic.transform(value),
          child: child,
        ),
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        padding: const EdgeInsets.only(left: 6),
        decoration: BoxDecoration(
          color: hasUnread ? unreadColor.withOpacity(.075) : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: hasUnread
                ? unreadColor.withOpacity(.18)
                : Colors.transparent,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Get.toNamed(
            AppPages.conversation,
            arguments: {
              'userId': conversation.participantIds.isNotEmpty
                  ? conversation.participantIds.first
                  : null,
              'name': conversation.name ?? 'Chat',
              'color': AppColors.primary,
              'avatar': conversation.avatarUrl,
            },
            parameters: {'chatId': conversation.id},
          ),
          onLongPress: () => _showConversationActions(
            context: context,
            conversation: conversation,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 9, 12, 9),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  width: hasUnread ? 3 : 0,
                  height: 54,
                  margin: EdgeInsets.only(right: hasUnread ? 8 : 0),
                  decoration: BoxDecoration(
                    color: unreadColor,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                SizedBox(
                  width: 56,
                  height: 56,
                  child: ClipOval(
                    child: _Avatar(chat: conversation, isDark: isDark),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Nom + badge regroupés : le badge reste collé au nom.
                          Flexible(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    conversation.name ?? 'Discussion',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTextStyles.bodyLarge.copyWith(
                                      fontWeight: hasUnread
                                          ? FontWeight.w900
                                          : FontWeight.w700,
                                      color: colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                                if (conversation.participantIds.isNotEmpty) ...[
                                  const SizedBox(width: 4),
                                  UserCertifiedBadge(
                                    userId: conversation.participantIds.first,
                                    size: 16,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _formatTime(conversation.updatedAt),
                            style: AppTextStyles.caption.copyWith(
                              color: hasUnread
                                  ? unreadColor
                                  : colorScheme.onSurfaceVariant.withOpacity(
                                      .5,
                                    ),
                              fontWeight: hasUnread
                                  ? FontWeight.w800
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _getMessagePreview(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.bodySmall.copyWith(
                                color: hasUnread
                                    ? colorScheme.onSurface
                                    : colorScheme.onSurfaceVariant.withOpacity(
                                        .7,
                                      ),
                                fontWeight: hasUnread
                                    ? FontWeight.w700
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                          if (hasUnread)
                            Container(
                              margin: const EdgeInsets.only(left: 8),
                              constraints: const BoxConstraints(
                                minWidth: 24,
                                minHeight: 24,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 4,
                              ),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: unreadColor,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '${conversation.unreadCount}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (conversation.lastMessage != null &&
                          conversation.lastMessage!.senderId == currentUserId)
                        Align(
                          alignment: Alignment.centerRight,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 3, right: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _ReceiptStatusIcon(
                                  status: conversation.lastMessage!.status,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _receiptLabel(
                                    conversation.lastMessage!.status,
                                  ),
                                  style: AppTextStyles.caption.copyWith(
                                    fontSize: 10,
                                    color:
                                        conversation.lastMessage!.status ==
                                            MessageStatus.read
                                        ? Colors.blue
                                        : colorScheme.onSurfaceVariant
                                              .withOpacity(.65),
                                  ),
                                ),
                              ],
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
      ),
    );
    return Dismissible(
      key: ValueKey('dismissible-${conversation.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (direction) async {
        await _confirmDelete(context);
        return false;
      },
      background: const SizedBox.shrink(),
      secondaryBackground: Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Icon(
          Icons.delete_outline_rounded,
          color: Colors.white,
          size: 28,
        ),
      ),
      child: tile,
    );
  }

  String _getMessagePreview() {
    final msg = conversation.lastMessage;
    if (msg == null) return 'Aucun message';
    final prefix = msg.senderId == currentUserId
        ? '${'chats_you_prefix'.tr} '
        : '';
    switch (msg.type) {
      case MessageType.image:
        return '$prefix🖼️ Photo';
      case MessageType.video:
        return '$prefix🎥 Vidéo';
      case MessageType.audio:
        return '$prefix🎤 Audio';
      case MessageType.file:
        return '$prefix${msg.text?.trim().isNotEmpty == true ? msg.text!.trim() : '📎 Fichier'}';
      case MessageType.poll:
        return '$prefix📊 Sondage';
      case MessageType.text:
        return '$prefix${msg.text ?? ''}';
    }
  }

  String _receiptLabel(MessageStatus status) {
    switch (status) {
      case MessageStatus.pending:
      case MessageStatus.sending:
        return 'Envoi en cours';
      case MessageStatus.sent:
        return 'Envoyé';
      case MessageStatus.delivered:
      case MessageStatus.received:
        return 'Reçu';
      case MessageStatus.read:
        return 'Lu';
      case MessageStatus.failed:
      case MessageStatus.error:
        return 'Échec de l’envoi';
    }
  }

  String _formatTime(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return 'time_ago_just_now'.tr;
    if (diff.inMinutes < 60) return '${diff.inMinutes}${'time_unit_minute'.tr}';
    if (diff.inHours < 24) return DateFormat.Hm().format(date);
    return DateFormat.Md().format(date);
  }
}

Future<void> _showConversationActions({
  required BuildContext context,
  required ConversationModel conversation,
}) async {
  final controller = Get.find<DirectMessagesController>();
  final action = await ScroleBottomSheet.show<String>(
    context: context,
    showCancel: true,
    child: ScroleBottomSheetGroup(
      children: [
        ScroleBottomSheetAction(
          label: conversation.isPinned ? 'Désépingler' : 'Épingler',
          icon: conversation.isPinned
              ? Icons.push_pin_outlined
              : Icons.push_pin_rounded,
          onTap: () => Navigator.of(context).pop('pin'),
        ),
        const ScroleBottomSheetDivider(),
        ScroleBottomSheetAction(
          label: 'Supprimer la discussion',
          icon: Icons.delete_outline_rounded,
          color: Theme.of(context).colorScheme.error,
          onTap: () => Navigator.of(context).pop('delete'),
        ),
      ],
    ),
  );
  if (action == 'pin') {
    await controller.togglePin(conversation.id);
  } else if (action == 'delete') {
    await _confirmConversationDelete(context, conversation.id);
  }
}
