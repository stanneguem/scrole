import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../../../../app/local_storage/structured/app_cache_database.dart';

enum RelationState {
  self,
  friend,
  requestSent,
  requestReceived,
  retryLater,
  blockedByMe,
  none,
}

class SocialLocalDao {
  final AppDatabase _appDb;
  final StreamController<void> _socialChanges = StreamController<void>.broadcast();

  SocialLocalDao(this._appDb);

  Stream<void> get socialChanges => _socialChanges.stream;

  void _notify() {
    if (!_socialChanges.isClosed) {
      _socialChanges.add(null);
    }
  }

  Future<Database> get _db => _appDb.database;

  // --- Relation State Calculator (§1) ---

  Future<RelationState> getRelationState(String currentUserId, String targetUserId) async {
    if (currentUserId == targetUserId) return RelationState.self;

    final db = await _db;

    // 1. Check blocked_users
    final blockedRows = await db.query(
      'blocked_users',
      where: 'bloque_id = ? AND statut = 1',
      whereArgs: [targetUserId],
      limit: 1,
    );
    if (blockedRows.isNotEmpty) {
      final until = blockedRows.first['bloque_jusquau'] as String?;
      if (until == null || DateTime.tryParse(until)?.isAfter(DateTime.now().toUtc()) == true) {
        return RelationState.blockedByMe;
      }
    }

    // 2. Check friendships (sorted pair: user_a < user_b)
    final userA = currentUserId.compareTo(targetUserId) < 0 ? currentUserId : targetUserId;
    final userB = currentUserId.compareTo(targetUserId) < 0 ? targetUserId : currentUserId;
    final friendRows = await db.query(
      'friendships',
      where: 'user_a_id = ? AND user_b_id = ?',
      whereArgs: [userA, userB],
      limit: 1,
    );
    if (friendRows.isNotEmpty) {
      return RelationState.friend;
    }

    // 3. Check friend_requests
    final reqRows = await db.query(
      'friend_requests',
      where: '(sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?)',
      whereArgs: [currentUserId, targetUserId, targetUserId, currentUserId],
    );

    for (final row in reqRows) {
      final sender = row['sender_id'] as String;
      final receiver = row['receiver_id'] as String;
      final status = row['status'] as String;

      if (sender == currentUserId && receiver == targetUserId) {
        if (status == 'pending') return RelationState.requestSent;
        if (status == 'rejected') {
          final retryAt = row['next_retry_at'] as String?;
          if (retryAt != null && DateTime.tryParse(retryAt)?.isAfter(DateTime.now().toUtc()) == true) {
            return RelationState.retryLater;
          }
        }
      } else if (sender == targetUserId && receiver == currentUserId) {
        if (status == 'pending') return RelationState.requestReceived;
      }
    }

    return RelationState.none;
  }

  // --- Friendships ---

  Future<void> saveFriendships(List<Map<String, dynamic>> list, {bool replaceAll = false}) async {
    final db = await _db;
    await db.transaction((txn) async {
      if (replaceAll) {
        await txn.delete('friendships', where: 'sync_status = ?', whereArgs: ['synced']);
      }
      for (final item in list) {
        final rawA = (item['user_a_id'] ?? '').toString();
        final rawB = (item['user_b_id'] ?? '').toString();
        if (rawA.isEmpty || rawB.isEmpty) continue;

        final userA = rawA.compareTo(rawB) < 0 ? rawA : rawB;
        final userB = rawA.compareTo(rawB) < 0 ? rawB : rawA;

        await txn.insert('friendships', {
          'user_a_id': userA,
          'user_b_id': userB,
          'created_at': (item['created_at'] ?? DateTime.now().toIso8601String()).toString(),
          'sync_status': (item['sync_status'] ?? 'synced').toString(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
    _notify();
  }

  Future<void> removeFriendship(String currentUserId, String targetUserId) async {
    final db = await _db;
    final userA = currentUserId.compareTo(targetUserId) < 0 ? currentUserId : targetUserId;
    final userB = currentUserId.compareTo(targetUserId) < 0 ? targetUserId : currentUserId;
    await db.delete('friendships', where: 'user_a_id = ? AND user_b_id = ?', whereArgs: [userA, userB]);
    await db.delete('friend_requests', where: '(sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?)', whereArgs: [currentUserId, targetUserId, targetUserId, currentUserId]);
    _notify();
  }

  Future<List<Map<String, dynamic>>> getFriendships(String currentUserId) async {
    final db = await _db;
    return await db.query(
      'friendships',
      where: 'user_a_id = ? OR user_b_id = ?',
      whereArgs: [currentUserId, currentUserId],
    );
  }

  // --- Friend Requests ---

  Future<void> saveFriendRequests(List<Map<String, dynamic>> list, {bool replaceAll = false}) async {
    final db = await _db;
    await db.transaction((txn) async {
      if (replaceAll) {
        await txn.delete('friend_requests', where: 'sync_status = ?', whereArgs: ['synced']);
      }
      for (final item in list) {
        final id = (item['id'] ?? '').toString();
        if (id.isEmpty) continue;

        await txn.insert('friend_requests', {
          'id': id,
          'sender_id': (item['sender_id'] ?? '').toString(),
          'receiver_id': (item['receiver_id'] ?? '').toString(),
          'status': (item['status'] ?? 'pending').toString(),
          'attempt_count': (item['attempt_count'] as num?)?.toInt() ?? 1,
          'next_retry_at': item['next_retry_at']?.toString(),
          'created_at': (item['created_at'] ?? DateTime.now().toIso8601String()).toString(),
          'responded_at': item['responded_at']?.toString(),
          'sync_status': (item['sync_status'] ?? 'synced').toString(),
          'sync_error': item['sync_error']?.toString(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
    _notify();
  }

  Future<void> removeFriendRequest(String requestId) async {
    final db = await _db;
    await db.delete('friend_requests', where: 'id = ?', whereArgs: [requestId]);
    _notify();
  }

  Future<List<Map<String, dynamic>>> getFriendRequests(String currentUserId) async {
    final db = await _db;
    return await db.query(
      'friend_requests',
      where: 'sender_id = ? OR receiver_id = ?',
      whereArgs: [currentUserId, currentUserId],
    );
  }

  // --- Blocked Users ---

  Future<void> saveBlockedUsers(List<Map<String, dynamic>> list, {bool replaceAll = false}) async {
    final db = await _db;
    await db.transaction((txn) async {
      if (replaceAll) {
        await txn.delete('blocked_users', where: 'sync_status = ?', whereArgs: ['synced']);
      }
      for (final item in list) {
        final id = (item['id'] ?? '').toString();
        if (id.isEmpty) continue;

        await txn.insert('blocked_users', {
          'id': id,
          'bloque_id': (item['bloque_id'] ?? '').toString(),
          'raison': item['raison']?.toString(),
          'bloque_jusquau': item['bloque_jusquau']?.toString(),
          'statut': (item['statut'] == false || item['statut'] == 0) ? 0 : 1,
          'bloque_le': (item['bloque_le'] ?? item['created_at'] ?? DateTime.now().toIso8601String()).toString(),
          'sync_status': (item['sync_status'] ?? 'synced').toString(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
    _notify();
  }

  Future<void> removeBlockedUser(String bloqueId) async {
    final db = await _db;
    await db.delete('blocked_users', where: 'bloque_id = ?', whereArgs: [bloqueId]);
    _notify();
  }

  Future<Set<String>> getBlockedUserIds() async {
    final db = await _db;
    final rows = await db.query(
      'blocked_users',
      where: 'statut = 1',
    );
    final now = DateTime.now().toUtc();
    final set = <String>{};

    for (final r in rows) {
      final id = (r['bloque_id'] ?? '').toString();
      final until = r['bloque_jusquau'] as String?;
      if (id.isNotEmpty) {
        if (until == null || DateTime.tryParse(until)?.isAfter(now) == true) {
          set.add(id);
        }
      }
    }
    return set;
  }

  // --- User QR Codes ---

  Future<void> saveUserQrCodes(List<Map<String, dynamic>> list) async {
    final db = await _db;
    await db.transaction((txn) async {
      for (final item in list) {
        final id = (item['id'] ?? '').toString();
        if (id.isEmpty) continue;

        await txn.insert('user_qr_codes', {
          'id': id,
          'user_id': (item['user_id'] ?? '').toString(),
          'uses_remaining': (item['uses_remaining'] as num?)?.toInt() ?? 3,
          'created_at': (item['created_at'] ?? DateTime.now().toIso8601String()).toString(),
          'sync_status': (item['sync_status'] ?? 'synced').toString(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
    _notify();
  }

  Future<void> updateUserQrCodeSyncStatus(String qrId, String syncStatus) async {
    final db = await _db;
    await db.update(
      'user_qr_codes',
      {'sync_status': syncStatus},
      where: 'id = ?',
      whereArgs: [qrId],
    );
    _notify();
  }

  Future<Map<String, dynamic>?> getActiveUserQrCode(String userId) async {
    final db = await _db;
    final rows = await db.query(
      'user_qr_codes',
      where: 'user_id = ? AND uses_remaining > 0',
      whereArgs: [userId],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first;
  }

  // --- People (Subset of user_profiles) ---

  Future<void> savePeople(List<Map<String, dynamic>> profiles) async {
    final db = await _db;
    final now = DateTime.now().toIso8601String();

    await db.transaction((txn) async {
      for (final p in profiles) {
        final userId = (p['user_id'] ?? p['id'] ?? '').toString();
        if (userId.isEmpty) continue;

        await txn.insert('people', {
          'user_id': userId,
          'username': p['username']?.toString(),
          'first_name': p['first_name']?.toString(),
          'last_name': p['last_name']?.toString(),
          'photo_url': p['photo_url']?.toString(),
          'is_verified': (p['is_verified'] == true || p['is_verified'] == 1) ? 1 : 0,
          'account_status': p['account_status']?.toString(),
          'deleted_at': p['deleted_at']?.toString(),
          'fetched_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
    _notify();
  }

  Future<List<Map<String, dynamic>>> getPeople(List<String> userIds) async {
    if (userIds.isEmpty) return [];
    final db = await _db;
    final placeholders = List.filled(userIds.length, '?').join(',');
    return await db.query(
      'people',
      where: 'user_id IN ($placeholders) AND (deleted_at IS NULL OR deleted_at = "")',
      whereArgs: userIds,
    );
  }

  // --- Social Outbox ---

  Future<int> enqueueOutbox({
    required String userId,
    required String operation,
    required Map<String, dynamic> payload,
  }) async {
    final db = await _db;
    return await db.insert('social_outbox', {
      'user_id': userId,
      'operation': operation,
      'payload': jsonEncode(payload),
      'attempts': 0,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getPendingOutbox(String userId) async {
    final db = await _db;
    return await db.query(
      'social_outbox',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'id ASC',
    );
  }

  Future<void> removeFromOutbox(int id) async {
    final db = await _db;
    await db.delete('social_outbox', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateOutboxAttempts(int id, int attempts, String lastError) async {
    final db = await _db;
    await db.update(
      'social_outbox',
      {'attempts': attempts, 'last_error': lastError},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
