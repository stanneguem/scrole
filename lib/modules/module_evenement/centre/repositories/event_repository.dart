import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:scrole/app/utils/boot_timing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../externe/services/supabase_event_service.dart';
import '../../interne/controllers/event_controller.dart';
import '../persistence/evenement_local_dao.dart';
import '../models/activity_model.dart';
import '../models/staff_model.dart';
import '../models/co_creator_model.dart';
import '../models/checkin_model.dart';
import '../models/event_transfer_model.dart';
import '../models/event_model.dart';
import '../models/event_preview_model.dart';
import '../models/event_comment.dart';
import '../models/event_day_models.dart';
import '../models/ticket_model.dart';
import '../models/event_guest_invitation_model.dart';
import '../models/event_statistics_model.dart';
import '../models/event_sponsor_invitation_model.dart';
import '../../../../app/repository_global/r2_media_repository.dart';
import '../../../../modules/module_discussion_direct/interne/controllers/contacts_controller.dart';
import '../../../../shared/models/interest_model.dart';

class EventNotFoundException implements Exception {
  final String eventId;
  final String message;

  const EventNotFoundException(this.eventId, [this.message = 'Événement introuvable.']);

  @override
  String toString() => message;
}

class EventRepository {
  final SupabaseEventService _remote;
  final EvenementLocalDao _dao;
  final Map<String, RealtimeChannel> _eventChannels = {};
  final Map<String, bool> _eventSubscribedOnce = {};
  final StreamController<EventModel> _eventUpdatedController = StreamController<EventModel>.broadcast();

  EventRepository(this._remote, this._dao);

  Stream<void> get eventChanges => _dao.eventChanges;
  Stream<EventModel> get onEventUpdated => _eventUpdatedController.stream;

  void notifyEventUpdated(EventModel updatedEvent) {
    debugPrint('[EventRepository] emitting event update for ${updatedEvent.id} (${updatedEvent.name})');
    if (!_eventUpdatedController.isClosed) {
      _eventUpdatedController.add(updatedEvent);
    }
  }

  void subscribeToEventUpdates(String eventId) {
    if (_eventChannels.containsKey(eventId)) return;

    final client = _remote.client;
    final channel = client.channel('event:$eventId')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'events',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'id',
          value: eventId,
        ),
        callback: (payload) async {
          if (payload.eventType == PostgresChangeEvent.delete) {
            // Requirement §7: Purge local cache immediately on event_deleted
            await _dao.deleteEvent(eventId);
          } else {
            await _dao.upsertEvent(payload.newRecord);
          }
        },
      )
      ..onBroadcast(
        event: 'event_deleted',
        callback: (payload) async {
          // Requirement §7: Purge local cache immediately
          await _dao.deleteEvent(eventId);
        },
      )
      ..onBroadcast(
        event: 'event_updated',
        callback: (payload) async {
          try {
            final fresh = await _remote.fetchEventById(eventId);
            await _dao.upsertEvent(fresh);
          } catch (_) {}
        },
      );

    _eventChannels[eventId] = channel;
    
    channel.subscribe((status, error) async {
      if (status == RealtimeSubscribeStatus.subscribed) {
        if (_eventSubscribedOnce[eventId] == true) {
          // RECONNEXION après coupure : Rattrapage ciblé
          debugPrint('[Sync] Event $eventId channel reconnected, refetching fresh details...');
          try {
            // Un simple refetch de cette seule ligne suffit pour combler le trou
            final fresh = await _remote.fetchEventById(eventId);
            await _dao.upsertEvent(fresh);
            debugPrint('[Sync] Event $eventId catch-up completed.');
          } catch (e) {
            debugPrint('[Error] Event catch-up failed for $eventId: $e');
          }
        }
        _eventSubscribedOnce[eventId] = true;
      }
    });
  }

  void unsubscribeFromEventUpdates(String eventId) {
    final channel = _eventChannels.remove(eventId);
    if (channel != null) {
      channel.unsubscribe();
    }
    _eventSubscribedOnce.remove(eventId);
  }

  RealtimeChannel? subscribeToUserEventsRealtime({
    required String userId,
    required Function(String eventId) onEventUpdated,
    required Function(String eventId) onEventDeleted,
  }) {
    final client = _remote.client;
    final session = client.auth.currentSession;
    if (session == null || session.isExpired) {
      debugPrint('[Realtime] Skipping user events subscription: session expired or null');
      return null;
    }
    final channelKey = 'user_events:$userId';
    if (_eventChannels.containsKey(channelKey)) {
      return _eventChannels[channelKey];
    }

    final channel = client.channel(channelKey, opts: const RealtimeChannelConfig(private: true))
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'events',
        callback: (payload) {
          final newRec = payload.newRecord;
          final oldRec = payload.oldRecord;
          final eventId = (newRec['id'] ?? oldRec['id'])?.toString();
          debugPrint('[Realtime] Postgres change on events received for event_id=$eventId');
          if (payload.eventType == PostgresChangeEvent.delete) {
            if (eventId != null && eventId.isNotEmpty) onEventDeleted(eventId);
          } else if (eventId != null && eventId.isNotEmpty) {
            onEventUpdated(eventId);
          }
        },
      )
      ..onBroadcast(
        event: 'event_updated',
        callback: (payload) {
          final eventId = payload['event_id']?.toString();
          if (eventId != null && eventId.isNotEmpty) onEventUpdated(eventId);
        },
      )
      ..onBroadcast(
        event: 'event_validated',
        callback: (payload) {
          final eventId = payload['event_id']?.toString();
          if (eventId != null && eventId.isNotEmpty) onEventUpdated(eventId);
        },
      )
      ..onBroadcast(
        event: 'event_deleted',
        callback: (payload) {
          final eventId = payload['event_id']?.toString();
          if (eventId != null && eventId.isNotEmpty) onEventDeleted(eventId);
        },
      );

    _eventChannels[channelKey] = channel;
    channel.subscribe();
    return channel;
  }

  Future<EventModel> refreshSingleEvent(String eventId) async {
    try {
      final data = await _remote.fetchEventById(eventId);
      await _dao.saveEventStructured(data);
      await _dao.upsertEvent(data);
      final refreshed = EventModel.fromJson(data);
      notifyEventUpdated(refreshed);
      return refreshed;
    } catch (e) {
      if (_isNotFoundException(e)) {
        await purgeEventLocally(eventId);
        throw EventNotFoundException(eventId);
      }
      rethrow;
    }
  }

  Future<List<EventActivityModel>> getEventActivities(String eventId) async {
    final Map<String, EventActivityModel> mergedMap = {};

    // 1. Distant (Serveur)
    try {
      final data = await _remote.fetchEventActivities(eventId);
      debugPrint('[EventRepository] fetchEventActivities returned ${data.length} rows for $eventId');
      for (final row in data) {
        final model = EventActivityModel.fromJson(row);
        final key = model.activityId.isNotEmpty ? model.activityId : model.id;
        if (key.isNotEmpty) {
          mergedMap[key] = model;
        }
      }
    } catch (e) {
      debugPrint('[Error] getEventActivities remote: $e');
    }

    // 2. Local (En attente de poussée)
    try {
      final pending = await _dao.getPendingActivities(eventId);
      for (final row in pending) {
        final donnees = row['donnees'];
        if (donnees == null) continue;
        final data = jsonDecode(donnees.toString());
        final model = EventActivityModel.fromJson({
          ...data,
          'id': row['id'],
          'statut': 'en_attente',
          'statut_sync': row['statut_sync'],
          'activites': {
            'nom': data['nom'] ?? data['name'],
            'description': data['description'],
          }
        });
        final key = model.activityId.isNotEmpty ? model.activityId : model.id;
        if (key.isNotEmpty && !mergedMap.containsKey(key)) {
          mergedMap[key] = model;
        }
      }
    } catch (e) {
      debugPrint('[Error] getEventActivities local: $e');
    }

    final result = mergedMap.values.toList();
    debugPrint('[EventRepository] total event activities loaded for $eventId: ${result.length}');
    return result;
  }

  Future<List<ActivityModel>> searchActivities(String query, {String eventId = ''}) async {
    final data = await _remote.searchActivities(query, eventId: eventId);
    return data.map((e) => ActivityModel.fromJson(e)).toList();
  }

  Future<List<AvailableActivityModel>> fetchActiveActivitiesForEvent({
    required String eventId,
    String? search,
    int limit = 30,
    int offset = 0,
  }) async {
    final data = await _remote.getActiveActivitiesForEvent(
      eventId: eventId,
      search: search,
      limit: limit,
      offset: offset,
    );
    return data.map((e) => AvailableActivityModel.fromJson(e)).toList();
  }

  Future<void> validateActivity(String id, bool accept) async {
    final status = accept ? 'validee' : 'rejetee';
    await _remote.updateEventActivityStatus(id, status);
  }

  Future<List<StaffMemberModel>> getEventStaff(String eventId) async {
    // 1. Distant
    final List<StaffMemberModel> remoteStaff = [];
    try {
      final data = await _remote.fetchEventStaff(eventId);
      remoteStaff.addAll(data.map((e) => StaffMemberModel.fromJson(e)).toList());
    } catch (e) {
      debugPrint('[Error] getEventStaff remote: $e');
    }

    // 2. Local
    final List<StaffMemberModel> localStaff = [];
    try {
      final pending = await _dao.getPendingStaff(eventId);
      for (final row in pending) {
        final donnees = row['donnees'];
        if (donnees == null) continue;
        final data = jsonDecode(donnees.toString());
        localStaff.add(StaffMemberModel.fromJson({
          ...data,
          'id': row['id'],
          'statut': 'en_attente',
          'statut_sync': row['statut_sync'],
          'user_profiles': {
            'user_id': data['user_id'],
            'first_name': data['first_name'],
            'last_name': data['last_name'],
            'photo_url': data['photo_url'],
          }
        }));
      }
    } catch (e) {
      debugPrint('[Error] getEventStaff local: $e');
    }

    return [...localStaff, ...remoteStaff];
  }

  Future<void> addActivityOptimistic({
    required String eventId,
    required String activityId,
    required double price,
    required String currency,
    required String userId,
    required Map<String, dynamic> activityInfo,
  }) async {
    final id = generateLocalId();
    
    // 1. Local
    final localData = {
      ...activityInfo,
      'prix_reel': price,
      'devise': currency,
      'evenement_id': eventId,
      'activite_id': activityId,
    };
    
    await _dao.insertActivity(id: id, userId: userId, eventId: eventId, data: localData);

    try {
      // 2. Distant
      await _remote.addActivityToEvent(
        eventId: eventId,
        activityId: activityId,
        price: price,
        currency: currency,
      );
      // 3. Succès
      await _dao.updateActivitySyncStatus(id, 'synchronise');
    } catch (e) {
      // 4. Échec
      await _dao.updateActivitySyncStatus(id, 'echec', error: e.toString());
      rethrow;
    }
  }

  Future<void> addActivityToEvent({
    required String eventId,
    required String activityId,
    required double price,
    required String currency,
  }) async {
    await _remote.addActivityToEvent(
      eventId: eventId,
      activityId: activityId,
      price: price,
      currency: currency,
    );
  }

  Future<String?> addEventToCalendar(String eventId) async {
    return await _remote.addEventToCalendar(eventId);
  }

  Future<void> removeEventFromCalendar(String eventId) async {
    await _remote.removeEventFromCalendar(eventId);
  }

  Future<void> assignStaffToActivity(String eventActivityId, String staffEvenementId) async {
    await setEventStaffActivities(
      eventStaffId: staffEvenementId,
      activityIds: [eventActivityId],
    );
  }

  Future<void> promoteEventStaffToCoCreator({required String eventId, required String userId}) async {
    await _remote.promoteEventStaffToCoCreator(eventId: eventId, userId: userId);
  }

  Future<void> removeActivity(String id) async {
    await _remote.removeEventActivity(id);
  }

  Future<void> deleteEvent(String eventId) async {
    // 1. Suppression locale immédiate (Optimiste)
    await _dao.deleteEvent(eventId);
    
    // 2. Propagation au backend
    try {
      await _remote.deleteEvent(eventId);
    } catch (e) {
      debugPrint('[Error] deleteEvent remote: $e');
      // On ne re-insert pas forcément l'event en local car l'ordre de suppression 
      // est donné. Si le serveur a une latence de 24h, l'utilisateur ne le verra 
      // quand même plus dans son app locale.
    }
  }

  Future<List<EventModel>> getEvents() async {
    final data = await _remote.fetchEvents();
    return data.map((e) => EventModel.fromJson(e)).toList();
  }

  Future<List<EventModel>> getSuggestedEvents({bool forceRefresh = false}) async {
    final userId = Supabase.instance.client.auth.currentUser?.id ?? 'guest';
    final cacheKey = 'event_suggestions_$userId';
    if (!forceRefresh) {
      final cached = await _dao.getDiscoveryCache(cacheKey);
      if (cached != null) {
        final (payload, cachedAt) = cached;
        final age = DateTime.now().difference(cachedAt);
        if (age < const Duration(hours: 5)) {
          final List<dynamic> list = jsonDecode(payload);
          return _deduplicateRawSuggestions(list);
        }
      }
    }

    try {
      final data = await _remote.fetchSuggestedEvents(limit: 50);
      await _dao.saveDiscoveryCache(cacheKey, jsonEncode(data));
      return _deduplicateRawSuggestions(data);
    } catch (e) {
      debugPrint('[Error] getSuggestedEvents: $e');
      // En cas d'erreur réseau/RPC, on essaie quand même de retourner le cache même s'il est vieux
      final cached = await _dao.getDiscoveryCache(cacheKey);
      if (cached != null) {
        final List<dynamic> list = jsonDecode(cached.$1);
        return _deduplicateRawSuggestions(list);
      }
      rethrow;
    }
  }

  /// Déduplique les événements par catégorie de sorte que (category, event.id) soit strictement unique.
  /// Préserve un même événement s'il est présent dans des catégories DIFFÉRENTES.
  List<EventModel> _deduplicateRawSuggestions(List<dynamic> rawList) {
    final List<EventModel> result = [];
    final Set<String> seenCategoryAndId = {};

    for (final item in rawList) {
      if (item is Map) {
        final map = Map<String, dynamic>.from(item);
        final category = (map['category'] ?? map['categorie'] ?? '').toString().toLowerCase().trim();
        final id = (map['id'] ?? map['evenement_id'] ?? '').toString().trim();
        final key = '${category}_$id';

        if (id.isNotEmpty && seenCategoryAndId.contains(key)) {
          continue; // Saute les doublons au sein d'une MÊME catégorie
        }

        if (id.isNotEmpty) {
          seenCategoryAndId.add(key);
        }
        result.add(EventModel.fromJson(map));
      }
    }
    return result;
  }

  Future<List<EventModel>> getRelevantCalendarEvents({
    required DateTime startMonth,
    int nbMonths = 3,
    bool forceRefresh = false,
  }) async {
    final userId = Supabase.instance.client.auth.currentUser?.id ?? 'guest';
    final startDate = DateTime(startMonth.year, startMonth.month, 1);
    final calculatedEndDate = DateTime(startMonth.year, startMonth.month + nbMonths, 0);
    final maxEndAllowed = startDate.add(const Duration(days: 175));
    final endDate = calculatedEndDate.isBefore(maxEndAllowed) ? calculatedEndDate : maxEndAllowed;

    final startDateStr = '${startDate.year}-${startDate.month.toString().padLeft(2, '0')}-01';
    final endDateStr = '${endDate.year}-${endDate.month.toString().padLeft(2, '0')}-${endDate.day.toString().padLeft(2, '0')}';

    final cacheKey = 'home_calendar_${userId}_${startDateStr}_$endDateStr';

    if (!forceRefresh) {
      final cached = await _dao.getDiscoveryCache(cacheKey);
      if (cached != null) {
        final (payload, cachedAt) = cached;
        final age = DateTime.now().difference(cachedAt);
        if (age < const Duration(hours: 5)) {
          final List<dynamic> list = jsonDecode(payload);
          return _deduplicateCalendarEvents(list);
        }
      }
    }

    try {
      final data = await _remote.fetchHomeCalendarEvents(
        startDate: startDateStr,
        endDate: endDateStr,
      );
      if (data.isNotEmpty) {
        await _dao.saveDiscoveryCache(cacheKey, jsonEncode(data));
      }
      return _deduplicateCalendarEvents(data);
    } catch (e) {
      debugPrint('[Error] getRelevantCalendarEvents: $e');
      final cached = await _dao.getDiscoveryCache(cacheKey);
      if (cached != null) {
        final List<dynamic> list = jsonDecode(cached.$1);
        return _deduplicateCalendarEvents(list);
      }
      return [];
    }
  }

  Future<bool> toggleEventLike(String eventId, bool currentIsLiked) async {
    final userId = _remote.client.auth.currentUser?.id;
    if (userId == null) return currentIsLiked;

    if (currentIsLiked) {
      await _dao.removeLikeStructured(userId, eventId);
      await _remote.removeEventLike(eventId);
      return false;
    } else {
      await _dao.saveLikeStructured(userId, eventId);
      await _remote.addEventLike(eventId);
      return true;
    }
  }

  Future<bool> isEventLikedLocal(String eventId) async {
    final userId = _remote.client.auth.currentUser?.id;
    if (userId == null) return false;
    return await _dao.isEventLikedStructured(userId, eventId);
  }

  Future<int?> shareEvent(String eventId) async {
    try {
      return await _remote.shareEvent(eventId);
    } catch (e) {
      debugPrint('[EventRepository] shareEvent error: $e');
      return null;
    }
  }

  Future<List<EventComment>> getEventComments({
    required String eventId,
    int limit = 20,
    DateTime? beforeCreatedAt,
  }) async {
    try {
      final rawList = await _remote.getEventComments(
        eventId: eventId,
        limit: limit,
        beforeCreatedAt: beforeCreatedAt,
      );
      return rawList.map((m) => EventComment.fromJson(m)).toList();
    } catch (e) {
      debugPrint('[EventRepository] getEventComments error: $e');
      rethrow;
    }
  }

  Future<List<EventComment>> getEventCommentReplies({
    required String commentId,
    int limit = 20,
    DateTime? beforeCreatedAt,
  }) async {
    try {
      final rawList = await _remote.getEventCommentReplies(
        commentId: commentId,
        limit: limit,
        beforeCreatedAt: beforeCreatedAt,
      );
      return rawList.map((m) => EventComment.fromJson(m)).toList();
    } catch (e) {
      debugPrint('[EventRepository] getEventCommentReplies error: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> likeEventComment(String commentId) async {
    try {
      return await _remote.likeEventComment(commentId);
    } catch (e) {
      debugPrint('[EventRepository] likeEventComment error: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> unlikeEventComment(String commentId) async {
    try {
      return await _remote.unlikeEventComment(commentId);
    } catch (e) {
      debugPrint('[EventRepository] unlikeEventComment error: $e');
      rethrow;
    }
  }

  Future<EventComment?> createEventComment({
    required String eventId,
    required String content,
    String? parentCommentId,
  }) async {
    try {
      final rawMap = await _remote.createEventComment(
        eventId: eventId,
        content: content,
        parentCommentId: parentCommentId,
      );
      if (rawMap != null) {
        return EventComment.fromJson(rawMap);
      }
      return null;
    } catch (e) {
      debugPrint('[EventRepository] createEventComment error: $e');
      rethrow;
    }
  }

  RealtimeChannel? subscribeToEventCommentsRealtime(String eventId, VoidCallback onCommentsChanged) {
    final client = _remote.client;
    final channelKey = 'event_comments:$eventId';
    if (_eventChannels.containsKey(channelKey)) {
      return _eventChannels[channelKey];
    }

    final channel = client.channel(channelKey)
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'event_comments',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'event_id',
            value: eventId,
          ),
          callback: (payload) {
            debugPrint('[Realtime] event_comments change received for event_id=$eventId');
            onCommentsChanged();
          },
        );

    _eventChannels[channelKey] = channel;
    channel.subscribe();
    return channel;
  }

  void unsubscribeFromEventCommentsRealtime(String eventId) {
    final channelKey = 'event_comments:$eventId';
    final channel = _eventChannels.remove(channelKey);
    if (channel != null) {
      channel.unsubscribe();
    }
  }

  Future<List<EventOpenDay>> getEventOpenDays(String eventId) async {
    try {
      final rawList = await _remote.getEventOpenDays(eventId);
      return rawList.map((m) => EventOpenDay.fromJson(m)).toList();
    } catch (e) {
      debugPrint('[EventRepository] getEventOpenDays error: $e');
      rethrow;
    }
  }

  Future<void> setEventOpenDays(String eventId, List<DateTime> dates) async {
    try {
      final List<String> formatted = dates.map((d) => DateFormat('yyyy-MM-dd').format(d)).toList();
      await _remote.setEventOpenDays(eventId, formatted);
    } catch (e) {
      debugPrint('[EventRepository] setEventOpenDays error: $e');
      rethrow;
    }
  }

  Future<void> addEventToCalendarWithDays(String eventId, List<DateTime> dates) async {
    try {
      final List<String> formatted = dates.map((d) => DateFormat('yyyy-MM-dd').format(d)).toList();
      await _remote.addEventToCalendarWithDays(eventId, formatted);
    } catch (e) {
      debugPrint('[EventRepository] addEventToCalendarWithDays error: $e');
      rethrow;
    }
  }

  Future<void> updateEventCalendarDays(String eventId, List<DateTime> dates) async {
    try {
      final List<String> formatted = dates.map((d) => DateFormat('yyyy-MM-dd').format(d)).toList();
      await _remote.updateEventCalendarDays(eventId, formatted);
    } catch (e) {
      debugPrint('[EventRepository] updateEventCalendarDays error: $e');
      rethrow;
    }
  }

  Future<List<EventPlannedDay>> getMyEventCalendarDays(String eventId) async {
    try {
      final rawList = await _remote.getMyEventCalendarDays(eventId);
      return rawList.map((m) => EventPlannedDay.fromJson(m)).toList();
    } catch (e) {
      debugPrint('[EventRepository] getMyEventCalendarDays error: $e');
      rethrow;
    }
  }


  Future<Map<String, Map<String, dynamic>>> getMyEventItineraryPlans(String eventId) async {
    try {
      final rows = await _remote.getMyEventItineraryPlans(eventId);
      return {
        for (final row in rows)
          (row['planned_date'] ?? '').toString(): Map<String, dynamic>.from(
            row['plan'] is Map ? row['plan'] as Map : <String, dynamic>{},
          ),
      };
    } catch (e) {
      debugPrint('[EventRepository] getMyEventItineraryPlans error: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getExternalEventItinerary({
    required String userId,
    required String eventId,
  }) async {
    return _remote.getExternalEventItinerary(userId: userId, eventId: eventId);
  }

  Future<void> saveMyEventItineraryPlan({
    required String eventId,
    required String plannedDate,
    required Map<String, dynamic> plan,
  }) async {
    await _remote.saveMyEventItineraryPlan(
      eventId: eventId,
      plannedDate: plannedDate,
      plan: plan,
    );
  }

  Future<List<EventDayAttendance>> getEventDayAttendance(String eventId) async {
    try {
      final rawList = await _remote.getEventDayAttendance(eventId);
      return rawList.map((m) => EventDayAttendance.fromJson(m)).toList();
    } catch (e) {
      debugPrint('[EventRepository] getEventDayAttendance error: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> rateEvent({
    required String eventId,
    required int rating,
  }) async {
    try {
      return await _remote.rateEvent(eventId: eventId, rating: rating);
    } catch (e) {
      debugPrint('[EventRepository] rateEvent error: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> getEventInteractionStats(String eventId) async {
    try {
      return await _remote.getEventInteractionStats(eventId);
    } catch (e) {
      debugPrint('[EventRepository] getEventInteractionStats error: $e');
      return null;
    }
  }

  /// Déduplique les événements du calendrier par event.id.
  List<EventModel> _deduplicateCalendarEvents(List<dynamic> rawList) {
    final Set<String> seenIds = {};
    final List<EventModel> result = [];

    for (final item in rawList) {
      if (item is Map) {
        final map = Map<String, dynamic>.from(item);
        final id = (map['id'] ?? map['evenement_id'] ?? '').toString().trim();

        if (id.isNotEmpty && seenIds.contains(id)) {
          continue; // Saute les événements en double
        }

        if (id.isNotEmpty) {
          seenIds.add(id);
        }
        result.add(EventModel.fromJson(map));
      }
    }
    return result;
  }

  Future<EventModel> getEventById(String id) async {
    try {
      final data = await _remote.fetchEventById(id);
      await _dao.saveEventStructured(data);
      return EventModel.fromJson(data);
    } catch (e) {
      final local = await _dao.getEventStructuredById(id);
      if (local != null) {
        return EventModel.fromJson(local);
      }
      rethrow;
    }
  }

  Future<List<EventModel>> getUserAgenda(String userId) async {
    final data = await _remote.fetchUserAgenda(userId);
    final List<EventModel> events = data.map((item) => EventModel.fromJson(item)).toList();
    events.sort((a, b) => a.startsAt.compareTo(b.startsAt));
    return events;
  }

  Future<List<EventModel>>? _inFlightManagedLocalFuture;

  Future<List<EventModel>> getManagedEventsLocal() async {
    if (_inFlightManagedLocalFuture != null) {
      return await _inFlightManagedLocalFuture!;
    }
    _inFlightManagedLocalFuture = bootMeasureAsync('EventRepository.getManagedEventsLocal', () async {
      final userId = _remote.client.auth.currentUser?.id;
      debugPrint('[Sync] getManagedEventsLocal: Current Session UserId = $userId');
      if (userId == null) return [];

      final List<EventModel> list = [];
      try {
        final structuredLocal = await _dao.getEventsStructured(creatorId: userId);
        debugPrint('[Sync] getManagedEventsLocal: Found ${structuredLocal.length} events in structured local DB');
        for (final row in structuredLocal) {
          try {
            final event = EventModel.fromJson(row);
            list.add(event);
            debugPrint('[Sync] getManagedEventsLocal: Loaded local event ${event.id} (${event.name})');
          } catch (e) {
            debugPrint('[Sync] getManagedEventsLocal: Error parsing local row: $e');
          }
        }
        list.sort((a, b) => b.startsAt.compareTo(a.startsAt));
      } catch (e) {
        debugPrint('[Error] getManagedEventsLocal: $e');
      }
      bootLog('EventRepository.getManagedEventsLocal : ${list.length} événements chargés');
      return list;
    });

    try {
      return await _inFlightManagedLocalFuture!;
    } finally {
      _inFlightManagedLocalFuture = null;
    }
  }

  Future<List<EventModel>> syncManagedEventsRemote() async {
    return await bootMeasureAsync('EventRepository.syncManagedEventsRemote', () async {
      final userId = _remote.client.auth.currentUser?.id;
      debugPrint('[Sync] syncManagedEventsRemote: Current Session UserId = $userId');
      if (userId == null) return [];

      final Map<String, EventModel> merged = {};

      try {
        debugPrint('[Sync] syncManagedEventsRemote: Fetching membership list from remote...');
        final rawMemberships = await _remote.fetchManagedEvents();
        debugPrint('[Sync] syncManagedEventsRemote: Found ${rawMemberships.length} memberships on remote');

        final Map<String, String> roleMap = {};
        for (final m in rawMemberships) {
          final id = (m['evenement_id'] ?? m['id'] ?? '').toString();
          if (id.isNotEmpty && id != 'null') {
            roleMap[id] = (m['role'] ?? 'membre').toString();
          }
        }

        final localEvents = await getManagedEventsLocal();
        for (final e in localEvents) {
          if (e.creatorId == userId || roleMap.containsKey(e.id)) {
            merged[e.id] = e;
          }
        }

        if (roleMap.isNotEmpty) {
          final List<String> eventIds = roleMap.keys.toList();
          debugPrint('[Sync] syncManagedEventsRemote: Fetching summary details for ${eventIds.length} events...');

          final List<Map<String, dynamic>> summaryEventsData = [];
          for (int i = 0; i < eventIds.length; i += 50) {
            final chunk = eventIds.sublist(i, i + 50 > eventIds.length ? eventIds.length : i + 50);
            final chunkData = await _remote.fetchEventSummariesByIds(chunk);
            summaryEventsData.addAll(chunkData);
          }

          final fetchedIds = summaryEventsData.map((e) => (e['id'] ?? '').toString()).toSet();
          final missingIds = eventIds.where((id) => !fetchedIds.contains(id)).toList();
          if (missingIds.isNotEmpty) {
            final truncatedMissing = missingIds.map((id) => id.length > 8 ? '${id.substring(0, 8)}...' : id).join(', ');
            debugPrint('[Sync] syncManagedEventsRemote: ${missingIds.length} event IDs in roleMap not found in remote events table (deleted/purged/RLS): [$truncatedMissing]');
          }

          final List<Map<String, dynamic>> toCache = [];

          for (final json in summaryEventsData) {
            try {
              final id = (json['id'] ?? '').toString();
              if (id.isEmpty || id == 'null') continue;

              final role = roleMap[id];
              final augmentedJson = {...json, 'user_role': role};
              final remoteEvent = EventModel.fromJson(augmentedJson);
              toCache.add(augmentedJson);

              final localSyncStatus = (merged[remoteEvent.id]?.statutSync ?? 'synchronise').toString();
              merged[remoteEvent.id] = remoteEvent.copyWith(
                statutSync: localSyncStatus == 'echec' ? 'echec' : 'synchronise',
              );
            } catch (e) {
              debugPrint('[Sync] syncManagedEventsRemote: Error parsing summary event: $e');
            }
          }

          if (toCache.isNotEmpty) {
            await _dao.upsertEventsBatch(toCache);
          }
        } else {
          // Si aucune adhésion distante mais des événements créés localement par l'utilisateur
          final localEvents = await getManagedEventsLocal();
          for (final e in localEvents) {
            if (e.creatorId == userId) {
              merged[e.id] = e;
            }
          }
        }
      } catch (e) {
        debugPrint('[Error] syncManagedEventsRemote: $e');
      }

      final result = merged.values.toList();
      result.sort((a, b) => b.startsAt.compareTo(a.startsAt));
      debugPrint('[Sync] syncManagedEventsRemote: Total merged events to display = ${result.length}');
      bootLog('EventRepository.syncManagedEventsRemote : ${result.length} événements fusionnés');
      return result;
    });
  }

  Future<List<EventModel>> getManagedEvents() async {
    return await bootMeasureAsync('EventRepository.getManagedEvents', () async {
      final local = await getManagedEventsLocal();
      if (local.isNotEmpty) {
        unawaited(syncManagedEventsRemote());
        return local;
      }
      return await syncManagedEventsRemote();
    });
  }

  Future<List<EventModel>> getStaffEvents() async {
    final userId = _remote.client.auth.currentUser?.id;
    final Map<String, EventModel> merged = {};

    // 1. Distant (Les événements officiels où on est staff)
    try {
      final data = await _remote.fetchStaffActivities();
      for (final json in data) {
        try {
          final event = EventModel.fromJson(json);
          if (event.id.isNotEmpty && event.id != 'null') {
            merged[event.id] = event;
          }
        } catch (e) {
          debugPrint('[Sync] getStaffEvents: Error parsing remote staff event: $e');
        }
      }
    } catch (e) {
      debugPrint('[Error] getStaffEvents remote: $e');
    }

    // 2. Local (Invitations locales en attente, si applicable)
    if (userId != null) {
      try {
        // Pour l'instant, on n'a pas de table cache pour les "evenements tiers" 
        // mais on pourrait scanner staff_locaux si besoin.
      } catch (e) {
        debugPrint('[Error] getStaffEvents local: $e');
      }
    }

    final result = merged.values.toList();
    result.sort((a, b) => b.startsAt.compareTo(a.startsAt));
    return result;
  }

  Future<void> inviteStaffOptimistic(String eventId, String userId, Map<String, dynamic> userData) async {
    final id = generateLocalId();
    
    // 1. Enregistrement local immédiat
    await _dao.insertStaff(
      id: id,
      eventId: eventId,
      userId: userId,
      data: userData,
    );

    try {
      // 2. Appel RPC
      await _remote.inviteStaff(eventId: eventId, userId: userId);
      
      // 3. Succès
      await _dao.updateStaffSyncStatus(id, 'synchronise');
    } catch (e) {
      // 4. Échec
      await _dao.updateStaffSyncStatus(id, 'echec', error: e.toString());
      rethrow;
    }
  }

  Future<void> inviteStaff(String eventId, String userId, {List<String> activityIds = const []}) async {
    final currentUserId = _remote.client.auth.currentUser?.id ?? '';
    await _dao.enqueueOutbox(
      userId: currentUserId,
      eventId: eventId,
      tableName: 'event_staff',
      operation: 'invite_staff',
      payload: {'p_event_id': eventId, 'p_user_id': userId, 'p_activity_ids': activityIds},
    );

    try {
      await _remote.inviteStaff(eventId: eventId, userId: userId, activityIds: activityIds);
    } catch (e) {
      debugPrint('[Outbox Queue] inviteStaff error/offline: $e');
    }
  }

  Future<List<CoCreatorModel>> getEventCoCreators(String eventId) async {
    try {
      final data = await _remote.fetchEventCoCreators(eventId);
      return data.map((e) => CoCreatorModel.fromJson(e)).toList();
    } catch (e) {
      debugPrint('[Error] getEventCoCreators: $e');
      return [];
    }
  }

  Future<void> inviteCoCreatorOptimistic(String eventId, String userId) async {
    final currentUserId = _remote.client.auth.currentUser?.id ?? '';
    await _dao.enqueueOutbox(
      userId: currentUserId,
      eventId: eventId,
      tableName: 'event_co_creators',
      operation: 'invite_co_creator',
      payload: {'p_event_id': eventId, 'p_user_id': userId},
    );

    try {
      await _remote.inviteCoCreator(eventId: eventId, userId: userId);
    } catch (e) {
      debugPrint('[Outbox Queue] inviteCoCreator error/offline: $e');
    }
  }

  Future<void> removeCoCreator(String eventId, String userId) async {
    await _remote.removeEventCoCreator(eventId: eventId, userId: userId);
  }

  Future<void> removeStaff(String eventId, String userId) async {
    await _remote.removeEventStaff(eventId: eventId, userId: userId);
  }

  Future<List<CoCreatorModel>> getMyPendingCoCreatorInvites() async {
    final data = await _remote.fetchMyPendingCoCreatorInvites();
    return data.map((e) => CoCreatorModel.fromJson(e)).toList();
  }

  Future<List<StaffMemberModel>> getMyPendingStaffInvites() async {
    final data = await _remote.fetchMyPendingStaffInvites();
    return data.map((e) => StaffMemberModel.fromJson(e)).toList();
  }

  Future<List<EventTransferModel>> getMyPendingTransfersReceived() async {
    final data = await _remote.fetchMyPendingTransfersReceived();
    return data.map((e) => EventTransferModel.fromJson(e)).toList();
  }

  Future<List<EventTransferModel>> getMyPendingTransfersSent(String eventId) async {
    final data = await _remote.fetchMyPendingTransfersSent(eventId);
    return data.map((e) => EventTransferModel.fromJson(e)).toList();
  }

  Future<void> respondToCoCreatorInvite(String inviteId, bool accept) async {
    await _remote.respondToCoCreatorInvite(inviteId: inviteId, accept: accept);
  }

  Future<void> respondToStaffInvite(String inviteId, bool accept) async {
    await _remote.respondToStaffInvitation(staffEvenementId: inviteId, accept: accept);
  }

  // --- Invitations d'Honneur (Guests) ---

  Future<List<EventGuestInvitationModel>> getEventGuestInvitations(String eventId) async {
    final data = await _remote.fetchEventGuestInvitations(eventId);
    return data.map((e) => EventGuestInvitationModel.fromJson(e)).toList();
  }

  Future<List<ContactModel>> getEligibleGuestCandidates(String eventId, {String? search}) async {
    final data = await _remote.fetchEligibleGuestCandidates(eventId, search: search);
    return data.map((json) {
      final first = (json['first_name'] as String? ?? '').trim();
      final last = (json['last_name'] as String? ?? '').trim();
      final username = (json['username'] as String? ?? '').trim();
      final name = '$first $last'.trim();
      return ContactModel(
        id: json['user_id'] as String? ?? json['id'] as String? ?? '',
        name: name.isEmpty ? (username.isNotEmpty ? username : 'Utilisateur') : name,
        username: username,
        avatarUrl: json['photo_url'] as String?,
      );
    }).toList();
  }

  Future<void> inviteEventGuest({required String eventId, required String userId}) async {
    await _remote.inviteEventGuest(eventId: eventId, userId: userId);
  }

  Future<void> respondToGuestInvite({required String inviteId, required bool accept}) async {
    await _remote.respondToGuestInvite(inviteId: inviteId, accept: accept);
  }

  Future<void> removeEventGuest({required String eventId, required String userId, String? inviteId}) async {
    await _remote.removeEventGuest(eventId: eventId, userId: userId, inviteId: inviteId);
  }

  Future<List<EventGuestInvitationModel>> getMyPendingGuestInvites() async {
    final data = await _remote.fetchMyPendingGuestInvites();
    return data.map((e) => EventGuestInvitationModel.fromJson(e)).toList();
  }

  Future<bool> isUserAcceptedGuest({required String eventId, required String userId}) async {
    return await _remote.isUserAcceptedGuest(eventId: eventId, userId: userId);
  }

  // --- Invitations Sponsor ---

  Future<List<EventSponsorInvitationModel>> getEventSponsorInvitations(String eventId) async {
    final data = await _remote.fetchEventSponsorInvitations(eventId);
    return data.map((e) => EventSponsorInvitationModel.fromJson(e)).toList();
  }

  Future<List<ContactModel>> getEligibleSponsorCandidates(String eventId, {String? search}) async {
    final data = await _remote.fetchEligibleSponsorCandidates(eventId, search: search);
    return data.map((json) {
      final first = (json['first_name'] as String? ?? '').trim();
      final last = (json['last_name'] as String? ?? '').trim();
      final username = (json['username'] as String? ?? '').trim();
      final name = '$first $last'.trim();
      return ContactModel(
        id: json['user_id'] as String? ?? json['id'] as String? ?? '',
        name: name.isEmpty ? (username.isNotEmpty ? username : 'Utilisateur') : name,
        username: username,
        avatarUrl: json['photo_url'] as String?,
      );
    }).toList();
  }

  Future<void> inviteEventSponsor({required String eventId, required String userId}) async {
    await _remote.inviteEventSponsor(eventId: eventId, userId: userId);
  }

  Future<void> respondToSponsorInvite({required String inviteId, required bool accept}) async {
    await _remote.respondToSponsorInvite(inviteId: inviteId, accept: accept);
  }

  Future<void> removeEventSponsor({required String inviteId}) async {
    await _remote.removeEventSponsor(inviteId: inviteId);
  }

  Future<List<EventSponsorInvitationModel>> getMyPendingSponsorInvites() async {
    final data = await _remote.fetchMyPendingSponsorInvites();
    return data.map((e) => EventSponsorInvitationModel.fromJson(e)).toList();
  }

  Future<bool> isUserAcceptedSponsor({required String eventId, required String userId}) async {
    return await _remote.isUserAcceptedSponsor(eventId: eventId, userId: userId);
  }

  Future<List<EventModel>> getPendingEventsAdmin() async {
    final data = await _remote.fetchPendingEventsAdmin();
    return data.map((e) => EventModel.fromJson(e)).toList();
  }

  Future<void> validateEventAdmin(String eventId) async {
    await _remote.validateEventAdmin(eventId);
    final local = await _dao.getEventStructuredById(eventId);
    if (local != null) {
      await _dao.saveEventStructured({...local, 'status': 'active'}, syncStatus: 'synced');
    }
  }

  Future<void> rejectEventAdmin(String eventId, String reason) async {
    await _remote.rejectEventAdmin(eventId, reason);
    final local = await _dao.getEventStructuredById(eventId);
    if (local != null) {
      await _dao.saveEventStructured({...local, 'status': 'rejected'}, syncStatus: 'synced', syncError: reason);
    }
  }

  Future<List<CheckinModel>> getEventCheckinsTree(String eventId) async {
    final data = await _remote.fetchEventCheckinsTree(eventId);
    return data.map((e) => CheckinModel.fromJson(e)).toList();
  }

  Future<CheckinScanResult> scanCheckinOptimistic({
    required String eventId,
    required String targetUserId,
    String? activityId,
    int quantity = 1,
  }) async {
    final currentUserId = _remote.client.auth.currentUser?.id ?? '';
    await _dao.enqueueOutbox(
      userId: currentUserId,
      eventId: eventId,
      tableName: 'event_checkins',
      operation: 'checkin_scan',
      payload: {
        'p_event_id': eventId,
        'p_user_id': targetUserId,
        if (activityId != null) 'p_activity_id': activityId,
        'p_quantite': quantity,
      },
    );

    try {
      final res = await _remote.scanEventCheckin(
        eventId: eventId,
        userId: targetUserId,
        activityId: activityId,
        quantity: quantity,
      );
      return res;
    } catch (e) {
      debugPrint('[Outbox Queue] scanCheckin error/offline: $e');
      rethrow;
    }
  }

  Future<void> invalidateCheckinChain(String checkinId, String reason) async {
    await _remote.invalidateCheckinChain(checkinId: checkinId, reason: reason);
  }

  Future<void> addActivityToEventOptimistic({required String eventId, required String activityId, required double price, String currency = 'XAF'}) async {
    final currentUserId = _remote.client.auth.currentUser?.id ?? '';
    await _dao.enqueueOutbox(
      userId: currentUserId,
      eventId: eventId,
      tableName: 'event_activities',
      operation: 'add_activity',
      payload: {'p_event_id': eventId, 'p_activity_id': activityId, 'p_price': price, 'currency': currency},
    );

    try {
      await _remote.addActivityToEvent(eventId: eventId, activityId: activityId, price: price, currency: currency);
    } catch (e) {
      debugPrint('[Outbox Queue] addActivityToEvent offline/error: $e');
    }
  }

  Future<void> removeActivityFromEventOptimistic({required String eventId, required String activityId}) async {
    final currentUserId = _remote.client.auth.currentUser?.id ?? '';
    await _dao.enqueueOutbox(
      userId: currentUserId,
      eventId: eventId,
      tableName: 'event_activities',
      operation: 'remove_activity',
      payload: {'p_event_id': eventId, 'p_activity_id': activityId},
    );

    try {
      await _remote.removeActivityFromEvent(eventId: eventId, activityId: activityId);
    } catch (e) {
      debugPrint('[Outbox Queue] removeActivityFromEvent offline/error: $e');
    }
  }

  Future<void> updateEventInterestsOptimistic({required String eventId, required List<String> interestIds}) async {
    final currentUserId = _remote.client.auth.currentUser?.id ?? '';
    await _dao.enqueueOutbox(
      userId: currentUserId,
      eventId: eventId,
      tableName: 'event_interests',
      operation: 'update_interests',
      payload: {'p_event_id': eventId, 'p_interest_ids': interestIds},
    );

    try {
      await _remote.updateEventInterests(eventId: eventId, interestIds: interestIds);
    } catch (e) {
      debugPrint('[Outbox Queue] updateEventInterests offline/error: $e');
    }
  }

  Future<void> linkEventToCommunityOptimistic({required String eventId, required String communityId}) async {
    final currentUserId = _remote.client.auth.currentUser?.id ?? '';
    await _dao.enqueueOutbox(
      userId: currentUserId,
      eventId: eventId,
      tableName: 'events',
      operation: 'link_community',
      payload: {'p_event_id': eventId, 'p_community_id': communityId},
    );

    try {
      await _remote.linkEventToCommunity(eventId: eventId, communityId: communityId);
    } catch (e) {
      debugPrint('[Outbox Queue] linkEventToCommunity offline/error: $e');
    }
  }

  Future<EventModel> createEventOptimistic(String userId, Map<String, dynamic> data) async {
    final id = generateLocalId();
    
    final name = (data['name'] ?? data['nom'] ?? 'Événement').toString();
    final slug = (data['slug'] ?? '').toString();
    final description = data['description']?.toString();
    final photo = (data['photo'] ?? data['photo_url'])?.toString();
    final countryId = (data['country_id'] ?? data['pays_id'])?.toString();
    final cityId = (data['city_id'] ?? data['ville_id'])?.toString();
    final startsAt = (data['starts_at'] ?? data['date_debut'] ?? DateTime.now().toUtc().toIso8601String()).toString();
    final endsAt = data['ends_at'] ?? data['date_fin'];
    final isVirtual = data['is_virtual'] == true;
    final virtualLink = (data['virtual_link'] ?? data['online_url'])?.toString();
    final address = (data['address'] ?? data['adresse'])?.toString();
    final isPublic = data['is_public'] != false;
    final isFree = data['is_free'] == true || data['est_gratuit'] == true;
    final realCreatedAt = data['real_created_at']?.toString();

    final localData = {
      'id': id,
      'creator_id': userId,
      'name': name,
      'slug': slug,
      'description': description,
      'photo': photo,
      'country_id': countryId,
      'city_id': cityId,
      'address': address,
      'is_virtual': isVirtual ? 1 : 0,
      'virtual_link': virtualLink,
      'starts_at': startsAt,
      'ends_at': endsAt,
      'is_free': isFree ? 1 : 0,
      'status': 'en_attente',
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    };

    // 1. Enregistrement local immédiat (Offline-first)
    await _dao.saveEventStructured(localData, syncStatus: 'pending_push');

    final rpcParams = <String, dynamic>{
      'p_id': id,
      'p_name': name,
      'p_slug': slug,
      'p_starts_at': startsAt,
      if (description != null && description.isNotEmpty) 'p_description': description,
      if (photo != null && photo.isNotEmpty) 'p_photo': photo,
      'p_is_virtual': isVirtual,
      if (isVirtual && virtualLink != null && virtualLink.isNotEmpty) 'p_virtual_link': virtualLink,
      if (!isVirtual && countryId != null && countryId.isNotEmpty) 'p_country_id': countryId,
      if (!isVirtual && cityId != null && cityId.isNotEmpty) 'p_city_id': cityId,
      if (!isVirtual && address != null && address.isNotEmpty) 'p_address': address,
      if (endsAt != null && endsAt.toString().isNotEmpty) 'p_ends_at': endsAt.toString(),
      'p_is_free': isFree,
      'p_is_public': isPublic,
      if (realCreatedAt != null && realCreatedAt.isNotEmpty) 'p_real_created_at': realCreatedAt,
    };

    // Une certification incluse doit être confirmée par le serveur avant
    // de considérer l'événement comme certifié. On ne met pas cette action en outbox :
    // une création hors ligne ne doit jamais consommer ou simuler un quota.
    if (data['certify_with_subscription'] == true) {
      try {
        final response = await _remote.createCertifiedEvent(rpcParams);
        await _dao.saveEventStructured(response, syncStatus: 'synced');
        return EventModel.fromJson(response);
      } catch (e) {
        await _dao.deleteEvent(id);
        rethrow;
      }
    }

    // 2. Enfilement outbox
    await _dao.enqueueOutbox(
      userId: userId,
      eventId: id,
      tableName: 'events',
      operation: 'create_event',
      payload: rpcParams,
    );

    try {
      // 3. Essai d'appel RPC direct si en ligne
      final response = await _remote.createEvent(rpcParams);
      await _dao.saveEventStructured(response, syncStatus: 'synced');
      return EventModel.fromJson(response);
    } catch (e) {
      final errStr = e.toString().toLowerCase();
      final isNetwork = errStr.contains('socketexception') ||
          errStr.contains('timeout') ||
          errStr.contains('network') ||
          errStr.contains('connection closed') ||
          errStr.contains('handshakeexception');

      if (isNetwork) {
        debugPrint('[Outbox Queue] createEvent offline: $e. Conservé en outbox.');
        return EventModel.fromJson(localData);
      }
      // En cas d'erreur serveur / validation, rethrow l'erreur pour empêcher la navigation! (§8)
      rethrow;
    }
  }

  Future<EventModel> updateEventOptimistic(String id, String userId, Map<String, dynamic> data) async {
    // 1. Fusion avec l'enregistrement local existant pour ne pas perdre les champs non modifiés
    final existingLocal = await _dao.getEventStructuredById(id);

    final mergedMap = <String, dynamic>{
      if (existingLocal != null) ...existingLocal,
      'id': id,
      'creator_id': userId,
      if (data['nom'] != null || data['name'] != null) 'name': data['name'] ?? data['nom'],
      if (data['slug'] != null) 'slug': data['slug'],
      if (data['description'] != null) 'description': data['description'],
      if (data['photo'] != null || data['photo_url'] != null) 'photo': data['photo'] ?? data['photo_url'],
      if (data['pays_id'] != null || data['country_id'] != null) 'country_id': data['country_id'] ?? data['pays_id'],
      if (data['ville_id'] != null || data['city_id'] != null) 'city_id': data['city_id'] ?? data['ville_id'],
      if (data['adresse'] != null || data['address'] != null) 'address': data['address'] ?? data['adresse'],
      if (data['est_virtuel'] != null || data['is_virtual'] != null) 'is_virtual': data['is_virtual'] ?? data['est_virtuel'],
      if (data['lien_virtuel'] != null || data['virtual_link'] != null) 'virtual_link': data['virtual_link'] ?? data['lien_virtuel'],
      if (data['date_debut'] != null || data['starts_at'] != null) 'starts_at': data['starts_at'] ?? data['date_debut'],
      if (data['date_fin'] != null || data['ends_at'] != null) 'ends_at': data['ends_at'] ?? data['date_fin'],
      if (data['est_gratuit'] != null || data['is_free'] != null) 'is_free': data['is_free'] ?? data['est_gratuit'],
      if (data['is_public'] != null || data['est_public'] != null) 'is_public': data['is_public'] ?? data['est_public'],
      'updated_at': DateTime.now().toIso8601String(),
    };

    // 2. Sauvegarde locale immédiate
    await _dao.saveEventStructured(mergedMap, syncStatus: 'pending_push');
    await _dao.upsertEvent(mergedMap);

    // 3. Construction du modèle optimiste et émission locale immédiate
    final optimisticEvent = EventModel.fromJson(mergedMap);
    notifyEventUpdated(optimisticEvent);

    // 4. Outbox
    await _dao.enqueueOutbox(
      userId: userId,
      eventId: id,
      tableName: 'events',
      operation: 'update_event',
      payload: data,
    );

    // 5. Synchronisation backend en arrière-plan (non bloquante)
    unawaited(_syncUpdateWithBackend(id, data, existingLocal));

    return optimisticEvent;
  }

  Future<void> _syncUpdateWithBackend(String id, Map<String, dynamic> data, Map<String, dynamic>? previousLocal) async {
    try {
      await _remote.updateEvent(id, data);
      await _dao.updateEventSyncStatusStructured(id, 'synced');

      // Delete the previous R2 cover only after the server has accepted the new URL.
      final previousPhoto = (previousLocal?['photo'] ?? previousLocal?['photo_url'])?.toString() ?? '';
      final requestedPhoto = (data['photo'] ?? data['photo_url'])?.toString();
      if (requestedPhoto != null &&
          previousPhoto.isNotEmpty && previousPhoto != requestedPhoto) {
        try {
          await deleteEventCover(previousPhoto);
        } catch (cleanupError) {
          debugPrint('[EventRepository] Replaced event cover cleanup deferred: $cleanupError');
        }
      }

      try {
        final freshData = await _remote.fetchEventById(id);
        await _dao.saveEventStructured(freshData, syncStatus: 'synced');
        await _dao.upsertEvent(freshData);
        final reconciledEvent = EventModel.fromJson(freshData);
        notifyEventUpdated(reconciledEvent);
        Get.snackbar(
          'Synchronisé',
          'La modification de l\'événement a été confirmée par le serveur.',
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 3),
        );
      } catch (_) {}
    } catch (e) {
      debugPrint('[Outbox Queue] updateEvent offline/error: $e. Conservé en outbox.');
      final isFatalError = e.toString().toLowerCase().contains('permission_denied') ||
          e.toString().toLowerCase().contains('unauthorized') ||
          e.toString().toLowerCase().contains('violates foreign key constraint') ||
          e.toString().toLowerCase().contains('403') ||
          e.toString().toLowerCase().contains('401');

      if (isFatalError && previousLocal != null) {
        // Rollback en cas de refus fatal backend
        await _dao.saveEventStructured(previousLocal, syncStatus: 'echec', syncError: e.toString());
        await _dao.upsertEvent(previousLocal);
        final restoredEvent = EventModel.fromJson(previousLocal);
        notifyEventUpdated(restoredEvent);
        Get.snackbar(
          'Échec de la modification',
          'La modification n\'a pas pu être enregistrée. Les anciennes informations ont été restaurées.',
          backgroundColor: Colors.red,
          colorText: Colors.white,
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 5),
        );
      }
    }
  }

  Future<void> setEventRestrictions({
    required String eventId,
    int? minAge,
    int? maxAge,
    List<String>? allowedGenders,
    bool? idRequired,
    bool? servesAlcohol,
    bool? overnightEvent,
    bool? smokingAllowed,
    String? otherRestrictions,
    bool? isPublic,
  }) async {
    final previousLocal = await _dao.getEventStructuredById(eventId);

    if (previousLocal != null && isPublic != null) {
      final updatedLocal = <String, dynamic>{
        ...previousLocal,
        'is_public': isPublic ? 1 : 0,
        'updated_at': DateTime.now().toIso8601String(),
      };
      await _dao.saveEventStructured(updatedLocal, syncStatus: 'pending_push');
      await _dao.upsertEvent(updatedLocal);
      final optimisticEvent = EventModel.fromJson(updatedLocal);
      notifyEventUpdated(optimisticEvent);
    }

    unawaited(_syncRestrictionsWithBackend(
      eventId: eventId,
      minAge: minAge,
      maxAge: maxAge,
      allowedGenders: allowedGenders,
      idRequired: idRequired,
      servesAlcohol: servesAlcohol,
      overnightEvent: overnightEvent,
      smokingAllowed: smokingAllowed,
      otherRestrictions: otherRestrictions,
      isPublic: isPublic,
      previousLocal: previousLocal,
    ));
  }

  Future<void> _syncRestrictionsWithBackend({
    required String eventId,
    int? minAge,
    int? maxAge,
    List<String>? allowedGenders,
    bool? idRequired,
    bool? servesAlcohol,
    bool? overnightEvent,
    bool? smokingAllowed,
    String? otherRestrictions,
    bool? isPublic,
    Map<String, dynamic>? previousLocal,
  }) async {
    try {
      if (isPublic != null) {
        await _remote.updateEvent(eventId, {'is_public': isPublic});
      }

      await _remote.setEventRestrictions(
        eventId: eventId,
        minAge: minAge,
        maxAge: maxAge,
        allowedGenders: allowedGenders,
        idRequired: idRequired,
        servesAlcohol: servesAlcohol,
        overnightEvent: overnightEvent,
        smokingAllowed: smokingAllowed,
        otherRestrictions: otherRestrictions,
      );

      final fresh = await refreshSingleEvent(eventId);
      Get.snackbar(
        'Conditions d\'accès',
        'Conditions d\'accès enregistrées avec succès.',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 3),
      );
    } catch (e) {
      debugPrint('[EventRepository] setEventRestrictions error: $e');
      if (previousLocal != null) {
        await _dao.saveEventStructured(previousLocal, syncStatus: 'echec', syncError: e.toString());
        await _dao.upsertEvent(previousLocal);
        final restoredEvent = EventModel.fromJson(previousLocal);
        notifyEventUpdated(restoredEvent);
        Get.snackbar(
          'Échec de l\'enregistrement',
          'Impossible d\'enregistrer les conditions d\'accès. Les anciennes conditions ont été restaurées.',
          backgroundColor: Colors.red,
          colorText: Colors.white,
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 4),
        );
      }
    }
  }

  Future<void> updateEventActivityPrice({
    required String eventActivityId,
    required double newPrice,
    required String eventId,
    String? activityId,
  }) async {
    debugPrint('[ActivityEventPrice] start update eventId=$eventId, activityId=$activityId, eventActivityId=$eventActivityId, newPrice=$newPrice');
    try {
      if (eventActivityId.isNotEmpty) {
        await _remote.client
            .from('event_activities')
            .update({'price': newPrice, 'updated_at': DateTime.now().toIso8601String()})
            .eq('id', eventActivityId);
        debugPrint('[ActivityEventPrice] backend update success for id=$eventActivityId');
      } else if (activityId != null && activityId.isNotEmpty) {
        await _remote.client
            .from('event_activities')
            .update({'price': newPrice, 'updated_at': DateTime.now().toIso8601String()})
            .eq('event_id', eventId)
            .eq('activity_id', activityId);
        debugPrint('[ActivityEventPrice] backend update success for eventId=$eventId, activityId=$activityId');
      }
    } catch (e) {
      debugPrint('[ActivityEventPrice] update failed: $e');
      if (activityId != null && activityId.isNotEmpty) {
        try {
          await _remote.client
              .from('event_activities')
              .update({'price': newPrice})
              .eq('event_id', eventId)
              .eq('activity_id', activityId);
          debugPrint('[ActivityEventPrice] fallback update by event_id & activity_id success');
          return;
        } catch (err) {
          debugPrint('[ActivityEventPrice] fallback update failed: $err');
        }
      }
      rethrow;
    }
  }

  Future<List<StaffMemberModel>> getEventActivityStaff({
    required String eventId,
    required String activityId,
  }) async {
    try {
      final data = await _remote.getEventActivityStaff(eventId: eventId, activityId: activityId);
      return data.map((e) {
        final firstName = (e['first_name'] ?? e['prenom'] ?? '').toString().trim();
        final lastName = (e['last_name'] ?? e['nom'] ?? '').toString().trim();
        final fullName = '$firstName $lastName'.trim();
        final uname = (e['username'] ?? '').toString().trim();
        final nameVal = fullName.isNotEmpty ? fullName : (uname.isNotEmpty ? '@$uname' : 'Utilisateur');

        return StaffMemberModel(
          id: (e['event_staff_id'] ?? e['id'] ?? '').toString(),
          userId: (e['user_id'] ?? '').toString(),
          name: nameVal,
          username: uname.isNotEmpty ? uname : null,
          avatarUrl: e['photo_url']?.toString(),
          status: StaffStatusExt.fromString((e['staff_status'] ?? e['statut'] ?? 'acceptee').toString()),
          invitedAt: DateTime.now(),
        );
      }).toList();
    } catch (e) {
      debugPrint('[EventRepository] getEventActivityStaff error: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getEventStaffStats(String eventStaffId) async {
    return _remote.getEventStaffStats(eventStaffId);
  }

  Future<void> setEventStaffActivities({
    required String eventStaffId,
    required List<String> activityIds,
  }) async {
    await _remote.setEventStaffActivities(
      eventStaffId: eventStaffId,
      activityIds: activityIds,
    );
  }

  Future<void> deleteEventOptimistic(String eventId, String userId) async {
    final local = await _dao.getEventStructuredById(eventId);
    if (local != null) {
      await _dao.saveEventStructured({...local, 'status': 'pending_deletion'}, syncStatus: 'pending_push');
    }

    await _dao.enqueueOutbox(
      userId: userId,
      eventId: eventId,
      tableName: 'events',
      operation: 'delete_event',
      payload: {'p_id': eventId},
    );

    try {
      await _remote.deleteEvent(eventId);
      if (local != null) {
        await _dao.saveEventStructured({...local, 'status': 'pending_deletion'}, syncStatus: 'synced');
      }
    } catch (e) {
      debugPrint('[Outbox Queue] deleteEvent offline/error: $e. Conservé en outbox.');
    }
  }

  Future<String?> addEventToCalendarOptimistic(String eventId, String userId) async {
    await _dao.saveCalendarEventStructured(userId, eventId, syncStatus: 'pending_push');
    await _dao.enqueueOutbox(
      userId: userId,
      eventId: eventId,
      tableName: 'event_calendar',
      operation: 'add_to_calendar',
      payload: {'p_event_id': eventId},
    );

    try {
      final suggestedCommunityId = await _remote.addEventToCalendar(eventId);
      await _dao.saveCalendarEventStructured(userId, eventId, syncStatus: 'synced');
      return suggestedCommunityId;
    } catch (e) {
      debugPrint('[Outbox Queue] addEventToCalendar offline/error: $e. Conservé en outbox.');
      return null;
    }
  }

  Future<void> removeEventFromCalendarOptimistic(String eventId, String userId) async {
    await _dao.removeCalendarEventStructured(userId, eventId);
    await _dao.enqueueOutbox(
      userId: userId,
      eventId: eventId,
      tableName: 'event_calendar',
      operation: 'remove_from_calendar',
      payload: {'p_event_id': eventId},
    );

    try {
      await _remote.removeEventFromCalendar(eventId);
    } catch (e) {
      debugPrint('[Outbox Queue] removeEventFromCalendar offline/error: $e. Conservé en outbox.');
    }
  }

  Future<String> uploadCover(String eventId, File file) async {
    return _remote.uploadEventCover(eventId, file);
  }

  Future<void> deleteEventCover(String publicUrl) async {
    if (publicUrl.trim().isEmpty) return;
    // The R2 repository ignores legacy Supabase Storage URLs, so existing
    // event covers remain untouched until explicitly migrated by a separate task.
    await R2MediaRepository().deleteReplacedPublicMedia(publicUrl);
  }

  Future<void> updateEvent(String id, Map<String, dynamic> data) async {
    await _remote.updateEvent(id, data);
  }

  Future<String> proposeTransfer(String eventId, String targetUserId) async {
    return await _remote.proposeTransfer(eventId: eventId, targetUserId: targetUserId);
  }

  Future<EventStatisticsModel> getEventStatistics(String eventId, {bool forceRefresh = false}) async {
    // Les statistiques sont une fonctionnalité protégée par la certification active.
    // Ne jamais servir un cache local avant la validation serveur : la certification
    // peut avoir expiré ou avoir été suspendue depuis le dernier affichage.
    try {
      final data = await _remote.getEventStatistics(eventId: eventId);
      if (data.isNotEmpty) {
        final userId = Supabase.instance.client.auth.currentUser?.id ?? 'guest';
        final cacheKey = 'event_statistics_${userId}_$eventId';
        await _dao.saveDiscoveryCache(cacheKey, jsonEncode(data));
        return EventStatisticsModel.fromJson(data);
      }
      throw Exception('Aucune statistique disponible pour cet événement.');
    } catch (e) {
      debugPrint('[Error] getEventStatistics refused or unavailable for $eventId: $e');
      // Pas de repli vers le cache : il pourrait révéler des statistiques après
      // expiration/suspension de la certification ou changement des droits.
      rethrow;
    }
  }

  Future<void> updateEventPricing({required String eventId, required bool isFree}) async {
    final previousLocal = await _dao.getEventStructuredById(eventId);
    if (previousLocal != null) {
      final updatedLocal = <String, dynamic>{
        ...previousLocal,
        'is_free': isFree ? 1 : 0,
        'est_gratuit': isFree ? 1 : 0,
        'updated_at': DateTime.now().toIso8601String(),
      };
      await _dao.saveEventStructured(updatedLocal, syncStatus: 'pending_push');
      await _dao.upsertEvent(updatedLocal);
      final optimisticEvent = EventModel.fromJson(updatedLocal);
      notifyEventUpdated(optimisticEvent);
    }

    try {
      await _remote.updateEventPricing(eventId: eventId, isFree: isFree);
      final fresh = await refreshSingleEvent(eventId);
      if (fresh != null) {
        notifyEventUpdated(fresh);
      }
    } catch (e) {
      debugPrint('[EventRepository] updateEventPricing remote error: $e');
      if (previousLocal != null) {
        await _dao.saveEventStructured(previousLocal, syncStatus: 'echec', syncError: e.toString());
        await _dao.upsertEvent(previousLocal);
        final restoredEvent = EventModel.fromJson(previousLocal);
        notifyEventUpdated(restoredEvent);
      }
      rethrow;
    }
  }

  Future<List<Interest>> getEventInterests(String eventId) async {
    try {
      final data = await _remote.fetchEventInterests(eventId);
      final List<Interest> list = [];
      for (final row in data) {
        if (row['interests'] is Map) {
          list.add(Interest.fromJson(Map<String, dynamic>.from(row['interests'] as Map)));
        }
      }
      return list;
    } catch (e) {
      debugPrint('[EventRepository] getEventInterests error: $e');
      return [];
    }
  }

  Future<void> updateEventInterests({required String eventId, required List<String> interestIds}) async {
    await _remote.updateEventInterests(eventId: eventId, interestIds: interestIds);
  }

  Future<List<EventTransferModel>> getEventTransferProposals(String eventId) async {
    try {
      final data = await _remote.getEventTransferProposals(eventId: eventId);
      return data.map((e) => EventTransferModel.fromJson(e)).toList();
    } catch (e) {
      debugPrint('[EventRepository] getEventTransferProposals error: $e');
      return [];
    }
  }

  Future<void> cancelTransfer(String transferId) async {
    await _remote.cancelTransfer(transferId);
  }

  Future<void> respondToTransfer(String transferId, bool accept) async {
    await _remote.respondToTransfer(transferId: transferId, accept: accept);
  }

  Future<void> respondToStaffInvitation(String staffEvenementId, bool accept) async {
    await _remote.respondToStaffInvitation(staffEvenementId: staffEvenementId, accept: accept);
  }

  Future<List<TicketModel>> getEventTickets(String eventId) async {
    // 1. Distant
    final List<TicketModel> remoteTickets = [];
    try {
      final data = await _remote.fetchEventTickets(eventId);
      remoteTickets.addAll(data.map((e) => TicketModel.fromJson(e)).toList());
    } catch (e) {
      debugPrint('[Error] getEventTickets remote: $e');
    }

    // 2. Local
    final List<TicketModel> localTickets = [];
    try {
      final pending = await _dao.getPendingTickets(eventId);
      for (final row in pending) {
        final donnees = row['donnees'];
        if (donnees == null) continue;
        final data = jsonDecode(donnees.toString());
        localTickets.add(TicketModel.fromJson({
          ...data,
          'id': row['id'],
          'statut_sync': row['statut_sync'],
        }));
      }
    } catch (e) {
      debugPrint('[Error] getEventTickets local: $e');
    }

    return [...localTickets, ...remoteTickets];
  }

  Future<void> addTicketOptimistic(Map<String, dynamic> data) async {
    final id = generateLocalId();
    final eventId = (data['evenement_id'] ?? data['event_id'] ?? '').toString();
    final currentUserId = _remote.client.auth.currentUser?.id ?? '';

    // 1. Local
    await _dao.insertTicket(id: id, eventId: eventId, data: data);

    try {
      // 2. Distant
      await _remote.addTicket(data);
      await _dao.deleteTicketLocal(id);
    } catch (e) {
      debugPrint('[Outbox Queue] addTicket remote failed: $e. Cleaning up local temporary ticket...');
      await _dao.deleteTicketLocal(id);
      rethrow;
    }
  }

  Future<void> addTicket(Map<String, dynamic> data) async {
    await addTicketOptimistic(data);
  }

  Future<void> deleteTicket(String id, {String eventId = ''}) async {
    final currentUserId = _remote.client.auth.currentUser?.id ?? '';
    await _dao.deleteTicketLocal(id);

    try {
      if (!id.startsWith('local_')) {
        await _remote.deleteTicket(id);
      }
    } catch (e) {
      debugPrint('[Outbox Queue] deleteTicket offline/error: $e');
    }
  }

  Future<CheckinScanResult> scanEntry(String eventId, String userId, String scannerId) async {
    return await _remote.scanEventCheckin(eventId: eventId, userId: userId);
  }

  Future<String?> scanActivity(String eventActivityId, String userId, String scannerId) async {
    return await _remote.scanActivity(eventActivityId: eventActivityId, userId: userId, scannerId: scannerId);
  }

  bool _isNotFoundException(dynamic error) {
    final str = error.toString().toLowerCase();
    return str.contains('event_not_found') ||
        str.contains('événement introuvable') ||
        str.contains('evenement introuvable') ||
        str.contains('introuvable') ||
        str.contains('pgrst116') ||
        str.contains('row not found') ||
        str.contains('no rows returned') ||
        str.contains('not found');
  }

  bool _isNetworkError(dynamic error) {
    final str = error.toString().toLowerCase();
    return str.contains('socketexception') ||
        str.contains('timeout') ||
        str.contains('network') ||
        str.contains('connection closed') ||
        str.contains('handshakeexception');
  }

  Future<void> purgeEventLocally(String eventId) async {
    debugPrint('[EventPreview] request eventId=$eventId');
    debugPrint('[EventPreview] backend result=EVENT_NOT_FOUND');
    debugPrint('[EventCache] purge eventId=$eventId');

    await _dao.deleteEvent(eventId);
    debugPrint('[EventCache] event removed from SQLite');

    if (Get.isRegistered<EventController>()) {
      Get.find<EventController>().purgeEventFromMemory(eventId);
    }

    debugPrint('[EventCache] preview removed eventId=$eventId');
    debugPrint('[EventState] selectedEventId cleared eventId=$eventId');
  }

  Future<EventPreviewModel> getEventPreviewOwner(String eventId) async {
    try {
      final data = await _remote.getEventPreviewOwner(eventId);
      final model = EventPreviewModel.fromJson(data);
      if (data['event'] is Map) {
        await _dao.saveEventStructured(Map<String, dynamic>.from(data['event'] as Map));
      }
      return model;
    } catch (e) {
      if (_isNotFoundException(e)) {
        await purgeEventLocally(eventId);
        throw EventNotFoundException(eventId);
      }
      if (_isNetworkError(e)) {
        debugPrint('[Error] getEventPreviewOwner network error: $e. Using local cache...');
        final local = await _dao.getEventStructuredById(eventId);
        if (local != null) {
          return EventPreviewModel(event: EventModel.fromJson(local));
        }
      }
      rethrow;
    }
  }

  Future<EventPreviewModel> getEventPreviewPublic(String eventId) async {
    try {
      final data = await _remote.getEventPreviewPublic(eventId);
      final model = EventPreviewModel.fromJson(data);
      if (data['event'] is Map) {
        await _dao.saveEventStructured(Map<String, dynamic>.from(data['event'] as Map));
      }
      return model;
    } catch (e) {
      if (_isNotFoundException(e)) {
        await purgeEventLocally(eventId);
        throw EventNotFoundException(eventId);
      }
      if (_isNetworkError(e)) {
        debugPrint('[Error] getEventPreviewPublic network error: $e. Using local cache...');
        final local = await _dao.getEventStructuredById(eventId);
        if (local != null) {
          return EventPreviewModel(event: EventModel.fromJson(local));
        }
      }
      rethrow;
    }
  }

  Future<EventPreviewModel> getEventPreviewStaff(String eventId) async {
    try {
      final data = await _remote.getEventPreviewStaff(eventId);
      final model = EventPreviewModel.fromJson(data);
      if (data['event'] is Map) {
        await _dao.saveEventStructured(Map<String, dynamic>.from(data['event'] as Map));
      }
      return model;
    } catch (e) {
      if (_isNotFoundException(e)) {
        await purgeEventLocally(eventId);
        throw EventNotFoundException(eventId);
      }
      if (_isNetworkError(e)) {
        debugPrint('[Error] getEventPreviewStaff network error: $e. Using local cache...');
        final local = await _dao.getEventStructuredById(eventId);
        if (local != null) {
          return EventPreviewModel(event: EventModel.fromJson(local));
        }
      }
      rethrow;
    }
  }

  Future<EventPreviewModel> getEventPreview(String eventId) async {
    final userId = _remote.client.auth.currentUser?.id;
    try {
      final local = await _dao.getEventStructuredById(eventId);
      final isOwner = local != null && local['creator_id'] == userId;

      if (isOwner) {
        return await getEventPreviewOwner(eventId);
      }
      try {
        return await getEventPreviewPublic(eventId);
      } catch (e) {
        if (_isNotFoundException(e)) {
          await purgeEventLocally(eventId);
          throw EventNotFoundException(eventId);
        }
        return await getEventPreviewOwner(eventId);
      }
    } catch (e) {
      if (_isNotFoundException(e)) {
        await purgeEventLocally(eventId);
        throw EventNotFoundException(eventId);
      }
      debugPrint('[Error] getEventPreview cascade failed: $e. Trying base...');
      try {
        final data = await _remote.getEventPreviewBase(eventId);
        return EventPreviewModel.fromJson(data);
      } catch (err) {
        if (_isNotFoundException(err)) {
          await purgeEventLocally(eventId);
          throw EventNotFoundException(eventId);
        }
        if (_isNetworkError(err)) {
          final local = await _dao.getEventStructuredById(eventId);
          if (local != null) {
            return EventPreviewModel(event: EventModel.fromJson(local));
          }
        }
        rethrow;
      }
    }
  }

  String generateLocalId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // Version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // Variant IETF
    String hex(int b) => b.toRadixString(16).padLeft(2, '0');
    final chars = bytes.map(hex).join();
    return '${chars.substring(0, 8)}-${chars.substring(8, 12)}-${chars.substring(12, 16)}-${chars.substring(16, 20)}-${chars.substring(20, 32)}';
  }
}
