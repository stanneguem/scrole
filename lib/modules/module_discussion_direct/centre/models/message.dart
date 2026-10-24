enum MessageType { text, audio, image, video, file, poll }

enum MessageStatus { pending, sent, delivered, read, failed, sending, received, error }

class Message {
  const Message({
    required this.id,
    required this.localId,
    required this.conversationId,
    required this.senderId,
    this.content,
    this.mediaUrls,
    this.audioUrl,
    this.audioDuration,
    this.type = MessageType.text,
    required this.sentAt,
    this.status = MessageStatus.sent,
    this.editedAt,
    this.deletedAt,
    this.deletedForMe = false,
    this.isDeletedForEveryone = false,
    this.senderIsCertifiedAtDeletion,
    this.repliedToId,
  });

  final String id;
  final String localId;
  final String conversationId;
  final String senderId;
  final String? content;
  final List<String>? mediaUrls;
  final String? audioUrl;
  final Duration? audioDuration;
  final MessageType type;
  final DateTime sentAt;
  final MessageStatus status;
  final DateTime? editedAt;
  final DateTime? deletedAt;
  final bool deletedForMe;
  final bool isDeletedForEveryone;
  final bool? senderIsCertifiedAtDeletion;
  final String? repliedToId;

  String? get text => content;
  DateTime get createdAt => sentAt;
  bool get isEdited => editedAt != null;
  bool get isDeleted => deletedForMe || isDeletedForEveryone || deletedAt != null;
  bool get deletedSilently => deletedForMe || (isDeletedForEveryone && senderIsCertifiedAtDeletion == true);
  bool get editedSilently => senderIsCertifiedAtDeletion == true;

  Message copyWith({
    String? id,
    String? localId,
    String? conversationId,
    String? senderId,
    String? content,
    List<String>? mediaUrls,
    String? audioUrl,
    Duration? audioDuration,
    MessageType? type,
    DateTime? sentAt,
    MessageStatus? status,
    DateTime? editedAt,
    DateTime? deletedAt,
    bool? deletedForMe,
    bool? isDeletedForEveryone,
    bool? senderIsCertifiedAtDeletion,
    String? repliedToId,
  }) => Message(
    id: id ?? this.id,
    localId: localId ?? this.localId,
    conversationId: conversationId ?? this.conversationId,
    senderId: senderId ?? this.senderId,
    content: content ?? this.content,
    mediaUrls: mediaUrls ?? this.mediaUrls,
    audioUrl: audioUrl ?? this.audioUrl,
    audioDuration: audioDuration ?? this.audioDuration,
    type: type ?? this.type,
    sentAt: sentAt ?? this.sentAt,
    status: status ?? this.status,
    editedAt: editedAt ?? this.editedAt,
    deletedAt: deletedAt ?? this.deletedAt,
    deletedForMe: deletedForMe ?? this.deletedForMe,
    isDeletedForEveryone: isDeletedForEveryone ?? this.isDeletedForEveryone,
    senderIsCertifiedAtDeletion: senderIsCertifiedAtDeletion ?? this.senderIsCertifiedAtDeletion,
    repliedToId: repliedToId ?? this.repliedToId,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'local_id': localId,
    'conversation_id': conversationId,
    'sender_id': senderId,
    'content': content,
    'text': content,
    'media_urls': mediaUrls,
    'audio_url': audioUrl,
    'audio_duration': audioDuration?.inSeconds,
    'type': type.name,
    'sent_at': sentAt.toIso8601String(),
    'created_at': sentAt.toIso8601String(),
    'status': status.name,
    'edited_at': editedAt?.toIso8601String(),
    'deleted_at': deletedAt?.toIso8601String(),
    'deleted_for_me': deletedForMe,
    'is_deleted_for_everyone': isDeletedForEveryone,
    'sender_is_certified_at_deletion': senderIsCertifiedAtDeletion,
    'replied_to_id': repliedToId,
  };

  factory Message.fromJson(Map<String, dynamic> json) {
    final created = json['sent_at'] ?? json['created_at'];
    final rawMediaUrls = json['media_urls'];
    final parsedMediaUrls = rawMediaUrls is List
        ? rawMediaUrls.map((value) => value.toString()).toList()
        : rawMediaUrls is String && rawMediaUrls.isNotEmpty
            ? <String>[rawMediaUrls]
            : null;

    return Message(
      id: '${json['id']}',
      localId: '${json['local_id'] ?? json['id']}',
      conversationId: '${json['conversation_id']}',
      senderId: '${json['sender_id']}',
      content: (json['content'] ?? json['text']) as String?,
      mediaUrls: parsedMediaUrls,
      audioUrl: json['audio_url'] as String?,
      audioDuration: json['audio_duration'] == null ? null : Duration(seconds: (json['audio_duration'] as num).toInt()),
      type: MessageType.values.firstWhere((e) => e.name == json['type'], orElse: () => MessageType.text),
      sentAt: _parseDateTime(created),
      status: _status(json['status'] as String?),
      editedAt: json['edited_at'] == null ? null : _parseDateTime(json['edited_at']),
      deletedAt: json['deleted_at'] == null ? null : _parseDateTime(json['deleted_at']),
      deletedForMe: json['deleted_for_me'] == true || json['deleted_for_me'] == 1,
      isDeletedForEveryone: json['is_deleted_for_everyone'] == true || json['is_deleted_for_everyone'] == 1 || json['deleted_at'] != null,
      senderIsCertifiedAtDeletion: _parseNullableBool(json['sender_is_certified_at_deletion']),
      repliedToId: json['replied_to_id'] as String?,
    );
  }

  static bool? _parseNullableBool(dynamic value) {
    if (value == null) return null;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = value.toString().trim().toLowerCase();
    if (text == 'true' || text == '1') return true;
    if (text == 'false' || text == '0') return false;
    return null;
  }

  static DateTime _parseDateTime(dynamic value) {
    if (value is DateTime) return value.toUtc();
    if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true);
    final text = '$value'.trim();
    final numeric = num.tryParse(text);
    if (numeric != null) return DateTime.fromMillisecondsSinceEpoch(numeric.toInt(), isUtc: true);
    return DateTime.parse(text).toUtc();
  }

  static MessageStatus _status(String? value) {
    switch (value) {
      case 'pending': case 'sending': return MessageStatus.pending;
      case 'delivered': case 'received': return MessageStatus.delivered;
      case 'read': return MessageStatus.read;
      case 'failed': case 'error': return MessageStatus.failed;
      default: return MessageStatus.sent;
    }
  }
}
