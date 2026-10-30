import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../../app/local_storage/structured/app_cache_database.dart';

/// Persistance SQLite locale des messages de salons, isolée par compte et salon.
class SalonChatLocalCache {
  SalonChatLocalCache(this._appDatabase);

  final AppDatabase _appDatabase;

  Future<List<Map<String, dynamic>>> readMessages({
    required String userId,
    required String salonId,
    int limit = 300,
  }) async {
    final db = await _appDatabase.database;
    final rows = await db.query(
      'community_salon_messages_cache',
      columns: ['payload'],
      where: 'user_id = ? AND salon_id = ?',
      whereArgs: [userId, salonId],
      orderBy: 'sent_at DESC, message_id DESC',
      limit: limit,
    );
    final messages = <Map<String, dynamic>>[];
    for (final row in rows.reversed) {
      try {
        final decoded = jsonDecode(row['payload'] as String);
        if (decoded is Map) messages.add(Map<String, dynamic>.from(decoded));
      } catch (_) {}
    }
    return messages;
  }

  Future<void> upsertMessages({
    required String userId,
    required String salonId,
    required List<Map<String, dynamic>> messages,
  }) async {
    if (messages.isEmpty) return;
    final db = await _appDatabase.database;
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      for (final message in messages) {
        final id = message['id']?.toString();
        if (id == null || id.isEmpty || message['is_uploading'] == true) continue;
        if (message['is_deleted'] == true) {
          await txn.delete(
            'community_salon_messages_cache',
            where: 'user_id = ? AND salon_id = ? AND message_id = ?',
            whereArgs: [userId, salonId, id],
          );
          continue;
        }
        final rawSentAt = message['sent_at'] ?? message['created_at'];
        final sentAt = DateTime.tryParse(rawSentAt?.toString() ?? '')?.toUtc().millisecondsSinceEpoch ?? now;
        await txn.insert(
          'community_salon_messages_cache',
          {
            'user_id': userId,
            'salon_id': salonId,
            'message_id': id,
            'sent_at': sentAt,
            'payload': jsonEncode(message),
            'cached_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      // Garder un historique local borné, les plus récents en priorité.
      await txn.rawDelete(
        '''DELETE FROM community_salon_messages_cache
           WHERE user_id = ? AND salon_id = ? AND message_id NOT IN (
             SELECT message_id FROM community_salon_messages_cache
             WHERE user_id = ? AND salon_id = ?
             ORDER BY sent_at DESC, message_id DESC LIMIT 500
           )''',
        [userId, salonId, userId, salonId],
      );
    });
  }

  Future<Map<String, dynamic>?> readCursor({
    required String userId,
    required String salonId,
  }) async {
    final db = await _appDatabase.database;
    final rows = await db.query(
      'community_salon_sync_cursors',
      where: 'user_id = ? AND salon_id = ?',
      whereArgs: [userId, salonId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return {
      'sent_at': DateTime.fromMillisecondsSinceEpoch(
        (rows.first['last_sent_at'] as num).toInt(),
        isUtc: true,
      ).toIso8601String(),
      'id': rows.first['last_message_id']?.toString() ?? '',
    };
  }

  Future<void> advanceCursor({
    required String userId,
    required String salonId,
    required DateTime sentAt,
    required String messageId,
  }) async {
    if (messageId.isEmpty) return;
    final db = await _appDatabase.database;
    final nextAt = sentAt.toUtc().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      final existing = await txn.query(
        'community_salon_sync_cursors',
        where: 'user_id = ? AND salon_id = ?',
        whereArgs: [userId, salonId],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        final previousAt = (existing.first['last_sent_at'] as num).toInt();
        final previousId = existing.first['last_message_id']?.toString() ?? '';
        if (nextAt < previousAt || (nextAt == previousAt && messageId.compareTo(previousId) <= 0)) return;
      }
      await txn.insert(
        'community_salon_sync_cursors',
        {
          'user_id': userId,
          'salon_id': salonId,
          'last_sent_at': nextAt,
          'last_message_id': messageId,
          'updated_at': DateTime.now().toUtc().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<void> deleteMessage({
    required String userId,
    required String salonId,
    required String messageId,
  }) async {
    final db = await _appDatabase.database;
    await db.delete(
      'community_salon_messages_cache',
      where: 'user_id = ? AND salon_id = ? AND message_id = ?',
      whereArgs: [userId, salonId, messageId],
    );
  }

  Future<void> clearSalon({
    required String userId,
    required String salonId,
  }) async {
    final db = await _appDatabase.database;
    await db.delete(
      'community_salon_messages_cache',
      where: 'user_id = ? AND salon_id = ?',
      whereArgs: [userId, salonId],
    );
  }
}
