import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../../../../shared/models/badge_model.dart';
import '../../../../shared/utils/number_formatter.dart';
import '../../interne/enums/event_enum.dart';

class EventCountryInfo {
  final String name;
  final String codeIso;

  const EventCountryInfo({required this.name, required this.codeIso});

  factory EventCountryInfo.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const EventCountryInfo(name: '', codeIso: '');
    return EventCountryInfo(
      name: (json['name'] ?? json['nom'] ?? '').toString(),
      codeIso: (json['code_iso'] ?? json['code'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {'name': name, 'code_iso': codeIso};
}

class EventCityInfo {
  final String name;

  const EventCityInfo({required this.name});

  factory EventCityInfo.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const EventCityInfo(name: '');
    return EventCityInfo(
      name: (json['name'] ?? json['nom'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {'name': name};
}

class EventModel {
  final String id;
  final String creatorId;
  final String name;
  final String slug;
  final String? description;
  final String? coverImageUrl;
  final List<String> galleryUrls;
  final String? countryId;
  final String? cityId;
  final EventCountryInfo? country;
  final EventCityInfo? city;
  final String? address;
  final double? latitude;
  final double? longitude;
  final bool isOnline;
  final String? onlineUrl;
  final DateTime startsAt;
  final DateTime? endsAt;
  final DateTime? realCreatedAt;
  final String? timezone;
  final EventVisibility visibility;
  final EventStatus status;
  final int? maxParticipants;
  final bool requiresApproval;
  final bool isFree;
  final double? price;
  final String? currency;
  final int interestedCount;
  final int goingCount;
  final int checkedInCount;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? statutSync; // Info locale: 'en_attente', 'synchronise', 'echec'
  final String? userRole;   // Rôle de l'utilisateur (createur, staff, membre)
  final DateTime? slugLockedUntil; // Verrouillage du slug depuis le backend

  // ===== NOUVEAUX CHAMPS =====
  final int totalAddedCount;        // nombre d'ajouts au calendrier
  final int shareCount;             // nombre de partages
  final int? countryRank;           // rang dans le pays
  final bool isRecurring;           // event annuel/récurrent
  final List<BadgeModel> badges;    // badges possibles
  final String? category;          // catégorie sémantique backend (pour_vous, populaires, etc.)

  EventModel({
    required this.id,
    required this.creatorId,
    required this.name,
    required this.slug,
    this.description,
    this.coverImageUrl,
    this.galleryUrls = const [],
    this.countryId,
    this.cityId,
    this.country,
    this.city,
    this.address,
    this.latitude,
    this.longitude,
    this.isOnline = false,
    this.onlineUrl,
    required this.startsAt,
    this.endsAt,
    this.realCreatedAt,
    this.timezone,
    this.visibility = EventVisibility.public,
    this.status = EventStatus.draft,
    this.maxParticipants,
    this.requiresApproval = false,
    this.isFree = true,
    this.price,
    this.currency,
    this.interestedCount = 0,
    this.goingCount = 0,
    this.checkedInCount = 0,
    required this.createdAt,
    this.updatedAt,
    this.statutSync,
    this.userRole,
    this.slugLockedUntil,
    this.totalAddedCount = 0,
    this.shareCount = 0,
    this.countryRank,
    this.isRecurring = false,
    this.badges = const [],
    this.category,
  });

  DateTime get dateOnly => DateTime(startsAt.year, startsAt.month, startsAt.day);

  String? get timeString {
    final h = startsAt.hour.toString().padLeft(2, '0');
    final m = startsAt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  int get popularity => interestedCount;
  int get enthusiasm => goingCount;

  bool get isOngoingMeaningful {
    final now = DateTime.now();
    if (startsAt.isBefore(now) || startsAt.isAtSameMomentAs(now)) {
      if (endsAt != null) {
        final remaining = endsAt!.difference(now);
        return remaining.inHours > 48;
      }
    }
    return false;
  }

  bool get isFinished {
    final now = DateTime.now();
    return endsAt != null && endsAt!.isBefore(now);
  }

  String get priceDisplay {
    if (isFree) {
      return 'events_is_free'.tr;
    }
    if (price == null || price == 0) {
      return 'events_paid_entry'.tr;
    }
    final formattedPrice = NumberFormatter.formatPrice(price!, currency ?? 'XAF');
    return 'events_price_from'.trParams({'price': formattedPrice});
  }

  String get locationDisplay {
    if (isOnline) {
      return onlineUrl != null && onlineUrl!.isNotEmpty ? onlineUrl! : 'Événement virtuel';
    }
    final parts = <String>[];
    if (address != null && address!.isNotEmpty) parts.add(address!);
    if (city != null && city!.name.isNotEmpty) parts.add(city!.name);
    if (country != null && country!.name.isNotEmpty) parts.add(country!.name);
    return parts.isNotEmpty ? parts.join(', ') : 'Lieu non spécifié';
  }

  factory EventModel.fromJson(Map<String, dynamic> json) {
    try {
      // Sécurisation des dates qui sont les sources fréquentes de crash
      DateTime parsedStartsAt;
      try {
        final dateStr = json['date_debut'] ?? json['starts_at'];
        parsedStartsAt = dateStr != null ? DateTime.parse(dateStr.toString()) : DateTime.now();
      } catch (_) {
        parsedStartsAt = DateTime.now();
      }

      DateTime? parsedEndsAt;
      try {
        final dateStr = json['date_fin'] ?? json['ends_at'];
        if (dateStr != null) parsedEndsAt = DateTime.parse(dateStr.toString());
      } catch (_) {}

      DateTime parsedCreatedAt;
      try {
        final dateStr = json['created_at'] ?? json['date_creation'];
        parsedCreatedAt = dateStr != null ? DateTime.parse(dateStr.toString()) : DateTime.now();
      } catch (_) {
        parsedCreatedAt = DateTime.now();
      }

      final name = (json['nom'] ?? json['name']);
      final id = (json['id'] ?? '').toString();

      // Sécurisation du cast des listes qui peut contenir des nulls
      List<String> parseStringList(dynamic val) {
        if (val == null || val is! List) return [];
        return val.where((e) => e != null).map((e) => e.toString()).toList();
      }

      num? toNum(dynamic val) {
        if (val == null) return null;
        if (val is num) return val;
        if (val is String) return num.tryParse(val);
        return null;
      }

      final idStr = (json['id'] ?? json['evenement_id'] ?? '').toString();
      final creatorIdStr = (json['created_by'] ?? json['creator_id'] ?? '').toString();

      final countryObj = json['country'] is Map
          ? EventCountryInfo.fromJson(Map<String, dynamic>.from(json['country'] as Map))
          : null;

      final cityObj = json['city'] is Map
          ? EventCityInfo.fromJson(Map<String, dynamic>.from(json['city'] as Map))
          : null;

      DateTime? parsedRealCreatedAt;
      try {
        final dateStr = json['real_created_at'] ?? json['date_origine'];
        if (dateStr != null) parsedRealCreatedAt = DateTime.tryParse(dateStr.toString());
      } catch (_) {}

      return EventModel(
        id: idStr,
        creatorId: creatorIdStr,
        name: (json['nom'] ?? json['name'] ?? json['title'] ?? 'Événement sans nom').toString(),
        slug: (json['slug'] ?? '').toString(),
        description: json['description']?.toString(),
        coverImageUrl: (json['photo_url'] ?? json['cover_image_url'] ?? json['photo'])?.toString(),
        galleryUrls: parseStringList(json['gallery_urls']),
        countryId: (json['pays_id'] ?? json['country_id'])?.toString(),
        cityId: (json['ville_id'] ?? json['city_id'])?.toString(),
        country: countryObj,
        city: cityObj,
        address: (json['adresse'] ?? json['lieu_texte'] ?? json['address'])?.toString(),
        latitude: toNum(json['latitude'])?.toDouble(),
        longitude: toNum(json['longitude'])?.toDouble(),
        isOnline: (json['est_virtuel'] ?? json['is_virtual'] ?? json['is_online']) == true,
        onlineUrl: (json['lien_virtuel'] ?? json['virtual_link'] ?? json['online_url'])?.toString(),
        startsAt: parsedStartsAt,
        endsAt: parsedEndsAt,
        realCreatedAt: parsedRealCreatedAt,
        timezone: json['timezone']?.toString(),
        visibility: EventVisibilityExt.fromString(json['visibility']?.toString() ?? 'public'),
        status: (json['is_pending_deletion'] == true || json['deletion_requested_at'] != null)
            ? EventStatus.pendingDeletion
            : EventStatusExt.fromString((json['statut'] ?? json['status'])?.toString() ?? 'en_attente'),
        maxParticipants: toNum(json['max_participants'])?.toInt(),
        requiresApproval: json['requires_approval'] == true,
        isFree: (json['est_gratuit'] ?? json['is_free']) != false,
        price: toNum(json['min_ticket_price'] ?? json['prix_min'] ?? json['price'] ?? json['prix'])?.toDouble(),
        currency: (json['min_ticket_currency_code'] ?? json['currency_code'] ?? json['currency'] ?? json['devise'] ?? 'XAF').toString(),
        interestedCount: toNum(json['interested_count'] ?? json['likes_count'])?.toInt() ?? 0,
        goingCount: toNum(json['going_count'] ?? json['calendar_count'])?.toInt() ?? 0,
        checkedInCount: toNum(json['checked_in_count'])?.toInt() ?? 0,
        createdAt: parsedCreatedAt,
        updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'].toString()) : null,
        statutSync: (json['statut_sync'] ?? 'synchronise').toString(),
        userRole: (json['user_role'] ?? json['role'])?.toString(),
        slugLockedUntil: json['slug_locked_until'] != null 
            ? DateTime.tryParse(json['slug_locked_until'].toString())
            : (json['date_limite_slug'] != null ? DateTime.tryParse(json['date_limite_slug'].toString()) : null),
        totalAddedCount: toNum(json['total_added_count'] ?? json['calendar_count'])?.toInt() ?? 0,
        shareCount: toNum(json['unique_sharers_count'] ?? json['share_count'] ?? json['shares_count'] ?? json['shares'])?.toInt() ?? 0,
        countryRank: toNum(json['country_rank'])?.toInt(),
        isRecurring: (json['est_recurrent'] ?? json['is_recurring']) == true,
        category: (json['category'] ?? json['categorie'])?.toString(),
      );
    } catch (e, stack) {
      debugPrint('[Error] EventModel.fromJson failed: $e');
      debugPrint('[Error] JSON was: $json');
      rethrow;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'created_by': creatorId,
      'nom': name,
      'slug': slug,
      'description': description,
      'photo_url': coverImageUrl,
      'pays_id': countryId,
      'ville_id': cityId,
      'adresse': address,
      'est_virtuel': isOnline,
      'lien_virtuel': onlineUrl,
      'date_debut': startsAt.toIso8601String(),
      'date_fin': endsAt?.toIso8601String(),
      'statut': status.value,
      'est_gratuit': isFree,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'user_role': userRole,
    };
  }

  EventModel copyWith({
    String? id,
    String? creatorId,
    String? name,
    String? slug,
    String? description,
    String? coverImageUrl,
    List<String>? galleryUrls,
    String? countryId,
    String? cityId,
    String? address,
    double? latitude,
    double? longitude,
    bool? isOnline,
    String? onlineUrl,
    DateTime? startsAt,
    DateTime? endsAt,
    String? timezone,
    EventVisibility? visibility,
    EventStatus? status,
    int? maxParticipants,
    bool? requiresApproval,
    bool? isFree,
    double? price,
    String? currency,
    int? interestedCount,
    int? goingCount,
    int? checkedInCount,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? statutSync,
    String? userRole,
    int? totalAddedCount,
    int? countryRank,
    bool? isRecurring,
    List<BadgeModel>? badges,
  }) {
    return EventModel(
      id: id ?? this.id,
      creatorId: creatorId ?? this.creatorId,
      name: name ?? this.name,
      slug: slug ?? this.slug,
      description: description ?? this.description,
      coverImageUrl: coverImageUrl ?? this.coverImageUrl,
      galleryUrls: galleryUrls ?? this.galleryUrls,
      countryId: countryId ?? this.countryId,
      cityId: cityId ?? this.cityId,
      address: address ?? this.address,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      isOnline: isOnline ?? this.isOnline,
      onlineUrl: onlineUrl ?? this.onlineUrl,
      startsAt: startsAt ?? this.startsAt,
      endsAt: endsAt ?? this.endsAt,
      timezone: timezone ?? this.timezone,
      visibility: visibility ?? this.visibility,
      status: status ?? this.status,
      maxParticipants: maxParticipants ?? this.maxParticipants,
      requiresApproval: requiresApproval ?? this.requiresApproval,
      isFree: isFree ?? this.isFree,
      price: price ?? this.price,
      currency: currency ?? this.currency,
      interestedCount: interestedCount ?? this.interestedCount,
      goingCount: goingCount ?? this.goingCount,
      checkedInCount: checkedInCount ?? this.checkedInCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      statutSync: statutSync ?? this.statutSync,
      userRole: userRole ?? this.userRole,
      totalAddedCount: totalAddedCount ?? this.totalAddedCount,
      countryRank: countryRank ?? this.countryRank,
      isRecurring: isRecurring ?? this.isRecurring,
      badges: badges ?? this.badges,
    );
  }
}
