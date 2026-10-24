import 'package:flutter/foundation.dart';

num _toNum(dynamic val) {
  if (val == null) return 0;
  if (val is num) return val;
  if (val is String) return num.tryParse(val) ?? 0;
  return 0;
}

class EventStatsInfo {
  final String id;
  final String name;
  final String status;
  final DateTime startsAt;
  final DateTime? endsAt;
  final bool isFree;
  final bool isVirtual;
  final String? address;
  final DateTime createdAt;
  final int? eventDurationMinutes;
  final int daysUntilEvent;
  final bool isUpcoming;
  final bool isOngoing;
  final bool isFinished;

  EventStatsInfo({
    required this.id,
    required this.name,
    required this.status,
    required this.startsAt,
    this.endsAt,
    required this.isFree,
    required this.isVirtual,
    this.address,
    required this.createdAt,
    this.eventDurationMinutes,
    required this.daysUntilEvent,
    required this.isUpcoming,
    required this.isOngoing,
    required this.isFinished,
  });

  factory EventStatsInfo.fromJson(Map<String, dynamic> json) {
    return EventStatsInfo(
      id: (json['event_id'] ?? json['id'] ?? '').toString(),
      name: (json['name'] ?? json['nom'] ?? 'Événement').toString(),
      status: (json['status'] ?? 'active').toString(),
      startsAt: json['starts_at'] != null ? DateTime.parse(json['starts_at'].toString()) : DateTime.now(),
      endsAt: json['ends_at'] != null ? DateTime.tryParse(json['ends_at'].toString()) : null,
      isFree: json['is_free'] == true,
      isVirtual: json['is_virtual'] == true,
      address: json['address']?.toString(),
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at'].toString()) : DateTime.now(),
      eventDurationMinutes: json['event_duration_minutes'] != null ? _toNum(json['event_duration_minutes']).toInt() : null,
      daysUntilEvent: _toNum(json['days_until_event']).toInt(),
      isUpcoming: json['is_upcoming'] == true,
      isOngoing: json['is_ongoing'] == true,
      isFinished: json['is_finished'] == true,
    );
  }
}

class EventStatsOverview {
  final int totalUniquePeople;
  final int agendaCount;
  final int uniqueAttendees;
  final double attendanceRate;
  final double noShowRate;
  final int likesCount;
  final double ratingAverage;
  final double prestigeScore;
  final double prestigeStars;

  EventStatsOverview({
    required this.totalUniquePeople,
    required this.agendaCount,
    required this.uniqueAttendees,
    required this.attendanceRate,
    required this.noShowRate,
    required this.likesCount,
    required this.ratingAverage,
    required this.prestigeScore,
    required this.prestigeStars,
  });

  factory EventStatsOverview.fromJson(Map<String, dynamic> json) {
    return EventStatsOverview(
      totalUniquePeople: _toNum(json['total_unique_people']).toInt(),
      agendaCount: _toNum(json['agenda_count'] ?? json['calendar_count'] ?? json['calendar_people_count']).toInt(),
      uniqueAttendees: _toNum(json['unique_attendees'] ?? json['valid_checkins']).toInt(),
      attendanceRate: _toNum(json['attendance_rate']).toDouble(),
      noShowRate: _toNum(json['no_show_rate']).toDouble(),
      likesCount: _toNum(json['likes_count'] ?? json['likes']).toInt(),
      ratingAverage: _toNum(json['rating_average']).toDouble(),
      prestigeScore: _toNum(json['prestige_score'] ?? json['prestige']?['prestige_score']).toDouble(),
      prestigeStars: _toNum(json['prestige_stars'] ?? json['prestige']?['prestige_stars']).toDouble(),
    );
  }
}

class EventStatsAudience {
  final int totalUniquePeople;
  final int calendarPeopleCount;
  final int regularAttendeesCount;
  final int guestsOfHonorCount;
  final int sponsorsCount;
  final int staffCount;
  final int cofoundersCount;
  final int founderCount;

  EventStatsAudience({
    required this.totalUniquePeople,
    required this.calendarPeopleCount,
    required this.regularAttendeesCount,
    required this.guestsOfHonorCount,
    required this.sponsorsCount,
    required this.staffCount,
    required this.cofoundersCount,
    required this.founderCount,
  });

  factory EventStatsAudience.fromJson(Map<String, dynamic> json) {
    return EventStatsAudience(
      totalUniquePeople: _toNum(json['total_unique_people']).toInt(),
      calendarPeopleCount: _toNum(json['calendar_people_count']).toInt(),
      regularAttendeesCount: _toNum(json['regular_attendees_count']).toInt(),
      guestsOfHonorCount: _toNum(json['guests_of_honor_count'] ?? json['accepted_guest_count']).toInt(),
      sponsorsCount: _toNum(json['sponsors_count'] ?? json['accepted_sponsor_count']).toInt(),
      staffCount: _toNum(json['staff_count']).toInt(),
      cofoundersCount: _toNum(json['cofounders_count']).toInt(),
      founderCount: _toNum(json['founder_count']).toInt(),
    );
  }
}

class EventStatsAttendance {
  final int uniqueAttendees;
  final int totalValidCheckins;
  final int invalidatedCheckins;
  final int activityParticipants;
  final double attendanceRate;
  final double noShowRate;

  EventStatsAttendance({
    required this.uniqueAttendees,
    required this.totalValidCheckins,
    required this.invalidatedCheckins,
    required this.activityParticipants,
    required this.attendanceRate,
    required this.noShowRate,
  });

  factory EventStatsAttendance.fromJson(Map<String, dynamic> json) {
    return EventStatsAttendance(
      uniqueAttendees: _toNum(json['unique_attendees']).toInt(),
      totalValidCheckins: _toNum(json['total_valid_checkins']).toInt(),
      invalidatedCheckins: _toNum(json['invalidated_checkins']).toInt(),
      activityParticipants: _toNum(json['activity_participants']).toInt(),
      attendanceRate: _toNum(json['attendance_rate']).toDouble(),
      noShowRate: _toNum(json['no_show_rate']).toDouble(),
    );
  }
}

class EventStatsEngagement {
  final int likesCount;
  final int commentsCount;
  final int sharesCount;
  final int uniqueSharersCount;
  final int calendarCount;
  final int ratingsCount;
  final double ratingAverage;
  final Map<String, int> ratingDistribution;
  final int totalInteractions;
  final double engagementRate;

  EventStatsEngagement({
    required this.likesCount,
    required this.commentsCount,
    required this.sharesCount,
    required this.uniqueSharersCount,
    required this.calendarCount,
    required this.ratingsCount,
    required this.ratingAverage,
    required this.ratingDistribution,
    required this.totalInteractions,
    required this.engagementRate,
  });

  factory EventStatsEngagement.fromJson(Map<String, dynamic> json) {
    final distMap = <String, int>{};
    if (json['rating_distribution'] is Map) {
      (json['rating_distribution'] as Map).forEach((k, v) {
        distMap[k.toString()] = _toNum(v).toInt();
      });
    }
    return EventStatsEngagement(
      likesCount: _toNum(json['likes_count'] ?? json['likes']).toInt(),
      commentsCount: _toNum(json['comments_count'] ?? json['comments']).toInt(),
      sharesCount: _toNum(json['shares_count'] ?? json['shares']).toInt(),
      uniqueSharersCount: _toNum(json['unique_sharers_count']).toInt(),
      calendarCount: _toNum(json['calendar_additions'] ?? json['calendar_count'] ?? json['agenda_count']).toInt(),
      ratingsCount: _toNum(json['ratings_count'] ?? json['ratings']).toInt(),
      ratingAverage: _toNum(json['rating_average']).toDouble(),
      ratingDistribution: distMap,
      totalInteractions: _toNum(json['total_interactions']).toInt(),
      engagementRate: _toNum(json['engagement_rate']).toDouble(),
    );
  }
}

class EventStatsFunnel {
  final int previewSessions;
  final int agendaAdditions;
  final int uniqueAttendees;
  final int activityParticipants;
  final double previewToAgendaRate;
  final double agendaToAttendanceRate;
  final double attendanceToActivityRate;

  EventStatsFunnel({
    required this.previewSessions,
    required this.agendaAdditions,
    required this.uniqueAttendees,
    required this.activityParticipants,
    required this.previewToAgendaRate,
    required this.agendaToAttendanceRate,
    required this.attendanceToActivityRate,
  });

  factory EventStatsFunnel.fromJson(Map<String, dynamic> json) {
    return EventStatsFunnel(
      previewSessions: _toNum(json['preview_sessions']).toInt(),
      agendaAdditions: _toNum(json['agenda_additions']).toInt(),
      uniqueAttendees: _toNum(json['unique_attendees']).toInt(),
      activityParticipants: _toNum(json['activity_participants']).toInt(),
      previewToAgendaRate: _toNum(json['preview_to_agenda_rate']).toDouble(),
      agendaToAttendanceRate: _toNum(json['agenda_to_attendance_rate']).toDouble(),
      attendanceToActivityRate: _toNum(json['attendance_to_activity_rate']).toDouble(),
    );
  }
}

class ActivityStatsInfo {
  final String activityId;
  final String name;
  final double price;
  final String currencyCode;
  final int participationCount;
  final int uniqueParticipants;
  final double participationRate;
  final double estimatedGrossRevenue;
  final int rankByParticipation;

  ActivityStatsInfo({
    required this.activityId,
    required this.name,
    required this.price,
    required this.currencyCode,
    required this.participationCount,
    required this.uniqueParticipants,
    required this.participationRate,
    required this.estimatedGrossRevenue,
    required this.rankByParticipation,
  });

  factory ActivityStatsInfo.fromJson(Map<String, dynamic> json) {
    return ActivityStatsInfo(
      activityId: (json['activity_id'] ?? '').toString(),
      name: (json['name'] ?? 'Activité').toString(),
      price: _toNum(json['price']).toDouble(),
      currencyCode: (json['currency_code'] ?? 'XAF').toString(),
      participationCount: _toNum(json['participation_count']).toInt(),
      uniqueParticipants: _toNum(json['unique_participants']).toInt(),
      participationRate: _toNum(json['participation_rate']).toDouble(),
      estimatedGrossRevenue: _toNum(json['estimated_gross_revenue'] ?? json['estimated_gross_value']).toDouble(),
      rankByParticipation: _toNum(json['rank_by_participation']).toInt(),
    );
  }
}

class ActivityDepthStats {
  final int attendeesWith0Activities;
  final int attendeesWith1Activity;
  final int attendeesWith2Activities;
  final int attendeesWith3PlusActivities;
  final double averageActivitiesPerAttendee;

  ActivityDepthStats({
    required this.attendeesWith0Activities,
    required this.attendeesWith1Activity,
    required this.attendeesWith2Activities,
    required this.attendeesWith3PlusActivities,
    required this.averageActivitiesPerAttendee,
  });

  factory ActivityDepthStats.fromJson(Map<String, dynamic> json) {
    return ActivityDepthStats(
      attendeesWith0Activities: _toNum(json['attendees_with_0_activities']).toInt(),
      attendeesWith1Activity: _toNum(json['attendees_with_1_activity']).toInt(),
      attendeesWith2Activities: _toNum(json['attendees_with_2_activities']).toInt(),
      attendeesWith3PlusActivities: _toNum(json['attendees_with_3_plus_activities']).toInt(),
      averageActivitiesPerAttendee: _toNum(json['average_activities_per_attendee']).toDouble(),
    );
  }
}

class StaffMemberStatsInfo {
  final String staffUserId;
  final String status;
  final int assignedActivitiesCount;
  final int totalValidatedScans;

  StaffMemberStatsInfo({
    required this.staffUserId,
    required this.status,
    required this.assignedActivitiesCount,
    required this.totalValidatedScans,
  });

  factory StaffMemberStatsInfo.fromJson(Map<String, dynamic> json) {
    return StaffMemberStatsInfo(
      staffUserId: (json['staff_user_id'] ?? '').toString(),
      status: (json['status'] ?? 'accepted').toString(),
      assignedActivitiesCount: _toNum(json['assigned_activities_count']).toInt(),
      totalValidatedScans: _toNum(json['total_validated_scans']).toInt(),
    );
  }
}

class EventStatsStaff {
  final int totalStaff;
  final int staffMembersWithScans;
  final int totalStaffScans;
  final double averageScansPerActiveStaff;
  final List<StaffMemberStatsInfo> staffList;

  EventStatsStaff({
    required this.totalStaff,
    required this.staffMembersWithScans,
    required this.totalStaffScans,
    required this.averageScansPerActiveStaff,
    required this.staffList,
  });

  factory EventStatsStaff.fromJson(Map<String, dynamic> json) {
    final list = <StaffMemberStatsInfo>[];
    if (json['staff_list'] is List) {
      for (var item in (json['staff_list'] as List)) {
        if (item is Map) {
          list.add(StaffMemberStatsInfo.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    return EventStatsStaff(
      totalStaff: _toNum(json['total_staff']).toInt(),
      staffMembersWithScans: _toNum(json['staff_members_with_scans']).toInt(),
      totalStaffScans: _toNum(json['total_staff_scans']).toInt(),
      averageScansPerActiveStaff: _toNum(json['average_scans_per_active_staff']).toDouble(),
      staffList: list,
    );
  }
}

class InvitationFunnelStats {
  final int sent;
  final int accepted;
  final int declined;
  final int pending;
  final double acceptanceRate;

  InvitationFunnelStats({
    required this.sent,
    required this.accepted,
    required this.declined,
    required this.pending,
    required this.acceptanceRate,
  });

  factory InvitationFunnelStats.fromJson(Map<String, dynamic> json) {
    return InvitationFunnelStats(
      sent: _toNum(json['sent']).toInt(),
      accepted: _toNum(json['accepted']).toInt(),
      declined: _toNum(json['declined']).toInt(),
      pending: _toNum(json['pending']).toInt(),
      acceptanceRate: _toNum(json['acceptance_rate']).toDouble(),
    );
  }
}

class EventStatsInvitations {
  final InvitationFunnelStats guestInvitations;
  final InvitationFunnelStats sponsorInvitations;

  EventStatsInvitations({
    required this.guestInvitations,
    required this.sponsorInvitations,
  });

  factory EventStatsInvitations.fromJson(Map<String, dynamic> json) {
    return EventStatsInvitations(
      guestInvitations: InvitationFunnelStats.fromJson(
        json['guest_invitations'] is Map ? Map<String, dynamic>.from(json['guest_invitations'] as Map) : {},
      ),
      sponsorInvitations: InvitationFunnelStats.fromJson(
        json['sponsor_invitations'] is Map ? Map<String, dynamic>.from(json['sponsor_invitations'] as Map) : {},
      ),
    );
  }
}

class EventStatsFinancial {
  final double estimatedActivityRevenue;
  final double estimatedTicketingRevenue;
  final double ticketMinPrice;
  final String currency;
  final bool isRealRevenueAvailable;

  EventStatsFinancial({
    required this.estimatedActivityRevenue,
    required this.estimatedTicketingRevenue,
    required this.ticketMinPrice,
    required this.currency,
    required this.isRealRevenueAvailable,
  });

  factory EventStatsFinancial.fromJson(Map<String, dynamic> json) {
    final realRev = json['real_revenue'] is Map ? json['real_revenue'] as Map : {};
    return EventStatsFinancial(
      estimatedActivityRevenue: _toNum(json['estimated_activity_revenue'] ?? json['activity_estimated_gross_value']).toDouble(),
      estimatedTicketingRevenue: _toNum(json['estimated_ticketing_revenue'] ?? json['ticket_potential_value']).toDouble(),
      ticketMinPrice: _toNum(json['ticket_min_price']).toDouble(),
      currency: (json['currency'] ?? json['currency_code'] ?? 'XAF').toString(),
      isRealRevenueAvailable: realRev['available'] == true,
    );
  }
}

class EventStatsPrestige {
  final double score;
  final double stars;

  EventStatsPrestige({required this.score, required this.stars});

  factory EventStatsPrestige.fromJson(Map<String, dynamic> json) {
    return EventStatsPrestige(
      score: _toNum(json['prestige_score'] ?? json['score']).toDouble(),
      stars: _toNum(json['prestige_stars'] ?? json['stars']).toDouble(),
    );
  }
}

class EventStatsDiscovery {
  final int previewSessions;
  final int uniquePreviewUsers;
  final int ticketSelectionsCount;
  final int activitySelectionsCount;

  EventStatsDiscovery({
    required this.previewSessions,
    required this.uniquePreviewUsers,
    required this.ticketSelectionsCount,
    required this.activitySelectionsCount,
  });

  factory EventStatsDiscovery.fromJson(Map<String, dynamic> json) {
    return EventStatsDiscovery(
      previewSessions: _toNum(json['preview_sessions']).toInt(),
      uniquePreviewUsers: _toNum(json['unique_preview_users']).toInt(),
      ticketSelectionsCount: _toNum(json['ticket_selections_count']).toInt(),
      activitySelectionsCount: _toNum(json['activity_selections_count']).toInt(),
    );
  }
}

class EventTrendPoint {
  final String date;
  final int likes;
  final int comments;
  final int shares;
  final int calendarAdditions;
  final int checkins;

  EventTrendPoint({
    required this.date,
    required this.likes,
    required this.comments,
    required this.shares,
    required this.calendarAdditions,
    required this.checkins,
  });

  factory EventTrendPoint.fromJson(Map<String, dynamic> json) {
    return EventTrendPoint(
      date: (json['date'] ?? '').toString(),
      likes: _toNum(json['likes']).toInt(),
      comments: _toNum(json['comments']).toInt(),
      shares: _toNum(json['shares']).toInt(),
      calendarAdditions: _toNum(json['calendar_additions']).toInt(),
      checkins: _toNum(json['checkins']).toInt(),
    );
  }
}

class EventStatisticsModel {
  final EventStatsInfo event;
  final EventStatsOverview overview;
  final EventStatsAudience audience;
  final EventStatsAttendance attendance;
  final EventStatsEngagement engagement;
  final EventStatsFunnel funnel;
  final List<ActivityStatsInfo> activities;
  final ActivityDepthStats activityDepth;
  final EventStatsStaff staff;
  final EventStatsInvitations invitations;
  final EventStatsFinancial financial;
  final EventStatsPrestige prestige;
  final EventStatsDiscovery discovery;
  final List<EventTrendPoint> trends;
  final DateTime calculatedAt;

  EventStatisticsModel({
    required this.event,
    required this.overview,
    required this.audience,
    required this.attendance,
    required this.engagement,
    required this.funnel,
    required this.activities,
    required this.activityDepth,
    required this.staff,
    required this.invitations,
    required this.financial,
    required this.prestige,
    required this.discovery,
    required this.trends,
    required this.calculatedAt,
  });

  factory EventStatisticsModel.fromJson(Map<String, dynamic> json) {
    final actList = <ActivityStatsInfo>[];
    if (json['activities'] is List) {
      for (var item in (json['activities'] as List)) {
        if (item is Map) {
          actList.add(ActivityStatsInfo.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }

    final trList = <EventTrendPoint>[];
    if (json['trends'] is List) {
      for (var item in (json['trends'] as List)) {
        if (item is Map) {
          trList.add(EventTrendPoint.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }

    final metaMap = json['metadata'] is Map ? Map<String, dynamic>.from(json['metadata'] as Map) : {};

    return EventStatisticsModel(
      event: EventStatsInfo.fromJson(json['event'] is Map ? Map<String, dynamic>.from(json['event'] as Map) : {}),
      overview: EventStatsOverview.fromJson(json['overview'] is Map ? Map<String, dynamic>.from(json['overview'] as Map) : {}),
      audience: EventStatsAudience.fromJson(json['audience'] is Map ? Map<String, dynamic>.from(json['audience'] as Map) : {}),
      attendance: EventStatsAttendance.fromJson(json['attendance'] is Map ? Map<String, dynamic>.from(json['attendance'] as Map) : {}),
      engagement: EventStatsEngagement.fromJson(json['engagement'] is Map ? Map<String, dynamic>.from(json['engagement'] as Map) : {}),
      funnel: EventStatsFunnel.fromJson(json['funnel'] is Map ? Map<String, dynamic>.from(json['funnel'] as Map) : {}),
      activities: actList,
      activityDepth: ActivityDepthStats.fromJson(json['activity_depth'] is Map ? Map<String, dynamic>.from(json['activity_depth'] as Map) : {}),
      staff: EventStatsStaff.fromJson(json['staff'] is Map ? Map<String, dynamic>.from(json['staff'] as Map) : {}),
      invitations: EventStatsInvitations.fromJson(json['invitations'] is Map ? Map<String, dynamic>.from(json['invitations'] as Map) : {}),
      financial: EventStatsFinancial.fromJson(json['financial'] is Map ? Map<String, dynamic>.from(json['financial'] as Map) : {}),
      prestige: EventStatsPrestige.fromJson(json['prestige'] is Map ? Map<String, dynamic>.from(json['prestige'] as Map) : {}),
      discovery: EventStatsDiscovery.fromJson(json['discovery'] is Map ? Map<String, dynamic>.from(json['discovery'] as Map) : {}),
      trends: trList,
      calculatedAt: metaMap['calculated_at'] != null ? DateTime.tryParse(metaMap['calculated_at'].toString()) ?? DateTime.now() : DateTime.now(),
    );
  }

  Map<String, dynamic> rawJson = {};
}
