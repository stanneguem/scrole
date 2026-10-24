import 'package:get/get.dart';

class ExcludedUser {
  final String userId;
  final String firstName;
  final String lastName;
  final String username;
  final String? avatarUrl;
  final bool isVerified;
  final String? reason;

  const ExcludedUser({
    required this.userId,
    required this.firstName,
    required this.lastName,
    required this.username,
    this.avatarUrl,
    required this.isVerified,
    this.reason,
  });

  factory ExcludedUser.fromJson(Map<String, dynamic> json) {
    final user = json['user'] is Map ? Map<String, dynamic>.from(json['user']) : <String, dynamic>{};
    final rawVerified = user['is_verified'] ?? json['is_verified'];
    bool isVerified = false;
    if (rawVerified is bool) {
      isVerified = rawVerified;
    } else if (rawVerified is num) {
      isVerified = rawVerified == 1;
    } else if (rawVerified is String) {
      isVerified = rawVerified.toLowerCase() == 'true' || rawVerified == '1';
    }

    return ExcludedUser(
      userId: user['user_id']?.toString() ?? user['id']?.toString() ?? json['user_id']?.toString() ?? '',
      firstName: user['first_name']?.toString() ?? '',
      lastName: user['last_name']?.toString() ?? '',
      username: user['username']?.toString() ?? '',
      avatarUrl: user['photo_url']?.toString() ?? user['avatar_url']?.toString(),
      isVerified: isVerified,
      reason: json['reason']?.toString(),
    );
  }

  String get displayName {
    final name = '$firstName $lastName'.trim();
    return name.isEmpty ? (username.isNotEmpty ? username : 'excluded_members_unknown_user'.tr) : name;
  }
}
