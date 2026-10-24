import 'package:sqflite/sqflite.dart';
import '../../../../app/local_storage/structured/app_cache_database.dart';

/// Accès SQLite partagé par le module de messagerie.
/// Il n'existe qu'une seule connexion SQLite locale pour l'application.
class MessagingDatabase {
  MessagingDatabase(this.db);
  final AppDatabase db;

  Future<Database> get database => db.database;

  Future<void> ensureSchema() async {
    final database = await db.database;
    await database.execute('''
      CREATE TABLE IF NOT EXISTS direct_chat_deleted_conversations (
        user_id TEXT NOT NULL,
        conversation_id TEXT NOT NULL,
        deleted_at INTEGER NOT NULL,
        other_user_id TEXT,
        name TEXT,
        avatar_url TEXT,
        PRIMARY KEY(user_id, conversation_id)
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_direct_chat_deleted_conversations_user
      ON direct_chat_deleted_conversations(user_id, deleted_at DESC)
    ''');
  }

  Future<void> _tryAddColumn(Database database, String sql) async {
    try {
      await database.execute(sql);
    } catch (_) {}
  }
}
