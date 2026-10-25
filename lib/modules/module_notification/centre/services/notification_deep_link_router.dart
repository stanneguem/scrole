import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/routes/app_pages.dart';
import '../../../module_communautes/interne/pages/community_feed_screen.dart';
import '../../../module_principale/interne/pages/home_feed_screen.dart';

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
      // Comment/reply/mention payloads usually carry community_id and post_id.
      if (communityId != null &&
          (postId != null ||
              type.contains('mention') ||
              type.contains('comment') ||
              type.contains('publication') ||
              type.contains('community'))) {
        Get.to(
          () => CommunityFeedScreen(
            communityId: communityId,
            communityName: (value(['community_name', 'community_nom']) ?? 'Communauté'),
          ),
          arguments: {
            'postId': postId,
            'commentId': commentId ?? value(['parent_comment_id']),
            'openComment': commentId != null,
          },
        );
        return;
      }

      if (postId != null) {
        // A personal-feed mention has no source community. Open the home feed
        // with the exact post/comment target instead of falling through to the
        // mentioned event's page.
        Get.to(
          () => const HomeFeedScreen(),
          arguments: {
            'targetPostId': postId,
            'targetCommentId': commentId ?? value(['parent_comment_id']),
          },
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
