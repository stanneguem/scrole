import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../app/routes/app_pages.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';
import '../../../../shared/widgets/user_certified_badge.dart';
import '../../centre/services/chat_service.dart';
import '../controllers/contacts_controller.dart';

class ContactsScreen extends GetView<ContactsController> {
  const ContactsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: controller.onBack,
        ),
        title: Text(
          'contacts_title'.tr.toUpperCase(),
          style: AppTextStyles.h6.copyWith(fontWeight: FontWeight.w900, letterSpacing: 1.2),
        ),
      ),
      body: Column(
        children: [
          _buildSearchBar(colorScheme),
          Expanded(child: _buildContactsList(colorScheme)),
        ],
      ),
    );
  }

  Widget _buildSearchBar(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
        ),
        child: TextField(
          onChanged: (v) => controller.searchQuery.value = v,
          decoration: InputDecoration(
            hintText: 'discover_search_hint'.tr,
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ),
    );
  }

  Widget _buildContactsList(ColorScheme colorScheme) {
    return Obx(() {
      final hasCachedContacts = controller.contacts.isNotEmpty;
      if (controller.isLoading.value && !hasCachedContacts) {
        return const Center(child: CircularProgressIndicator());
      }

      if (controller.error.value.isNotEmpty && !hasCachedContacts) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded, size: 42),
                const SizedBox(height: 12),
                Text(controller.error.value, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: controller.loadContacts,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Réessayer'),
                ),
              ],
            ),
          ),
        );
      }

      final list = controller.filteredContacts;
      if (list.isEmpty) {
        return Center(
          child: Text(
            controller.contacts.isEmpty
                ? 'Vous n’avez aucune connexion pour le moment.'
                : 'Aucun contact trouvé.',
            style: TextStyle(color: Colors.grey[500]),
          ),
        );
      }

      return RefreshIndicator(
        onRefresh: controller.loadContacts,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: list.length,
          separatorBuilder: (_, index) => Divider(
            height: 1,
            color: colorScheme.outlineVariant.withValues(alpha: 0.2),
          ),
          itemBuilder: (context, index) {
            final contact = list[index];
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(vertical: 4),
              leading: CircleAvatar(
                radius: 24,
                backgroundColor: colorScheme.primary.withValues(alpha: 0.1),
                backgroundImage: contact.avatarUrl != null && contact.avatarUrl!.isNotEmpty
                    ? NetworkImage(contact.avatarUrl!)
                    : null,
                child: contact.avatarUrl == null || contact.avatarUrl!.isEmpty
                    ? Text(
                        contact.name.isEmpty ? '?' : contact.name.characters.first.toUpperCase(),
                        style: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.bold),
                      )
                    : null,
              ),
              title: Row(
                children: [
                  Flexible(
                    child: Text(
                      contact.name,
                      style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (contact.isCertified) ...[
                    const SizedBox(width: 4),
                    UserCertifiedBadge(size: 14, userId: contact.id)
                  ],
                ],
              ),
              subtitle: Text(
                contact.isBlockedByMe
                    ? '${contact.username.isEmpty ? '' : '@${contact.username} · '}Bloqué par vous'
                    : '@${contact.username}',
                style: TextStyle(
                  color: contact.isBlockedByMe
                      ? colorScheme.error
                      : Colors.grey[500],
                ),
              ),
              trailing: contact.isBlockedByMe
                  ? TextButton.icon(
                      onPressed: () => controller.unblockContact(contact.id),
                      icon: const Icon(Icons.lock_open_rounded, size: 17),
                      label: const Text('Débloquer'),
                      style: TextButton.styleFrom(
                        foregroundColor: colorScheme.primary,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                    )
                  : contact.isOnline
                      ? Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.success,
                            shape: BoxShape.circle,
                          ),
                        )
                      : null,
              onTap: () => _openConversation(contact.id, contact.name, contact.avatarUrl),
            );
          },
        ),
      );
    });
  }

  Future<void> _openConversation(String userId, String userName, String? avatarUrl) async {
    final chatService = Get.find<ChatService>();

    Get.dialog(
      const Center(child: CircularProgressIndicator()),
      barrierDismissible: false,
    );

    final conversation = await chatService.startConversation(userId);

    if (Get.isDialogOpen ?? false) Get.back();

    if (conversation == null) {
      Get.snackbar(
        'Erreur',
        'Impossible d\'ouvrir cette conversation.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    await Get.toNamed(
      AppPages.conversation,
      arguments: {
        'userId': userId,
        'name': conversation.name ?? userName,
        'color': AppColors.primary,
        'avatar': conversation.avatarUrl ?? avatarUrl,
      },
      parameters: {'chatId': conversation.id},
    );
  }
}
