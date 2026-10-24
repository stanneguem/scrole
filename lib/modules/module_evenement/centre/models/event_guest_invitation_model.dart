enum GuestInvitationStatus { pending, accepted, declined }

class EventGuestInvitationModel {
  final String id;
  final String eventId;
  final String userId;
  final String invitedBy;
  final String userName;
  final String? userUsername;
  final String? avatarUrl;
  final String? eventName;
  final GuestInvitationStatus status;
  final DateTime createdAt;
  final DateTime? respondedAt;

  const EventGuestInvitationModel({
    required this.id,
    required this.eventId,
    required this.userId,
    required this.invitedBy,
    required this.userName,
    this.userUsername,
    this.avatarUrl,
    this.eventName,
    required this.status,
    required this.createdAt,
    this.respondedAt,
  });

  factory EventGuestInvitationModel.fromJson(Map<String, dynamic> json) {
    GuestInvitationStatus parsedStatus = GuestInvitationStatus.pending;
    final statusStr = json['status']?.toString().toLowerCase();
    if (statusStr == 'acceptee' || statusStr == 'accepted') {
      parsedStatus = GuestInvitationStatus.accepted;
    } else if (statusStr == 'refusee' || statusStr == 'declined') {
      parsedStatus = GuestInvitationStatus.declined;
    }

    String name = 'Utilisateur';
    String? username;
    String? avatar;
    String? eventName;

    if (json['user_profiles'] is Map) {
      final p = json['user_profiles'] as Map;
      final first = (p['first_name'] as String? ?? '').trim();
      final last = (p['last_name'] as String? ?? '').trim();
      username = (p['username'] as String? ?? '').trim();
      final fullName = '$first $last'.trim();
      name = fullName.isNotEmpty ? fullName : (username.isNotEmpty ? username : 'Utilisateur');
      avatar = p['photo_url'] as String?;
    } else if (json['name'] != null || json['first_name'] != null) {
      final first = (json['first_name'] as String? ?? '').trim();
      final last = (json['last_name'] as String? ?? '').trim();
      username = (json['username'] as String? ?? '').trim();
      final fullName = '$first $last'.trim();
      name = fullName.isNotEmpty ? fullName : (json['name'] as String? ?? 'Utilisateur');
      avatar = json['photo_url'] as String?;
    }

    if (json['events'] is Map) {
      final ev = json['events'] as Map;
      eventName = (ev['name'] ?? ev['nom'])?.toString();
    }

    return EventGuestInvitationModel(
      id: json['id']?.toString() ?? '',
      eventId: json['event_id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      invitedBy: json['invited_by']?.toString() ?? '',
      userName: name,
      userUsername: username,
      avatarUrl: avatar,
      eventName: eventName,
      status: parsedStatus,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now() : DateTime.now(),
      respondedAt: json['responded_at'] != null ? DateTime.tryParse(json['responded_at'].toString()) : null,
    );
  }
}
