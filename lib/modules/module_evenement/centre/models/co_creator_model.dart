enum CoCreatorStatus { pending, accepted, rejected }

class CoCreatorModel {
  final String id;
  final String eventId;
  final String userId;
  final String name;
  final String? username;
  final String? avatarUrl;
  final CoCreatorStatus status;
  final String invitedBy;
  final DateTime createdAt;

  const CoCreatorModel({
    required this.id,
    required this.eventId,
    required this.userId,
    required this.name,
    this.username,
    this.avatarUrl,
    required this.status,
    required this.invitedBy,
    required this.createdAt,
  });

  factory CoCreatorModel.fromJson(Map<String, dynamic> json) {
    final statusStr = (json['status'] ?? json['statut'] ?? 'en_attente').toString();
    CoCreatorStatus parsedStatus = CoCreatorStatus.pending;
    if (statusStr == 'acceptee' || statusStr == 'accepted') {
      parsedStatus = CoCreatorStatus.accepted;
    } else if (statusStr == 'refusee' || statusStr == 'rejected') {
      parsedStatus = CoCreatorStatus.rejected;
    }

    String fullName = 'Co-créateur';
    String? photo;
    String? uname;

    if (json['user_profiles'] is Map) {
      final profile = json['user_profiles'] as Map;
      final first = profile['first_name']?.toString() ?? '';
      final last = profile['last_name']?.toString() ?? '';
      uname = profile['username']?.toString();
      fullName = '$first $last'.trim();
      if (fullName.isEmpty) fullName = uname != null && uname.isNotEmpty ? uname : 'Co-créateur';
      photo = profile['photo_url']?.toString();
    }

    return CoCreatorModel(
      id: (json['id'] ?? '').toString(),
      eventId: (json['event_id'] ?? json['evenement_id'] ?? '').toString(),
      userId: (json['user_id'] ?? '').toString(),
      name: fullName,
      username: uname ?? json['username']?.toString(),
      avatarUrl: photo ?? json['photo_url']?.toString(),
      status: parsedStatus,
      invitedBy: (json['invited_by'] ?? '').toString(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
