import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../../../../app/local_storage/structured/app_cache_database.dart';
import '../models/community_model.dart';

class CommunityLocalDao {
  final AppDatabase _db;

  CommunityLocalDao(this._db);

  Future<void> saveCommunity(CommunityModel community) async {
    final db = await _db.database;
    await db.insert(
      'communities',
      community.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<CommunityModel?> getCommunity(String id) async {
    final db = await _db.database;
    final maps = await db.query('communities', where: 'id = ?', whereArgs: [id]);
    if (maps.isNotEmpty) {
      return CommunityModel.fromMap(maps.first);
    }
    return null;
  }

  Future<List<CommunityModel>> getAllCommunities() async {
    final db = await _db.database;
    final maps = await db.query('communities', orderBy: 'cached_at DESC');
    return maps.map((m) => CommunityModel.fromMap(m)).toList();
  }

  Future<List<Map<String, dynamic>>> getAllCommunitiesRaw() async {
    final db = await _db.database;
    return await db.query('communities', orderBy: 'cached_at DESC');
  }

  Future<void> deleteCommunity(String id) async {
    final db = await _db.database;
    await db.delete('communities', where: 'id = ?', whereArgs: [id]);
    await db.delete('community_members', where: 'community_id = ?', whereArgs: [id]);
  }

  Future<void> ensureCommunityMember(String userId, String communityId, {String status = 'active'}) async {
    final db = await _db.database;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final id = '${communityId}_$userId';
    await db.insert(
      'community_members',
      {
        'id': id,
        'community_id': communityId,
        'user_id': userId,
        'status': status,
        'cached_at': nowMs,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<CommunityModel>> getCommunities(String userId) async {
    final db = await _db.database;
    const query = '''
      SELECT DISTINCT c.* FROM communities c
      LEFT JOIN community_members m ON m.community_id = c.id
      WHERE (m.user_id = ? AND (c.status = 'confirmed' OR c.status = 'pending'))
         OR (c.status = 'pending')
      ORDER BY c.cached_at DESC
    ''';
    debugPrint('[COMMUNITY_SYNC] [Dao] Executing query for userId=$userId');
    final maps = await db.rawQuery(query, [userId]);

    debugPrint('[COMMUNITY_SYNC] [Dao] getCommunities for userId=$userId returned ${maps.length} communities');
    return maps.map((m) => CommunityModel.fromMap(m)).toList();
  }

  Future<void> updateCommunityStatus(String communityId, String status) async {
    debugPrint('[COMMUNITY_SYNC] Status change event: communityId=$communityId, status=$status');
    final db = await _db.database;
    await db.update(
      'communities',
      {'status': status},
      where: 'id = ?',
      whereArgs: [communityId],
    );
  }

  Future<int> insertCommunityOutbox({
    required String operationId,
    required String userId,
    required String communityId,
    required String operationType,
    required String payload,
  }) async {
    final db = await _db.database;
    final now = DateTime.now().toIso8601String();
    return await db.insert('community_outbox', {
      'operation_id': operationId,
      'user_id': userId,
      'community_id': communityId,
      'operation_type': operationType,
      'payload': payload,
      'status': 'pending',
      'attempt_count': 0,
      'next_retry_at': 0,
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<List<Map<String, dynamic>>> getPendingOutboxOperations(String userId) async {
    final db = await _db.database;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    return await db.query(
      'community_outbox',
      where: 'user_id = ? AND status = "pending" AND next_retry_at <= ?',
      whereArgs: [userId, nowMs],
      orderBy: 'created_at ASC',
    );
  }

  Future<void> markOutboxOperationCompleted(int id) async {
    final db = await _db.database;
    await db.delete('community_outbox', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> markOutboxOperationFailed({required int id, required String lastError}) async {
    final db = await _db.database;
    final now = DateTime.now().toIso8601String();
    await db.update(
      'community_outbox',
      {
        'status': 'failed',
        'last_error': lastError,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markOutboxOperationRetry({
    required int id,
    required int attemptCount,
    required int nextRetryAt,
    required String lastError,
  }) async {
    final db = await _db.database;
    final now = DateTime.now().toIso8601String();
    await db.update(
      'community_outbox',
      {
        'attempt_count': attemptCount,
        'next_retry_at': nextRetryAt,
        'last_error': lastError,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
