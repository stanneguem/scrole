import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../app/repository_global/r2_media_repository.dart';
import '../../centre/models/checkin_model.dart';

class SupabaseEventService {
  final SupabaseClient _client;

  SupabaseEventService(this._client);

  SupabaseClient get client => _client;

  Future<List<Map<String, dynamic>>> fetchEventActivities(String eventId) async {
    try {
      final response = await _client
          .from('event_activities')
          .select('*, activities(*)')
          .eq('event_id', eventId);
      debugPrint('[SupabaseEventService] fetchEventActivities returned ${response.length} rows for $eventId');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('[SupabaseEventService] fetchEventActivities main query failed: $e. Trying fallback query...');
      try {
        final response = await _client
            .from('event_activities')
            .select()
            .eq('event_id', eventId);
        return List<Map<String, dynamic>>.from(response);
      } catch (err) {
        debugPrint('[SupabaseEventService] fetchEventActivities fallback failed: $err');
        return [];
      }
    }
  }

  Future<List<Map<String, dynamic>>> getActiveActivitiesForEvent({
    required String eventId,
    String? search,
    int limit = 30,
    int offset = 0,
  }) async {
    try {
      final response = await _client.rpc('get_active_activities_for_event', params: {
        'p_event_id': eventId,
        'p_search': (search != null && search.trim().isNotEmpty) ? search.trim() : null,
        'p_limit': limit,
        'p_offset': offset,
      });
      if (response is List) {
        return response.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('[SupabaseEventService] get_active_activities_for_event error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> searchActivities(String query, {String eventId = ''}) async {
    if (eventId.isNotEmpty) {
      return getActiveActivitiesForEvent(eventId: eventId, search: query);
    }
    try {
      var request = _client.from('activities').select();
      if (query.isNotEmpty) {
        request = request.ilike('name', '%$query%');
      }
      final response = await request.limit(30);
      return List<Map<String, dynamic>>.from(response);
    } catch (_) {
      return [];
    }
  }

  Future<void> updateEventActivityStatus(String id, String status) async {
    await _client
        .from('event_activities')
        .update({'status': status})
        .eq('id', id);
  }

  Future<List<Map<String, dynamic>>> fetchEventStaff(String eventId) async {
    try {
      final response = await _client
          .from('event_staff')
          .select('*, user_profiles!event_staff_user_id_fkey(user_id, first_name, last_name, photo_url, username)')
          .eq('event_id', eventId);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      final response = await _client
          .from('event_staff')
          .select('*, user_profiles(user_id, first_name, last_name, photo_url, username)')
          .eq('event_id', eventId);
      return List<Map<String, dynamic>>.from(response);
    }
  }

  Future<List<Map<String, dynamic>>> fetchEventCoCreators(String eventId) async {
    try {
      final response = await _client
          .from('event_co_creators')
          .select('*, user_profiles!event_co_creators_user_id_fkey(user_id, first_name, last_name, photo_url, username)')
          .eq('event_id', eventId);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      final response = await _client
          .from('event_co_creators')
          .select('*, user_profiles(user_id, first_name, last_name, photo_url, username)')
          .eq('event_id', eventId);
      return List<Map<String, dynamic>>.from(response);
    }
  }

  Future<List<Map<String, dynamic>>> fetchMyPendingCoCreatorInvites() async {
    final response = await _client
        .from('event_co_creators')
        .select('*, events(id, name, photo)')
        .eq('user_id', _client.auth.currentUser?.id ?? '')
        .eq('status', 'en_attente');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> fetchMyPendingStaffInvites() async {
    final response = await _client
        .from('event_staff')
        .select('*, events(id, name, photo)')
        .eq('user_id', _client.auth.currentUser?.id ?? '')
        .eq('status', 'en_attente');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> addActivityToEvent({
    required String eventId,
    required String activityId,
    required double price,
    required String currency,
  }) async {
    try {
      await _client.rpc('add_activity_to_event', params: {
        'p_event_id': eventId,
        'p_activity_id': activityId,
        'p_price': price,
      });
    } catch (_) {
      await _client.from('event_activities').insert({
        'event_id': eventId,
        'activity_id': activityId,
        'price': price,
        'currency': currency,
      });
    }
  }

  Future<List<Map<String, dynamic>>> getEventActivityStaff({
    required String eventId,
    required String activityId,
  }) async {
    try {
      final response = await _client.rpc('get_event_activity_staff', params: {
        'p_event_id': eventId,
        'p_activity_id': activityId,
      });
      if (response is List) {
        return response.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('[SupabaseEventService] getEventActivityStaff error: $e');
      rethrow;
    }
  }

  Future<void> assignStaffToActivity(String eventActivityId, String staffEvenementId) async {
    await setEventStaffActivities(
      eventStaffId: staffEvenementId,
      activityIds: [eventActivityId],
    );
  }

  Future<void> removeEventActivity(String id) async {
    try {
      await _client.from('event_activities').delete().eq('id', id);
    } catch (e) {
      debugPrint('[SupabaseEventService] removeEventActivity error: $e');
    }
  }

  Future<List<Map<String, dynamic>>> fetchEventInterests(String eventId) async {
    try {
      final response = await _client
          .from('event_interests')
          .select('interest_id, interests(*)')
          .eq('event_id', eventId);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('[SupabaseEventService] fetchEventInterests error: $e');
      return [];
    }
  }

  Future<void> removeActivityFromEvent({required String eventId, required String activityId}) async {
    try {
      await _client.rpc('remove_activity_from_event', params: {
        'p_event_id': eventId,
        'p_activity_id': activityId,
      });
    } catch (e) {
      debugPrint('[Error] RPC remove_activity_from_event failed: $e. Fallback to delete...');
      await _client.from('event_activities').delete().eq('event_id', eventId).eq('activity_id', activityId);
    }
  }

  Future<void> updateEventInterests({required String eventId, required List<String> interestIds}) async {
    try {
      await _client.rpc('update_event_interests', params: {
        'p_event_id': eventId,
        'p_interest_ids': interestIds,
      });
    } catch (e) {
      debugPrint('[Error] RPC update_event_interests failed: $e');
    }
  }

  Future<void> linkEventToCommunity({required String eventId, required String communityId}) async {
    try {
      await _client.rpc('link_event_to_community', params: {
        'p_event_id': eventId,
        'p_community_id': communityId,
      });
    } catch (e) {
      debugPrint('[Error] RPC link_event_to_community failed: $e');
    }
  }

  Future<void> addEventLike(String eventId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await _client.from('event_likes').insert({
        'user_id': userId,
        'event_id': eventId,
      });
    } catch (e) {
      debugPrint('[SupabaseEventService] addEventLike error: $e');
      rethrow;
    }
  }

  Future<void> removeEventLike(String eventId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await _client
          .from('event_likes')
          .delete()
          .eq('user_id', userId)
          .eq('event_id', eventId);
    } catch (e) {
      debugPrint('[SupabaseEventService] removeEventLike error: $e');
      rethrow;
    }
  }

  Future<int?> shareEvent(String eventId) async {
    try {
      final response = await _client.rpc('share_event', params: {'p_event_id': eventId});
      debugPrint('[SupabaseEventService] share_event RPC response: $response');
      if (response is num) return response.toInt();
      if (response is Map) {
        final map = Map<String, dynamic>.from(response);
        if (map['unique_sharers_count'] != null) {
          return (map['unique_sharers_count'] as num).toInt();
        }
        if (map['share_count'] != null) {
          return (map['share_count'] as num).toInt();
        }
      }
      if (response is List && response.isNotEmpty) {
        final first = response.first;
        if (first is num) return first.toInt();
        if (first is Map) {
          if (first['unique_sharers_count'] != null) {
            return (first['unique_sharers_count'] as num).toInt();
          }
          if (first['share_count'] != null) {
            return (first['share_count'] as num).toInt();
          }
        }
      }
      return null;
    } catch (e) {
      debugPrint('[Error] RPC share_event failed: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getEventComments({
    required String eventId,
    int limit = 20,
    DateTime? beforeCreatedAt,
  }) async {
    try {
      final response = await _client.rpc('get_event_comments', params: {
        'p_event_id': eventId,
        'p_limit': limit,
        'p_before_created_at': beforeCreatedAt?.toIso8601String(),
      });
      debugPrint('[SupabaseEventService] get_event_comments RPC count: ${(response as List?)?.length}');
      if (response is List) {
        return response.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('[Error] RPC get_event_comments failed: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getEventCommentReplies({
    required String commentId,
    int limit = 20,
    DateTime? beforeCreatedAt,
  }) async {
    try {
      final response = await _client.rpc('get_event_comment_replies', params: {
        'p_comment_id': commentId,
        'p_limit': limit,
        'p_before_created_at': beforeCreatedAt?.toIso8601String(),
      });
      debugPrint('[SupabaseEventService] get_event_comment_replies RPC count: ${(response as List?)?.length}');
      if (response is List) {
        return response.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('[Error] RPC get_event_comment_replies failed: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> likeEventComment(String commentId) async {
    try {
      final response = await _client.rpc('like_event_comment', params: {
        'p_comment_id': commentId,
      });
      debugPrint('[SupabaseEventService] like_event_comment RPC response: $response');
      if (response is Map) {
        return Map<String, dynamic>.from(response);
      }
      if (response is List && response.isNotEmpty && response.first is Map) {
        return Map<String, dynamic>.from(response.first as Map);
      }
      return null;
    } catch (e) {
      debugPrint('[Error] RPC like_event_comment failed: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> unlikeEventComment(String commentId) async {
    try {
      final response = await _client.rpc('unlike_event_comment', params: {
        'p_comment_id': commentId,
      });
      debugPrint('[SupabaseEventService] unlike_event_comment RPC response: $response');
      if (response is Map) {
        return Map<String, dynamic>.from(response);
      }
      if (response is List && response.isNotEmpty && response.first is Map) {
        return Map<String, dynamic>.from(response.first as Map);
      }
      return null;
    } catch (e) {
      debugPrint('[Error] RPC unlike_event_comment failed: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> createEventComment({
    required String eventId,
    required String content,
    String? parentCommentId,
  }) async {
    try {
      final response = await _client.rpc('create_event_comment', params: {
        'p_event_id': eventId,
        'p_content': content,
        'p_parent_comment_id': parentCommentId,
      });
      debugPrint('[SupabaseEventService] create_event_comment RPC response: $response');
      if (response is Map) {
        return Map<String, dynamic>.from(response);
      }
      if (response is List && response.isNotEmpty && response.first is Map) {
        return Map<String, dynamic>.from(response.first as Map);
      }
      return null;
    } catch (e) {
      debugPrint('[Error] RPC create_event_comment failed: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> rateEvent({
    required String eventId,
    required int rating,
  }) async {
    try {
      final response = await _client.rpc('rate_event', params: {
        'p_event_id': eventId,
        'p_rating': rating,
      });
      debugPrint('[SupabaseEventService] rate_event response: $response');
      if (response is Map) {
        return Map<String, dynamic>.from(response);
      }
      return null;
    } catch (e) {
      debugPrint('[Error] RPC rate_event failed: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> getEventInteractionStats(String eventId) async {
    try {
      final response = await _client.rpc('get_event_interaction_stats', params: {
        'p_event_id': eventId,
      });
      debugPrint('[SupabaseEventService] get_event_interaction_stats response: $response');
      if (response is Map) {
        return Map<String, dynamic>.from(response);
      }
      return null;
    } catch (e) {
      debugPrint('[Error] RPC get_event_interaction_stats failed: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getEventOpenDays(String eventId) async {
    try {
      final response = await _client.rpc('get_event_open_days', params: {'p_event_id': eventId});
      debugPrint('[SupabaseEventService] get_event_open_days response: $response');
      if (response is List) {
        return response.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('[Error] RPC get_event_open_days failed: $e');
      rethrow;
    }
  }

  Future<void> setEventOpenDays(String eventId, List<String> dates) async {
    try {
      await _client.rpc('set_event_open_days', params: {
        'p_event_id': eventId,
        'p_dates': dates,
      });
      debugPrint('[SupabaseEventService] set_event_open_days successful');
    } catch (e) {
      debugPrint('[Error] RPC set_event_open_days failed: $e');
      rethrow;
    }
  }

  Future<void> addEventToCalendarWithDays(String eventId, List<String> dates) async {
    try {
      await _client.rpc('add_event_to_calendar_with_days', params: {
        'p_event_id': eventId,
        'p_dates': dates,
      });
      debugPrint('[SupabaseEventService] add_event_to_calendar_with_days successful');
    } catch (e) {
      debugPrint('[Error] RPC add_event_to_calendar_with_days failed: $e');
      rethrow;
    }
  }

  Future<void> updateEventCalendarDays(String eventId, List<String> dates) async {
    try {
      await _client.rpc('update_event_calendar_days', params: {
        'p_event_id': eventId,
        'p_dates': dates,
      });
      debugPrint('[SupabaseEventService] update_event_calendar_days successful');
    } catch (e) {
      debugPrint('[Error] RPC update_event_calendar_days failed: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getMyEventCalendarDays(String eventId) async {
    try {
      final response = await _client.rpc('get_my_event_calendar_days', params: {'p_event_id': eventId});
      debugPrint('[SupabaseEventService] get_my_event_calendar_days response: $response');
      if (response is List) {
        return response.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('[Error] RPC get_my_event_calendar_days failed: $e');
      rethrow;
    }
  }


  Future<List<Map<String, dynamic>>> getMyEventItineraryPlans(String eventId) async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Vous devez être connecté pour consulter votre planning.');
    final response = await _client
        .from('event_itinerary_plans')
        .select('planned_date, plan')
        .eq('event_id', eventId)
        .eq('user_id', user.id)
        .order('planned_date');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<Map<String, dynamic>> getExternalEventItinerary({
    required String userId,
    required String eventId,
  }) async {
    final response = await _client.rpc('get_external_event_itinerary', params: {
      'p_user_id': userId,
      'p_event_id': eventId,
    });
    if (response is Map) return Map<String, dynamic>.from(response);
    throw StateError('Réponse de planning invalide.');
  }

  Future<void> saveMyEventItineraryPlan({
    required String eventId,
    required String plannedDate,
    required Map<String, dynamic> plan,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Vous devez être connecté pour enregistrer un planning.');
    await _client.from('event_itinerary_plans').upsert({
      'user_id': user.id,
      'event_id': eventId,
      'planned_date': plannedDate,
      'plan': plan,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id,event_id,planned_date');
  }

  Future<List<Map<String, dynamic>>> getEventDayAttendance(String eventId) async {
    try {
      final response = await _client.rpc('get_event_day_attendance', params: {'p_event_id': eventId});
      debugPrint('[SupabaseEventService] get_event_day_attendance response: $response');
      if (response is List) {
        return response.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('[Error] RPC get_event_day_attendance failed: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> deleteEvent(String eventId) async {
    try {
      final response = await _client.rpc('delete_event', params: {'p_id': eventId});
      if (response == null) return null;
      return Map<String, dynamic>.from(response is List ? response.first : response);
    } catch (e) {
      debugPrint('[Error] RPC delete_event failed: $e. Trying fallback supprimer_evenement...');
      await _client.rpc('supprimer_evenement', params: {'p_evenement_id': eventId});
      return null;
    }
  }

  Future<String> inviteStaff({required String eventId, required String userId, List<String> activityIds = const []}) async {
    try {
      final response = await _client.rpc('invite_event_staff', params: {
        'p_event_id': eventId,
        'p_user_id': userId,
        'p_activity_ids': activityIds,
      });
      return response.toString();
    } catch (_) {
      final response = await _client.rpc('inviter_staff_evenement', params: {
        'p_evenement_id': eventId,
        'p_user_id': userId,
      });
      return response.toString();
    }
  }

  Future<void> removeEventStaff({required String eventId, required String userId}) async {
    try {
      await _client.rpc('remove_event_staff', params: {
        'p_event_id': eventId,
        'p_user_id': userId,
      });
    } catch (_) {
      await _client.from('event_staff').delete().eq('event_id', eventId).eq('user_id', userId);
    }
  }

  Future<void> promoteEventStaffToCoCreator({required String eventId, required String userId}) async {
    try {
      await _client.rpc('promote_event_staff_to_co_creator', params: {
        'p_event_id': eventId,
        'p_user_id': userId,
      });
    } catch (e) {
      debugPrint('[SupabaseEventService] promoteEventStaffToCoCreator error: $e');
      rethrow;
    }
  }

  Future<void> removeEventCoCreator({required String eventId, required String userId}) async {
    try {
      await _client.rpc('remove_event_co_creator', params: {
        'p_event_id': eventId,
        'p_user_id': userId,
      });
    } catch (_) {
      await _client.from('event_co_creators').delete().eq('event_id', eventId).eq('user_id', userId);
    }
  }

  Future<String?> inviteCoCreator({required String eventId, required String userId}) async {
    final response = await _client.rpc('invite_event_co_creator', params: {
      'p_event_id': eventId,
      'p_user_id': userId,
    });
    return response?.toString();
  }

  Future<void> respondToCoCreatorInvite({required String inviteId, required bool accept}) async {
    try {
      await _client.rpc('respond_event_co_creator_invite', params: {
        'p_invite_id': inviteId,
        'p_accepted': accept,
      });
    } catch (_) {
      await _client.rpc('repondre_invitation_co_createur', params: {
        'p_invite_id': inviteId,
        'p_accepte': accept,
      });
    }
  }

  // --- Invitations d'Honneur (Guests) ---

  Future<List<Map<String, dynamic>>> fetchEventGuestInvitations(String eventId) async {
    try {
      final response = await _client.rpc('get_event_guest_invitations', params: {
        'p_event_id': eventId,
      });
      if (response is List) {
        return List<Map<String, dynamic>>.from(response);
      }
    } catch (_) {}

    try {
      final res = await _client
          .from('event_guest_invitations')
          .select('*, user_profiles!event_guest_invitations_user_id_fkey(user_id, first_name, last_name, photo_url, username)')
          .eq('event_id', eventId);
      return List<Map<String, dynamic>>.from(res);
    } catch (e) {
      debugPrint('[SupabaseEventService] fetchEventGuestInvitations error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchEligibleGuestCandidates(String eventId, {String? search}) async {
    try {
      final response = await _client.rpc('get_event_guest_candidates', params: {
        'p_event_id': eventId,
        if (search != null && search.isNotEmpty) 'p_search': search,
      });
      if (response is List) {
        return List<Map<String, dynamic>>.from(response);
      }
    } catch (_) {
      try {
        final response = await _client.rpc('fetch_eligible_guest_candidates', params: {
          'p_event_id': eventId,
        });
        if (response is List) {
          return List<Map<String, dynamic>>.from(response);
        }
      } catch (_) {}
    }

    try {
      final eventRes = await _client.from('events').select('creator_id').eq('id', eventId).maybeSingle();
      final founderId = eventRes?['creator_id']?.toString();

      final staffRes = await _client.from('event_staff').select('user_id').eq('event_id', eventId);
      final staffUserIds = (staffRes as List).map((e) => e['user_id']?.toString()).whereType<String>().toSet();

      final guestsRes = await _client.from('event_guest_invitations').select('user_id').eq('event_id', eventId);
      final guestUserIds = (guestsRes as List).map((e) => e['user_id']?.toString()).whereType<String>().toSet();

      final currentUserId = _client.auth.currentUser?.id;

      final excludedIds = <String>{
        if (founderId != null) founderId,
        if (currentUserId != null) currentUserId,
        ...staffUserIds,
        ...guestUserIds,
      };

      final profiles = await _client
          .from('user_profiles')
          .select('user_id, first_name, last_name, photo_url, username');

      final list = List<Map<String, dynamic>>.from(profiles.where((p) {
        final uid = p['user_id']?.toString();
        return uid != null && !excludedIds.contains(uid);
      }));

      if (search != null && search.isNotEmpty) {
        final q = search.toLowerCase();
        return list.where((p) {
          final first = (p['first_name'] as String? ?? '').toLowerCase();
          final last = (p['last_name'] as String? ?? '').toLowerCase();
          final username = (p['username'] as String? ?? '').toLowerCase();
          return first.contains(q) || last.contains(q) || username.contains(q);
        }).toList();
      }

      return list;
    } catch (e) {
      debugPrint('[SupabaseEventService] fetchEligibleGuestCandidates error: $e');
      return [];
    }
  }

  Future<void> inviteEventGuest({required String eventId, required String userId}) async {
    final currentUserId = _client.auth.currentUser?.id;
    if (currentUserId == null) throw 'Utilisateur non connecté';

    try {
      await _client.rpc('invite_event_guest', params: {
        'p_event_id': eventId,
        'p_user_id': userId,
      });
    } catch (_) {
      await _client.from('event_guest_invitations').upsert({
        'event_id': eventId,
        'user_id': userId,
        'invited_by': currentUserId,
        'status': 'en_attente',
      });
    }
  }

  Future<void> respondToGuestInvite({required String inviteId, required bool accept}) async {
    try {
      await _client.rpc('respond_event_guest_invitation', params: {
        'p_invite_id': inviteId,
        'p_accepted': accept,
      });
    } catch (_) {
      try {
        await _client.rpc('respond_event_guest_invite', params: {
          'p_invite_id': inviteId,
          'p_accept': accept,
        });
      } catch (_) {
        final status = accept ? 'acceptee' : 'refusee';
        final inviteRes = await _client
            .from('event_guest_invitations')
            .update({
              'status': status,
              'responded_at': DateTime.now().toIso8601String(),
            })
            .eq('id', inviteId)
            .select()
            .maybeSingle();

        if (accept && inviteRes != null && inviteRes['event_id'] != null) {
          final eventId = inviteRes['event_id'].toString();
          await _client.rpc('add_event_to_calendar', params: {'p_event_id': eventId}).catchError((_) async {
            final userId = _client.auth.currentUser?.id;
            if (userId != null) {
              await _client.from('event_calendar').upsert({'event_id': eventId, 'user_id': userId, 'source': 'guest_invitation'});
            }
          });
        }
      }
    }
  }

  Future<void> removeEventGuest({required String eventId, required String userId, String? inviteId}) async {
    try {
      if (inviteId != null && inviteId.isNotEmpty) {
        await _client.rpc('remove_event_guest', params: {
          'p_invite_id': inviteId,
        });
        return;
      }
      await _client.rpc('remove_event_guest', params: {
        'p_event_id': eventId,
        'p_user_id': userId,
      });
    } catch (_) {
      await _client.from('event_guest_invitations').delete().eq('event_id', eventId).eq('user_id', userId);
    }
  }

  Future<List<Map<String, dynamic>>> fetchMyPendingGuestInvites() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];
    try {
      final res = await _client
          .from('event_guest_invitations')
          .select('*, events!event_guest_invitations_event_id_fkey(id, name, nom, cover_image_url, photo)')
          .eq('user_id', userId)
          .eq('status', 'en_attente');
      return List<Map<String, dynamic>>.from(res);
    } catch (e) {
      debugPrint('[SupabaseEventService] fetchMyPendingGuestInvites error: $e');
      return [];
    }
  }

  Future<bool> isUserAcceptedGuest({required String eventId, required String userId}) async {
    try {
      final res = await _client
          .from('event_guest_invitations')
          .select('id')
          .eq('event_id', eventId)
          .eq('user_id', userId)
          .eq('status', 'acceptee')
          .maybeSingle();
      return res != null;
    } catch (_) {
      return false;
    }
  }

  // --- Invitations Sponsor ---

  Future<List<Map<String, dynamic>>> fetchEventSponsorInvitations(String eventId) async {
    try {
      final response = await _client.rpc('get_event_sponsor_invitations', params: {
        'p_event_id': eventId,
      });
      if (response is List) {
        return List<Map<String, dynamic>>.from(response);
      }
    } catch (_) {}

    try {
      final res = await _client
          .from('event_sponsor_invitations')
          .select('*, user_profiles!event_sponsor_invitations_user_id_fkey(user_id, first_name, last_name, photo_url, username)')
          .eq('event_id', eventId)
          .neq('status', 'annulee');
      return List<Map<String, dynamic>>.from(res);
    } catch (e) {
      debugPrint('[SupabaseEventService] fetchEventSponsorInvitations error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchEligibleSponsorCandidates(String eventId, {String? search}) async {
    try {
      final response = await _client.rpc('get_event_sponsor_candidates', params: {
        'p_event_id': eventId,
        if (search != null && search.isNotEmpty) 'p_search': search,
      });
      if (response is List) {
        return List<Map<String, dynamic>>.from(response);
      }
    } catch (_) {}

    try {
      final eventRes = await _client.from('events').select('creator_id').eq('id', eventId).maybeSingle();
      final founderId = eventRes?['creator_id']?.toString();

      final staffRes = await _client.from('event_staff').select('user_id').eq('event_id', eventId);
      final staffUserIds = (staffRes as List).map((e) => e['user_id']?.toString()).whereType<String>().toSet();

      final sponsorsRes = await _client.from('event_sponsor_invitations').select('user_id').eq('event_id', eventId).neq('status', 'annulee');
      final sponsorUserIds = (sponsorsRes as List).map((e) => e['user_id']?.toString()).whereType<String>().toSet();

      final currentUserId = _client.auth.currentUser?.id;

      final excludedIds = <String>{
        if (founderId != null) founderId,
        if (currentUserId != null) currentUserId,
        ...staffUserIds,
        ...sponsorUserIds,
      };

      final profiles = await _client
          .from('user_profiles')
          .select('user_id, first_name, last_name, photo_url, username');

      final list = List<Map<String, dynamic>>.from(profiles.where((p) {
        final uid = p['user_id']?.toString();
        return uid != null && !excludedIds.contains(uid);
      }));

      if (search != null && search.isNotEmpty) {
        final q = search.toLowerCase();
        return list.where((p) {
          final first = (p['first_name'] as String? ?? '').toLowerCase();
          final last = (p['last_name'] as String? ?? '').toLowerCase();
          final username = (p['username'] as String? ?? '').toLowerCase();
          return first.contains(q) || last.contains(q) || username.contains(q);
        }).toList();
      }

      return list;
    } catch (e) {
      debugPrint('[SupabaseEventService] fetchEligibleSponsorCandidates error: $e');
      return [];
    }
  }

  Future<void> inviteEventSponsor({required String eventId, required String userId}) async {
    final currentUserId = _client.auth.currentUser?.id;
    if (currentUserId == null) throw 'Utilisateur non connecté';

    try {
      await _client.rpc('invite_event_sponsor', params: {
        'p_event_id': eventId,
        'p_user_id': userId,
      });
    } catch (_) {
      await _client.from('event_sponsor_invitations').upsert({
        'event_id': eventId,
        'user_id': userId,
        'invited_by': currentUserId,
        'status': 'en_attente',
      });
    }
  }

  Future<void> respondToSponsorInvite({required String inviteId, required bool accept}) async {
    try {
      await _client.rpc('respond_event_sponsor_invitation', params: {
        'p_invite_id': inviteId,
        'p_accepted': accept,
      });
    } catch (_) {
      final status = accept ? 'acceptee' : 'refusee';
      final inviteRes = await _client
          .from('event_sponsor_invitations')
          .update({
            'status': status,
            'responded_at': DateTime.now().toIso8601String(),
          })
          .eq('id', inviteId)
          .select()
          .maybeSingle();

      if (accept && inviteRes != null && inviteRes['event_id'] != null) {
        final eventId = inviteRes['event_id'].toString();
        await _client.rpc('add_event_to_calendar', params: {'p_event_id': eventId}).catchError((_) async {
          final userId = _client.auth.currentUser?.id;
          if (userId != null) {
            await _client.from('event_calendar').upsert({'event_id': eventId, 'user_id': userId, 'source': 'sponsor_invitation'});
          }
        });
      }
    }
  }

  Future<void> removeEventSponsor({required String inviteId}) async {
    try {
      await _client.rpc('remove_event_sponsor', params: {
        'p_invite_id': inviteId,
      });
    } catch (_) {
      await _client.from('event_sponsor_invitations').update({'status': 'annulee'}).eq('id', inviteId);
    }
  }

  Future<List<Map<String, dynamic>>> fetchMyPendingSponsorInvites() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];
    try {
      final res = await _client
          .from('event_sponsor_invitations')
          .select('*, events!event_sponsor_invitations_event_id_fkey(id, name, nom, cover_image_url, photo)')
          .eq('user_id', userId)
          .eq('status', 'en_attente');
      return List<Map<String, dynamic>>.from(res);
    } catch (e) {
      debugPrint('[SupabaseEventService] fetchMyPendingSponsorInvites error: $e');
      return [];
    }
  }

  Future<bool> isUserAcceptedSponsor({required String eventId, required String userId}) async {
    try {
      final res = await _client
          .from('event_sponsor_invitations')
          .select('id')
          .eq('event_id', eventId)
          .eq('user_id', userId)
          .eq('status', 'acceptee')
          .maybeSingle();
      return res != null;
    } catch (_) {
      return false;
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
  }) async {
    final params = <String, dynamic>{
      'p_event_id': eventId,
      'p_min_age': minAge,
      'p_max_age': maxAge,
      'p_allowed_genders': allowedGenders,
      'p_id_required': idRequired,
      'p_serves_alcohol': servesAlcohol,
      'p_overnight_event': overnightEvent,
      'p_smoking_allowed': smokingAllowed,
      'p_other_restrictions': otherRestrictions,
    };
    await _client.rpc('set_event_restrictions', params: params);
  }

  Future<void> setEventStaffActivities({
    required String eventStaffId,
    required List<String> activityIds,
  }) async {
    await _client.rpc('set_event_staff_activities', params: {
      'p_event_staff_id': eventStaffId,
      'p_activity_ids': activityIds,
    });
  }

  Future<Map<String, dynamic>> createCertifiedEvent(Map<String, dynamic> params) async {
    final response = await _client.rpc('create_certified_event_with_subscription', params: params);
    if (response == null) {
      throw Exception('Erreur lors de la création de l’événement certifié');
    }
    if (response is List && response.isNotEmpty) {
      return Map<String, dynamic>.from(response.first as Map);
    }
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> createEvent(Map<String, dynamic> params) async {
    final response = await _client.rpc('create_event', params: params);
    if (response == null) throw Exception('Erreur lors de la création de l\'événement');
    if (response is List && response.isNotEmpty) {
      return Map<String, dynamic>.from(response.first as Map);
    }
    return Map<String, dynamic>.from(response as Map);
  }

  Future<String> uploadEventCover(String eventId, File file) async {
    final uploaded = await R2MediaRepository(client: _client).uploadFile(
      file: file,
      category: 'event_media',
      mediaType: 'image',
      entityId: eventId,
    );
    final url = uploaded.publicUrl;
    if (url == null || url.isEmpty) {
      throw StateError('Cloudflare R2 n’a pas retourné d’URL publique pour la couverture de l’événement.');
    }
    return url;
  }

  Future<void> updateEvent(String id, Map<String, dynamic> data) async {
    try {
      final rpcParams = <String, dynamic>{
        'p_id': id,
        'p_name': data['name'] ?? data['nom'],
        'p_slug': data['slug'],
        'p_description': data['description'],
        'p_photo': data['photo'] ?? data['photo_url'],
        'p_country_id': data['country_id'] ?? data['pays_id'],
        'p_city_id': data['city_id'] ?? data['ville_id'],
        'p_starts_at': data['starts_at'] ?? data['date_debut'],
        'p_ends_at': data['ends_at'] ?? data['date_fin'],
        'p_is_free': data['is_free'] ?? data['est_gratuit'],
        'p_is_virtual': data['is_virtual'] ?? data['est_virtuel'],
        'p_virtual_link': data['virtual_link'] ?? data['lien_virtuel'],
        'p_address': data['address'] ?? data['adresse'],
        'p_is_public': data['is_public'] ?? data['est_public'] ?? true,
        'p_real_created_at': data['real_created_at'] ?? data['date_origine'],
      };
      await _client.rpc('update_event', params: rpcParams);
    } catch (e) {
      debugPrint('[Error] RPC update_event failed: $e. Fallback to events table update...');
      await _client.from('events').update(data).eq('id', id);
    }
  }

  Future<String> proposeTransfer({required String eventId, required String targetUserId}) async {
    try {
      final response = await _client.rpc('propose_event_transfer', params: {
        'p_event_id': eventId,
        'p_to_user_id': targetUserId,
      });
      return response.toString();
    } catch (_) {
      final response = await _client.rpc('proposer_transfert_evenement', params: {
        'p_evenement_id': eventId,
        'p_destinataire_id': targetUserId,
      });
      return response.toString();
    }
  }

  Future<List<Map<String, dynamic>>> getEventTransferProposals({required String eventId}) async {
    try {
      final response = await _client.rpc('get_event_transfer_proposals', params: {
        'p_event_id': eventId,
      });
      if (response is List) {
        return response.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('[SupabaseEventService] getEventTransferProposals RPC failed: $e. Fallback to direct query...');
      try {
        final response = await _client
            .from('event_transfers')
            .select('*, recipient:proposed_to(user_id, first_name, last_name, photo_url, username)')
            .eq('event_id', eventId);
        return List<Map<String, dynamic>>.from(response);
      } catch (_) {
        return [];
      }
    }
  }

  Future<Map<String, dynamic>> getEventStatistics({required String eventId}) async {
    try {
      final response = await _client.rpc('get_event_statistics', params: {'p_event_id': eventId});
      if (response is Map) {
        return Map<String, dynamic>.from(response);
      }
    } catch (e) {
      debugPrint('[SupabaseEventService] get_event_statistics RPC failed for $eventId: $e');
    }
    return {};
  }

  Future<void> updateEventPricing({required String eventId, required bool isFree}) async {
    try {
      await _client.rpc('update_event', params: {
        'p_id': eventId,
        'p_is_free': isFree,
      });
    } catch (e) {
      debugPrint('[SupabaseEventService] RPC update_event failed: $e. Fallback to events table update...');
      await _client.from('events').update({'is_free': isFree, 'est_gratuit': isFree}).eq('id', eventId);
    }
  }

  Future<void> cancelTransfer(String transferId) async {
    try {
      await _client.rpc('cancel_event_transfer', params: {
        'p_transfer_id': transferId,
      });
    } catch (_) {
      await _client.rpc('annuler_transfert_evenement', params: {
        'p_transfert_id': transferId,
      });
    }
  }

  Future<Map<String, dynamic>> getEventStaffStats(String eventStaffId) async {
    try {
      final response = await _client.rpc('get_event_staff_stats', params: {
        'p_event_staff_id': eventStaffId,
      });
      if (response is List && response.isNotEmpty) {
        return Map<String, dynamic>.from(response.first as Map);
      }
      if (response is Map) {
        return Map<String, dynamic>.from(response as Map);
      }
      return {};
    } catch (e) {
      debugPrint('[SupabaseEventService] getEventStaffStats error: $e');
      rethrow;
    }
  }

  Future<void> respondToTransfer({required String transferId, required bool accept}) async {
    try {
      await _client.rpc('respond_event_transfer', params: {
        'p_transfer_id': transferId,
        'p_accepted': accept,
      });
    } catch (_) {
      await _client.rpc('repondre_transfert_evenement', params: {
        'p_transfert_id': transferId,
        'p_accepte': accept,
      });
    }
  }

  Future<List<Map<String, dynamic>>> fetchMyPendingTransfersReceived() async {
    try {
      final response = await _client
          .from('event_transfers')
          .select('*, events(id, name), proposer:proposed_by(user_id, first_name, last_name, username)')
          .eq('proposed_to', _client.auth.currentUser?.id ?? '')
          .eq('status', 'en_attente');
      return List<Map<String, dynamic>>.from(response);
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchMyPendingTransfersSent(String eventId) async {
    try {
      final response = await _client
          .from('event_transfers')
          .select('*, events(id, name), recipient:proposed_to(user_id, first_name, last_name, username)')
          .eq('event_id', eventId)
          .eq('proposed_by', _client.auth.currentUser?.id ?? '')
          .eq('status', 'en_attente');
      return List<Map<String, dynamic>>.from(response);
    } catch (_) {
      return [];
    }
  }

  Future<void> respondToStaffInvitation({required String staffEvenementId, required bool accept}) async {
    await _client.rpc('respond_event_staff_invite', params: {
      'p_invite_id': staffEvenementId,
      'p_accepted': accept,
    });
  }

  Future<List<Map<String, dynamic>>> fetchEvents() async {
    const cols = 'id, name, slug, description, photo, country_id, city_id, address, is_online, online_url, starts_at, ends_at, creator_id, status, created_at';
    try {
      final response = await _client
          .from('events')
          .select(cols)
          .eq('status', 'active')
          .order('starts_at', ascending: true);
      return List<Map<String, dynamic>>.from(response);
    } catch (_) {
      final response = await _client
          .from('events')
          .select()
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    }
  }

  Future<Map<String, dynamic>> fetchEventById(String id) async {
    try {
      final response = await _client.from('events').select().eq('id', id).single();
      return response;
    } catch (_) {
      final response = await _client.from('events').select().eq('id', id).single();
      return response;
    }
  }

  Future<List<Map<String, dynamic>>> fetchEventTickets(String eventId) async {
    try {
      final response = await _client
          .from('event_tickets')
          .select()
          .eq('event_id', eventId);
      debugPrint('[SupabaseEventService] fetchEventTickets returned ${response.length} rows for eventId=$eventId');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('[SupabaseEventService] fetchEventTickets error: $e');
      return [];
    }
  }

  Future<void> addTicket(Map<String, dynamic> data) async {
    final cleanData = <String, dynamic>{
      'event_id': data['event_id'] ?? data['evenement_id'],
      'name': data['name'] ?? data['nom'],
      'price': data['price'] ?? data['prix'],
      'currency_code': data['currency_code'] ?? data['currency'] ?? data['devise'] ?? 'XAF',
      if (data['quantity'] != null || data['quantite_disponible'] != null)
        'quantity': data['quantity'] ?? data['quantite_disponible'],
    };

    final rawId = data['id']?.toString();
    if (rawId != null && !rawId.startsWith('local_') && rawId.isNotEmpty) {
      cleanData['id'] = rawId;
    }

    debugPrint('[SupabaseEventService] addTicket inserting into event_tickets: $cleanData');
    try {
      await _client.from('event_tickets').insert(cleanData);
      debugPrint('[SupabaseEventService] addTicket successfully inserted ticket into event_tickets');
    } catch (e) {
      debugPrint('[Error] SupabaseEventService.addTicket failed: $e');
      rethrow;
    }
  }

  Future<void> deleteTicket(String id) async {
    try {
      await _client.from('event_tickets').delete().eq('id', id);
      debugPrint('[SupabaseEventService] deleteTicket successfully deleted ticket id=$id');
    } catch (e) {
      debugPrint('[Error] SupabaseEventService.deleteTicket failed: $e');
      rethrow;
    }
  }

  Future<String?> addEventToCalendar(String eventId) async {
    try {
      final response = await _client.rpc('add_event_to_calendar', params: {'p_event_id': eventId});
      if (response != null && response is List && response.isNotEmpty) {
        final row = response.first;
        if (row is Map && row['suggested_community_id'] != null) {
          return row['suggested_community_id'].toString();
        }
      } else if (response != null && response is Map && response['suggested_community_id'] != null) {
        return response['suggested_community_id'].toString();
      }
    } catch (e) {
      debugPrint('[Error] addEventToCalendar RPC: $e');
      rethrow;
    }
    return null;
  }

  Future<void> removeEventFromCalendar(String eventId) async {
    try {
      await _client.rpc('remove_event_from_calendar', params: {'p_event_id': eventId});
    } catch (e) {
      debugPrint('[Error] removeEventFromCalendar RPC: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getActivityPreviewRpc(String activityId) async {
    try {
      final response = await _client.rpc('get_activity_preview', params: {
        'p_activity_id': activityId,
      });
      if (response is List && response.isNotEmpty) {
        return Map<String, dynamic>.from(response.first as Map);
      }
      if (response is Map) {
        return Map<String, dynamic>.from(response as Map);
      }
      return {};
    } catch (e) {
      debugPrint('[SupabaseEventService] getActivityPreviewRpc error: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> fetchUserAgenda(String userId) async {
    try {
      final response = await _client.rpc('get_my_agenda');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      final response = await _client.rpc('get_mon_agenda');
      return List<Map<String, dynamic>>.from(response);
    }
  }

  Future<List<Map<String, dynamic>>> fetchManagedEvents() async {
    try {
      final response = await _client.rpc('get_my_managed_events');
      if (response is List) return response.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) {}

    final response = await _client.rpc('get_mes_evenements_geres');
    if (response is! List) return [];
    return response.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<List<Map<String, dynamic>>> fetchEventSummariesByIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    final response = await _client
        .from('events')
        .select()
        .inFilter('id', ids);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> fetchStaffActivities() async {
    try {
      final response = await _client.rpc('get_my_staffed_events');
      if (response is List && response.isNotEmpty) {
        return List<Map<String, dynamic>>.from(response);
      }
    } catch (e) {
      debugPrint('[SupabaseEventService] get_my_staffed_events RPC failed: $e');
    }

    try {
      final response = await _client.rpc('get_mes_evenements_staff');
      if (response is List && response.isNotEmpty) {
        return List<Map<String, dynamic>>.from(response);
      }
    } catch (_) {}

    try {
      final response = await _client.rpc('get_mes_activites_staff');
      if (response is List && response.isNotEmpty) {
        return List<Map<String, dynamic>>.from(response);
      }
    } catch (_) {}

    // Fallback direct table queries on event_staff and event_co_creators
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId != null) {
        final List<Map<String, dynamic>> list = [];
        
        try {
          final staffRes = await _client
              .from('event_staff')
              .select('*, events(*)')
              .eq('user_id', userId)
              .inFilter('status', ['acceptee', 'accepted', 'actif', 'active']);
          for (final row in staffRes) {
            if (row['events'] is Map) {
              final evMap = Map<String, dynamic>.from(row['events'] as Map);
              if (!list.any((e) => e['id'] == evMap['id'])) {
                list.add(evMap);
              }
            }
          }
        } catch (e) {
          debugPrint('[SupabaseEventService] fetchStaffActivities event_staff query error: $e');
        }

        try {
          final coCreatorRes = await _client
              .from('event_co_creators')
              .select('*, events(*)')
              .eq('user_id', userId)
              .inFilter('status', ['acceptee', 'accepted', 'actif', 'active']);
          for (final row in coCreatorRes) {
            if (row['events'] is Map) {
              final evMap = Map<String, dynamic>.from(row['events'] as Map);
              if (!list.any((e) => e['id'] == evMap['id'])) {
                list.add(evMap);
              }
            }
          }
        } catch (e) {
          debugPrint('[SupabaseEventService] fetchStaffActivities event_co_creators query error: $e');
        }

        return list;
      }
    } catch (e) {
      debugPrint('[SupabaseEventService] fetchStaffActivities fallback query failed: $e');
    }

    return [];
  }

  Future<List<Map<String, dynamic>>> fetchSuggestedEvents({int limit = 50}) async {
    try {
      final response = await _client.rpc('get_home_event_suggestions', params: {
        'p_days_ahead': 30,
        'p_limit_per_category': limit,
      });
      if (response != null && response is List) {
        return List<Map<String, dynamic>>.from(response);
      }
      return [];
    } catch (e) {
      debugPrint('[SupabaseEventService] RPC get_home_event_suggestions failed: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> fetchHomeCalendarEvents({
    required String startDate,
    required String endDate,
  }) async {
    try {
      final response = await _client.rpc('get_home_calendar_events', params: {
        'p_start_date': startDate,
        'p_end_date': endDate,
      });
      if (response != null && response is List) {
        return List<Map<String, dynamic>>.from(response);
      }
    } catch (e) {
      debugPrint('[SupabaseEventService] get_home_calendar_events RPC failed: $e');
    }
    return [];
  }

  Future<CheckinScanResult> scanEventCheckin({
    required String eventId,
    required String userId,
    String? activityId,
    int quantity = 1,
  }) async {
    final params = <String, dynamic>{
      'p_event_id': eventId,
      'p_user_id': userId,
      if (activityId != null && activityId.isNotEmpty) 'p_activity_id': activityId,
      'p_quantite': quantity,
    };
    final response = await _client.rpc('checkin_scan', params: params);
    return CheckinScanResult.fromJson(response);
  }

  Future<List<Map<String, dynamic>>> fetchEventCheckinsTree(String eventId) async {
    try {
      final response = await _client
          .from('event_checkins')
          .select('*, user_profiles:user_id(user_id, first_name, last_name, photo_url, username), validator:validated_by_user_id(user_id, first_name, last_name, photo_url, username)')
          .eq('event_id', eventId)
          .order('created_at', ascending: true);
      return List<Map<String, dynamic>>.from(response);
    } catch (_) {
      return [];
    }
  }

  Future<void> invalidateCheckinChain({required String checkinId, required String reason}) async {
    try {
      await _client.rpc('invalidate_checkin_chain', params: {
        'p_checkin_id': checkinId,
        'p_raison': reason,
      });
    } catch (e) {
      debugPrint('[Error] RPC invalidate_checkin_chain: $e. Trying fallback...');
      await _client.rpc('invalider_checkin_chaine', params: {
        'p_checkin_id': checkinId,
        'p_raison': reason,
      });
    }
  }

  Future<String?> scanActivity({required String eventActivityId, required String userId, required String scannerId}) async {
    final response = await _client.rpc('scanner_activite', params: {
      'p_evenement_activite_id': eventActivityId,
      'p_user_id': userId,
      'p_scanneur_id': scannerId,
    });
    return response as String?;
  }

  Future<Map<String, dynamic>> getEventPreviewOwner(String eventId) async {
    final response = await _client.rpc('get_event_preview_owner', params: {'p_event_id': eventId});
    if (response is List && response.isNotEmpty) {
      return Map<String, dynamic>.from(response.first as Map);
    }
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> getEventPreviewPublic(String eventId) async {
    final response = await _client.rpc('get_event_preview_public', params: {'p_event_id': eventId});
    if (response is List && response.isNotEmpty) {
      return Map<String, dynamic>.from(response.first as Map);
    }
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> getEventPreviewStaff(String eventId) async {
    final response = await _client.rpc('get_event_preview_staff', params: {'p_event_id': eventId});
    if (response is List && response.isNotEmpty) {
      return Map<String, dynamic>.from(response.first as Map);
    }
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> getEventPreviewBase(String eventId) async {
    final response = await _client.rpc('get_event_preview_base', params: {'p_event_id': eventId});
    if (response is List && response.isNotEmpty) {
      return Map<String, dynamic>.from(response.first as Map);
    }
    return Map<String, dynamic>.from(response as Map);
  }

  Future<List<Map<String, dynamic>>> fetchPendingEventsAdmin() async {
    try {
      final response = await _client
          .from('events')
          .select('*, user_profiles(user_id, first_name, last_name, photo_url, username)')
          .eq('status', 'en_attente')
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (_) {
      final response = await _client
          .from('events')
          .select()
          .eq('status', 'en_attente')
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    }
  }

  Future<void> validateEventAdmin(String eventId) async {
    try {
      await _client.rpc('valider_evenement', params: {'p_id': eventId});
    } catch (e) {
      debugPrint('[Error] RPC valider_evenement: $e. Trying fallback valider_evenement_admin...');
      await _client.rpc('valider_evenement_admin', params: {'p_evenement_id': eventId});
    }
  }

  Future<void> rejectEventAdmin(String eventId, String reason) async {
    try {
      await _client.rpc('rejeter_evenement', params: {
        'p_id': eventId,
        'p_raison': reason,
      });
    } catch (e) {
      debugPrint('[Error] RPC rejeter_evenement: $e. Trying fallback rejeter_evenement_admin...');
      await _client.rpc('rejeter_evenement_admin', params: {
        'p_evenement_id': eventId,
        'p_raison': reason,
      });
    }
  }
}
