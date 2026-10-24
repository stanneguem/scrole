import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../../../../app/local_storage/structured/app_cache_database.dart';
import '../models/activity_cache_entity.dart';
import '../models/activity_model.dart';

/// DAO local pour la gestion du cache des activités et de la file Outbox.
/// Respecte l'isolation stricte par (viewer_user_id, activity_id).
class ActivityLocalDao {
  final AppDatabase _appDb;

  ActivityLocalDao(this._appDb);

  Future<Database> get _db => _appDb.database;

  // --- 1. CACHE PRINCIPAL (activity_cache) ---

  Future<void> saveActivityCache(ActivityCacheEntity entity) async {
    final db = await _db;
    await db.insert(
      'activity_cache',
      entity.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    // Sync legacy table for backward compatibility
    await saveLegacyActivity(entity.toActivity());
  }

  Future<ActivityCacheEntity?> getActivityCache(String viewerUserId, String activityId) async {
    final db = await _db;
    final rows = await db.query(
      'activity_cache',
      where: 'viewer_user_id = ? AND activity_id = ?',
      whereArgs: [viewerUserId, activityId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ActivityCacheEntity.fromMap(rows.first);
  }

  Future<void> deleteActivityCache(String viewerUserId, String activityId) async {
    final db = await _db;
    await db.delete(
      'activity_cache',
      where: 'viewer_user_id = ? AND activity_id = ?',
      whereArgs: [viewerUserId, activityId],
    );
  }

  // --- 2. INDEXES (my_activities_index & managed_activities_index) ---

  Future<void> saveMyActivitiesIndex({
    required String viewerUserId,
    required List<ActivityCacheEntity> entities,
  }) async {
    final db = await _db;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.transaction((txn) async {
      await txn.delete(
        'my_activities_index',
        where: 'viewer_user_id = ?',
        whereArgs: [viewerUserId],
      );

      for (int i = 0; i < entities.length; i++) {
        final entity = entities[i];
        await txn.insert(
          'activity_cache',
          entity.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        await txn.insert(
          'my_activities_index',
          {
            'viewer_user_id': viewerUserId,
            'activity_id': entity.activityId,
            'position': i,
            'cached_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
    debugPrint('[ActivityFlow][CACHE] upserted activity count=${entities.length}');
    debugPrint('[ActivityFlow][INDEX] my_activities_index count=${entities.length} for viewer=$viewerUserId');
  }

  Future<List<ActivityCacheEntity>> getMyActivitiesFromCache(String viewerUserId) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT c.* 
      FROM activity_cache c
      INNER JOIN my_activities_index idx 
        ON c.viewer_user_id = idx.viewer_user_id AND c.activity_id = idx.activity_id
      WHERE c.viewer_user_id = ? AND c.status != 'deleted'
      ORDER BY idx.position ASC
    ''', [viewerUserId]);

    debugPrint('[ActivityFlow][CACHE] read my_activities_cache count=${rows.length} for viewer=$viewerUserId');
    return rows.map((r) => ActivityCacheEntity.fromMap(r)).toList();
  }

  Future<void> saveManagedActivitiesIndex({
    required String viewerUserId,
    required List<ActivityCacheEntity> entities,
  }) async {
    final db = await _db;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.transaction((txn) async {
      await txn.delete(
        'managed_activities_index',
        where: 'viewer_user_id = ?',
        whereArgs: [viewerUserId],
      );

      for (int i = 0; i < entities.length; i++) {
        final entity = entities[i];
        await txn.insert(
          'activity_cache',
          entity.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        await txn.insert(
          'managed_activities_index',
          {
            'viewer_user_id': viewerUserId,
            'activity_id': entity.activityId,
            'position': i,
            'cached_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
    debugPrint('[ActivityFlow][INDEX] managed_activities_index count=${entities.length} for viewer=$viewerUserId');
  }

  Future<List<ActivityCacheEntity>> getManagedActivitiesFromCache(String viewerUserId) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT c.* 
      FROM activity_cache c
      INNER JOIN managed_activities_index idx 
        ON c.viewer_user_id = idx.viewer_user_id AND c.activity_id = idx.activity_id
      WHERE c.viewer_user_id = ? AND c.status != 'deleted'
      ORDER BY idx.position ASC
    ''', [viewerUserId]);

    debugPrint('[ActivityFlow][CACHE] read managed_activities_cache count=${rows.length} for viewer=$viewerUserId');
    return rows.map((r) => ActivityCacheEntity.fromMap(r)).toList();
  }

  // --- 3. OUTBOX OFFICIELLE (activity_outbox) (§12 & §13) ---

  Future<int> enqueueOutboxOperation({
    required String operationId,
    required String viewerUserId,
    required String activityId,
    required String operationType,
    required Map<String, dynamic> payload,
  }) async {
    final db = await _db;
    final now = DateTime.now();

    return await db.insert('activity_outbox', {
      'operation_id': operationId,
      'viewer_user_id': viewerUserId,
      'activity_id': activityId,
      'operation_type': operationType,
      'payload': jsonEncode(payload),
      'status': 'pending',
      'attempt_count': 0,
      'next_retry_at': 0,
      'last_error': null,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getPendingOutboxOperations(String viewerUserId) async {
    final db = await _db;
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    return await db.query(
      'activity_outbox',
      where: 'viewer_user_id = ? AND status = ? AND next_retry_at <= ?',
      whereArgs: [viewerUserId, 'pending', nowMs],
      orderBy: 'id ASC',
    );
  }

  Future<void> lockOutboxOperation(int id) async {
    final db = await _db;
    await db.update(
      'activity_outbox',
      {
        'status': 'processing',
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markOutboxOperationCompleted(int id) async {
    final db = await _db;
    await db.delete('activity_outbox', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> markOutboxOperationRetry({
    required int id,
    required int attemptCount,
    required int nextRetryAt,
    required String lastError,
  }) async {
    final db = await _db;
    await db.update(
      'activity_outbox',
      {
        'status': 'pending',
        'attempt_count': attemptCount,
        'next_retry_at': nextRetryAt,
        'last_error': lastError,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markOutboxOperationFailed({
    required int id,
    required String lastError,
  }) async {
    final db = await _db;
    await db.update(
      'activity_outbox',
      {
        'status': 'failed',
        'last_error': lastError,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // --- 4. ISOLATION ET PURGE DE COMPTE (§25 & §26) ---

  Future<void> clearUserCache(String viewerUserId) async {
    final db = await _db;
    await db.delete('activity_cache', where: 'viewer_user_id = ?', whereArgs: [viewerUserId]);
    await db.delete('my_activities_index', where: 'viewer_user_id = ?', whereArgs: [viewerUserId]);
    await db.delete('managed_activities_index', where: 'viewer_user_id = ?', whereArgs: [viewerUserId]);
  }

  // --- 5. COMPATIBILITÉ ET TRANSITION ---

  Future<List<Activity>> getMyActivities(String userId) async {
    final cached = await getMyActivitiesFromCache(userId);
    return cached.map((e) => e.toActivity()).toList();
  }

  Future<void> saveActivity(Activity activity) async {
    await saveLegacyActivity(activity);
  }

  Future<Activity?> getActivityById(String id) async {
    final db = await _db;
    final rows = await db.query('activities', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    final r = rows.first;
    return Activity(
      id: r['id'].toString(),
      creatorId: r['creator_id'].toString(),
      name: r['name'].toString(),
      description: r['description']?.toString() ?? '',
      basePrice: (r['base_price'] as num?)?.toDouble() ?? 0.0,
      currencyCode: r['currency_code']?.toString() ?? 'XAF',
      status: r['status'].toString(),
      addedCount: (r['added_count'] as num?)?.toInt() ?? 0,
      eventOnly: (r['event_only'] as num?)?.toInt() == 1,
      scheduledDeletionAt: r['scheduled_deletion_at'] != null ? DateTime.tryParse(r['scheduled_deletion_at'].toString()) : null,
      createdAt: DateTime.tryParse(r['created_at'].toString()) ?? DateTime.now(),
      updatedAt: DateTime.tryParse(r['updated_at'].toString()) ?? DateTime.now(),
      syncStatus: r['sync_status'].toString(),
      syncError: r['sync_error']?.toString(),
    );
  }

  Future<void> deleteActivityLocal(String id) async {
    final db = await _db;
    await db.delete('activities', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> saveSubscription(String userId, String activityId, {String syncStatus = 'synced'}) async {
    final db = await _db;
    await db.insert('activity_subscriptions', {
      'user_id': userId,
      'activity_id': activityId,
      'created_at': DateTime.now().toIso8601String(),
      'sync_status': syncStatus,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteSubscription(String userId, String activityId) async {
    final db = await _db;
    await db.delete('activity_subscriptions', where: 'user_id = ? AND activity_id = ?', whereArgs: [userId, activityId]);
  }

  Future<List<Map<String, dynamic>>> getPendingOutbox() async {
    final db = await _db;
    return await db.query('activity_outbox', where: 'status = ?', whereArgs: ['pending'], orderBy: 'id ASC');
  }

  Future<int> enqueueOutbox({
    required String tableName,
    required String operation,
    required String recordId,
    required Map<String, dynamic> payload,
  }) async {
    final viewerId = payload['user_id']?.toString() ?? payload['creator_id']?.toString() ?? '';
    final actId = payload['activity_id']?.toString() ?? recordId;
    return await enqueueOutboxOperation(
      operationId: recordId,
      viewerUserId: viewerId,
      activityId: actId,
      operationType: operation,
      payload: payload,
    );
  }

  Future<void> removeFromOutbox(int id) async {
    await markOutboxOperationCompleted(id);
  }

  Future<void> updateOutboxAttempts(int id, int attempts, String lastError) async {
    await markOutboxOperationRetry(id: id, attemptCount: attempts, nextRetryAt: DateTime.now().millisecondsSinceEpoch + 15000, lastError: lastError);
  }

  Future<void> saveLegacyActivity(Activity activity) async {
    final db = await _db;
    await db.insert(
      'activities',
      {
        'id': activity.id,
        'creator_id': activity.creatorId,
        'name': activity.name,
        'description': activity.description,
        'base_price': activity.basePrice,
        'currency_code': activity.currencyCode,
        'status': activity.status,
        'added_count': activity.addedCount,
        'event_only': activity.eventOnly ? 1 : 0,
        'scheduled_deletion_at': activity.scheduledDeletionAt?.toIso8601String(),
        'created_at': activity.createdAt.toIso8601String(),
        'updated_at': activity.updatedAt.toIso8601String(),
        'sync_status': activity.syncStatus,
        'sync_error': activity.syncError,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // --- Sync Cursors ---

  Future<DateTime?> getSyncCursor(String tableName) async {
    final db = await _db;
    final rows = await db.query(
      'activity_sync_cursors',
      where: 'table_name = ?',
      whereArgs: [tableName],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return DateTime.tryParse(rows.first['last_synced_at'].toString());
  }

  Future<void> saveSyncCursor(String tableName, DateTime lastSyncedAt) async {
    final db = await _db;
    await db.insert(
      'activity_sync_cursors',
      {
        'table_name': tableName,
        'last_synced_at': lastSyncedAt.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
