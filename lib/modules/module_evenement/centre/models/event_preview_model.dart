import 'event_model.dart';

class EventCreatorInfo {
  final String userId;
  final String username;
  final String fullName;
  final String? photoUrl;

  const EventCreatorInfo({
    required this.userId,
    required this.username,
    required this.fullName,
    this.photoUrl,
  });

  factory EventCreatorInfo.fromJson(Map<String, dynamic> json) {
    return EventCreatorInfo(
      userId: (json['user_id'] ?? json['id'] ?? '').toString(),
      username: (json['username'] ?? 'Créateur').toString(),
      fullName: (json['full_name'] ?? json['username'] ?? 'Créateur').toString(),
      photoUrl: json['photo_url']?.toString(),
    );
  }
}

class EventFriendInAgenda {
  final String userId;
  final String username;
  final String fullName;
  final String? photoUrl;

  const EventFriendInAgenda({
    required this.userId,
    required this.username,
    required this.fullName,
    this.photoUrl,
  });

  factory EventFriendInAgenda.fromJson(Map<String, dynamic> json) {
    return EventFriendInAgenda(
      userId: (json['user_id'] ?? json['id'] ?? '').toString(),
      username: (json['username'] ?? 'Ami').toString(),
      fullName: (json['full_name'] ?? json['username'] ?? 'Ami').toString(),
      photoUrl: json['photo_url']?.toString(),
    );
  }
}

class EventRankingInfo {
  final int rang;
  final int sur;
  final double score;
  final String critere;

  const EventRankingInfo({
    this.rang = 0,
    this.sur = 0,
    this.score = 0.0,
    this.critere = '',
  });

  factory EventRankingInfo.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const EventRankingInfo();
    return EventRankingInfo(
      rang: (json['rang'] as num?)?.toInt() ?? 0,
      sur: (json['sur'] as num?)?.toInt() ?? 0,
      score: (json['score'] as num?)?.toDouble() ?? 0.0,
      critere: (json['critere'] ?? '').toString(),
    );
  }
}

class ConvertedPrice {
  final double amount;
  final String currencyCode;
  final String symbol;

  const ConvertedPrice({
    required this.amount,
    required this.currencyCode,
    required this.symbol,
  });

  factory ConvertedPrice.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const ConvertedPrice(amount: 0.0, currencyCode: 'XAF', symbol: 'FCFA');
    }
    return ConvertedPrice(
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      currencyCode: (json['currency_code'] ?? 'XAF').toString(),
      symbol: (json['symbol'] ?? 'FCFA').toString(),
    );
  }

  String get displayString => '$amount $symbol';
}

class EventPreviewTicket {
  final String id;
  final String name;
  final double price;
  final String currencyCode;
  final ConvertedPrice converted;

  const EventPreviewTicket({
    required this.id,
    required this.name,
    required this.price,
    required this.currencyCode,
    required this.converted,
  });

  factory EventPreviewTicket.fromJson(Map<String, dynamic> json) {
    return EventPreviewTicket(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? json['nom'] ?? 'Billet').toString(),
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      currencyCode: (json['currency_code'] ?? 'XAF').toString(),
      converted: ConvertedPrice.fromJson(json['converted'] as Map<String, dynamic>?),
    );
  }
}

class EventPreviewActivity {
  final String activityId;
  final String name;
  final double price;
  final String currencyCode;
  final ConvertedPrice converted;

  const EventPreviewActivity({
    required this.activityId,
    required this.name,
    required this.price,
    required this.currencyCode,
    required this.converted,
  });

  factory EventPreviewActivity.fromJson(Map<String, dynamic> json) {
    return EventPreviewActivity(
      activityId: (json['activity_id'] ?? json['id'] ?? '').toString(),
      name: (json['name'] ?? json['nom'] ?? 'Activité').toString(),
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      currencyCode: (json['currency_code'] ?? 'XAF').toString(),
      converted: ConvertedPrice.fromJson(json['converted'] as Map<String, dynamic>?),
    );
  }
}

class EventRestrictionsInfo {
  final int? minAge;
  final int? maxAge;
  final List<String> allowedGenders;
  final bool idRequired;
  final bool servesAlcohol;
  final bool overnightEvent;
  final bool smokingAllowed;
  final String? otherRestrictions;

  const EventRestrictionsInfo({
    this.minAge,
    this.maxAge,
    this.allowedGenders = const [],
    this.idRequired = false,
    this.servesAlcohol = false,
    this.overnightEvent = false,
    this.smokingAllowed = false,
    this.otherRestrictions,
  });

  factory EventRestrictionsInfo.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const EventRestrictionsInfo();
    List<String> genders = [];
    if (json['allowed_genders'] is List) {
      genders = (json['allowed_genders'] as List).map((e) => e.toString()).toList();
    }
    return EventRestrictionsInfo(
      minAge: (json['min_age'] as num?)?.toInt(),
      maxAge: (json['max_age'] as num?)?.toInt(),
      allowedGenders: genders,
      idRequired: json['id_required'] == true,
      servesAlcohol: json['serves_alcohol'] == true,
      overnightEvent: json['overnight_event'] == true,
      smokingAllowed: json['smoking_allowed'] == true,
      otherRestrictions: json['other_restrictions']?.toString(),
    );
  }
}

class EventPreviewModel {
  final EventModel event;
  final EventCreatorInfo? creator;
  final bool canView;
  final bool canViewPublicPreview;
  final String? viewerRole;
  final String? message;
  final bool isInMyCalendar;
  final bool isLikedByMe;
  final int likesCount;
  final int attendeeCount;
  final int shareCount;
  final List<EventFriendInAgenda> amisDansAgenda;
  final int amisDansAgendaCount;
  final List<String> amisDansAgendaPhotos;
  final EventRankingInfo ranking;
  final List<EventPreviewTicket> tickets;
  final EventPreviewTicket? cheapestTicket;
  final List<EventPreviewActivity> activitiesLiees;
  final EventRestrictionsInfo restrictions;
  final bool canAccess;
  final bool canInteract;
  final bool canLike;
  final bool canComment;
  final bool canRate;
  final bool canShare;
  final bool canAddToCalendar;
  final bool canRegister;
  final double prestigeScore;
  final double prestigeStars;

  const EventPreviewModel({
    required this.event,
    this.creator,
    this.canView = true,
    this.canViewPublicPreview = true,
    this.viewerRole,
    this.message,
    this.isInMyCalendar = false,
    this.isLikedByMe = false,
    this.likesCount = 0,
    this.attendeeCount = 0,
    this.shareCount = 0,
    this.amisDansAgenda = const [],
    this.amisDansAgendaCount = 0,
    this.amisDansAgendaPhotos = const [],
    this.ranking = const EventRankingInfo(),
    this.tickets = const [],
    this.cheapestTicket,
    this.activitiesLiees = const [],
    this.restrictions = const EventRestrictionsInfo(),
    this.canAccess = true,
    this.canInteract = true,
    this.canLike = true,
    this.canComment = true,
    this.canRate = true,
    this.canShare = true,
    this.canAddToCalendar = true,
    this.canRegister = true,
    this.prestigeScore = 0.0,
    this.prestigeStars = 0.0,
  });

  EventPreviewModel copyWith({List<EventPreviewActivity>? activitiesLiees}) {
    return EventPreviewModel(
      event: event,
      creator: creator,
      canView: canView,
      canViewPublicPreview: canViewPublicPreview,
      viewerRole: viewerRole,
      message: message,
      isInMyCalendar: isInMyCalendar,
      isLikedByMe: isLikedByMe,
      likesCount: likesCount,
      attendeeCount: attendeeCount,
      shareCount: shareCount,
      amisDansAgenda: amisDansAgenda,
      amisDansAgendaCount: amisDansAgendaCount,
      amisDansAgendaPhotos: amisDansAgendaPhotos,
      ranking: ranking,
      tickets: tickets,
      cheapestTicket: cheapestTicket,
      activitiesLiees: activitiesLiees ?? this.activitiesLiees,
      restrictions: restrictions,
      canAccess: canAccess,
      canInteract: canInteract,
      canLike: canLike,
      canComment: canComment,
      canRate: canRate,
      canShare: canShare,
      canAddToCalendar: canAddToCalendar,
      canRegister: canRegister,
      prestigeScore: prestigeScore,
      prestigeStars: prestigeStars,
    );
  }

  factory EventPreviewModel.fromJson(Map<String, dynamic> json) {
    final eventMap = json['event'] is Map<String, dynamic>
        ? json['event'] as Map<String, dynamic>
        : (json['event'] is Map ? Map<String, dynamic>.from(json['event'] as Map) : json);

    List<EventFriendInAgenda> friends = [];
    if (json['amis_dans_agenda'] is List) {
      friends = (json['amis_dans_agenda'] as List)
          .whereType<Map>()
          .map((m) => EventFriendInAgenda.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    }

    List<String> friendPhotos = [];
    if (json['amis_dans_agenda_photos'] is List) {
      friendPhotos = (json['amis_dans_agenda_photos'] as List)
          .where((e) => e != null)
          .map((e) => e.toString())
          .toList();
    }

    List<EventPreviewTicket> tickets = [];
    if (json['tickets'] is List) {
      tickets = (json['tickets'] as List)
          .whereType<Map>()
          .map((m) => EventPreviewTicket.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    }

    List<EventPreviewActivity> activities = [];
    if (json['activities_liees'] is List) {
      activities = (json['activities_liees'] as List)
          .whereType<Map>()
          .map((m) => EventPreviewActivity.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    }

    EventPreviewTicket? cheapest;
    if (json['cheapest_ticket'] is Map) {
      cheapest = EventPreviewTicket.fromJson(
        Map<String, dynamic>.from(json['cheapest_ticket'] as Map),
      );
    }

    final viewerRole = json['viewer_role']?.toString().toLowerCase() ?? '';
    final isPrivileged = viewerRole == 'creator' ||
        viewerRole == 'co_creator' ||
        viewerRole == 'staff' ||
        viewerRole == 'founder' ||
        viewerRole == 'organizer' ||
        json['is_creator'] == true ||
        json['is_staff'] == true ||
        json['is_co_creator'] == true;

    final canAddToCalendar = (json['can_add_to_calendar'] != false) && !isPrivileged;

    return EventPreviewModel(
      event: EventModel.fromJson(eventMap),
      creator: json['creator'] is Map ? EventCreatorInfo.fromJson(Map<String, dynamic>.from(json['creator'] as Map)) : null,
      canView: json['can_view'] != false,
      canViewPublicPreview: json['can_view_public_preview'] != false,
      viewerRole: json['viewer_role']?.toString(),
      message: json['message']?.toString(),
      isInMyCalendar: json['is_in_my_calendar'] == true,
      isLikedByMe: json['is_liked_by_me'] == true,
      likesCount: (json['likes_count'] as num?)?.toInt() ?? 0,
      attendeeCount: (json['attendee_count'] as num?)?.toInt() ?? 0,
      shareCount: (json['unique_sharers_count'] as num?)?.toInt() ?? (json['share_count'] as num?)?.toInt() ?? (json['shares_count'] as num?)?.toInt() ?? 0,
      amisDansAgenda: friends,
      amisDansAgendaCount: (json['amis_dans_agenda_count'] as num?)?.toInt() ?? friends.length,
      amisDansAgendaPhotos: friendPhotos,
      ranking: EventRankingInfo.fromJson(json['classement'] as Map<String, dynamic>?),
      tickets: tickets,
      cheapestTicket: cheapest,
      activitiesLiees: activities,
      restrictions: EventRestrictionsInfo.fromJson(json['restrictions'] as Map<String, dynamic>?),
      canAccess: json['can_access'] != false,
      canInteract: json['can_interact'] != false,
      canLike: json['can_like'] != false,
      canComment: json['can_comment'] != false,
      canRate: json['can_rate'] != false,
      canShare: json['can_share'] != false,
      canAddToCalendar: canAddToCalendar,
      canRegister: json['can_register'] != false,
      prestigeScore: (json['prestige_score'] as num?)?.toDouble() ?? 0.0,
      prestigeStars: (json['prestige_stars'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
