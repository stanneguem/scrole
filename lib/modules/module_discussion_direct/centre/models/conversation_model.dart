import 'conversation.dart';
import 'message.dart';
import 'message_model.dart';

/// Compatibility facade for the unchanged conversation-list view.
class ConversationModel extends Conversation {
  const ConversationModel({
    required super.id,
    super.name,
    super.avatarUrl,
    required super.participantIds,
    MessageModel? lastMessage,
    required super.updatedAt,
    super.unreadCount,
    super.isGroup,
    super.isPinned,
  }) : super(lastMessagePreview: lastMessage);

  MessageModel? get lastMessage => lastMessagePreview == null ? null : MessageModel.fromMessage(lastMessagePreview!);

  factory ConversationModel.fromJson(Map<String, dynamic> json) => ConversationModel(
    id: '${json['id']}', name: json['name'] as String?, avatarUrl: json['avatar_url'] as String?,
    participantIds: List<String>.from(json['participant_ids'] ?? const []),
    lastMessage: json['last_message'] is Map ? MessageModel.fromMessage(Message.fromJson(Map<String, dynamic>.from(json['last_message'] as Map))) : null,
    updatedAt: DateTime.parse('${json['updated_at']}').toUtc(), unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
    isGroup: json['is_group'] == true, isPinned: json['is_pinned'] == true,
  );

  factory ConversationModel.fromBackendJson(Map<String, dynamic> json) {
    final first = json['other_first_name'] as String?;
    final last = json['other_last_name'] as String?;
    final username = json['other_username'] as String?;
    final name = [first, last].where((e) => e != null && e.trim().isNotEmpty).join(' ').trim();
    final text = json['last_message_text'] as String?;
    final at = json['last_message_at'] as String?;
    final preview = text == null || at == null ? null : MessageModel(
      id: '${json['last_message_id'] ?? ''}', conversationId: '${json['id']}', senderId: '${json['last_message_sender_id'] ?? ''}',
      text: text, type: MessageType.values.firstWhere((e) => e.name == json['last_message_type'], orElse: () => MessageType.text), createdAt: DateTime.parse(at).toUtc(),
    );
    return ConversationModel(
      id: '${json['id']}', name: name.isNotEmpty ? name : username, avatarUrl: json['other_photo_url'] as String?, participantIds: ['${json['other_user_id']}'],
      lastMessage: preview, updatedAt: DateTime.parse('${at ?? DateTime.now().toIso8601String()}').toUtc(), unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
    );
  }
}