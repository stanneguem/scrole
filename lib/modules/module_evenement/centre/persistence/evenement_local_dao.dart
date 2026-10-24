import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../../../../app/local_storage/structured/app_cache_database.dart';

class EvenementLocalDao {
  final AppDatabase _appDb;
  final StreamController<void> _eventChanges = StreamController<void>.broadcast();

  EvenementLocalDao(this._appDb);

  Stream<void> get eventChanges => _eventChanges.stream;

  void _notifyChanges() {
    if (!_eventChanges.isClosed) {
      _eventChanges.add(null);
    }
  }

  Future<Database> get _db => _appDb.database;

  Future<void> insertEvent({
    required String id,
    required String userId,
    required Map<String, dynamic> data,
    String statutSync = 'en_attente',
  }) async {
    final db = await _db;
    await db.insert('evenements_locaux', {
      'id': id,
      'user_id': userId,
      'donnees': jsonEncode(data),
      'statut_sync': statutSync,
      'created_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    _notifyChanges();
  }

  Future<void> updateEventSyncStatus(String id, String status, {String? error}) async {
    final db = await _db;
    await db.update('evenements_locaux', {
      'statut_sync': status,
      'erreur': error,
    }, where: 'id = ?', whereArgs: [id]);
    _notifyChanges();
  }

  Future<List<Map<String, dynamic>>> getPendingEvents(String userId) async {
    final db = await _db;
    return await db.query('evenements_locaux', 
      where: 'user_id = ? AND statut_sync != ?', 
      whereArgs: [userId, 'synchronise'],
      orderBy: 'created_at DESC');
  }

  Future<List<Map<String, dynamic>>> getAllLocalEvents(String userId) async {
    final db = await _db;
    return await db.query('evenements_locaux', 
      where: 'user_id = ?', 
      whereArgs: [userId],
      orderBy: 'created_at DESC');
  }

  Future<void> upsertEvent(Map<String, dynamic> row) async {
    final db = await _db;
    final id = (row['id'] ?? row['evenement_id'] ?? '').toString();
    final userId = (row['created_by'] ?? row['creator_id'] ?? '').toString();
    
    if (id.isEmpty) {
      debugPrint('[Warning] upsertEvent: Cannot upsert event with empty ID');
      return;
    }

    await db.insert('evenements_locaux', {
      'id': id,
      'user_id': userId,
      'donnees': jsonEncode(row),
      'statut_sync': 'synchronise',
      'created_at': (row['created_at'] ?? DateTime.now().toIso8601String()).toString(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    _notifyChanges();
  }

  Future<void> upsertEventsBatch(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    final db = await _db;
    final batch = db.batch();
    for (final row in rows) {
      final id = (row['id'] ?? row['evenement_id'] ?? '').toString();
      final userId = (row['created_by'] ?? row['creator_id'] ?? '').toString();
      if (id.isNotEmpty) {
        batch.insert('evenements_locaux', {
          'id': id,
          'user_id': userId,
          'donnees': jsonEncode(row),
          'statut_sync': 'synchronise',
          'created_at': (row['created_at'] ?? DateTime.now().toIso8601String()).toString(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);

        batch.insert('events', {
          'id': id,
          'creator_id': userId,
          'name': (row['name'] ?? row['nom'] ?? '').toString(),
          'slug': (row['slug'] ?? '').toString(),
          'description': row['description']?.toString(),
          'photo': (row['photo'] ?? row['cover_image_url'] ?? row['photo_url'])?.toString(),
          'country_id': (row['country_id'] ?? row['pays_id'])?.toString(),
          'city_id': (row['city_id'] ?? row['ville_id'])?.toString(),
          'starts_at': (row['starts_at'] ?? row['date_debut'] ?? DateTime.now().toIso8601String()).toString(),
          'ends_at': row['ends_at']?.toString(),
          'is_free': (row['is_free'] == true || row['est_gratuit'] == true) ? 1 : 0,
          'status': (row['status'] ?? row['statut'] ?? 'en_attente').toString(),
          'scheduled_deletion_at': (row['scheduled_deletion_at'] ?? row['deletion_requested_at'])?.toString(),
          'community_id': row['community_id']?.toString(),
          'created_at': (row['created_at'] ?? DateTime.now().toIso8601String()).toString(),
          'updated_at': (row['updated_at'] ?? DateTime.now().toIso8601String()).toString(),
          'sync_status': 'synced',
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }
    await batch.commit(noResult: true);
    _notifyChanges();
  }

  Future<void> deleteEvent(String id) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete('evenements_locaux', where: 'id = ?', whereArgs: [id]);
      await txn.delete('events', where: 'id = ?', whereArgs: [id]);
      await txn.delete('event_calendar', where: 'event_id = ?', whereArgs: [id]);
      await txn.delete('event_likes', where: 'event_id = ?', whereArgs: [id]);
      await txn.delete('event_activities', where: 'event_id = ?', whereArgs: [id]);
      await txn.delete('event_tickets', where: 'event_id = ?', whereArgs: [id]);
      await txn.delete('event_staff', where: 'event_id = ?', whereArgs: [id]);
      await txn.delete('event_co_creators', where: 'event_id = ?', whereArgs: [id]);
      await txn.delete('discovery_cache', where: 'key LIKE ?', whereArgs: ['%$id%']);
    });
    _notifyChanges();
  }

  // --- Activités ---

  Future<void> insertActivity({
    required String id,
    required String userId,
    String? eventId,
    required Map<String, dynamic> data,
    String statutSync = 'en_attente',
  }) async {
    final db = await _db;
    await db.insert('activites_locales', {
      'id': id,
      'user_id': userId,
      'evenement_id': eventId,
      'donnees': jsonEncode(data),
      'statut_sync': statutSync,
      'created_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    _notifyChanges();
  }

  Future<void> updateActivitySyncStatus(String id, String status, {String? error}) async {
    final db = await _db;
    await db.update('activites_locales', {
      'statut_sync': status,
      'erreur': error,
    }, where: 'id = ?', whereArgs: [id]);
    _notifyChanges();
  }

  Future<List<Map<String, dynamic>>> getPendingActivities(String eventId) async {
    final db = await _db;
    return await db.query('activites_locales',
        where: 'evenement_id = ? AND statut_sync != ?',
        whereArgs: [eventId, 'synchronise'],
        orderBy: 'created_at DESC');
  }

  // --- Billets ---

  Future<void> insertTicket({
    required String id,
    required String eventId,
    required Map<String, dynamic> data,
    String statutSync = 'en_attente',
  }) async {
    final db = await _db;
    await db.insert('billets_locaux', {
      'id': id,
      'evenement_id': eventId,
      'donnees': jsonEncode(data),
      'statut_sync': statutSync,
      'created_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    _notifyChanges();
  }

  Future<void> updateTicketSyncStatus(String id, String status, {String? error}) async {
    final db = await _db;
    await db.update('billets_locaux', {
      'statut_sync': status,
      'erreur': error,
    }, where: 'id = ?', whereArgs: [id]);
    _notifyChanges();
  }

  Future<List<Map<String, dynamic>>> getPendingTickets(String eventId) async {
    final db = await _db;
    return await db.query('billets_locaux',
        where: 'evenement_id = ? AND statut_sync != ?',
        whereArgs: [eventId, 'synchronise'],
        orderBy: 'created_at DESC');
  }

  Future<void> deleteTicketLocal(String id) async {
    final db = await _db;
    await db.delete('billets_locaux', where: 'id = ?', whereArgs: [id]);
    _notifyChanges();
  }

  // --- Staff ---

  Future<void> insertStaff({
    required String id,
    required String eventId,
    required String userId,
    required Map<String, dynamic> data,
    String statutSync = 'en_attente',
  }) async {
    final db = await _db;
    await db.insert('staff_locaux', {
      'id': id,
      'evenement_id': eventId,
      'user_id': userId,
      'donnees': jsonEncode(data),
      'statut_sync': statutSync,
      'created_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    _notifyChanges();
  }

  Future<void> updateStaffSyncStatus(String id, String status, {String? error}) async {
    final db = await _db;
    await db.update('staff_locaux', {
      'statut_sync': status,
      'erreur': error,
    }, where: 'id = ?', whereArgs: [id]);
    _notifyChanges();
  }

  Future<List<Map<String, dynamic>>> getPendingStaff(String eventId) async {
    final db = await _db;
    return await db.query('staff_locaux',
        where: 'evenement_id = ? AND statut_sync != ?',
        whereArgs: [eventId, 'synchronise'],
        orderBy: 'created_at DESC');
  }

  // --- Event Outbox ---

  Future<int> enqueueOutbox({
    required String userId,
    required String eventId,
    required String tableName,
    required String operation,
    required Map<String, dynamic> payload,
  }) async {
    final db = await _db;
    return await db.insert('event_outbox', {
      'user_id': userId,
      'event_id': eventId,
      'table_name': tableName,
      'operation': operation,
      'payload': jsonEncode(payload),
      'attempts': 0,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getPendingOutbox(String userId) async {
    final db = await _db;
    return await db.query(
      'event_outbox',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'id ASC',
    );
  }

  Future<void> removeFromOutbox(int id) async {
    final db = await _db;
    await db.delete('event_outbox', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateOutboxAttempts(int id, int attempts, String lastError) async {
    final db = await _db;
    await db.update(
      'event_outbox',
      {'attempts': attempts, 'last_error': lastError},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // --- Sync Cursors (§3) ---

  Future<String?> getSyncCursor(String tableName) async {
    final db = await _db;
    final rows = await db.query('event_sync_cursors', where: 'table_name = ?', whereArgs: [tableName], limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['last_synced_at'] as String?;
  }

  Future<void> setSyncCursor(String tableName, String lastSyncedAt) async {
    final db = await _db;
    await db.insert('event_sync_cursors', {
      'table_name': tableName,
      'last_synced_at': lastSyncedAt,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // --- Structured Storage Methods (§1) ---

  Future<void> saveEventStructured(Map<String, dynamic> row, {String syncStatus = 'synced', String? syncError}) async {
    final db = await _db;
    final id = row['id']?.toString() ?? '';
    if (id.isEmpty) return;

    await db.insert('events', {
      'id': id,
      'creator_id': (row['creator_id'] ?? row['created_by'] ?? '').toString(),
      'name': (row['name'] ?? row['nom'] ?? '').toString(),
      'slug': (row['slug'] ?? '').toString(),
      'description': row['description']?.toString(),
      'photo': (row['photo'] ?? row['photo_url'])?.toString(),
      'country_id': (row['country_id'] ?? row['pays_id'])?.toString(),
      'city_id': (row['city_id'] ?? row['ville_id'])?.toString(),
      'starts_at': (row['starts_at'] ?? row['date_debut'] ?? DateTime.now().toIso8601String()).toString(),
      'ends_at': row['ends_at']?.toString(),
      'is_free': (row['is_free'] == true || row['est_gratuit'] == true) ? 1 : 0,
      'status': (row['status'] ?? row['statut'] ?? 'en_attente').toString(),
      'scheduled_deletion_at': row['scheduled_deletion_at']?.toString(),
      'community_id': row['community_id']?.toString(),
      'created_at': (row['created_at'] ?? DateTime.now().toIso8601String()).toString(),
      'updated_at': (row['updated_at'] ?? DateTime.now().toIso8601String()).toString(),
      'sync_status': syncStatus,
      'sync_error': syncError,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    _notifyChanges();
  }

  Future<Map<String, dynamic>?> getEventStructuredById(String id) async {
    final db = await _db;
    final rows = await db.query('events', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return rows.first;
  }

  Future<List<Map<String, dynamic>>> getEventsStructured({String? creatorId, String? syncStatus}) async {
    final db = await _db;
    final whereClauses = <String>[];
    final whereArgs = <dynamic>[];

    if (creatorId != null) {
      whereClauses.add('creator_id = ?');
      whereArgs.add(creatorId);
    }
    if (syncStatus != null) {
      whereClauses.add('sync_status = ?');
      whereArgs.add(syncStatus);
    }

    return await db.query(
      'events',
      where: whereClauses.isNotEmpty ? whereClauses.join(' AND ') : null,
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      orderBy: 'starts_at DESC',
    );
  }

  Future<void> updateEventSyncStatusStructured(String id, String syncStatus, {String? error}) async {
    final db = await _db;
    await db.update('events', {
      'sync_status': syncStatus,
      'sync_error': error,
    }, where: 'id = ?', whereArgs: [id]);
    _notifyChanges();
  }

  Future<void> saveCalendarEventStructured(String userId, String eventId, {String syncStatus = 'synced'}) async {
    final db = await _db;
    await db.insert('event_calendar', {
      'user_id': userId,
      'event_id': eventId,
      'created_at': DateTime.now().toIso8601String(),
      'sync_status': syncStatus,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    _notifyChanges();
  }

  Future<void> removeCalendarEventStructured(String userId, String eventId) async {
    final db = await _db;
    await db.delete('event_calendar', where: 'user_id = ? AND event_id = ?', whereArgs: [userId, eventId]);
    _notifyChanges();
  }

  Future<bool> isEventInCalendarStructured(String userId, String eventId) async {
    final db = await _db;
    final rows = await db.query('event_calendar', where: 'user_id = ? AND event_id = ?', whereArgs: [userId, eventId], limit: 1);
    return rows.isNotEmpty;
  }

  Future<void> saveLikeStructured(String userId, String eventId, {String syncStatus = 'synced'}) async {
    final db = await _db;
    await db.insert('event_likes', {
      'user_id': userId,
      'event_id': eventId,
      'created_at': DateTime.now().toIso8601String(),
      'sync_status': syncStatus,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    _notifyChanges();
  }

  Future<void> removeLikeStructured(String userId, String eventId) async {
    final db = await _db;
    await db.delete('event_likes', where: 'user_id = ? AND event_id = ?', whereArgs: [userId, eventId]);
    _notifyChanges();
  }

  Future<bool> isEventLikedStructured(String userId, String eventId) async {
    final db = await _db;
    final rows = await db.query('event_likes', where: 'user_id = ? AND event_id = ?', whereArgs: [userId, eventId], limit: 1);
    return rows.isNotEmpty;
  }

  // --- Discovery Cache ---

  Future<void> saveDiscoveryCache(String key, String payload) async {
    final db = await _db;
    await db.insert('discovery_cache', {
      'key': key,
      'payload': payload,
      'cached_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<(String, DateTime)?> getDiscoveryCache(String key) async {
    final db = await _db;
    final rows = await db.query('discovery_cache', where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    return (
      rows.first['payload'] as String,
      DateTime.fromMillisecondsSinceEpoch(rows.first['cached_at'] as int)
    );
  }

  // --- Purge Uniquement Événements (§1 & §17) ---

  Future<void> purgeEventCacheOnly() async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete('events');
      await txn.delete('event_activities');
      await txn.delete('event_tickets');
      await txn.delete('event_likes');
      await txn.delete('event_calendar');
      await txn.delete('event_co_creators');
      await txn.delete('event_staff');
      await txn.delete('event_staff_activities');
      await txn.delete('event_checkins');
      await txn.delete('event_transfers');
      await txn.delete('event_interests');
      await txn.delete('event_outbox');
      await txn.delete('event_sync_cursors');
      await txn.delete('discovery_cache');
      try { await txn.delete('evenements_locaux'); } catch (_) {}
      try { await txn.delete('activites_locales'); } catch (_) {}
      try { await txn.delete('billets_locaux'); } catch (_) {}
      try { await txn.delete('staff_locaux'); } catch (_) {}
    });
    _notifyChanges();
    debugPrint('[EvenementLocalDao] EVENT CACHE PURGED CLEANLY (§1 & §17).');
  }

  void closeStream() {
    _eventChanges.close();
  }
}
