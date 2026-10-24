import 'dart:convert';

class RemoteNotificationModel {
  const RemoteNotificationModel({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.actorId,
    required this.data,
    required this.readAt,
    required this.createdAt,
  });

  final String id;
  final String type;
  final String title;
  final String body;
  final String? actorId;
  final Map<String, dynamic> data;
  final DateTime? readAt;
  final DateTime createdAt;

  bool get isRead => readAt != null;

  String? get requestId => data['request_id']?.toString();
  String? get userId => data['user_id']?.toString() ?? actorId;

  String get localPayload => jsonEncode({
        'source': 'supabase',
        'notification_id': id,
        'type': type,
        'data': data,
        'actor_id': actorId,
      });

  factory RemoteNotificationModel.fromJson(Map<String, dynamic> json) {
    final rawData = json['data'];
    return RemoteNotificationModel(
      id: json['id'].toString(),
      type: json['type']?.toString() ?? 'info',
      title: json['title']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
      actorId: json['actor_id']?.toString(),
      data: rawData is Map
          ? Map<String, dynamic>.from(rawData)
          : <String, dynamic>{},
      readAt: json['read_at'] == null
          ? null
          : DateTime.tryParse(json['read_at'].toString()),
      createdAt: DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now(),
    );
  }
}
