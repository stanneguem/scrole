import 'activity_model.dart';

/// Modèle local de cache activité isolé par (viewerUserId, activityId)
/// d'après la section 5 de la spécification de refonte.
class ActivityCacheEntity {
  final String viewerUserId;
  final String activityId;
  final String creatorId;
  final String name;
  final String description;
  final double displayPrice;
  final String displayCurrency;
  final String status; // en_attente | active | rejected | pending_deletion | deleted
  final int addedCount;
  final bool eventOnly;
  final DateTime? scheduledDeletionAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int cachedAt;

  const ActivityCacheEntity({
    required this.viewerUserId,
    required this.activityId,
    required this.creatorId,
    required this.name,
    this.description = '',
    required this.displayPrice,
    required this.displayCurrency,
    this.status = 'en_attente',
    this.addedCount = 0,
    this.eventOnly = false,
    this.scheduledDeletionAt,
    required this.createdAt,
    required this.updatedAt,
    required this.cachedAt,
  });

  /// Conversion vers le modèle UI `Activity`
  Activity toActivity() {
    return Activity(
      id: activityId,
      creatorId: creatorId,
      name: name,
      description: description,
      basePrice: displayPrice,
      currencyCode: displayCurrency,
      status: status,
      addedCount: addedCount,
      eventOnly: eventOnly,
      scheduledDeletionAt: scheduledDeletionAt,
      createdAt: createdAt,
      updatedAt: updatedAt,
      syncStatus: 'synced',
    );
  }

  /// Création depuis la réponse RPC Supabase
  factory ActivityCacheEntity.fromRpcJson({
    required String viewerUserId,
    required Map<String, dynamic> json,
  }) {
    num? parseNum(dynamic val) {
      if (val is num) return val;
      if (val is String) return num.tryParse(val);
      return null;
    }

    bool parseBool(dynamic val) {
      if (val is bool) return val;
      if (val is num) return val == 1;
      if (val is String) return val == 'true' || val == '1';
      return false;
    }

    final id = (json['id'] ?? json['activity_id'] ?? '').toString();
    final creator = (json['creator_id'] ?? json['created_by'] ?? json['user_id'] ?? '').toString();
    final price = parseNum(json['base_price'] ?? json['price'] ?? json['display_price'])?.toDouble() ?? 0.0;
    final currency = (json['currency_code'] ?? json['currency'] ?? json['display_currency'] ?? 'XAF').toString();
    final now = DateTime.now();

    return ActivityCacheEntity(
      viewerUserId: viewerUserId,
      activityId: id,
      creatorId: creator,
      name: (json['name'] ?? json['title'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      displayPrice: price,
      displayCurrency: currency,
      status: (json['status'] ?? 'en_attente').toString(),
      addedCount: parseNum(json['added_count'] ?? json['usage_count'])?.toInt() ?? 0,
      eventOnly: parseBool(json['event_only']),
      scheduledDeletionAt: json['scheduled_deletion_at'] != null
          ? DateTime.tryParse(json['scheduled_deletion_at'].toString())
          : null,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? now,
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? '') ?? now,
      cachedAt: now.millisecondsSinceEpoch,
    );
  }

  /// Convertit vers une ligne Map SQLite pour la table `activity_cache`
  Map<String, dynamic> toMap() {
    return {
      'viewer_user_id': viewerUserId,
      'activity_id': activityId,
      'creator_id': creatorId,
      'name': name,
      'description': description,
      'display_price': displayPrice,
      'display_currency': displayCurrency,
      'status': status,
      'added_count': addedCount,
      'event_only': eventOnly ? 1 : 0,
      'scheduled_deletion_at': scheduledDeletionAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'cached_at': cachedAt,
    };
  }

  factory ActivityCacheEntity.fromMap(Map<String, dynamic> map) {
    return ActivityCacheEntity(
      viewerUserId: map['viewer_user_id'].toString(),
      activityId: map['activity_id'].toString(),
      creatorId: map['creator_id'].toString(),
      name: map['name'].toString(),
      description: (map['description'] ?? '').toString(),
      displayPrice: (map['display_price'] as num?)?.toDouble() ?? 0.0,
      displayCurrency: (map['display_currency'] ?? 'XAF').toString(),
      status: map['status'].toString(),
      addedCount: (map['added_count'] as num?)?.toInt() ?? 0,
      eventOnly: (map['event_only'] as num?)?.toInt() == 1,
      scheduledDeletionAt: map['scheduled_deletion_at'] != null
          ? DateTime.tryParse(map['scheduled_deletion_at'].toString())
          : null,
      createdAt: DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now(),
      updatedAt: DateTime.tryParse(map['updated_at'].toString()) ?? DateTime.now(),
      cachedAt: (map['cached_at'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
    );
  }
}
