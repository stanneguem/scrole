import 'dart:convert';
import 'dart:async';
import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';
import '../../../../app/local_storage/structured/app_cache_database.dart';

class NotificationEntry {
  const NotificationEntry({required this.id, required this.userId, required this.title, required this.message, required this.type, required this.createdAt, required this.isRead, this.payload, this.actionStatus = 'pending'});
  final String id;
  final String userId;
  final String title;
  final String message;
  final String type;
  final DateTime createdAt;
  final bool isRead;
  final String? payload;
  final String actionStatus; // 'pending', 'accepted', 'refused'
}

class NotificationDbService extends GetxService {
  NotificationDbService(this._appDb);
  final AppDatabase _appDb;
  final StreamController<String> _changes = StreamController<String>.broadcast();
  Future<Database> get database => _appDb.database;

  Future<bool> saveNotification({required String id, required String userId, required String title, required String message, required String type, String? payload, bool isRead = false, DateTime? createdAt, String? actionStatus}) async {
    final db = await database;
    
    // Vérifier si la notification a été supprimée par l'utilisateur
    final deleted = await db.query('deleted_notifications', where: 'user_id = ? AND notification_id = ?', whereArgs: [userId, id], limit: 1);
    if (deleted.isNotEmpty) return false;

    // Récupérer l'existant pour préserver l'action_status local
    final existing = await db.query('notifications', columns: ['action_status', 'is_read'], where: 'id = ? AND user_id = ?', whereArgs: [id, userId], limit: 1);
    if (existing.isNotEmpty) {
      // Actualiser le texte depuis la langue actuelle du compte, y compris pour
      // les notifications déjà mises en cache. Préserver l'état de lecture et
      // l'état d'action gérés localement.
      final wasRead = (existing.first['is_read'] as num?)?.toInt() == 1;
      final update = <String, Object?>{
        'title': title,
        'message': message,
        'type': type,
        'payload': payload,
        // Garder la date originale : une notification reçue de nouveau via
        // FCM/Realtime ne doit pas remonter en tête comme si elle était neuve.
        if (createdAt != null)
          'created_at': createdAt.millisecondsSinceEpoch,
      };
      if (isRead && !wasRead) update['is_read'] = 1;
      await db.update('notifications', update,
          where: 'id = ? AND user_id = ?', whereArgs: [id, userId]);
      _changes.add(userId);
      return false;
    }

    String finalActionStatus = actionStatus ?? 'pending';

    await db.insert('notifications', {
      'id': id, 
      'user_id': userId, 
      'title': title, 
      'message': message, 
      'type': type, 
      'created_at': (createdAt ?? DateTime.now()).millisecondsSinceEpoch, 
      'is_read': isRead ? 1 : 0, 
      'payload': payload,
      'action_status': finalActionStatus,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    _changes.add(userId);
    return true;
  }

  Future<List<Map<String, dynamic>>> _get(String userId) => database.then((db) => db.query('notifications', where: 'user_id = ?', whereArgs: [userId], orderBy: 'created_at DESC'));

  Stream<List<NotificationEntry>> watchNotifications(String userId) async* {
    Future<List<NotificationEntry>> read() async => (await _get(userId)).map(_fromRow).toList();
    yield await read();
    await for (final id in _changes.stream.where((v) => v == userId)) yield await read();
  }

  Stream<int> watchUnreadCount(String userId) async* {
    yield await _unread(userId);
    await for (final id in _changes.stream.where((v) => v == userId)) yield await _unread(id);
  }

  NotificationEntry _fromRow(Map<String, dynamic> row) => NotificationEntry(
    id: row['id']?.toString() ?? '',
    userId: row['user_id']?.toString() ?? '',
    title: row['title']?.toString() ?? '',
    message: row['message']?.toString() ?? '',
    type: row['type']?.toString() ?? 'info',
    createdAt: DateTime.fromMillisecondsSinceEpoch((row['created_at'] as num?)?.toInt() ?? 0),
    isRead: (row['is_read'] as num?)?.toInt() == 1,
    payload: row['payload']?.toString(),
    actionStatus: row['action_status']?.toString() ?? 'pending',
  );

  Future<void> updateActionStatus(String id, String status, {required String userId}) async {
    final db = await database;
    await db.update('notifications', {'action_status': status}, where: 'id = ? AND user_id = ?', whereArgs: [id, userId]);
    _changes.add(userId);
  }

  Future<int> _unread(String userId) async {
    final rows = await (await database).rawQuery('SELECT COUNT(*) AS c FROM notifications WHERE user_id = ? AND is_read = 0', [userId]);
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  Future<void> markAsRead(String id, {String? userId}) async {
    final db = await database;
    await db.update('notifications', {'is_read': 1}, where: userId == null ? 'id = ?' : 'id = ? AND user_id = ?', whereArgs: userId == null ? [id] : [id, userId]);
    
    if (userId != null) {
      await _enqueueOutbox(userId, id, 'mark_read');
      _changes.add(userId);
    }
  }

  Future<void> markAllAsRead(String userId) async {
    final db = await database;
    final unread = await db.query('notifications', columns: ['id'], where: 'user_id = ? AND is_read = 0', whereArgs: [userId]);
    
    await db.update('notifications', {'is_read': 1}, where: 'user_id = ?', whereArgs: [userId]);
    
    for (final row in unread) {
      await _enqueueOutbox(userId, row['id'].toString(), 'mark_read');
    }
    _changes.add(userId);
  }

  Future<void> deleteSalonMessageNotifications({
    required String userId,
    required String salonId,
  }) async {
    final db = await database;
    final rows = await db.query(
      'notifications',
      columns: ['id', 'payload'],
      where: 'user_id = ? AND type IN (?, ?)',
      whereArgs: [userId, 'community_salon_message', 'community_salon_reply'],
    );
    final ids = <String>[];
    for (final row in rows) {
      final raw = row['payload']?.toString();
      if (raw == null || raw.isEmpty) continue;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map && decoded['salon_id']?.toString() == salonId) {
          ids.add(row['id'].toString());
        }
      } catch (_) {}
    }
    if (ids.isEmpty) return;
    await db.delete(
      'notifications',
      where: 'user_id = ? AND id IN (${List.filled(ids.length, '?').join(',')})',
      whereArgs: [userId, ...ids],
    );
    _changes.add(userId);
  }

  Future<DateTime?> getLatestNotificationTimestamp(String userId) async {
    final db = await database;
    final rows = await db.query('notifications', columns: ['created_at'], where: 'user_id = ?', whereArgs: [userId], orderBy: 'created_at DESC', limit: 1);
    if (rows.isEmpty) return null;
    return DateTime.fromMillisecondsSinceEpoch((rows.first['created_at'] as num).toInt());
  }

  Future<void> deleteNotification(String id, {required String userId}) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('notifications', where: 'id = ? AND user_id = ?', whereArgs: [id, userId]);
      await txn.insert('deleted_notifications', {
        'user_id': userId,
        'notification_id': id,
        'deleted_at': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      
      await _enqueueOutbox(userId, id, 'delete', txn: txn);
    });
    _changes.add(userId);
  }

  Future<void> deleteAllNotifications(String userId) async {
    final db = await database;
    final allRows = await db.query('notifications', columns: ['id'], where: 'user_id = ?', whereArgs: [userId]);

    await db.transaction((txn) async {
      await txn.delete('notifications', where: 'user_id = ?', whereArgs: [userId]);
      for (final row in allRows) {
        final id = row['id'].toString();
        await txn.insert('deleted_notifications', {
          'user_id': userId,
          'notification_id': id,
          'deleted_at': DateTime.now().millisecondsSinceEpoch,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        await _enqueueOutbox(userId, id, 'delete', txn: txn);
      }
    });
    _changes.add(userId);
  }

  Future<void> _enqueueOutbox(String userId, String notificationId, String actionType, {Transaction? txn}) async {
    final executor = txn ?? await database;
    await executor.insert('notification_outbox', {
      'user_id': userId,
      'notification_id': notificationId,
      'action_type': actionType,
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'attempts': 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getPendingOutbox(String userId) async {
    final db = await database;
    return await db.query('notification_outbox', where: 'user_id = ? AND attempts < 5', whereArgs: [userId], orderBy: 'created_at ASC');
  }

  Future<void> removeFromOutbox(String userId, String notificationId, String actionType) async {
    final db = await database;
    await db.delete('notification_outbox', where: 'user_id = ? AND notification_id = ? AND action_type = ?', whereArgs: [userId, notificationId, actionType]);
  }

  Future<void> markOutboxAttempt(String userId, String notificationId, String actionType) async {
    final db = await database;
    await db.rawUpdate('UPDATE notification_outbox SET attempts = attempts + 1 WHERE user_id = ? AND notification_id = ? AND action_type = ?', [userId, notificationId, actionType]);
  }

  @override
  void onClose() {
    _changes.close();
    super.onClose();
  }
}
