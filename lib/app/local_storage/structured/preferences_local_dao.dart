import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'app_cache_database.dart';

class PreferencesLocalDao {
  final AppDatabase _appDb;

  PreferencesLocalDao(this._appDb);

  Future<Database> get _db => _appDb.database;

  Future<void> savePreferences(Map<String, dynamic> prefs) async {
    final db = await _db;
    await db.insert(
      'user_preferences',
      {
        'user_id': prefs['user_id'] ?? 'current',
        'language': prefs['language'] ?? 'fr',
        'theme': prefs['theme'] ?? 'system',
        'notifications_enabled': (prefs['notifications_enabled'] == true || prefs['notifications_enabled'] == 1) ? 1 : 0,
        'notif_push': (prefs['notif_push'] == true || prefs['notif_push'] == 1) ? 1 : 0,
        'notif_messages': (prefs['notif_messages'] == true || prefs['notif_messages'] == 1) ? 1 : 0,
        'notif_evenements': (prefs['notif_evenements'] == true || prefs['notif_evenements'] == 1) ? 1 : 0,
        'notif_communautes': (prefs['notif_communautes'] == true || prefs['notif_communautes'] == 1) ? 1 : 0,
        'notif_social': (prefs['notif_social'] == true || prefs['notif_social'] == 1) ? 1 : 0,
        'auto_play_videos': (prefs['auto_play_videos'] == true || prefs['auto_play_videos'] == 1) ? 1 : 0,
        'privacy_profile_visibility': prefs['privacy_profile_visibility'] ?? 'public',
        'updated_at': prefs['updated_at'] ?? DateTime.now().toIso8601String(),
        'sync_status': prefs['sync_status'] ?? 'synced',
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // --- Accumulateur de modifications en attente (pending_changes) ---

  Future<({Map<String, dynamic> changes, int? throughId})> getPendingChangesSnapshot(String userId) async {
    final db = await _db;
    final rows = await db.query(
      'user_preferences_outbox',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'id ASC',
    );
    final merged = <String, dynamic>{};
    for (final row in rows) {
      final payload = Map<String, dynamic>.from(jsonDecode(row['payload'].toString()));
      merged.addAll(payload);
    }
    return (changes: merged, throughId: rows.isEmpty ? null : rows.last['id'] as int);
  }

  Future<Map<String, dynamic>> getPendingChanges(String userId) async {
    return (await getPendingChangesSnapshot(userId)).changes;
  }

  Future<void> clearPendingChanges(String userId, {int? throughId}) async {
    final db = await _db;
    if (throughId == null) {
      await db.delete('user_preferences_outbox', where: 'user_id = ?', whereArgs: [userId]);
      return;
    }
    await db.delete(
      'user_preferences_outbox',
      where: 'user_id = ? AND id <= ?',
      whereArgs: [userId, throughId],
    );
  }

  Future<void> addPendingChanges(String userId, Map<String, dynamic> changes) async {
    final db = await _db;
    await db.insert('user_preferences_outbox', {
      'user_id': userId,
      'payload': jsonEncode(changes),
      'attempts': 0,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

}
