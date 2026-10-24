import 'package:get/get.dart';
import '../../../../app/service_global/currency_service.dart';
import '../../../../shared/models/interest_model.dart';

class Activity {
  final String id;
  final String creatorId;
  final String name;
  final String description;
  final double basePrice;
  final String currencyCode;
  final String status; // en_attente | active | rejected | pending_deletion | deleted
  final int addedCount;
  final bool eventOnly;
  final DateTime? scheduledDeletionAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isCreator;
  final List<Interest> interests;
  
  // Champs locaux
  final String syncStatus; // synced | pending_push | rejected
  final String? syncError;

  Activity({
    required this.id,
    required this.creatorId,
    String? name,
    String? title,
    this.description = '',
    double basePrice = 0.0,
    double? priceGeneral,
    this.currencyCode = 'XAF',
    this.status = 'en_attente',
    int addedCount = 0,
    int? totalSubscribers,
    int? usageCount,
    this.eventOnly = false,
    this.scheduledDeletionAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.isCreator = false,
    this.interests = const [],
    this.syncStatus = 'synced',
    this.syncError,
  })  : name = name ?? title ?? '',
        basePrice = basePrice > 0 ? basePrice : (priceGeneral ?? 0.0),
        addedCount = addedCount > 0 ? addedCount : (totalSubscribers ?? usageCount ?? 0),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  bool get isActive => status == 'active';
  bool get isPending => status == 'en_attente';
  bool get isRejected => status == 'rejected';
  bool get isPendingDeletion => status == 'pending_deletion';
  bool get isDeleted => status == 'deleted';

  // Formattage du prix avec le symbole de la devise résolu dynamiquement via CurrencyService
  String get formattedPrice {
    if (basePrice <= 0) return 'Gratuit';
    final formattedVal = basePrice.truncateToDouble() == basePrice
        ? basePrice.toInt().toString()
        : basePrice.toStringAsFixed(2);

    String symbol = currencyCode;
    try {
      if (Get.isRegistered<CurrencyService>()) {
        symbol = Get.find<CurrencyService>().getSymbol(currencyCode);
      }
    } catch (_) {}

    return '$formattedVal $symbol';
  }

  // Alias UI
  String get title => name;
  double get priceGeneral => basePrice;
  int get totalSubscribers => addedCount;
  int get usageCount => addedCount;

  static double _parseDouble(dynamic val) {
    if (val is num) return val.toDouble();
    if (val is String) return double.tryParse(val) ?? 0.0;
    return 0.0;
  }

  static int _parseInt(dynamic val) {
    if (val is num) return val.toInt();
    if (val is String) return int.tryParse(val) ?? 0;
    return 0;
  }

  static bool _parseBool(dynamic val) {
    if (val is bool) return val;
    if (val is num) return val == 1;
    if (val is String) return val == 'true' || val == '1';
    return false;
  }

  factory Activity.fromJson(Map<String, dynamic> json) {
    final bp = (json['base_price'] ?? json['price_general'] as num?)?.toDouble() ?? 0.0;
    final ac = (json['added_count'] ?? json['usage_count'] as num?)?.toInt() ?? 0;
    final code = (json['currency_code'] ?? json['currency'] ?? 'XAF').toString();

    return Activity(
      id: json['id']?.toString() ?? '',
      creatorId: json['creator_id']?.toString() ?? '',
      name: (json['name'] ?? json['title'] ?? '').toString(),
      description: json['description']?.toString() ?? '',
      basePrice: _parseDouble(bp),
      currencyCode: code,
      status: json['status']?.toString() ?? 'en_attente',
      addedCount: _parseInt(ac),
      eventOnly: _parseBool(json['event_only']),
      scheduledDeletionAt: json['scheduled_deletion_at'] != null
          ? DateTime.tryParse(json['scheduled_deletion_at'].toString())
          : null,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? ''),
      isCreator: json['is_creator'] == true,
      interests: json['interests'] != null
          ? (json['interests'] as List).map((e) => Interest.fromJson(Map<String, dynamic>.from(e))).toList()
          : const [],
      syncStatus: json['sync_status']?.toString() ?? 'synced',
      syncError: json['sync_error']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'creator_id': creatorId,
      'name': name,
      'description': description,
      'base_price': basePrice,
      'currency_code': currencyCode,
      'status': status,
      'added_count': addedCount,
      'event_only': eventOnly,
      'scheduled_deletion_at': scheduledDeletionAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'sync_status': syncStatus,
      'sync_error': syncError,
    };
  }

  Activity copyWith({
    String? name,
    String? description,
    double? basePrice,
    String? currencyCode,
    String? status,
    int? addedCount,
    bool? eventOnly,
    DateTime? scheduledDeletionAt,
    DateTime? updatedAt,
    String? syncStatus,
    String? syncError,
  }) {
    return Activity(
      id: id,
      creatorId: creatorId,
      name: name ?? this.name,
      description: description ?? this.description,
      basePrice: basePrice ?? this.basePrice,
      currencyCode: currencyCode ?? this.currencyCode,
      status: status ?? this.status,
      addedCount: addedCount ?? this.addedCount,
      eventOnly: eventOnly ?? this.eventOnly,
      scheduledDeletionAt: scheduledDeletionAt ?? this.scheduledDeletionAt,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      syncError: syncError ?? this.syncError,
    );
  }
}
