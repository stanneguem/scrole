import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/service_global/supabse_service.dart';
import '../../../../shared/models/interest_model.dart';
import '../../centre/models/activity_model.dart';

class ActivityRepository {
  final SupabaseService _supabase = Get.find();
  SupabaseClient get client => _supabase.client;

  /// Génération d'un UUID v4 côté client
  String generateLocalId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // Version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // Variant IETF
    String hex(int b) => b.toRadixString(16).padLeft(2, '0');
    final chars = bytes.map(hex).join();
    return '${chars.substring(0, 8)}-${chars.substring(8, 12)}-${chars.substring(12, 16)}-${chars.substring(16, 20)}-${chars.substring(20, 32)}';
  }

  /// Récupère tous les centres d'intérêts.
  Future<List<Interest>> getInterests() async {
    try {
      final response = await client
          .from('interests')
          .select()
          .order('name');

      final List<dynamic> data = response;
      return data.map((e) => Interest.fromJson(Map<String, dynamic>.from(e))).toList();
    } catch (e) {
      debugPrint('[Error] Chargement des centres d\'intérêts: $e');
      return [];
    }
  }

  /// RPC create_activity
  Future<Activity> createActivityRpc({
    required String id,
    required String name,
    double basePrice = 0.0,
    String currencyCode = 'XAF',
    bool eventOnly = false,
  }) async {
    final response = await client.rpc(
      'create_activity',
      params: {
        'p_id': id,
        'p_name': name,
        'p_base_price': basePrice,
        'p_currency_code': currencyCode,
        'p_event_only': eventOnly,
      },
    );

    if (response == null) {
      throw Exception('Erreur serveur lors de la création de l\'activité');
    }

    final row = Map<String, dynamic>.from(response is List ? response.first : response);
    return Activity.fromJson(row);
  }

  /// Creates an event-only activity already active and links it atomically to its event.
  Future<Activity> createEventActivityRpc({
    required String id,
    required String eventId,
    required String name,
    String? description,
    double basePrice = 0.0,
    String currencyCode = 'XAF',
  }) async {
    final response = await client.rpc(
      'create_event_activity',
      params: {
        'p_id': id,
        'p_event_id': eventId,
        'p_name': name,
        'p_description': description,
        'p_base_price': basePrice,
        'p_currency_code': currencyCode,
        'p_event_price': basePrice,
      },
    );
    if (response == null) {
      throw Exception('Erreur serveur lors de la création de l’activité dans l’événement');
    }
    final row = Map<String, dynamic>.from(response is List ? response.first : response);
    return Activity.fromJson(row);
  }

  /// RPC get_my_activities
  Future<List<Activity>> getMyActivitiesRpc() async {
    final user = client.auth.currentUser;
    debugPrint('[CurrencyDebug] auth user = ${user?.id}');

    final response = await client.rpc('get_my_activities');
    if (response == null) {
      debugPrint('[ActivityFlow][RPC] get_my_activities -> count=0');
      return [];
    }
    final List<dynamic> data = response is List ? response : [response];
    debugPrint('[ActivityFlow][RPC] get_my_activities -> count=${data.length}');

    final List<Activity> list = [];
    for (final item in data) {
      if (item is Map) {
        final map = Map<String, dynamic>.from(item);
        debugPrint(
          '[ActivityCurrencyDebug] '
          'id=${map['id']} '
          'name=${map['name']} '
          'price=${map['base_price']} '
          'currency=${map['currency_code']}',
        );
        final act = Activity.fromJson(map);
        if (act.status != 'deleted' && act.status != 'supprimee') {
          list.add(act);
        }
        debugPrint('[ActivityFlow][MODEL] id=${act.id} name=${act.name} status=${act.status} price=${act.basePrice} currency=${act.currencyCode}');
      }
    }

    debugPrint('[ActivityFlow][MODEL] mapped my_activities count=${list.length}');
    return list;
  }

  /// RPC get_my_managed_activities
  Future<List<Activity>> getMyManagedActivitiesRpc() async {
    try {
      final user = client.auth.currentUser;
      debugPrint('[CurrencyDebug] auth user = ${user?.id}');

      final response = await client.rpc('get_my_managed_activities');
      if (response == null) {
        debugPrint('[ActivityFlow][RPC] get_my_managed_activities -> count=0');
        return [];
      }
      final List<dynamic> data = response is List ? response : [response];
      debugPrint('[ActivityFlow][RPC] get_my_managed_activities -> count=${data.length}');

      final List<Activity> list = [];
      for (final item in data) {
        if (item is Map) {
          final map = Map<String, dynamic>.from(item);
          debugPrint(
            '[ManagedActivityCurrencyDebug] '
            'id=${map['id']} '
            'name=${map['name']} '
            'price=${map['base_price']} '
            'currency=${map['currency_code']}',
          );
          final act = Activity.fromJson(map);
          list.add(act);
          debugPrint('[ActivityFlow][MODEL] managed id=${act.id} name=${act.name} status=${act.status}');
        }
      }

      debugPrint('[ActivityFlow][MODEL] mapped managed_activities count=${list.length}');
      return list;
    } catch (e) {
      debugPrint('[ActivityRepository] getMyManagedActivitiesRpc error: $e');
      return [];
    }
  }

  /// RPC update_activity
  Future<Activity> updateActivityRpc({
    required String id,
    String? name,
    String? description,
    double? basePrice,
    String? currencyCode,
    bool? eventOnly,
  }) async {
    final params = <String, dynamic>{'p_id': id};
    if (name != null) params['p_name'] = name;
    if (description != null) params['p_description'] = description;
    if (basePrice != null) params['p_base_price'] = basePrice;
    if (currencyCode != null) params['p_currency_code'] = currencyCode;
    if (eventOnly != null) params['p_event_only'] = eventOnly;

    final response = await client.rpc('update_activity', params: params);

    if (response == null) {
      throw Exception('Erreur lors de la mise à jour de l\'activité');
    }

    final row = Map<String, dynamic>.from(response is List ? response.first : response);
    return Activity.fromJson(row);
  }

  /// RPC request_activity_deletion
  Future<Activity> requestActivityDeletionRpc(String id) async {
    final response = await client.rpc(
      'request_activity_deletion',
      params: {'p_id': id},
    );

    if (response == null) {
      throw Exception('Erreur lors de la demande de suppression');
    }

    final row = Map<String, dynamic>.from(response is List ? response.first : response);
    return Activity.fromJson(row);
  }

  /// RPC cancel_activity_deletion
  Future<Activity> cancelActivityDeletionRpc(String id) async {
    final response = await client.rpc(
      'cancel_activity_deletion',
      params: {'p_id': id},
    );

    if (response == null) {
      throw Exception('Erreur lors de l\'annulation de la suppression');
    }

    final row = Map<String, dynamic>.from(response is List ? response.first : response);
    return Activity.fromJson(row);
  }

  /// Direct select d'activités mises à jour depuis un curseur
  Future<List<Activity>> fetchActivitiesUpdatedAfter(DateTime cursor) async {
    final response = await client
        .from('activities')
        .select()
        .gt('updated_at', cursor.toUtc().toIso8601String())
        .order('updated_at', ascending: true);

    final List<dynamic> data = response;
    return data.map((e) => Activity.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  /// Refetch d'une activité par ID
  Future<Activity?> fetchActivityById(String id) async {
    try {
      final response = await client
          .from('activities')
          .select()
          .eq('id', id)
          .maybeSingle();

      if (response == null) return null;
      return Activity.fromJson(Map<String, dynamic>.from(response));
    } catch (_) {
      return null;
    }
  }

  // --- Subscriptions ---

  Future<void> subscribeActivity({required String userId, required String activityId}) async {
    await client.from('activity_subscriptions').insert({
      'user_id': userId,
      'activity_id': activityId,
    });
  }

  Future<void> unsubscribeActivity({required String userId, required String activityId}) async {
    await client
        .from('activity_subscriptions')
        .delete()
        .eq('activity_id', activityId)
        .eq('user_id', userId);
  }

  // --- Event Activities ---

  Future<void> addActivityToEventRpc({
    required String eventId,
    required String activityId,
    required double price,
  }) async {
    await client.rpc('add_activity_to_event', params: {
      'p_event_id': eventId,
      'p_activity_id': activityId,
      'p_price': price,
    });
  }

  Future<void> removeActivityFromEventRpc({
    required String eventId,
    required String activityId,
  }) async {
    await client.rpc('remove_activity_from_event', params: {
      'p_event_id': eventId,
      'p_activity_id': activityId,
    });
  }

  /// RPC leave_activity_staff
  Future<void> leaveActivityStaffRpc(String activityId) async {
    await client.rpc('leave_activity_staff', params: {'p_activity_id': activityId});
  }

  /// RPC get_activity_stats
  Future<Map<String, dynamic>> getActivityStatsRpc(String activityId) async {
    final response = await client.rpc('get_activity_stats', params: {'p_activity_id': activityId});
    return Map<String, dynamic>.from(response as Map);
  }

  /// RPC get_activity_preview
  Future<Map<String, dynamic>> getActivityPreviewRpc(String activityId) async {
    final response = await client.rpc('get_activity_preview', params: {'p_activity_id': activityId});
    return Map<String, dynamic>.from(response as Map);
  }

  /// RPC propose_activity_transfer
  Future<void> proposeActivityTransferRpc(String activityId, String targetUserId) async {
    await client.rpc('propose_activity_transfer', params: {
      'p_activity_id': activityId,
      'p_to_user_id': targetUserId,
    });
  }

  /// RPC cancel_activity_transfer
  Future<void> cancelActivityTransferRpc(String transferId) async {
    await client.rpc('cancel_activity_transfer', params: {'p_transfer_id': transferId});
  }

  /// RPC respond_activity_transfer
  Future<void> respondActivityTransferRpc(String transferId, bool accept) async {
    await client.rpc('respond_activity_transfer', params: {
      'p_transfer_id': transferId,
      'p_accepted': accept,
    });
  }

  /// RPC invite_activity_staff
  Future<void> inviteActivityStaffRpc(String activityId, String userId) async {
    await client.rpc('invite_activity_staff', params: {
      'p_activity_id': activityId,
      'p_user_id': userId,
    });
  }

  /// RPC remove_activity_staff
  Future<void> removeActivityStaffRpc(String activityId, String userId) async {
    await client.rpc('remove_activity_staff', params: {
      'p_activity_id': activityId,
      'p_user_id': userId,
    });
  }

  /// RPC get_activity_staff_members
  Future<List<Map<String, dynamic>>> getActivityStaffMembersRpc(String activityId) async {
    try {
      final response = await client.rpc('get_activity_staff_members', params: {'p_activity_id': activityId});
      if (response is List) return List<Map<String, dynamic>>.from(response);
      return [];
    } catch (e) {
      debugPrint('[ActivityRepository] getActivityStaffMembersRpc error: $e');
      return [];
    }
  }

  /// RPC get_activity_staff_candidates
  Future<List<Map<String, dynamic>>> getActivityStaffCandidatesRpc(String activityId) async {
    try {
      final response = await client.rpc('get_activity_staff_candidates', params: {'p_activity_id': activityId});
      if (response is List) return List<Map<String, dynamic>>.from(response);
      return [];
    } catch (e) {
      debugPrint('[ActivityRepository] getActivityStaffCandidatesRpc error: $e');
      return [];
    }
  }

  /// RPC cancel_activity_staff_invite
  Future<void> cancelActivityStaffInviteRpc(String activityId, String userId) async {
    await client.rpc('cancel_activity_staff_invite', params: {
      'p_activity_id': activityId,
      'p_user_id': userId,
    });
  }
}
