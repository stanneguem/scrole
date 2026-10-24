import 'package:get/get.dart';
import '../repositories/messaging_repository.dart';
import '../models/conversation_model.dart';
import '../models/message_model.dart';

/// Resolves the local chat state without creating a server conversation.
/// A missing conversation is represented by a local-only draft.
class ChatService {
  ChatService(this._repository);
  final MessagingRepository _repository;

  Future<ConversationModel?> startConversation(String userId) async {
    if (userId.isEmpty) return null;

    final local = await _repository.getLocalConversationWithUser(userId);
    if (local != null) {
      return ConversationModel(
        id: local.id,
        name: local.name,
        avatarUrl: local.avatarUrl,
        participantIds: local.participantIds,
        lastMessage: local.lastMessagePreview == null ? null : MessageModel.fromMessage(local.lastMessagePreview!),
        updatedAt: local.updatedAt,
        unreadCount: local.unreadCount,
        isGroup: local.isGroup,
        isPinned: local.isPinned,
      );
    }

    final currentUserId = _repository.currentUserId;
    if (currentUserId == null) return null;

    return ConversationModel(
      id: 'draft_$userId',
      name: null,
      avatarUrl: null,
      participantIds: [currentUserId, userId],
      lastMessage: null,
      updatedAt: DateTime.now().toUtc(),
      unreadCount: 0,
      isGroup: false,
      isPinned: false,
    );
  }
}

ChatService ensureChatService() {
  if (!Get.isRegistered<ChatService>()) {
    return Get.put(
      ChatService(Get.find<MessagingRepository>()),
      permanent: true,
    );
  }
  return Get.find<ChatService>();
}
