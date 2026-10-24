import 'package:get/get.dart';
import 'package:scrole/modules/module_discussion_direct/interne/controllers/chat_controller.dart' as messaging;
import 'package:scrole/modules/module_discussion_direct/centre/repositories/messaging_repository.dart';

typedef RecordingState = messaging.RecordingState;

/// Compatibility name required by the untouched discussion view.
/// The implementation lives entirely in [messaging.ChatController].
class DirectConversationController extends messaging.ChatController {
  DirectConversationController() : super(Get.find<MessagingRepository>());
}
