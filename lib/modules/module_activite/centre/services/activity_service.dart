import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:scrole/app/local_storage/structured/app_cache_database.dart';
import 'package:scrole/app/service_global/centre_interrets_service.dart';
import 'package:scrole/modules/module_activite/centre/models/activity_cache_entity.dart';
import 'package:scrole/modules/module_activite/centre/services/activity_outbox_processor.dart';
import 'package:scrole/modules/module_authentification/centre/services/auth_service.dart';
import '../../../../shared/models/interest_model.dart';
import '../models/activity_creation_data.dart';
import '../models/activity_model.dart';
import '../persistence/activity_local_dao.dart';
import '../../externe/repositories/activity_repository.dart';

class ActivityService extends GetxService {
  final ActivityRepository _repository = ActivityRepository();
  final InterestService _interestService = Get.find<InterestService>();
  final AuthService _authService = Get.find<AuthService>();
  late final ActivityLocalDao _dao;
  late final ActivityOutboxProcessor _outboxProcessor;

  final RxList<Activity> myActivities = <Activity>[].obs;
  final RxList<Activity> managedActivities = <Activity>[].obs;
  final RxBool isLoading = false.obs;

  RealtimeChannel? _userChannel;
  Worker? _authWorker;

  @override
  void onInit() {
    super.onInit();
    _dao = ActivityLocalDao(Get.find<AppDatabase>());
    _outboxProcessor = Get.put(ActivityOutboxProcessor());
    _initLocalDataAndRealtime();

    _authWorker = ever(_authService.currentUser, (user) {
      final oldUserId = _authService.userId;
      if (oldUserId != null) {
        unawaited(_dao.clearUserCache(oldUserId));
      }
      myActivities.clear();
      managedActivities.clear();
      _userChannel?.unsubscribe();
      _userChannel = null;
      if (user != null) {
        unawaited(_initLocalDataAndRealtime());
      }
    });
  }

  Future<void> _initLocalDataAndRealtime() async {
    final userId = _authService.userId;
    if (userId != null) {
      await loadLocalActivities();
      unawaited(_outboxProcessor.processPendingOperations());
      unawaited(catchupSync());
      listenRealtime(userId);
    }
  }

  Future<void> loadLocalActivities() async {
    final userId = _authService.userId;
    if (userId == null) {
      myActivities.clear();
      managedActivities.clear();
      return;
    }
    final myCached = await _dao.getMyActivitiesFromCache(userId);
    final managedCached = await _dao.getManagedActivitiesFromCache(userId);

    myActivities.assignAll(myCached.map((e) => e.toActivity()).toList());
    managedActivities.assignAll(managedCached.map((e) => e.toActivity()).toList());
  }

  // --- 1. Création d'une activité ---

  Future<Activity> createActivity(ActivityCreationData data, {bool eventOnly = false}) async {
    final userId = _authService.userId ?? '';
    final activityId = _repository.generateLocalId();
    final operationId = _repository.generateLocalId();
    final now = DateTime.now();

    final entity = ActivityCacheEntity(
      viewerUserId: userId,
      activityId: activityId,
      creatorId: userId,
      name: data.title,
      description: data.description,
      displayPrice: data.priceGeneral,
      displayCurrency: data.currencyCode,
      status: 'en_attente',
      eventOnly: eventOnly,
      createdAt: now,
      updatedAt: now,
      cachedAt: now.millisecondsSinceEpoch,
    );

    // 1. Écriture locale immédiate dans le cache isolé par viewer_user_id (§7.1)
    await _dao.saveActivityCache(entity);
    final activity = entity.toActivity();
    myActivities.insert(0, activity);

    // 2. Outbox avec operation_id fixe (§13)
    await _dao.enqueueOutboxOperation(
      operationId: operationId,
      viewerUserId: userId,
      activityId: activityId,
      operationType: 'create_activity',
      payload: {
        'activity_id': activityId,
        'name': data.title,
        'description': data.description,
        'base_price': data.priceGeneral,
        'currency_code': data.currencyCode,
        'event_only': eventOnly,
      },
    );

    // 3. Traitement Outbox
    unawaited(_outboxProcessor.processPendingOperations());

    return activity;
  }

  // --- 2. Modification d'une activité ---

  Future<void> updateActivity({
    required String id,
    String? name,
    String? description,
    double? basePrice,
    String? currencyCode,
    bool? eventOnly,
  }) async {
    final userId = _authService.userId ?? '';
    final local = await _dao.getActivityCache(userId, id);
    if (local == null) return;

    final updatedEntity = ActivityCacheEntity(
      viewerUserId: userId,
      activityId: id,
      creatorId: local.creatorId,
      name: name ?? local.name,
      description: description ?? local.description,
      displayPrice: basePrice ?? local.displayPrice,
      displayCurrency: currencyCode ?? local.displayCurrency,
      status: local.status,
      addedCount: local.addedCount,
      eventOnly: eventOnly ?? local.eventOnly,
      scheduledDeletionAt: local.scheduledDeletionAt,
      createdAt: local.createdAt,
      updatedAt: DateTime.now(),
      cachedAt: DateTime.now().millisecondsSinceEpoch,
    );

    await _dao.saveActivityCache(updatedEntity);
    _replaceInList(updatedEntity.toActivity());

    final operationId = _repository.generateLocalId();
    final payload = <String, dynamic>{'activity_id': id};
    if (name != null) payload['name'] = name;
    if (description != null) payload['description'] = description;
    if (basePrice != null) payload['base_price'] = basePrice;
    if (currencyCode != null) payload['currency_code'] = currencyCode;
    if (eventOnly != null) payload['event_only'] = eventOnly;

    await _dao.enqueueOutboxOperation(
      operationId: operationId,
      viewerUserId: userId,
      activityId: id,
      operationType: 'update_activity',
      payload: payload,
    );

    unawaited(_outboxProcessor.processPendingOperations());
  }

  // --- 3. Demande de suppression ---

  Future<void> requestDeletion(String id) async {
    final userId = _authService.userId ?? '';
    final local = await _dao.getActivityCache(userId, id);
    if (local == null) return;

    final updatedEntity = ActivityCacheEntity(
      viewerUserId: userId,
      activityId: id,
      creatorId: local.creatorId,
      name: local.name,
      description: local.description,
      displayPrice: local.displayPrice,
      displayCurrency: local.displayCurrency,
      status: 'pending_deletion',
      addedCount: local.addedCount,
      eventOnly: local.eventOnly,
      scheduledDeletionAt: DateTime.now().add(const Duration(days: 30)),
      createdAt: local.createdAt,
      updatedAt: DateTime.now(),
      cachedAt: DateTime.now().millisecondsSinceEpoch,
    );

    await _dao.saveActivityCache(updatedEntity);
    _replaceInList(updatedEntity.toActivity());

    final operationId = _repository.generateLocalId();
    await _dao.enqueueOutboxOperation(
      operationId: operationId,
      viewerUserId: userId,
      activityId: id,
      operationType: 'request_activity_deletion',
      payload: {'activity_id': id},
    );

    unawaited(_outboxProcessor.processPendingOperations());
  }

  Future<void> cancelDeletion(String id) async {
    final userId = _authService.userId ?? '';
    final local = await _dao.getActivityCache(userId, id);
    if (local == null) return;

    final updatedEntity = ActivityCacheEntity(
      viewerUserId: userId,
      activityId: id,
      creatorId: local.creatorId,
      name: local.name,
      description: local.description,
      displayPrice: local.displayPrice,
      displayCurrency: local.displayCurrency,
      status: 'active',
      addedCount: local.addedCount,
      eventOnly: local.eventOnly,
      scheduledDeletionAt: null,
      createdAt: local.createdAt,
      updatedAt: DateTime.now(),
      cachedAt: DateTime.now().millisecondsSinceEpoch,
    );

    await _dao.saveActivityCache(updatedEntity);
    _replaceInList(updatedEntity.toActivity());

    final operationId = _repository.generateLocalId();
    await _dao.enqueueOutboxOperation(
      operationId: operationId,
      viewerUserId: userId,
      activityId: id,
      operationType: 'cancel_activity_deletion',
      payload: {'activity_id': id},
    );

    unawaited(_outboxProcessor.processPendingOperations());
  }

  // --- 4. Abonnements ---

  Future<void> subscribe(String activityId) async {
    final userId = _authService.userId;
    if (userId == null) return;
    await _repository.subscribeActivity(userId: userId, activityId: activityId);
  }

  Future<void> unsubscribe(String activityId) async {
    final userId = _authService.userId;
    if (userId == null) return;
    await _repository.unsubscribeActivity(userId: userId, activityId: activityId);
  }

  // --- 5. Catchup Sync ---

  Future<void> catchupSync() async {
    final userId = _authService.userId;
    if (userId == null) return;

    try {
      isLoading.value = true;
      // 1. Process Outbox via ActivityOutboxProcessor (§20)
      await _outboxProcessor.processPendingOperations();

      // 2. Fetch My Activities (RPC get_my_activities)
      final remoteActivities = await _repository.getMyActivitiesRpc();
      final List<ActivityCacheEntity> myEntities = [];
      for (final act in remoteActivities) {
        final entity = ActivityCacheEntity(
          viewerUserId: userId,
          activityId: act.id,
          creatorId: act.creatorId,
          name: act.name,
          description: act.description,
          displayPrice: act.basePrice,
          displayCurrency: act.currencyCode,
          status: act.status,
          addedCount: act.addedCount,
          eventOnly: act.eventOnly,
          scheduledDeletionAt: act.scheduledDeletionAt,
          createdAt: act.createdAt,
          updatedAt: act.updatedAt,
          cachedAt: DateTime.now().millisecondsSinceEpoch,
        );
        myEntities.add(entity);
      }
      await _dao.saveMyActivitiesIndex(viewerUserId: userId, entities: myEntities);

      // 3. Fetch Managed Activities (RPC get_my_managed_activities)
      final remoteManaged = await _repository.getMyManagedActivitiesRpc();
      final List<ActivityCacheEntity> managedEntities = [];
      for (final act in remoteManaged) {
        final entity = ActivityCacheEntity(
          viewerUserId: userId,
          activityId: act.id,
          creatorId: act.creatorId,
          name: act.name,
          description: act.description,
          displayPrice: act.basePrice,
          displayCurrency: act.currencyCode,
          status: act.status,
          addedCount: act.addedCount,
          eventOnly: act.eventOnly,
          scheduledDeletionAt: act.scheduledDeletionAt,
          createdAt: act.createdAt,
          updatedAt: act.updatedAt,
          cachedAt: DateTime.now().millisecondsSinceEpoch,
        );
        managedEntities.add(entity);
      }
      await _dao.saveManagedActivitiesIndex(viewerUserId: userId, entities: managedEntities);

      await loadLocalActivities();
    } catch (e) {
      debugPrint('[Error] Catchup sync activités: $e');
    } finally {
      isLoading.value = false;
    }
  }

  // --- 6. Realtime Subscription ---

  void listenRealtime(String userId) {
    if (_userChannel != null) return;

    final session = Supabase.instance.client.auth.currentSession;
    if (session == null || session.isExpired) {
      debugPrint('[Realtime] Skipping activity subscription: session expired or null');
      return;
    }

    _userChannel = Supabase.instance.client
        .channel('user:$userId', opts: const RealtimeChannelConfig(private: true))
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'activities',
          callback: (payload) {
            final newRec = payload.newRecord;
            final oldRec = payload.oldRecord;
            final activityId = (newRec['id'] ?? oldRec['id'])?.toString();
            debugPrint('[Realtime] Postgres change on activities received for activity_id=$activityId');
            if (payload.eventType == PostgresChangeEvent.delete) {
              _handleRealtimeDelete(activityId);
            } else if (activityId != null && activityId.isNotEmpty) {
              _handleRealtimeRefetch(activityId);
            }
          },
        )
        .onBroadcast(
          event: 'activity_validated',
          callback: (payload) => _handleRealtimeRefetch(payload['activity_id']?.toString()),
        )
        .onBroadcast(
          event: 'activity_updated',
          callback: (payload) => _handleRealtimeRefetch(payload['activity_id']?.toString()),
        )
        .onBroadcast(
          event: 'activity_deleted',
          callback: (payload) => _handleRealtimeDelete(payload['activity_id']?.toString()),
        )
        .onBroadcast(
          event: 'activity_staff_added',
          callback: (payload) async {
            debugPrint('[Realtime] activity_staff_added received: $payload');
            await catchupSync();
          },
        )
        .subscribe((status, [error]) {
          if (status == RealtimeSubscribeStatus.subscribed) {
            unawaited(catchupSync());
          }
        });
  }

  Future<void> _handleRealtimeRefetch(String? activityId) async {
    if (activityId == null || activityId.isEmpty) return;
    final userId = _authService.userId;
    if (userId == null) return;

    debugPrint('[Realtime] event received');
    debugPrint('[Realtime] type=activity_updated');
    debugPrint('[Realtime] activity_id=$activityId');
    debugPrint('[Sync] fetching activity $activityId ...');

    try {
      final rawPreview = await _repository.getActivityPreviewRpc(activityId);
      final activityMap = rawPreview['activity'] is Map
          ? Map<String, dynamic>.from(rawPreview['activity'] as Map)
          : rawPreview;
      final entity = ActivityCacheEntity.fromRpcJson(viewerUserId: userId, json: activityMap);
      debugPrint('[Sync] activity fetched');
      debugPrint('[Cache] activity updated');
      await _dao.saveActivityCache(entity);
      debugPrint('[SQLite] activity updated');

      final updatedActivity = entity.toActivity();
      _replaceInList(updatedActivity);
      debugPrint('[Controller] activity replaced');
      debugPrint('[UI] card refreshed');
    } catch (e) {
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('not_found') || errStr.contains('introuvable') || errStr.contains('pgrst116')) {
        debugPrint('[Sync] activity $activityId NOT_FOUND on backend. Purging...');
        await _handleRealtimeDelete(activityId);
      } else {
        debugPrint('[ActivityService] Realtime refetch error: $e');
      }
    }
  }

  Future<void> _handleRealtimeDelete(String? activityId) async {
    if (activityId == null || activityId.isEmpty) return;
    final userId = _authService.userId;
    if (userId == null) return;

    debugPrint('[Realtime] event received');
    debugPrint('[Realtime] type=activity_deleted');
    debugPrint('[Realtime] activity_id=$activityId');

    await _dao.deleteActivityCache(userId, activityId);
    debugPrint('[SQLite] activity purged');
    debugPrint('[Cache] activity purged');

    myActivities.removeWhere((a) => a.id == activityId);
    managedActivities.removeWhere((a) => a.id == activityId);
    debugPrint('[Controller] activity removed');
    debugPrint('[UI] card refreshed');
  }

  void _replaceInList(Activity updated) {
    final userId = _authService.userId;

    if (userId != null && updated.creatorId == userId) {
      final idx = myActivities.indexWhere((a) => a.id == updated.id);
      if (idx != -1) {
        myActivities[idx] = updated;
      } else {
        myActivities.insert(0, updated);
      }
    }

    final mIdx = managedActivities.indexWhere((a) => a.id == updated.id);
    if (mIdx != -1) {
      managedActivities[mIdx] = updated;
    }
  }

  Future<List<Interest>> getInterests() => _interestService.getInterests();
  Future<void> clearInterestsCache() => _interestService.clearCache();

  @override
  void onClose() {
    _authWorker?.dispose();
    _userChannel?.unsubscribe();
    super.onClose();
  }
}
