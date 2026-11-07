import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../../../modules/module_communautes/centre/persistence/salon_chat_database.dart';

class AppDatabase {
  static const String _dbName = 'app_local.db';
  static const int _dbVersion = 33;
  Future<Database>? _dbOpenFuture;
  Database? _database;

  Future<Database> get database async {
    if (_database != null && _database!.isOpen) {
      return _database!;
    }
    _dbOpenFuture ??= _open();
    try {
      _database = await _dbOpenFuture!;
      return _database!;
    } catch (e) {
      _dbOpenFuture = null;
      rethrow;
    }
  }

  Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    return openDatabase(
      join(dbPath, _dbName),
      version: _dbVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
        await db.rawQuery('PRAGMA busy_timeout = 10000');
        await db.rawQuery('PRAGMA journal_mode = WAL');
      },
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await _createCommunityTables(db);
    await _createCommunityPreviewCacheTable(db);
    await _createCommunityOutboxTable(db);
    await _createCommunityFeedCacheTable(db);
    await _createNotificationTable(db);
    await _createNotificationOutboxTable(db);
    await _createMessagingTables(db);
    await _createMediaCacheTable(db);
    await _createMessageDeletionTable(db);
    await _createNotificationDeletionTable(db);
    await _createEventLocalTables(db);
    await _createActivityTables(db);
    await _createUserPreferencesTable(db);
    await _createDiscoveryCacheTable(db);
    await _createSocialTables(db);
    await _createPostOutboxTable(db);
    await _createHomeFeedCacheTable(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createNotificationTable(db);
      await _createMessagingTables(db);
    }
    if (oldVersion < 3) await _createMediaCacheTable(db);
    if (oldVersion < 4) {
      await db.execute(
        'ALTER TABLE direct_chat_conversations ADD COLUMN is_pinned INTEGER NOT NULL DEFAULT 0',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_direct_chat_conversations_pinned ON direct_chat_conversations(user_id,is_pinned,updated_at DESC)',
      );
    }
    if (oldVersion < 5) await _createMessageDeletionTable(db);
    if (oldVersion < 6) await _createNotificationDeletionTable(db);
    if (oldVersion < 7) await _createEventLocalTables(db);
    if (oldVersion < 8) {
      await db.execute('''CREATE TABLE IF NOT EXISTS billets_locaux (
        id TEXT PRIMARY KEY,
        evenement_id TEXT NOT NULL,
        donnees TEXT NOT NULL,
        statut_sync TEXT NOT NULL DEFAULT 'en_attente',
        erreur TEXT,
        created_at TEXT NOT NULL)''');
      
      await db.execute('''CREATE TABLE IF NOT EXISTS staff_locaux (
        id TEXT PRIMARY KEY,
        evenement_id TEXT NOT NULL,
        user_id TEXT NOT NULL,
        donnees TEXT NOT NULL,
        statut_sync TEXT NOT NULL DEFAULT 'en_attente',
        erreur TEXT,
        created_at TEXT NOT NULL)''');
    }
    if (oldVersion < 9) {
      await db.execute(
        'ALTER TABLE notifications ADD COLUMN action_status TEXT NOT NULL DEFAULT "pending"',
      );
    }
    if (oldVersion < 10) {
      // Sécurité : vérifier si la colonne existe avant d'essayer de l'ajouter
      // car la version 9 était instable sur certains appareils
      final columns = await db.rawQuery('PRAGMA table_info(notifications)');
      final hasActionStatus = columns.any((column) => column['name'] == 'action_status');
      if (!hasActionStatus) {
        await db.execute(
          'ALTER TABLE notifications ADD COLUMN action_status TEXT NOT NULL DEFAULT "pending"',
        );
      }
    }
    if (oldVersion < 11) {
      await _createDiscoveryCacheTable(db);
    }
    if (oldVersion < 12) {
      await _createNotificationOutboxTable(db);
    }
    if (oldVersion < 13) {
      // Sécurité ultime : on s'assure que toutes les tables cruciales existent
      await _createNotificationDeletionTable(db);
      await _createDiscoveryCacheTable(db);
      await _createNotificationOutboxTable(db);
    }
    if (oldVersion < 14) {
      await _createActivityTables(db);
    }
    if (oldVersion < 15) {
      await _createUserPreferencesTable(db);
    }
    if (oldVersion < 17) {
      await _createDiscoveryCacheTable(db);
      await _createNotificationOutboxTable(db);
    }
    if (oldVersion < 18) {
      await _createEventLocalTables(db);
    }
    if (oldVersion < 19) {
      await _createSocialTables(db);
    }
    if (oldVersion < 20) {
      final columns = await db.rawQuery('PRAGMA table_info(events)');
      final hasStatus = columns.any((column) => column['name'] == 'status');
      if (!hasStatus) {
        await db.execute(
          "ALTER TABLE events ADD COLUMN status TEXT NOT NULL DEFAULT 'en_attente'",
        );
      }
      final hasScheduledDeletion = columns.any((column) => column['name'] == 'scheduled_deletion_at');
      if (!hasScheduledDeletion) {
        await db.execute('ALTER TABLE events ADD COLUMN scheduled_deletion_at TEXT');
      }
    }
    if (oldVersion < 21) {
      await db.execute('DROP TABLE IF EXISTS community_settings');
      await db.execute(
        '''CREATE TABLE community_settings (
        community_id TEXT PRIMARY KEY REFERENCES communities(id) ON DELETE CASCADE,
        allow_posts INTEGER NOT NULL DEFAULT 1,
        posts_require_approval INTEGER NOT NULL DEFAULT 0,
        members_list_visible INTEGER NOT NULL DEFAULT 0,
        allow_reports INTEGER NOT NULL DEFAULT 1,
        allow_comments INTEGER NOT NULL DEFAULT 1,
        allow_reactions INTEGER NOT NULL DEFAULT 1)''',
      );
    }
    if (oldVersion < 22) {
      await _createCommunityPreviewCacheTable(db);
    }
    if (oldVersion < 23) {
      await db.execute('DROP TABLE IF EXISTS community_settings');
      await db.execute(
        '''CREATE TABLE community_settings (
        community_id TEXT PRIMARY KEY REFERENCES communities(id) ON DELETE CASCADE,
        post_permission TEXT NOT NULL DEFAULT 'everyone',
        posts_require_approval INTEGER NOT NULL DEFAULT 0,
        members_list_visible INTEGER NOT NULL DEFAULT 0,
        allow_reports INTEGER NOT NULL DEFAULT 1,
        allow_comments INTEGER NOT NULL DEFAULT 1,
        allow_reactions INTEGER NOT NULL DEFAULT 1)''',
      );
    }
    if (oldVersion < 25) {
      try {
        await db.execute('ALTER TABLE communities ADD COLUMN created_at INTEGER NOT NULL DEFAULT 0');
      } catch (_) {}
    }
    if (oldVersion < 24) {
      await _createCommunityOutboxTable(db);
      await _createCommunityFeedCacheTable(db);
    }
    if (oldVersion < 26) {
      await _createPostOutboxTable(db);
    }
    if (oldVersion < 27) {
      await _createHomeFeedCacheTable(db);
    }
    if (oldVersion < 28) {
      try {
        await db.execute('ALTER TABLE direct_chat_contacts ADD COLUMN is_certified INTEGER NOT NULL DEFAULT 0');
      } catch (_) {}
    }
    if (oldVersion < 29) {
      try {
        final columns = await db.rawQuery('PRAGMA table_info(community_members)');
        final hasCachedAt = columns.any((column) => column['name'] == 'cached_at');
        if (!hasCachedAt) {
          await db.execute('ALTER TABLE community_members ADD COLUMN cached_at INTEGER NOT NULL DEFAULT 0');
        }
      } catch (_) {}
    }
    if (oldVersion < 30) {
      try {
        await db.execute('DROP INDEX IF EXISTS idx_communities_slug');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_communities_slug ON communities(slug)');
      } catch (_) {}
    }
    if (oldVersion < 31) {
      final columns = await db.rawQuery('PRAGMA table_info(user_preferences)');
      final existing = columns.map((column) => column['name']).whereType<String>().toSet();
      const preferenceColumns = <String, String>{
        'notif_push': 'INTEGER NOT NULL DEFAULT 1',
        'notif_messages': 'INTEGER NOT NULL DEFAULT 1',
        'notif_evenements': 'INTEGER NOT NULL DEFAULT 1',
        'notif_communautes': 'INTEGER NOT NULL DEFAULT 1',
        'notif_social': 'INTEGER NOT NULL DEFAULT 1',
        'auto_play_videos': 'INTEGER NOT NULL DEFAULT 1',
      };
      for (final entry in preferenceColumns.entries) {
        if (!existing.contains(entry.key)) {
          await db.execute('ALTER TABLE user_preferences ADD COLUMN ${entry.key} ${entry.value}');
        }
      }
    }
  }

  Future<void> _createHomeFeedCacheTable(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS home_feed_cache (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      data TEXT NOT NULL,
      cached_at INTEGER NOT NULL)''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_home_feed_cache_user ON home_feed_cache(user_id, cached_at DESC)');
  }

  Future<void> _createPostOutboxTable(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS post_outbox (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      operation_id TEXT UNIQUE NOT NULL,
      user_id TEXT NOT NULL,
      community_id TEXT,
      payload TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'pending',
      attempt_count INTEGER NOT NULL DEFAULT 0,
      next_retry_at INTEGER NOT NULL DEFAULT 0,
      last_error TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_post_outbox_user ON post_outbox(user_id, status, next_retry_at)');
  }

  Future<void> _createCommunityOutboxTable(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS community_outbox (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      operation_id TEXT NOT NULL,
      user_id TEXT NOT NULL,
      community_id TEXT,
      post_id TEXT,
      comment_id TEXT,
      operation_type TEXT NOT NULL,
      payload TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'pending',
      attempt_count INTEGER NOT NULL DEFAULT 0,
      next_retry_at INTEGER NOT NULL DEFAULT 0,
      last_error TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_community_outbox_user ON community_outbox(user_id, status)');
  }

  Future<void> _createCommunityFeedCacheTable(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS community_feed_cache (
      community_id TEXT PRIMARY KEY,
      payload TEXT NOT NULL,
      cached_at INTEGER NOT NULL
    )''');
  }

  Future<void> _createCommunityPreviewCacheTable(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS community_preview_cache (
      community_id TEXT PRIMARY KEY,
      slug TEXT NOT NULL,
      payload TEXT NOT NULL,
      cached_at INTEGER NOT NULL,
      last_accessed_at INTEGER NOT NULL)''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_community_preview_slug ON community_preview_cache(slug)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_community_preview_lru ON community_preview_cache(last_accessed_at)');
  }

  Future<void> _createUserPreferencesTable(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS user_preferences (
      user_id TEXT PRIMARY KEY,
      language TEXT NOT NULL DEFAULT 'fr',
      theme TEXT NOT NULL DEFAULT 'system',
      notifications_enabled INTEGER NOT NULL DEFAULT 1,
      notif_push INTEGER NOT NULL DEFAULT 1,
      notif_messages INTEGER NOT NULL DEFAULT 1,
      notif_evenements INTEGER NOT NULL DEFAULT 1,
      notif_communautes INTEGER NOT NULL DEFAULT 1,
      notif_social INTEGER NOT NULL DEFAULT 1,
      auto_play_videos INTEGER NOT NULL DEFAULT 1,
      privacy_profile_visibility TEXT NOT NULL DEFAULT 'public',
      updated_at TEXT NOT NULL,
      sync_status TEXT NOT NULL DEFAULT 'synced',
      sync_error TEXT)''');

    await db.execute('''CREATE TABLE IF NOT EXISTS user_preferences_outbox (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id TEXT NOT NULL,
      payload TEXT NOT NULL,
      attempts INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL)''');
  }

  Future<void> _createActivityTables(Database db) async {
    // 1. Cache principal isolé par viewer_user_id (§7.1)
    await db.execute('''CREATE TABLE IF NOT EXISTS activity_cache (
      viewer_user_id TEXT NOT NULL,
      activity_id TEXT NOT NULL,
      creator_id TEXT NOT NULL,
      name TEXT NOT NULL,
      description TEXT,
      display_price REAL NOT NULL DEFAULT 0.0,
      display_currency TEXT NOT NULL DEFAULT 'XAF',
      status TEXT NOT NULL DEFAULT 'en_attente',
      added_count INTEGER NOT NULL DEFAULT 0,
      event_only INTEGER NOT NULL DEFAULT 0,
      scheduled_deletion_at TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      cached_at INTEGER NOT NULL,
      PRIMARY KEY (viewer_user_id, activity_id))''');

    await db.execute('CREATE INDEX IF NOT EXISTS idx_act_cache_viewer ON activity_cache(viewer_user_id)');

    // 2. Index des activités créées de l'utilisateur (§8.1)
    await db.execute('''CREATE TABLE IF NOT EXISTS my_activities_index (
      viewer_user_id TEXT NOT NULL,
      activity_id TEXT NOT NULL,
      position INTEGER NOT NULL DEFAULT 0,
      cached_at INTEGER NOT NULL,
      PRIMARY KEY (viewer_user_id, activity_id))''');

    // 3. Index des activités gérées de l'utilisateur (§8.2)
    await db.execute('''CREATE TABLE IF NOT EXISTS managed_activities_index (
      viewer_user_id TEXT NOT NULL,
      activity_id TEXT NOT NULL,
      position INTEGER NOT NULL DEFAULT 0,
      cached_at INTEGER NOT NULL,
      PRIMARY KEY (viewer_user_id, activity_id))''');

    // 4. Staff cache (§9)
    await db.execute('''CREATE TABLE IF NOT EXISTS activity_staff_cache (
      activity_id TEXT NOT NULL,
      user_id TEXT NOT NULL,
      username TEXT,
      first_name TEXT,
      last_name TEXT,
      photo_url TEXT,
      status TEXT NOT NULL DEFAULT 'en_attente',
      joined_at TEXT,
      cached_at INTEGER NOT NULL,
      PRIMARY KEY (activity_id, user_id))''');

    // 5. Staff invites (§10)
    await db.execute('''CREATE TABLE IF NOT EXISTS activity_staff_invites (
      invite_id TEXT PRIMARY KEY,
      activity_id TEXT NOT NULL,
      user_id TEXT NOT NULL,
      invited_by TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'en_attente',
      created_at TEXT NOT NULL,
      responded_at TEXT,
      cached_at INTEGER NOT NULL)''');

    // 6. Event activity relation cache (§11)
    await db.execute('''CREATE TABLE IF NOT EXISTS event_activity_cache (
      event_id TEXT NOT NULL,
      activity_id TEXT NOT NULL,
      price REAL NOT NULL DEFAULT 0.0,
      created_at TEXT NOT NULL,
      cached_at INTEGER NOT NULL,
      PRIMARY KEY (event_id, activity_id))''');

    // 7. Activity Outbox officielle (§12)
    await db.execute('''CREATE TABLE IF NOT EXISTS activity_outbox (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      operation_id TEXT NOT NULL,
      viewer_user_id TEXT NOT NULL,
      activity_id TEXT NOT NULL,
      operation_type TEXT NOT NULL,
      payload TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'pending',
      attempt_count INTEGER NOT NULL DEFAULT 0,
      next_retry_at INTEGER NOT NULL DEFAULT 0,
      last_error TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL)''');

    await db.execute('CREATE INDEX IF NOT EXISTS idx_act_outbox_viewer ON activity_outbox(viewer_user_id, status)');

    // Legacy table maintenance
    await db.execute('''CREATE TABLE IF NOT EXISTS activities (
      id TEXT PRIMARY KEY,
      creator_id TEXT NOT NULL,
      name TEXT NOT NULL,
      description TEXT,
      base_price REAL NOT NULL DEFAULT 0,
      currency_code TEXT NOT NULL DEFAULT 'XAF',
      status TEXT NOT NULL DEFAULT 'en_attente',
      added_count INTEGER NOT NULL DEFAULT 0,
      event_only INTEGER NOT NULL DEFAULT 0,
      scheduled_deletion_at TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      sync_status TEXT NOT NULL DEFAULT 'synced',
      sync_error TEXT)''');

    try {
      await db.execute("ALTER TABLE activities ADD COLUMN description TEXT");
    } catch (_) {}
    try {
      await db.execute("ALTER TABLE activities ADD COLUMN currency_code TEXT DEFAULT 'XAF'");
    } catch (_) {}

    await db.execute('''CREATE TABLE IF NOT EXISTS activity_subscriptions (
      user_id TEXT NOT NULL,
      activity_id TEXT NOT NULL,
      created_at TEXT NOT NULL,
      sync_status TEXT NOT NULL DEFAULT 'synced',
      PRIMARY KEY (user_id, activity_id))''');

    await db.execute('''CREATE TABLE IF NOT EXISTS activity_sync_cursors (
      table_name TEXT PRIMARY KEY,
      last_synced_at TEXT NOT NULL)''');
  }

  Future<void> _createEventLocalTables(Database db) async {
    // 1. events
    await db.execute('''CREATE TABLE IF NOT EXISTS events (
      id TEXT PRIMARY KEY,
      creator_id TEXT NOT NULL,
      name TEXT NOT NULL,
      slug TEXT NOT NULL,
      description TEXT,
      photo TEXT,
      country_id TEXT,
      city_id TEXT,
      starts_at TEXT NOT NULL,
      ends_at TEXT,
      is_free INTEGER NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT 'en_attente',
      scheduled_deletion_at TEXT,
      community_id TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      sync_status TEXT NOT NULL DEFAULT 'synced',
      sync_error TEXT)''');

    // 2. event_activities
    await db.execute('''CREATE TABLE IF NOT EXISTS event_activities (
      id TEXT PRIMARY KEY,
      event_id TEXT NOT NULL,
      activity_id TEXT NOT NULL,
      price REAL NOT NULL DEFAULT 0.0,
      added_by TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      sync_status TEXT NOT NULL DEFAULT 'synced',
      sync_error TEXT)''');

    // 3. event_tickets
    await db.execute('''CREATE TABLE IF NOT EXISTS event_tickets (
      id TEXT PRIMARY KEY,
      event_id TEXT NOT NULL,
      name TEXT NOT NULL,
      price REAL NOT NULL DEFAULT 0.0,
      currency_code TEXT NOT NULL DEFAULT 'XAF',
      created_at TEXT NOT NULL,
      sync_status TEXT NOT NULL DEFAULT 'synced',
      sync_error TEXT)''');

    // 4. event_likes
    await db.execute('''CREATE TABLE IF NOT EXISTS event_likes (
      user_id TEXT NOT NULL,
      event_id TEXT NOT NULL,
      created_at TEXT NOT NULL,
      sync_status TEXT NOT NULL DEFAULT 'synced',
      sync_error TEXT,
      PRIMARY KEY(user_id, event_id))''');

    // 5. event_calendar
    await db.execute('''CREATE TABLE IF NOT EXISTS event_calendar (
      user_id TEXT NOT NULL,
      event_id TEXT NOT NULL,
      created_at TEXT NOT NULL,
      sync_status TEXT NOT NULL DEFAULT 'synced',
      sync_error TEXT,
      PRIMARY KEY(user_id, event_id))''');

    // 6. event_co_creators
    await db.execute('''CREATE TABLE IF NOT EXISTS event_co_creators (
      id TEXT PRIMARY KEY,
      event_id TEXT NOT NULL,
      user_id TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'en_attente',
      invited_by TEXT NOT NULL,
      created_at TEXT NOT NULL,
      responded_at TEXT,
      sync_status TEXT NOT NULL DEFAULT 'synced',
      sync_error TEXT)''');

    // 7. event_staff
    await db.execute('''CREATE TABLE IF NOT EXISTS event_staff (
      id TEXT PRIMARY KEY,
      event_id TEXT NOT NULL,
      user_id TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'en_attente',
      invited_by TEXT NOT NULL,
      created_at TEXT NOT NULL,
      responded_at TEXT,
      sync_status TEXT NOT NULL DEFAULT 'synced',
      sync_error TEXT)''');

    // 8. event_staff_activities
    await db.execute('''CREATE TABLE IF NOT EXISTS event_staff_activities (
      event_staff_id TEXT NOT NULL,
      activity_id TEXT NOT NULL,
      PRIMARY KEY(event_staff_id, activity_id))''');

    // 9. event_checkins
    await db.execute('''CREATE TABLE IF NOT EXISTS event_checkins (
      id TEXT PRIMARY KEY,
      event_id TEXT NOT NULL,
      user_id TEXT NOT NULL,
      validated_by_user_id TEXT NOT NULL,
      parent_checkin_id TEXT,
      status TEXT NOT NULL DEFAULT 'valid',
      activity_id TEXT,
      invalidated_reason TEXT,
      created_at TEXT NOT NULL,
      sync_status TEXT NOT NULL DEFAULT 'synced',
      sync_error TEXT)''');

    // 10. event_transfers
    await db.execute('''CREATE TABLE IF NOT EXISTS event_transfers (
      id TEXT PRIMARY KEY,
      event_id TEXT NOT NULL,
      proposed_by TEXT NOT NULL,
      proposed_to TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'en_attente',
      created_at TEXT NOT NULL,
      responded_at TEXT,
      sync_status TEXT NOT NULL DEFAULT 'synced',
      sync_error TEXT)''');

    // 11. event_interests
    await db.execute('''CREATE TABLE IF NOT EXISTS event_interests (
      event_id TEXT NOT NULL,
      interest_id TEXT NOT NULL,
      PRIMARY KEY(event_id, interest_id))''');

    // Legacy compatibility wrappers
    await db.execute('''CREATE TABLE IF NOT EXISTS evenements_locaux (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      donnees TEXT NOT NULL,
      statut_sync TEXT NOT NULL DEFAULT 'en_attente',
      erreur TEXT,
      created_at TEXT NOT NULL)''');
    
    await db.execute('''CREATE TABLE IF NOT EXISTS activites_locales (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      evenement_id TEXT,
      donnees TEXT NOT NULL,
      statut_sync TEXT NOT NULL DEFAULT 'en_attente',
      erreur TEXT,
      created_at TEXT NOT NULL)''');

    await db.execute('''CREATE TABLE IF NOT EXISTS billets_locaux (
      id TEXT PRIMARY KEY,
      evenement_id TEXT NOT NULL,
      donnees TEXT NOT NULL,
      statut_sync TEXT NOT NULL DEFAULT 'en_attente',
      erreur TEXT,
      created_at TEXT NOT NULL)''');
    
    await db.execute('''CREATE TABLE IF NOT EXISTS staff_locaux (
      id TEXT PRIMARY KEY,
      evenement_id TEXT NOT NULL,
      user_id TEXT NOT NULL,
      donnees TEXT NOT NULL,
      statut_sync TEXT NOT NULL DEFAULT 'en_attente',
      erreur TEXT,
      created_at TEXT NOT NULL)''');

    // Outbox & Sync Cursors
    await db.execute('''CREATE TABLE IF NOT EXISTS event_outbox (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id TEXT NOT NULL,
      event_id TEXT NOT NULL,
      table_name TEXT NOT NULL,
      operation TEXT NOT NULL,
      payload TEXT NOT NULL,
      attempts INTEGER NOT NULL DEFAULT 0,
      last_error TEXT,
      created_at TEXT NOT NULL)''');

    await db.execute('''CREATE TABLE IF NOT EXISTS event_sync_cursors (
      table_name TEXT PRIMARY KEY,
      last_synced_at TEXT NOT NULL)''');
  }

  Future<void> _createNotificationDeletionTable(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS deleted_notifications (
      user_id TEXT NOT NULL, notification_id TEXT NOT NULL, deleted_at INTEGER NOT NULL,
      PRIMARY KEY(user_id, notification_id))''');
  }

  Future<void> _createCommunityTables(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS communities (
      id TEXT PRIMARY KEY, name TEXT NOT NULL, slug TEXT NOT NULL, description TEXT,
      avatar_url TEXT, banner_url TEXT, visibility TEXT NOT NULL, status TEXT NOT NULL,
      member_count INTEGER NOT NULL DEFAULT 0, cached_at INTEGER NOT NULL, created_at INTEGER NOT NULL DEFAULT 0)''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_communities_slug ON communities(slug)',
    );
    await db.execute('DROP TABLE IF EXISTS community_settings');
    await db.execute(
      '''CREATE TABLE community_settings (
      community_id TEXT PRIMARY KEY REFERENCES communities(id) ON DELETE CASCADE,
      post_permission TEXT NOT NULL DEFAULT 'everyone',
      posts_require_approval INTEGER NOT NULL DEFAULT 0,
      members_list_visible INTEGER NOT NULL DEFAULT 0,
      allow_reports INTEGER NOT NULL DEFAULT 1,
      allow_comments INTEGER NOT NULL DEFAULT 1,
      allow_reactions INTEGER NOT NULL DEFAULT 1)''',
    );
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS community_roles (
      id TEXT PRIMARY KEY, community_id TEXT NOT NULL REFERENCES communities(id) ON DELETE CASCADE, name TEXT NOT NULL)''',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_roles_community ON community_roles(community_id)',
    );
    await db.execute('''CREATE TABLE IF NOT EXISTS community_members (
      id TEXT PRIMARY KEY, community_id TEXT NOT NULL REFERENCES communities(id) ON DELETE CASCADE,
      user_id TEXT NOT NULL, role_id TEXT, status TEXT NOT NULL, cached_at INTEGER NOT NULL)''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_members_community ON community_members(community_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_members_user ON community_members(user_id)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_members_unique ON community_members(community_id,user_id)',
    );
    await db.execute('''CREATE TABLE IF NOT EXISTS posts (
      id TEXT PRIMARY KEY,
      community_id TEXT,
      author_id TEXT NOT NULL,
      content TEXT,
      media TEXT,
      status TEXT NOT NULL DEFAULT 'confirmed',
      cached_at INTEGER NOT NULL,
      created_at INTEGER NOT NULL)''');

    await db.execute('''CREATE TABLE IF NOT EXISTS post_outbox (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      operation_id TEXT NOT NULL,
      user_id TEXT NOT NULL,
      community_id TEXT,
      operation_type TEXT NOT NULL,
      payload TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'pending',
      attempt_count INTEGER NOT NULL DEFAULT 0,
      next_retry_at INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL)''');
  }

  Future<void> _createNotificationTable(Database db) async {
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS notifications (
      id TEXT PRIMARY KEY, user_id TEXT NOT NULL, title TEXT NOT NULL, message TEXT NOT NULL,
      type TEXT NOT NULL, created_at INTEGER NOT NULL, is_read INTEGER NOT NULL DEFAULT 0, 
      payload TEXT, action_status TEXT NOT NULL DEFAULT "pending")''',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_notifications_user_created ON notifications(user_id,created_at DESC)',
    );
  }

  Future<void> _createMessagingTables(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS direct_chat_conversations (
      user_id TEXT NOT NULL, id TEXT NOT NULL, name TEXT, avatar_url TEXT, participant_ids TEXT NOT NULL,
      last_message TEXT, updated_at INTEGER NOT NULL, is_group INTEGER NOT NULL DEFAULT 0,
      unread_count INTEGER NOT NULL DEFAULT 0, is_pinned INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY(user_id,id))''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_direct_chat_conversations_updated ON direct_chat_conversations(user_id,updated_at DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_direct_chat_conversations_pinned ON direct_chat_conversations(user_id,is_pinned,updated_at DESC)',
    );
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS direct_chat_messages (
      user_id TEXT NOT NULL, id TEXT NOT NULL, local_id TEXT NOT NULL DEFAULT '', conversation_id TEXT NOT NULL,
      sender_id TEXT NOT NULL, text TEXT, media_urls TEXT, audio_url TEXT, audio_duration_seconds INTEGER,
      type TEXT NOT NULL, created_at INTEGER NOT NULL, status TEXT NOT NULL, replied_to_id TEXT, deleted_at INTEGER,
      deleted_silently INTEGER NOT NULL DEFAULT 0, edited_at INTEGER, edited_silently INTEGER NOT NULL DEFAULT 0,
      deleted_for_me INTEGER NOT NULL DEFAULT 0, sender_is_certified_at_deletion INTEGER, PRIMARY KEY(user_id,id))''',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_direct_chat_messages_conversation ON direct_chat_messages(user_id,conversation_id,created_at DESC)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_direct_chat_messages_local_id ON direct_chat_messages(user_id,local_id)',
    );
    await db.execute('''CREATE TABLE IF NOT EXISTS direct_chat_outbox (
      user_id TEXT NOT NULL, id TEXT NOT NULL, conversation_id TEXT NOT NULL, payload TEXT NOT NULL,
      attempts INTEGER NOT NULL DEFAULT 0, last_error TEXT, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
      PRIMARY KEY(user_id,id))''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_direct_chat_outbox_pending ON direct_chat_outbox(user_id,created_at)',
    );
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS direct_chat_contacts (
      user_id TEXT NOT NULL, contact_id TEXT NOT NULL, name TEXT NOT NULL, username TEXT NOT NULL, avatar_url TEXT,
      is_online INTEGER NOT NULL DEFAULT 0, is_certified INTEGER NOT NULL DEFAULT 0, updated_at INTEGER NOT NULL, PRIMARY KEY(user_id,contact_id))''',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_direct_chat_contacts_user_name ON direct_chat_contacts(user_id,name)',
    );
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS direct_chat_read_cursors (
      user_id TEXT NOT NULL, conversation_id TEXT NOT NULL, last_read_at INTEGER,
      last_read_message_id TEXT, updated_at INTEGER NOT NULL, PRIMARY KEY(user_id,conversation_id))''',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_direct_chat_read_cursors_conversation ON direct_chat_read_cursors(user_id,conversation_id,last_read_at)',
    );
  }

  Future<void> _createMessageDeletionTable(Database db) async {
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS direct_chat_deleted_messages (
      user_id TEXT NOT NULL, message_id TEXT NOT NULL, local_id TEXT,
      conversation_id TEXT NOT NULL, deleted_at INTEGER NOT NULL,
      PRIMARY KEY(user_id,message_id))''',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_direct_chat_deleted_messages_local ON direct_chat_deleted_messages(user_id,local_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_direct_chat_deleted_messages_conversation ON direct_chat_deleted_messages(user_id,conversation_id)',
    );
  }

  Future<void> _createMediaCacheTable(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS direct_chat_media_cache (
      user_id TEXT NOT NULL, message_id TEXT NOT NULL, remote_ref TEXT NOT NULL,
      local_path TEXT NOT NULL, downloaded INTEGER NOT NULL DEFAULT 0, sha256 TEXT, downloaded_at INTEGER,
      PRIMARY KEY(user_id,message_id,remote_ref))''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_direct_chat_media_cache_message ON direct_chat_media_cache(user_id,message_id)',
    );
  }

  Future<void> _createDiscoveryCacheTable(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS discovery_cache (
      key TEXT PRIMARY KEY,
      payload TEXT NOT NULL,
      cached_at INTEGER NOT NULL)''');
  }

  Future<void> _createNotificationOutboxTable(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS notification_outbox (
      user_id TEXT NOT NULL,
      notification_id TEXT NOT NULL,
      action_type TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      attempts INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY(user_id, notification_id, action_type))''');
  }

  Future<void> _createSocialTables(Database db) async {
    // 1. friendships
    await db.execute('''CREATE TABLE IF NOT EXISTS friendships (
      user_a_id TEXT NOT NULL,
      user_b_id TEXT NOT NULL,
      created_at TEXT NOT NULL,
      sync_status TEXT NOT NULL DEFAULT 'synced',
      PRIMARY KEY (user_a_id, user_b_id)
    )''');

    // 2. friend_requests
    await db.execute('''CREATE TABLE IF NOT EXISTS friend_requests (
      id TEXT PRIMARY KEY,
      sender_id TEXT NOT NULL,
      receiver_id TEXT NOT NULL,
      status TEXT NOT NULL,
      attempt_count INTEGER NOT NULL DEFAULT 1,
      next_retry_at TEXT,
      created_at TEXT NOT NULL,
      responded_at TEXT,
      sync_status TEXT NOT NULL DEFAULT 'synced',
      sync_error TEXT
    )''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_fr_receiver ON friend_requests(receiver_id, status)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_fr_sender ON friend_requests(sender_id, status)');

    // 3. blocked_users
    await db.execute('''CREATE TABLE IF NOT EXISTS blocked_users (
      id TEXT PRIMARY KEY,
      bloque_id TEXT NOT NULL,
      raison TEXT,
      bloque_jusquau TEXT,
      statut INTEGER NOT NULL DEFAULT 1,
      bloque_le TEXT NOT NULL,
      sync_status TEXT NOT NULL DEFAULT 'synced'
    )''');

    // 4. user_qr_codes
    await db.execute('''CREATE TABLE IF NOT EXISTS user_qr_codes (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      uses_remaining INTEGER NOT NULL,
      created_at TEXT NOT NULL,
      sync_status TEXT NOT NULL DEFAULT 'synced'
    )''');

    // 5. people (subset of user_profiles)
    await db.execute('''CREATE TABLE IF NOT EXISTS people (
      user_id TEXT PRIMARY KEY,
      username TEXT,
      first_name TEXT,
      last_name TEXT,
      photo_url TEXT,
      is_verified INTEGER,
      account_status TEXT,
      deleted_at TEXT,
      fetched_at TEXT
    )''');

    // 6. social_outbox
    await db.execute('''CREATE TABLE IF NOT EXISTS social_outbox (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id TEXT NOT NULL,
      operation TEXT NOT NULL,
      payload TEXT NOT NULL,
      attempts INTEGER NOT NULL DEFAULT 0,
      last_error TEXT,
      created_at TEXT NOT NULL
    )''');
  }

  Future<void> clearUserData(String userId) async {
    final db = await database;
    await db.transaction((txn) async {
      // Tables avec user_id
      await txn.delete('notifications', where: 'user_id = ?', whereArgs: [userId]);
      await txn.delete('direct_chat_conversations', where: 'user_id = ?', whereArgs: [userId]);
      await txn.delete('direct_chat_messages', where: 'user_id = ?', whereArgs: [userId]);
      await txn.delete('direct_chat_outbox', where: 'user_id = ?', whereArgs: [userId]);
      await txn.delete('direct_chat_contacts', where: 'user_id = ?', whereArgs: [userId]);
      await txn.delete('direct_chat_read_cursors', where: 'user_id = ?', whereArgs: [userId]);
      await txn.delete('direct_chat_deleted_messages', where: 'user_id = ?', whereArgs: [userId]);
      await txn.delete('deleted_notifications', where: 'user_id = ?', whereArgs: [userId]);
      await txn.delete('direct_chat_media_cache', where: 'user_id = ?', whereArgs: [userId]);
      await txn.delete('community_members', where: 'user_id = ?', whereArgs: [userId]);
      
      // Note: On peut garder la table 'communities' car elle est globale, 
      // mais on a supprimé l'appartenance de l'utilisateur via community_members.
    });
    // Salon conversations live in their own SQLite file; purge that file's
    // account-scoped rows as part of the same logout/account-switch workflow.
    await SalonChatDatabase.instance.clearUserData(userId);
    debugPrint('[Database] Données locales purgées pour l\'utilisateur : $userId');
  }

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}
