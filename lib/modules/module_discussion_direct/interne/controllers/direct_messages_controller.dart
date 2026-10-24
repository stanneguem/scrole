import 'package:get/get.dart';
import 'package:scrole/modules/module_discussion_direct/interne/controllers/conversations_list_controller.dart';
import 'package:scrole/modules/module_discussion_direct/centre/repositories/messaging_repository.dart';

/// Compatibility name required by the untouched conversation-list view.
class DirectMessagesController extends ConversationsListController {
  DirectMessagesController() : super(Get.find<MessagingRepository>());

  Future<bool> deleteConversation(String conversationId) async {
    final repository = Get.find<MessagingRepository>();
    final result = await repository.deleteConversation(conversationId);
    if (!result.success) {
      Get.snackbar(
        'Discussions',
        result.message ?? 'Impossible de supprimer la discussion.',
      );
      return false;
    }
    return true;
  }
}
