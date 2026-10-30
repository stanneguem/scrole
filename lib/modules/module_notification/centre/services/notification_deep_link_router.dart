import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/routes/app_pages.dart';
import '../../../module_communautes/interne/pages/community_feed_screen.dart';
import '../../../module_communautes/interne/pages/community_chat_groups_screen.dart';
import '../../../module_principale/interne/pages/home_feed_screen.dart';
import '../../../../shared/widgets/shared_post_link_screen.dart';

/// Shared deep-link handler for taps from the notification center, FCM and
/// local notifications. Payloads are untrusted and identifiers are validated
/// before any navigation or backend lookup.
class NotificationDeepLinkRouter {
  NotificationDeepLinkRouter._();

  static Future<void> open(Map<String, dynamic> rawPayload) async {
    final payload = Map<String, dynamic>.from(rawPayload);
    final nested = payload['data'];
    final data = nested is Map
        ? Map<String, dynamic>.from(nested)
        : <String, dynamic>{};
    final type = (data['type'] ?? payload['type'] ?? '').toString().toLowerCase();

    String? value(List<String> keys) {
      for (final key in keys) {
        final candidate = data[key] ?? payload[key];
        if (candidate == null) continue;
        final text = candidate.toString().trim();
        if (text.isNotEmpty && text != 'null') return text;
      }
      return null;
    }

    final postId = value(['post_id', 'publication_id', 'source_post_id', 'target_post_id']);
    final commentId = value(['comment_id', 'commentaire_id', 'target_comment_id']);
    final communityId = value(['community_id', 'communaute_id', 'target_community_id']);
    final eventId = value(['event_id', 'evenement_id', 'eventId']);
    final actorId = value(['actor_id', 'sender_id', 'user_id', 'target_user_id']);

    try {
      if (type == 'community_salon_message') {
        final salonId = value(['salon_id']);
        if (salonId != null &&
            RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(salonId)) {
          final client = Supabase.instance.client;
          final rawSettings = await client.rpc(
            'get_community_chat_group_settings',
            params: {'p_salon_id': salonId},
          );
          final settings = Map<String, dynamic>.from(rawSettings as Map);
          final parentCommunityId = settings['community_id']?.toString() ?? '';
          final community = parentCommunityId.isEmpty
              ? null
              : await client
                  .from('communities')
                  .select('name')
                  .eq('id', parentCommunityId)
                  .maybeSingle();
          Get.to(
            () => CommunityChatGroupConversation(
              salonId: salonId,
              name: (settings['name'] ?? '').toString(),
              communityName: (community?['name'] ?? '').toString(),
              avatarUrl: settings['avatar_url']?.toString(),
            ),
            preventDuplicates: false,
          );
        }
        return;
      }

      // All post/comment mentions use one canonical detail screen. This works
      // for personal posts and community posts and can focus the exact comment.
      if (postId != null) {
        Get.to(
          () => SharedPostLinkScreen(
            postId: postId,
            commentId: commentId ?? value(['parent_comment_id']),
          ),
          preventDuplicates: false,
        );
        return;
      }

      if (eventId != null) {
        Get.toNamed(
          AppPages.eventPreview.replaceFirst(':id', eventId),
          arguments: {'id': eventId, 'eventId': eventId},
        );
        return;
      }

      if (actorId != null &&
          (type.contains('follow') ||
              type.contains('friend') ||
              type.contains('connection') ||
              type.contains('ami'))) {
        Get.toNamed(AppPages.externalProfilePath(actorId));
        return;
      }

      if (type == 'message_received') {
        final conversationId = value(['conversation_id']);
        if (conversationId != null) {
          Get.toNamed(
            AppPages.conversation,
            parameters: {'chatId': conversationId},
            arguments: {
              'userId': value(['sender_id']) ?? '',
              'name': value(['sender_name']) ?? 'Ami',
              'avatar': value(['sender_photo_url']),
            },
          );
        }
      }
    } catch (e, st) {
      debugPrint('[NotificationDeepLinkRouter] Navigation failed: $e');
      debugPrintStack(stackTrace: st);
      Get.snackbar(
        'Notification',
        'Impossible d’ouvrir ce contenu. Il a peut-être été supprimé ou tu n’y as plus accès.',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }
}
