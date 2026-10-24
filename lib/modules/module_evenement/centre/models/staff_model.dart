enum StaffStatus {
  pending,
  accepted,
  rejected
}

extension StaffStatusExt on StaffStatus {
  String get value {
    switch (this) {
      case StaffStatus.pending: return 'en_attente';
      case StaffStatus.accepted: return 'acceptee';
      case StaffStatus.rejected: return 'refusee';
    }
  }

  static StaffStatus fromString(String value) {
    switch (value) {
      case 'acceptee':
      case 'accepted':
        return StaffStatus.accepted;
      case 'refusee':
      case 'rejected':
        return StaffStatus.rejected;
      default:
        return StaffStatus.pending;
    }
  }
}

class StaffMemberModel {
  final String id;
  final String userId;
  final String name;
  final String? username;
  final String? avatarUrl;
  final StaffStatus status;
  final DateTime invitedAt;
  final List<String> assignedActivityIds;
  final List<String> assignedActivityNames;

  StaffMemberModel({
    required this.id,
    required this.userId,
    required this.name,
    this.username,
    this.avatarUrl,
    required this.status,
    required this.invitedAt,
    this.assignedActivityIds = const [],
    this.assignedActivityNames = const [],
  });

  factory StaffMemberModel.fromJson(Map<String, dynamic> json) {
    final user = (json['user_profiles'] ?? json['user'] ?? json['profile']) as Map<String, dynamic>?;

    DateTime parsedDate;
    try {
      final dateStr = json['invite_le'] ?? json['created_at'];
      parsedDate = dateStr != null ? DateTime.parse(dateStr.toString()) : DateTime.now();
    } catch (_) {
      parsedDate = DateTime.now();
    }

    String nameVal = 'Utilisateur';
    if (user != null) {
      final firstName = (user['first_name'] ?? '').toString().trim();
      final lastName = (user['last_name'] ?? '').toString().trim();
      final fullName = '$firstName $lastName'.trim();
      final uname = (user['username'] ?? '').toString().trim();
      nameVal = fullName.isNotEmpty ? fullName : (uname.isNotEmpty ? '@$uname' : 'Utilisateur');
    } else if (json['name'] != null) {
      nameVal = json['name'].toString();
    }

    final unameVal = user?['username']?.toString() ?? json['username']?.toString();
    final photoVal = user?['photo_url']?.toString() ?? json['photo_url']?.toString() ?? json['avatarUrl']?.toString();

    final statusStr = (json['statut'] ?? json['status'] ?? '').toString();

    List<String> actIds = [];
    List<String> actNames = [];

    final staffActivities = json['event_staff_activities'];
    if (staffActivities is List) {
      for (final item in staffActivities) {
        if (item is Map) {
          if (item['activity_id'] != null) actIds.add(item['activity_id'].toString());
          if (item['activities'] is Map && item['activities']['name'] != null) {
            actNames.add(item['activities']['name'].toString());
          }
        }
      }
    }

    if (json['assigned_activities'] is List && actNames.isEmpty) {
      actNames = (json['assigned_activities'] as List).map((a) => a.toString()).toList();
    }

    return StaffMemberModel(
      id: (json['id'] ?? '').toString(),
      userId: (json['user_id'] ?? json['userId'] ?? '').toString(),
      name: nameVal,
      username: unameVal,
      avatarUrl: photoVal,
      status: StaffStatusExt.fromString(statusStr),
      invitedAt: parsedDate,
      assignedActivityIds: actIds,
      assignedActivityNames: actNames,
    );
  }

  StaffMemberModel copyWith({
    String? id,
    String? userId,
    String? name,
    String? username,
    String? avatarUrl,
    StaffStatus? status,
    DateTime? invitedAt,
    List<String>? assignedActivityIds,
    List<String>? assignedActivityNames,
  }) {
    return StaffMemberModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      username: username ?? this.username,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      status: status ?? this.status,
      invitedAt: invitedAt ?? this.invitedAt,
      assignedActivityIds: assignedActivityIds ?? this.assignedActivityIds,
      assignedActivityNames: assignedActivityNames ?? this.assignedActivityNames,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'name': name,
      'username': username,
      'avatarUrl': avatarUrl,
      'statut': status.value,
      'created_at': invitedAt.toIso8601String(),
    };
  }
}
