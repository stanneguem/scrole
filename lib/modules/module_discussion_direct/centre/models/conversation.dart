import 'message.dart';

class Conversation {
  const Conversation({
    required this.id,
    required this.participantIds,
    this.lastMessagePreview,
    this.unreadCount = 0,
    required this.updatedAt,
    this.name,
    this.avatarUrl,
    this.isGroup = false,
    this.isPinned = false,
  });

  final String id;
  final List<String> participantIds;
  final Message? lastMessagePreview;
  final int unreadCount;
  final DateTime updatedAt;
  final String? name;
  final String? avatarUrl;
  final bool isGroup;
  final bool isPinned;

  String? peerId(String? currentUserId) {
    for (final id in participantIds) {
      if (id.isNotEmpty && id != currentUserId) return id;
    }
    for (final id in participantIds) {
      if (id.isNotEmpty) return id;
    }
    return null;
  }

  Conversation copyWith({List<String>? participantIds, Message? lastMessagePreview, int? unreadCount, DateTime? updatedAt, String? name, String? avatarUrl, bool? isPinned}) => Conversation(
    id: id,
    participantIds: participantIds ?? this.participantIds,
    lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
    unreadCount: unreadCount ?? this.unreadCount,
    updatedAt: updatedAt ?? this.updatedAt,
    name: name ?? this.name,
    avatarUrl: avatarUrl ?? this.avatarUrl,
    isGroup: isGroup,
    isPinned: isPinned ?? this.isPinned,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'participant_ids': participantIds,
    'last_message': lastMessagePreview?.toJson(),
    'unread_count': unreadCount,
    'updated_at': updatedAt.toIso8601String(),
    'name': name,
    'avatar_url': avatarUrl,
    'is_group': isGroup,
    'is_pinned': isPinned,
  };

  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
    id: '${json['id']}',
    participantIds: List<String>.from(json['participant_ids'] ?? const []),
    lastMessagePreview: json['last_message'] is Map ? Message.fromJson(Map<String, dynamic>.from(json['last_message'] as Map)) : null,
    unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
    updatedAt: DateTime.parse('${json['updated_at']}').toUtc(),
    name: json['name'] as String?,
    avatarUrl: json['avatar_url'] as String?,
    isGroup: json['is_group'] == true,
    isPinned: json['is_pinned'] == true,
  );
}
