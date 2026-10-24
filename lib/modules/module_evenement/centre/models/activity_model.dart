import '../../../../shared/utils/number_formatter.dart';

class ActivityModel {
  final String id;
  final String name;
  final String? description;
  final double priceIndicative;
  final String currency;
  final String status;

  ActivityModel({
    required this.id,
    required this.name,
    this.description,
    required this.priceIndicative,
    required this.currency,
    required this.status,
  });

  double get basePrice => priceIndicative;
  String get currencyCode => currency;

  factory ActivityModel.fromJson(Map<String, dynamic> json) {
    return ActivityModel(
      id: (json['id'] ?? '').toString(),
      name: (json['nom'] ?? 'Activité').toString(),
      description: json['description']?.toString(),
      priceIndicative: (json['prix_indicatif'] as num?)?.toDouble() ?? 0.0,
      currency: (json['devise'] ?? 'XAF').toString(),
      status: (json['statut'] ?? 'validee').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nom': name,
      'description': description,
      'prix_indicatif': priceIndicative,
      'devise': currency,
      'statut': status,
    };
  }
}

class EventActivityModel {
  final String id;
  final String eventId;
  final String activityId;
  final String name; // From join
  final String? description; // From join
  final double price; // event_activities.price
  final double? basePrice; // activities.base_price
  final String currency;
  final String status; // 'validee', 'en_attente', 'rejetee'
  final String? creatorId;
  final String? creatorUsername;
  final String? creatorFullName;
  final String? creatorPhotoUrl;
  final List<String> assignedStaffIds; // User IDs of staff assigned

  EventActivityModel({
    required this.id,
    required this.eventId,
    required this.activityId,
    required this.name,
    this.description,
    required this.price,
    this.basePrice,
    required this.currency,
    required this.status,
    this.creatorId,
    this.creatorUsername,
    this.creatorFullName,
    this.creatorPhotoUrl,
    this.assignedStaffIds = const [],
  });

  String get formattedEventPrice {
    return NumberFormatter.formatPrice(price, currency);
  }

  factory EventActivityModel.fromJson(Map<String, dynamic> json) {
    final activity = (json['activities'] ?? json['activites']) as Map<String, dynamic>?;
    final userProfile = activity != null && activity['user_profiles'] is Map
        ? Map<String, dynamic>.from(activity['user_profiles'] as Map)
        : (json['creator'] is Map ? Map<String, dynamic>.from(json['creator'] as Map) : null);

    num toNum(dynamic val) {
      if (val == null) return 0;
      if (val is num) return val;
      if (val is String) return num.tryParse(val) ?? 0;
      return 0;
    }

    final nameStr = activity != null
        ? (activity['name'] ?? activity['nom'] ?? 'Activité').toString()
        : (json['name'] ?? json['nom'] ?? 'Activité').toString();

    final descStr = activity != null
        ? activity['description']?.toString()
        : json['description']?.toString();

    final basePriceVal = activity != null
        ? toNum(activity['base_price'] ?? activity['prix_indicatif']).toDouble()
        : toNum(json['base_price']).toDouble();

    // IMPÉRATIF: event_activities.price est le prix événementiel!
    final rawPrice = toNum(json['price'] ?? json['prix_reel'] ?? json['prix']).toDouble();
    final eventPrice = rawPrice > 0 ? rawPrice : (basePriceVal > 0 ? basePriceVal : rawPrice);

    final currStr = (json['currency'] ?? json['currency_code'] ?? (activity != null ? activity['currency_code'] : null) ?? json['devise'] ?? 'XAF').toString();

    return EventActivityModel(
      id: (json['id'] ?? '').toString(),
      eventId: (json['event_id'] ?? json['evenement_id'] ?? '').toString(),
      activityId: (json['activity_id'] ?? json['activite_id'] ?? '').toString(),
      name: nameStr,
      description: descStr,
      price: eventPrice,
      basePrice: basePriceVal > 0 ? basePriceVal : null,
      currency: currStr,
      status: (json['status'] ?? json['statut'] ?? 'validee').toString(),
      creatorId: (userProfile?['user_id'] ?? activity?['creator_id'] ?? json['creator_id'])?.toString(),
      creatorUsername: (userProfile?['username'] ?? json['creator_username'])?.toString(),
      creatorFullName: (userProfile?['full_name'] ?? json['creator_full_name'])?.toString(),
      creatorPhotoUrl: (userProfile?['photo_url'] ?? json['creator_photo_url'])?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'event_id': eventId,
      'activity_id': activityId,
      'name': name,
      'description': description,
      'price': price,
      'base_price': basePrice,
      'currency': currency,
      'status': status,
    };
  }

  EventActivityModel copyWith({
    String? id,
    String? eventId,
    String? activityId,
    String? name,
    String? description,
    double? price,
    double? basePrice,
    String? currency,
    String? status,
    String? creatorId,
    String? creatorUsername,
    String? creatorFullName,
    String? creatorPhotoUrl,
    List<String>? assignedStaffIds,
  }) {
    return EventActivityModel(
      id: id ?? this.id,
      eventId: eventId ?? this.eventId,
      activityId: activityId ?? this.activityId,
      name: name ?? this.name,
      description: description ?? this.description,
      price: price ?? this.price,
      basePrice: basePrice ?? this.basePrice,
      currency: currency ?? this.currency,
      status: status ?? this.status,
      creatorId: creatorId ?? this.creatorId,
      creatorUsername: creatorUsername ?? this.creatorUsername,
      creatorFullName: creatorFullName ?? this.creatorFullName,
      creatorPhotoUrl: creatorPhotoUrl ?? this.creatorPhotoUrl,
      assignedStaffIds: assignedStaffIds ?? this.assignedStaffIds,
    );
  }
}

class AvailableActivityModel {
  final String id;
  final String name;
  final String? description;
  final double basePrice;
  final String currencyCode;
  final double basePriceConverted;
  final String displayCurrencyCode;
  final String displayCurrencySymbol;
  final bool eventOnly;
  final String? creatorId;
  final String? creatorUsername;
  final String? creatorFullName;
  final String? creatorPhotoUrl;
  final int addedCount;
  final int favoritesCount;
  final bool isAlreadyAdded;

  AvailableActivityModel({
    required this.id,
    required this.name,
    this.description,
    required this.basePrice,
    required this.currencyCode,
    required this.basePriceConverted,
    required this.displayCurrencyCode,
    required this.displayCurrencySymbol,
    this.eventOnly = false,
    this.creatorId,
    this.creatorUsername,
    this.creatorFullName,
    this.creatorPhotoUrl,
    this.addedCount = 0,
    this.favoritesCount = 0,
    this.isAlreadyAdded = false,
  });

  String get formattedConvertedPrice {
    return NumberFormatter.formatPrice(basePriceConverted, displayCurrencyCode.isNotEmpty ? displayCurrencyCode : 'XAF');
  }

  factory AvailableActivityModel.fromJson(Map<String, dynamic> json) {
    num toNum(dynamic val) {
      if (val == null) return 0;
      if (val is num) return val;
      if (val is String) return num.tryParse(val) ?? 0;
      return 0;
    }

    final basePrice = toNum(json['base_price'] ?? json['prix_indicatif']).toDouble();
    final basePriceConverted = toNum(json['base_price_converted'] ?? basePrice).toDouble();
    final symbol = (json['display_currency_symbol'] ?? json['symbol'] ?? json['devise'] ?? 'FCFA').toString();
    final code = (json['display_currency_code'] ?? json['currency_code'] ?? json['devise'] ?? 'XAF').toString();

    return AvailableActivityModel(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? json['nom'] ?? 'Activité').toString(),
      description: json['description']?.toString(),
      basePrice: basePrice,
      currencyCode: (json['currency_code'] ?? json['devise'] ?? 'XAF').toString(),
      basePriceConverted: basePriceConverted,
      displayCurrencyCode: code,
      displayCurrencySymbol: symbol,
      eventOnly: json['event_only'] == true,
      creatorId: (json['creator_id'] ?? json['created_by'])?.toString(),
      creatorUsername: json['creator_username']?.toString(),
      creatorFullName: (json['creator_full_name'] ?? json['creator_username'])?.toString(),
      creatorPhotoUrl: json['creator_photo_url']?.toString(),
      addedCount: toNum(json['added_count']).toInt(),
      favoritesCount: toNum(json['favorites_count']).toInt(),
      isAlreadyAdded: json['is_already_added'] == true,
    );
  }

  AvailableActivityModel copyWith({bool? isAlreadyAdded}) {
    return AvailableActivityModel(
      id: id,
      name: name,
      description: description,
      basePrice: basePrice,
      currencyCode: currencyCode,
      basePriceConverted: basePriceConverted,
      displayCurrencyCode: displayCurrencyCode,
      displayCurrencySymbol: displayCurrencySymbol,
      eventOnly: eventOnly,
      creatorId: creatorId,
      creatorUsername: creatorUsername,
      creatorFullName: creatorFullName,
      creatorPhotoUrl: creatorPhotoUrl,
      addedCount: addedCount,
      favoritesCount: favoritesCount,
      isAlreadyAdded: isAlreadyAdded ?? this.isAlreadyAdded,
    );
  }
}
