import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/routes/app_pages.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';
import '../../centre/services/notification_db_service.dart';
import '../../../module_communautes/interne/pages/community_feed_screen.dart';
import '../../../../shared/widgets/shared_post_link_screen.dart';
import '../controllers/notification_controller.dart';

class NotificationScreen extends GetView<NotificationController> {
  const NotificationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<NotificationController>()) {
      Get.put(NotificationController());
    }
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: colorScheme.onSurface),
          onPressed: Get.back,
        ),
        title: Text(
          'notifications_title'.tr,
          style: AppTextStyles.h6.copyWith(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.bold,
            fontSize: 17,
          ),
        ),
        actions: [
          Obx(() {
            if (controller.notifications.isEmpty) return const SizedBox.shrink();

            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (controller.unreadCount.value > 0)
                  TextButton(
                    onPressed: controller.markAllAsRead,
                    child: Text(
                      'notifications_mark_all_read'.tr,
                      style: AppTextStyles.labelMedium.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.delete_sweep_rounded, color: AppColors.error, size: 20),
                  tooltip: 'notifications_delete_all'.tr,
                  onPressed: () => _confirmDeleteAll(context),
                ),
              ],
            );
          }),
        ],
      ),
      body: Obx(() {
        if (controller.isLoading.value && controller.notifications.isEmpty) {
          return const Center(child: CircularProgressIndicator(color: AppColors.primary));
        }
        if (controller.notifications.isEmpty) {
          return _EmptyState(onRefresh: controller.refreshNotifications);
        }
        return RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () => controller.refreshNotifications(),
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: controller.notifications.length,
            separatorBuilder: (context, index) => const SizedBox(height: 6),
            itemBuilder: (_, index) {
              final notification = controller.notifications[index];
              return _NotificationTile(
                notification: notification,
                onTap: () => _handleNotification(notification),
                onMarkAsRead: () => controller.markAsRead(notification.id),
                onDelete: () => controller.deleteNotification(notification.id),
                avatarUrl: controller.photoUrlOf(notification),
              );
            },
          ),
        );
      }),
    );
  }

  void _confirmDeleteAll(BuildContext context) {
    Get.dialog(
      AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('notifications_delete_all_confirm_title'.tr),
        content: Text('notifications_delete_all_confirm_msg'.tr),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: Text('cancel'.tr),
          ),
          TextButton(
            onPressed: () {
              Get.back();
              controller.deleteAllNotifications();
            },
            child: Text(
              'delete'.tr,
              style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleNotification(NotificationEntry notification) async {
    await controller.markAsRead(notification.id);
    final payload = controller.payloadOf(notification);
    final rawData = payload['data'];
    final data = rawData is Map
        ? Map<String, dynamic>.from(rawData)
        : <String, dynamic>{};

    String? idOf(List<String> keys) {
      for (final key in keys) {
        final value = data[key] ?? payload[key];
        if (value != null && value.toString().isNotEmpty && value.toString() != 'null') {
          return value.toString();
        }
      }
      return null;
    }

    final type = notification.type.toLowerCase();

    if (type == 'follow_request') {
      Get.toNamed(AppPages.followRequests, arguments: {'requestId': data['request_id']});
      return;
    }

    // Mentions : ouvrir la cible (publication/commentaire) plutôt que seulement
    // marquer la notification comme lue. Pour une publication communautaire,
    // ouvrir le fil de cette communauté et transmettre les identifiants cibles.
    final isMention = type.contains('mention') ||
        type == 'mentioned_in_post' ||
        type == 'mentioned_in_comment' ||
        type == 'mention_publication' ||
        type == 'mention_commentaire';
    if (isMention) {
      final communityId = idOf(['community_id', 'communaute_id', 'target_community_id']);
      final postId = idOf(['post_id', 'publication_id', 'source_post_id', 'target_post_id']);
      final commentId = idOf(['comment_id', 'commentaire_id', 'target_comment_id']);
      final eventId = idOf(['event_id', 'evenement_id', 'target_event_id']);

      if (communityId != null && communityId.isNotEmpty) {
        Get.to(() => CommunityFeedScreen(communityId: communityId, communityName: (data['community_name'] ?? data['community_nom'] ?? 'Communauté').toString()), arguments: {
          'postId': postId,
          'commentId': commentId,
          'openComment': commentId != null,
        });
        return;
      }
      // If the mention was made inside a comment, open that comment's post first.
      // The event remains accessible from the comment itself.
      if (postId != null && postId.isNotEmpty) {
        try {
          final post = await Supabase.instance.client
              .from('posts')
              .select('id,community_id')
              .eq('id', postId)
              .maybeSingle();
          final targetCommunity = post?['community_id']?.toString() ?? communityId;
          if (targetCommunity != null && targetCommunity.isNotEmpty) {
            Get.to(() => CommunityFeedScreen(communityId: targetCommunity, communityName: (data['community_name'] ?? data['community_nom'] ?? 'Communauté').toString()), arguments: {
              'postId': postId,
              'commentId': commentId,
              'openComment': commentId != null,
            });
            return;
          }
        } catch (e) {
          debugPrint('[Notification] Could not resolve mention target post: $e');
        }
      }
      if (eventId != null && eventId.isNotEmpty) {
        await controller.goToEventPreview(eventId);
        return;
      }
      final mentionedUserId = idOf(['mentioned_user_id', 'target_user_id', 'profile_user_id']);
      if (mentionedUserId != null && mentionedUserId.isNotEmpty) {
        Get.toNamed(AppPages.externalProfilePath(mentionedUserId));
        return;
      }
    }

    // Lorsqu'une publication reçoit un commentaire ou une réponse, ouvrir
    // directement sa page dédiée « Publication » (qu'elle soit personnelle ou
    // communautaire), puis cibler le commentaire si son identifiant est fourni.
    final contentPostId = idOf(['post_id', 'publication_id', 'source_post_id', 'target_post_id']);
    final contentCommentId = idOf(['comment_id', 'commentaire_id', 'target_comment_id']);
    final isCommentNotification = type.contains('comment') ||
        type.contains('reply') ||
        type.contains('commentaire');
    if (contentPostId != null &&
        contentPostId.isNotEmpty &&
        isCommentNotification) {
      Get.to(
        () => SharedPostLinkScreen(
          postId: contentPostId,
          commentId: contentCommentId,
        ),
        preventDuplicates: false,
      );
      return;
    }

    // Les autres notifications liées à une communauté peuvent toujours ouvrir
    // le fil de la communauté sans passer par la page dédiée à une publication.
    final contentCommunityId = idOf(['community_id', 'communaute_id', 'target_community_id']);
    if (contentPostId != null &&
        contentCommunityId != null &&
        type == 'community_post_like') {
      Get.to(
        () => CommunityFeedScreen(
          communityId: contentCommunityId,
          communityName: (data['community_name'] ?? data['community_nom'] ?? 'Communauté').toString(),
        ),
        arguments: {'postId': contentPostId},
      );
      return;
    }

    // Les invitations d'événement ouvrent la fiche de l'événement.
    final eventTargetId = idOf(['event_id', 'evenement_id', 'eventId']);
    if (eventTargetId != null &&
        (type.contains('invitation') || type.contains('invite') || type.contains('evenement'))) {
      await controller.goToEventPreview(eventTargetId);
      return;
    }

    // Les notifications de communauté ouvrent la communauté visée.
    final communityTargetId = idOf(['community_id', 'communaute_id', 'target_community_id']);
    if (communityTargetId != null &&
        (type.contains('community') || type.contains('communaute') || type.contains('publication'))) {
      Get.to(() => CommunityFeedScreen(communityId: communityTargetId, communityName: (data['community_name'] ?? data['community_nom'] ?? 'Communauté').toString()));
      return;
    }

    // Les notifications de relation ouvrent le profil de l'autre personne.
    if (['new_follower', 'new_friend', 'follow_request_accepted', 'friend_via_qr',
         'connection_request', 'connection_accepted', 'demande_ami', 'demande_ami_acceptee', 'ami_confirme'].contains(type)) {
      final actorId = payload['actor_id']?.toString() ?? (data is Map ? data['user_id']?.toString() : null);
      if (actorId != null && actorId.isNotEmpty) {
        Get.toNamed(AppPages.externalProfilePath(actorId));
        return;
      }
    }

    // Cas 2 : Transfert, Invitation Staff, Invité d'honneur ou Sponsor -> Preview de l'événement
    if (notification.type == 'transfert_propriete_evenement' || 
        notification.type == 'invitation_staff' || 
        notification.type == 'invitation_guest_evenement' || 
        notification.type == 'invitation_guest' || 
        notification.type == 'guest_invitation' || 
        notification.type == 'invitation_sponsor_evenement' || 
        notification.type == 'invitation_sponsor' || 
        notification.type == 'sponsor_invitation' || 
        notification.type == 'evenement_modifie') {
      final eventId = data?['evenement_id']?.toString() ?? data?['event_id']?.toString();
      if (eventId != null && eventId.isNotEmpty) {
        await controller.goToEventPreview(eventId);
        return;
      }
    }
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.notification,
    required this.onTap,
    required this.onMarkAsRead,
    required this.onDelete,
    this.avatarUrl,
  });

  final NotificationEntry notification;
  final VoidCallback onTap;
  final VoidCallback onMarkAsRead;
  final VoidCallback onDelete;
  final String? avatarUrl;

  String? _genericNotificationFamily(String rawType) {
    final type = rawType.toLowerCase();
    const families = <String, String>{
      'evenement_like': 'like',
      'story_like': 'like',
      'community_post_like': 'like',
      'post_comment': 'comment',
      'story_comment': 'comment',
      'story_comment_reply': 'comment',
      'community_comment_mention': 'mention',
      'community_post_mention': 'mention',
      'community_mentioned_in_post': 'mention',
      'community_mentioned_in_comment': 'mention',
      'event_mentioned_in_comment': 'mention',
      'event_mentioned_in_post': 'mention',
      'event_organizer_mentioned_in_post': 'mention',
      'event_organizer_mentioned_in_comment': 'mention',
      'invitation_staff': 'invitation',
      'invitation_staff_evenement': 'invitation',
      'invitation_staff_activite': 'invitation',
      'invitation_guest_evenement': 'invitation',
      'invitation_guest': 'invitation',
      'guest_invitation': 'invitation',
      'invitation_sponsor_evenement': 'invitation',
      'invitation_sponsor': 'invitation',
      'sponsor_invitation': 'invitation',
      'connection_request': 'request',
      'demande_ami': 'request',
      'demande_connexion': 'request',
      'community_join_request': 'request',
      'connection_accepted': 'accepted',
      'demande_ami_acceptee': 'accepted',
      'reponse_demande_communaute': 'accepted',
      'post_shared_story': 'share',
      'bienvenue': 'welcome',
      'evenement_valide': 'approved',
      'invitation_guest_annulee': 'canceled',
      'invitation_staff_activite_annulee': 'canceled',
      'promotion_co_createur_evenement': 'promotion',
      'reponse_invitation_staff': 'reply',
      'evenement_modifie': 'event_update',
    };
    return families[type];
  }

  String _localizedTitle(NotificationController controller) {
    final type = notification.type.toLowerCase();
    const supported = {'new_follower', 'new_friend', 'follow_request', 'follow_request_accepted', 'friend_via_qr'};
    if (supported.contains(type)) {
      final payload = controller.payloadOf(notification);
      final rawData = payload['data'];
      final data = rawData is Map ? Map<String, dynamic>.from(rawData) : <String, dynamic>{};
      final name = (data['display_name'] ?? data['name'] ?? data['username'] ?? data['pseudo'] ?? payload['actor_name'] ?? '').toString();
      final key = switch (type) {
        'new_follower' => 'follow_notification_new_follower',
        'new_friend' => 'follow_notification_new_friend',
        'follow_request' => 'follow_notification_request',
        'follow_request_accepted' => 'follow_notification_accepted',
        _ => 'follow_notification_friend_qr',
      };
      return key.trParams({'name': name});
    }
    final family = _genericNotificationFamily(type);
    if (family != null) return 'notification_generic_${family}_title'.tr;
    // A direct message body is user-generated content and must never be translated.
    return notification.title;
  }

  String _localizedMessage(NotificationController controller) {
    final type = notification.type.toLowerCase();
    const followTypes = {'new_follower', 'new_friend', 'follow_request', 'follow_request_accepted', 'friend_via_qr'};
    if (followTypes.contains(type)) return '';
    final family = _genericNotificationFamily(type);
    if (family != null) return 'notification_generic_${family}_body'.tr;
    // For messages, keep the sender's original text exactly as written.
    return notification.message;
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<NotificationController>();
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final v = _getVisual(notification.type);
    final cardBg = notification.isRead
        ? Colors.transparent
        : (isDark
            ? AppColors.primary.withValues(alpha: 0.08)
            : AppColors.primary.withValues(alpha: 0.04));

    return Dismissible(
      key: ValueKey('dismiss-${notification.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(color: AppColors.error, borderRadius: BorderRadius.circular(12)),
        child: const Icon(Icons.delete_rounded, color: Colors.white, size: 20),
      ),
      onDismissed: (_) => onDelete(),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: notification.isRead
                  ? colorScheme.outlineVariant.withValues(alpha: 0.15)
                  : AppColors.primary.withValues(alpha: 0.2),
              width: 0.8,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildLeading(notification, avatarUrl, v),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            _localizedTitle(controller),
                            style: AppTextStyles.body.copyWith(
                              color: colorScheme.onSurface,
                              fontSize: 13.5,
                              fontWeight: notification.isRead ? FontWeight.w500 : FontWeight.bold,
                            ),
                          ),
                        ),
                        if (!notification.isRead)
                          Container(
                            width: 7,
                            height: 7,
                            margin: const EdgeInsets.only(left: 6, top: 4),
                            decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _localizedMessage(controller),
                      style: AppTextStyles.bodySmall.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.schedule_rounded,
                          size: 11,
                          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          _formatTime(notification.createdAt),
                          style: AppTextStyles.caption.copyWith(
                            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    _buildActionButtons(context, controller, notification),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert_rounded, color: colorScheme.onSurfaceVariant, size: 18),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onSelected: (value) {
                  if (value == 'read') onMarkAsRead();
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (_) => [
                  if (!notification.isRead) PopupMenuItem(value: 'read', child: Text('notifications_mark_as_read'.tr)),
                  PopupMenuItem(value: 'delete', child: Text('notifications_delete'.tr)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLeading(NotificationEntry notification, String? avatarUrl, ({IconData icon, Color color}) v) {
    if ((notification.type == 'connection_request' || 
         notification.type == 'invitation_staff' || 
         notification.type == 'invitation_guest_evenement' || 
         notification.type == 'invitation_guest' || 
         notification.type == 'guest_invitation' || 
         notification.type == 'invitation_sponsor_evenement' || 
         notification.type == 'invitation_sponsor' || 
         notification.type == 'sponsor_invitation') && avatarUrl != null && avatarUrl.isNotEmpty) {
      return CircleAvatar(radius: 18, backgroundImage: NetworkImage(avatarUrl));
    }
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: v.color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: Icon(v.icon, size: 18, color: v.color),
    );
  }

  Widget _buildActionButtons(BuildContext context, NotificationController controller, NotificationEntry notification) {
    final payload = controller.payloadOf(notification);
    final data = payload['data'] is Map ? Map<String, dynamic>.from(payload['data'] as Map) : <String, dynamic>{};
    final type = notification.type.toLowerCase();

    // Canceled/revoked invitations are informational and must not offer stale actions.
    final actionable = data['actionable'] ?? payload['actionable'];
    if (actionable == false ||
        type.endsWith('_annulee') ||
        type.endsWith('_annulée') ||
        type.contains('invitation_annulee')) {
      return const SizedBox.shrink();
    }

    // Si une action a déjà été prise, on affiche le résultat au lieu des boutons
    if (notification.actionStatus != 'pending') {
      final isAccepted = notification.actionStatus == 'accepted';
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: (isAccepted ? AppColors.success : AppColors.error).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isAccepted ? Icons.check_circle_rounded : Icons.cancel_rounded,
                size: 14,
                color: isAccepted ? AppColors.success : AppColors.error,
              ),
              const SizedBox(width: 5),
              Text(
                isAccepted ? 'notifications_action_accepted'.tr : 'notifications_action_refused'.tr,
                style: AppTextStyles.labelSmall.copyWith(
                  color: isAccepted ? AppColors.success : AppColors.error,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      );
    }

    String? resolveId(List<String> keys) {
      for (final k in keys) {
        final val = data[k] ?? payload[k];
        if (val != null && val.toString().isNotEmpty && val.toString() != 'null') {
          return val.toString();
        }
      }
      return null;
    }

    if (type == 'connection_request' || type == 'follow_request' || type == 'demande_ami' || type == 'friend_request' || type == 'demande_connexion') {
      final requestId = resolveId(['request_id', 'id', 'friend_request_id']);
      if (requestId == null) return const SizedBox.shrink();
      return _ActionRow(
        onAccept: () => _respond(controller, notification, () => controller.respondToConnectionRequest(notification.id, requestId, true)),
        onRefuse: () => _respond(controller, notification, () => controller.respondToConnectionRequest(notification.id, requestId, false)),
      );
    }

    if (type == 'invitation_staff_activite' || type == 'invitation_staff_activity' || type == 'staff_activity_invite') {
      final inviteId = resolveId(['p_invite_id', 'invite_id', 'id', 'staff_id']);
      if (inviteId == null) return const SizedBox.shrink();
      return _ActionRow(
        onAccept: () => _respond(controller, notification, () => controller.respondToActivityStaffInvitation(notification.id, inviteId, true)),
        onRefuse: () => _respond(controller, notification, () => controller.respondToActivityStaffInvitation(notification.id, inviteId, false)),
      );
    }

    if (type == 'proposition_transfert_activite' || type == 'transfert_propriete_activite' || type == 'activity_transfer') {
      final transferId = resolveId(['p_transfer_id', 'transfer_id', 'transfert_id', 'id']);
      if (transferId == null) return const SizedBox.shrink();
      return _ActionRow(
        onAccept: () => _respond(controller, notification, () => controller.respondToActivityTransferRequest(notification.id, transferId, true)),
        onRefuse: () => _respond(controller, notification, () => controller.respondToActivityTransferRequest(notification.id, transferId, false)),
      );
    }

    if (type == 'invitation_staff' || type == 'invitation_staff_evenement' || type == 'event_staff_invite') {
      final staffId = resolveId(['staff_evenement_id', 'staff_id', 'invite_id', 'id']);
      if (staffId == null) return const SizedBox.shrink();
      return _ActionRow(
        onAccept: () => _respond(controller, notification, () => controller.respondToStaffInvitation(notification.id, staffId, true)),
        onRefuse: () => _respond(controller, notification, () => controller.respondToStaffInvitation(notification.id, staffId, false)),
      );
    }

    if (type == 'invitation_co_createur_evenement' || type == 'invitation_co_creator' || type == 'co_creator_invite') {
      final inviteId = resolveId(['p_invite_id', 'invite_id', 'co_creator_id', 'id']);
      if (inviteId == null) return const SizedBox.shrink();
      return _ActionRow(
        onAccept: () => _respond(controller, notification, () => controller.respondToCoCreatorInvitation(notification.id, inviteId, true)),
        onRefuse: () => _respond(controller, notification, () => controller.respondToCoCreatorInvitation(notification.id, inviteId, false)),
      );
    }

    if (type == 'transfert_propriete_evenement' || type == 'proposition_transfert_evenement' || type == 'event_transfer') {
      final transferId = resolveId(['transfert_id', 'transfer_id', 'id']);
      if (transferId == null) return const SizedBox.shrink();
      return _ActionRow(
        onAccept: () => _respond(controller, notification, () => controller.respondToTransferRequest(notification.id, transferId, true)),
        onRefuse: () => _respond(controller, notification, () => controller.respondToTransferRequest(notification.id, transferId, false)),
      );
    }

    if (type == 'invitation_guest_evenement' ||
        type == 'invitation_guest' ||
        type == 'guest_invitation' ||
        type == 'invitation_invite_honneur') {
      final inviteId = resolveId(['p_invite_id', 'invite_id', 'id', 'guest_id']);
      if (inviteId == null) return const SizedBox.shrink();
      return _ActionRow(
        onAccept: () => _respond(controller, notification, () => controller.respondToGuestInvitation(notification.id, inviteId, true)),
        onRefuse: () => _respond(controller, notification, () => controller.respondToGuestInvitation(notification.id, inviteId, false)),
      );
    }

    if (type == 'invitation_sponsor_evenement' ||
        type == 'invitation_sponsor' ||
        type == 'sponsor_invitation') {
      final inviteId = resolveId(['p_invite_id', 'invite_id', 'id', 'sponsor_id']);
      if (inviteId == null) return const SizedBox.shrink();
      return _ActionRow(
        onAccept: () => _respond(controller, notification, () => controller.respondToSponsorInvitation(notification.id, inviteId, true)),
        onRefuse: () => _respond(controller, notification, () => controller.respondToSponsorInvitation(notification.id, inviteId, false)),
      );
    }

    return const SizedBox.shrink();
  }

  Future<void> _respond(NotificationController controller, NotificationEntry notification, Future<void> Function() action) async {
    try {
      await action();
      await controller.markAsRead(notification.id);
      Get.snackbar('profile_success_title'.tr, 'confirm'.tr);
    } catch (e) {
      Get.snackbar('profile_error_title'.tr, 'error'.tr);
    }
  }

  ({IconData icon, Color color}) _getVisual(String rawType) {
    final type = rawType.toLowerCase();
    switch (type) {
      case 'activite_validee':
      case 'activity_validated':
      case 'evenement_valide':
      case 'event_validated':
      case 'success':
        return (icon: Icons.verified_rounded, color: AppColors.success);
      case 'activite_rejetee':
      case 'activity_rejected':
      case 'evenement_rejete':
      case 'event_rejected':
      case 'warning':
        return (icon: Icons.gpp_bad_rounded, color: AppColors.error);
      case 'activite_suppression_j30':
      case 'activite_liee_suppression_j30':
      case 'evenement_suppression_j30':
        return (icon: Icons.pending_actions_rounded, color: Colors.orange);
      case 'new_follower':
      case 'new_friend':
      case 'follow_request':
      case 'follow_request_accepted':
      case 'friend_via_qr':
      case 'connection_request':
      case 'demande_ami':
      case 'friend_request':
      case 'demande_connexion':
        return (icon: Icons.person_add_rounded, color: AppColors.primary);
      case 'connection_accepted':
      case 'ami_accepte':
        return (icon: Icons.people_alt_rounded, color: AppColors.success);
      case 'transfert_propriete_evenement':
      case 'proposition_transfert_evenement':
      case 'proposition_transfert_activite':
      case 'transfert_propriete_activite':
        return (icon: Icons.swap_horizontal_circle_rounded, color: AppColors.primary);
      case 'invitation_staff':
      case 'invitation_staff_evenement':
      case 'invitation_staff_activite':
      case 'invitation_staff_activity':
        return (icon: Icons.badge_rounded, color: AppColors.primary);
      case 'invitation_co_createur_evenement':
      case 'invitation_co_creator':
        return (icon: Icons.groups_rounded, color: AppColors.primary);
      case 'invitation_guest_evenement':
      case 'invitation_guest':
      case 'guest_invitation':
      case 'invitation_invite_honneur':
      case 'invitation_guest_acceptee':
        return (icon: Icons.workspace_premium_rounded, color: AppColors.primary);
      case 'invitation_guest_refusee':
      case 'invitation_guest_annulee':
        return (icon: Icons.cancel_schedule_send_rounded, color: AppColors.error);
      case 'invitation_sponsor_evenement':
      case 'invitation_sponsor':
      case 'sponsor_invitation':
      case 'invitation_sponsor_acceptee':
        return (icon: Icons.workspace_premium_outlined, color: AppColors.primary);
      case 'invitation_sponsor_refusee':
      case 'invitation_sponsor_annulee':
        return (icon: Icons.cancel_schedule_send_rounded, color: AppColors.error);
      case 'evenement_modifie':
      case 'activity_updated':
        return (icon: Icons.edit_notifications_rounded, color: AppColors.primary);
      case 'offer':
        return (icon: Icons.local_offer_rounded, color: AppColors.secondary);
      default:
        return (icon: Icons.notifications_active_rounded, color: AppColors.primary);
    }
  }

  String _formatTime(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 60) return 'time_ago_minutes'.trParams({'count': diff.inMinutes.toString()});
    if (diff.inHours < 24) return 'time_ago_hours'.trParams({'count': diff.inHours.toString()});
    return DateFormat('dd/MM/yyyy HH:mm').format(date);
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.onAccept, required this.onRefuse});
  final VoidCallback onAccept;
  final VoidCallback onRefuse;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          _ActionButton(label: 'refuse'.tr, isPrimary: false, onTap: onRefuse),
          const SizedBox(width: 8),
          _ActionButton(label: 'accept'.tr, isPrimary: true, onTap: onAccept),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.label, required this.isPrimary, required this.onTap});
  final String label;
  final bool isPrimary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: isPrimary ? AppColors.primary : Colors.transparent,
          border: isPrimary ? null : Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          style: AppTextStyles.labelSmall.copyWith(
            color: isPrimary ? Colors.white : AppColors.textSecondary,
            fontWeight: FontWeight.bold,
            fontSize: 11,
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onRefresh});
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.notifications_none_rounded, size: 42, color: AppColors.primary),
            ),
            const SizedBox(height: 16),
            Text('notifications_empty_title'.tr, style: AppTextStyles.h6.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('notifications_empty_subtitle'.tr, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text('notifications_refresh'.tr, style: const TextStyle(fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }
}
