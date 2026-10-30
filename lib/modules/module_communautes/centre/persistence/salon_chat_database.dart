import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// Base SQLite dédiée exclusivement aux conversations des salons communautaires.
/// Elle est volontairement indépendante de la base générale de l'application
/// et de la base de la messagerie directe.
class SalonChatDatabase {
  SalonChatDatabase._();

  static final SalonChatDatabase instance = SalonChatDatabase._();

  static const String _databaseName = 'salon_chat_local.db';
  static const int _databaseVersion = 1;

  Database? _database;
  Future<Database>? _opening;

  Future<Database> get database async {
    if (_database != null && _database!.isOpen) return _database!;
    _opening ??= _open();
    try {
      _database = await _opening!;
      return _database!;
    } catch (_) {
      _opening = null;
      rethrow;
    }
  }

  Future<Database> _open() async {
    final directory = await getDatabasesPath();
    return openDatabase(
      join(directory, _databaseName),
      version: _databaseVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
        await db.execute('PRAGMA busy_timeout = 10000');
        await db.rawQuery('PRAGMA journal_mode = WAL');
      },
      onCreate: _createSchema,
      onUpgrade: _upgradeSchema,
    );
  }

  Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE salon_messages (
        user_id TEXT NOT NULL,
        salon_id TEXT NOT NULL,
        message_id TEXT NOT NULL,
        sent_at INTEGER NOT NULL,
        payload TEXT NOT NULL,
        cached_at INTEGER NOT NULL,
        PRIMARY KEY(user_id, salon_id, message_id)
      )
    ''');
    await db.execute('''
      CREATE INDEX idx_salon_messages_order
      ON salon_messages(user_id, salon_id, sent_at, message_id)
    ''');
    await db.execute('''
      CREATE TABLE salon_sync_cursors (
        user_id TEXT NOT NULL,
        salon_id TEXT NOT NULL,
        last_sent_at INTEGER NOT NULL,
        last_message_id TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY(user_id, salon_id)
      )
    ''');
    await db.execute('''
      CREATE INDEX idx_salon_sync_cursors_user
      ON salon_sync_cursors(user_id)
    ''');
    await db.execute('''
      CREATE TABLE salon_cache_metadata (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
  }

  Future<void> _upgradeSchema(Database db, int oldVersion, int newVersion) async {
    // Les futures évolutions du cache des salons seront versionnées ici,
    // sans modifier la base générale ni celle des messages directs.
  }

  Future<void> clearUserData(String userId) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('salon_messages', where: 'user_id = ?', whereArgs: [userId]);
      await txn.delete('salon_sync_cursors', where: 'user_id = ?', whereArgs: [userId]);
    });
  }

  Future<void> close() async {
    final db = _database;
    _database = null;
    _opening = null;
    if (db != null && db.isOpen) await db.close();
  }
}
