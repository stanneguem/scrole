export 'activity_model.dart';
import 'activity_model.dart';

enum CheckinStatus { valid, invalidated }

class CheckinModel {
  final String id;
  final String eventId;
  final String userId;
  final String userName;
  final String? userPhotoUrl;
  final String validatedByUserId;
  final String validatorName;
  final String? parentCheckinId;
  final CheckinStatus status;
  final String? activityId;
  final String? invalidatedReason;
  final DateTime createdAt;

  const CheckinModel({
    required this.id,
    required this.eventId,
    required this.userId,
    required this.userName,
    this.userPhotoUrl,
    required this.validatedByUserId,
    required this.validatorName,
    this.parentCheckinId,
    required this.status,
    this.activityId,
    this.invalidatedReason,
    required this.createdAt,
  });

  factory CheckinModel.fromJson(Map<String, dynamic> json) {
    String uName = 'Participant';
    String? uPhoto;
    if (json['user_profiles'] is Map) {
      final p = json['user_profiles'] as Map;
      final first = (p['first_name'] ?? '').toString();
      final last = (p['last_name'] ?? '').toString();
      final username = (p['username'] ?? '').toString();
      uName = '$first $last'.trim();
      if (uName.isEmpty) uName = username.isNotEmpty ? username : 'Participant';
      uPhoto = p['photo_url']?.toString();
    }

    String vName = 'Scanneur';
    if (json['validator'] is Map) {
      final p = json['validator'] as Map;
      final first = (p['first_name'] ?? '').toString();
      final last = (p['last_name'] ?? '').toString();
      final username = (p['username'] ?? '').toString();
      vName = '$first $last'.trim();
      if (vName.isEmpty) vName = username.isNotEmpty ? username : 'Scanneur';
    }

    final statusStr = (json['status'] ?? json['statut'] ?? 'valid').toString();

    return CheckinModel(
      id: (json['id'] ?? '').toString(),
      eventId: (json['event_id'] ?? json['evenement_id'] ?? '').toString(),
      userId: (json['user_id'] ?? '').toString(),
      userName: uName,
      userPhotoUrl: uPhoto,
      validatedByUserId: (json['validated_by_user_id'] ?? json['scanneur_id'] ?? '').toString(),
      validatorName: vName,
      parentCheckinId: json['parent_checkin_id']?.toString(),
      status: statusStr == 'invalidated' || statusStr == 'invalide' ? CheckinStatus.invalidated : CheckinStatus.valid,
      activityId: json['activity_id']?.toString(),
      invalidatedReason: json['invalidated_reason']?.toString(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

class CheckinScanResult {
  final bool presenceCreee;
  final bool alreadyPresent;
  final String? checkinId;
  final String? activityId;
  final int quantiteValidee;
  final List<AvailableActivityModel> availableActivities;
  final String? message;

  const CheckinScanResult({
    required this.presenceCreee,
    required this.alreadyPresent,
    this.checkinId,
    this.activityId,
    this.quantiteValidee = 1,
    required this.availableActivities,
    this.message,
  });

  factory CheckinScanResult.fromJson(dynamic json) {
    if (json is! Map) {
      return CheckinScanResult(
        presenceCreee: true,
        alreadyPresent: false,
        checkinId: json?.toString(),
        availableActivities: const [],
      );
    }

    final map = Map<String, dynamic>.from(json);

    final presenceCreee = map['presence_creee'] == true || map['success'] == true;
    final alreadyPresent = map['already_present'] == true || map['deja_present'] == true;
    final checkinId = map['checkin_id']?.toString() ?? map['id']?.toString();
    final activityId = map['activity_id']?.toString();
    final quantiteValidee = (map['quantite_validee'] as num? ?? map['quantite'] as num? ?? 1).toInt();

    List<AvailableActivityModel> activities = [];
    if (map['available_activities'] is List) {
      activities = (map['available_activities'] as List)
          .map((a) => AvailableActivityModel.fromJson(Map<String, dynamic>.from(a as Map)))
          .toList();
    } else if (map['activites_disponibles'] is List) {
      activities = (map['activites_disponibles'] as List)
          .map((a) => AvailableActivityModel.fromJson(Map<String, dynamic>.from(a as Map)))
          .toList();
    }

    return CheckinScanResult(
      presenceCreee: presenceCreee,
      alreadyPresent: alreadyPresent,
      checkinId: checkinId,
      activityId: activityId,
      quantiteValidee: quantiteValidee,
      availableActivities: activities,
      message: map['message']?.toString() ?? map['error']?.toString(),
    );
  }
}
