import 'dart:async';
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import 'messaging_database.dart';

class ConversationsDao {
  ConversationsDao(this._database);
  final MessagingDatabase _database;
  final StreamController<String> _changes = StreamController<String>.broadcast();
  Future<Database> get _db => _database.database;

  Stream<List<Conversation>> watchAll(String userId) async* {
    await _database.ensureSchema();
    yield await getAll(userId);
    await for (final changedUser in _changes.stream.where((id) => id == userId)) yield await getAll(changedUser);
  }

  Future<List<Conversation>> getAll(String userId) async {
    final db = await _db;
    final rows = await db.query('direct_chat_conversations', where: 'user_id=?', whereArgs: [userId], orderBy: 'is_pinned DESC, updated_at DESC');
    return rows.map(_fromRow).toList();
  }

  Future<Conversation?> getByOtherUser(String userId, String otherUserId) async {
    if (userId.isEmpty || otherUserId.isEmpty) return null;
    for (final conversation in await getAll(userId)) {
      if (!conversation.isGroup && conversation.lastMessagePreview != null && conversation.participantIds.contains(otherUserId)) return conversation;
    }
    return null;
  }

  Future<Conversation?> getById(String userId, String conversationId) async {
    final db = await _db;
    final rows = await db.query('direct_chat_conversations', where: 'user_id=? AND id=?', whereArgs: [userId, conversationId], limit: 1);
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  Future<int?> deletedAt(String userId, String conversationId) async {
    final db = await _db;
    final rows = await db.query('direct_chat_deleted_conversations', columns: ['deleted_at'], where: 'user_id=? AND conversation_id=?', whereArgs: [userId, conversationId], limit: 1);
    return rows.isEmpty ? null : (rows.first['deleted_at'] as num).toInt();
  }

  Future<List<Map<String, dynamic>>> deletedConversations(String userId) async {
    final db = await _db;
    return db.query('direct_chat_deleted_conversations', where: 'user_id=?', whereArgs: [userId]);
  }

  Future<bool> isDeletedLocally(String userId, String conversationId) async => await deletedAt(userId, conversationId) != null;

  Future<void> upsert(String userId, Conversation conversation) async {
    final deleted = await deletedAt(userId, conversation.id);
    if (deleted != null && conversation.updatedAt.millisecondsSinceEpoch <= deleted) return;
    final db = await _db;
    final existing = await db.query(
      'direct_chat_conversations',
      columns: ['is_pinned', 'name', 'avatar_url', 'participant_ids'],
      where: 'user_id=? AND id=?',
      whereArgs: [userId, conversation.id],
      limit: 1,
    );
    final pinned = existing.isNotEmpty ? existing.first['is_pinned'] == 1 : conversation.isPinned;
    final name = _nonEmpty(conversation.name) ??
        (existing.isEmpty ? null : _nonEmpty(existing.first['name']?.toString()));
    final avatar = _nonEmpty(conversation.avatarUrl) ??
        (existing.isEmpty ? null : _nonEmpty(existing.first['avatar_url']?.toString()));
    var participants = conversation.participantIds.where((id) => id.isNotEmpty && id != userId).toList();
    if (participants.isEmpty && existing.isNotEmpty) {
      final raw = existing.first['participant_ids'];
      if (raw is String && raw.isNotEmpty) {
        participants = List<String>.from(jsonDecode(raw)).where((id) => id.isNotEmpty && id != userId).toList();
      }
    }
    final message = conversation.lastMessagePreview;
    // Never create/reintroduce an inbox row without a visible message.
    if (message == null) return;
    await db.insert('direct_chat_conversations', {
      'user_id': userId, 'id': conversation.id, 'name': name, 'avatar_url': avatar,
      'participant_ids': jsonEncode(participants), 'last_message': message == null ? null : jsonEncode(message.toJson()),
      'updated_at': conversation.updatedAt.millisecondsSinceEpoch, 'is_group': conversation.isGroup ? 1 : 0,
      'unread_count': conversation.unreadCount, 'is_pinned': pinned ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    _changes.add(userId);
  }

  Future<void> replaceAll(String userId, List<Conversation> conversations) async {
    final db = await _db;
    final previous = await db.query('direct_chat_conversations', columns: ['id', 'is_pinned'], where: 'user_id=? AND is_pinned=1', whereArgs: [userId]);
    final pinnedIds = {for (final row in previous) '${row['id']}'};
    await db.transaction((txn) async {
      await txn.delete('direct_chat_conversations', where: 'user_id=?', whereArgs: [userId]);
      for (final conversation in conversations) {
        // The server inbox should contain only conversations with a visible message.
        if (conversation.lastMessagePreview == null) continue;
        final marker = await txn.query('direct_chat_deleted_conversations', columns: ['deleted_at'], where: 'user_id=? AND conversation_id=?', whereArgs: [userId, conversation.id], limit: 1);
        if (marker.isNotEmpty) {
          final deletedAt = (marker.first['deleted_at'] as num).toInt();
          final activityAt = conversation.lastMessagePreview?.sentAt ?? conversation.updatedAt;
          if (activityAt.millisecondsSinceEpoch <= deletedAt && conversation.unreadCount <= 0) continue;
        }
        final message = conversation.lastMessagePreview;
        final pinned = pinnedIds.contains(conversation.id) || conversation.isPinned;
        final participants = conversation.participantIds.where((id) => id.isNotEmpty && id != userId).toList();
        await txn.insert('direct_chat_conversations', {
          'user_id': userId, 'id': conversation.id, 'name': conversation.name, 'avatar_url': conversation.avatarUrl,
          'participant_ids': jsonEncode(participants), 'last_message': message == null ? null : jsonEncode(message.toJson()),
          'updated_at': conversation.updatedAt.millisecondsSinceEpoch, 'is_group': conversation.isGroup ? 1 : 0,
          'unread_count': conversation.unreadCount, 'is_pinned': pinned ? 1 : 0,
        });
      }
    });
    _changes.add(userId);
  }

  Future<bool> togglePinned(String userId, String conversationId) async {
    final db = await _db;
    final rows = await db.query('direct_chat_conversations', columns: ['is_pinned'], where: 'user_id=? AND id=?', whereArgs: [userId, conversationId], limit: 1);
    if (rows.isEmpty) return false;
    final next = rows.first['is_pinned'] != 1;
    await db.update('direct_chat_conversations', {'is_pinned': next ? 1 : 0}, where: 'user_id=? AND id=?', whereArgs: [userId, conversationId]);
    _changes.add(userId);
    return next;
  }

  Future<bool> isPinned(String userId, String conversationId) async {
    final db = await _db;
    final rows = await db.query('direct_chat_conversations', columns: ['is_pinned'], where: 'user_id=? AND id=?', whereArgs: [userId, conversationId], limit: 1);
    return rows.isNotEmpty && rows.first['is_pinned'] == 1;
  }

  Future<void> setUnread(String userId, String conversationId, int count) async {
    final db = await _db;
    await db.update('direct_chat_conversations', {'unread_count': count}, where: 'user_id=? AND id=?', whereArgs: [userId,conversationId]);
    _changes.add(userId);
  }

  Future<int> unreadCountSum(String userId) async {
    final db = await _db;
    final rows = await db.rawQuery('SELECT SUM(unread_count) as total FROM direct_chat_conversations WHERE user_id = ?', [userId]);
    return (rows.first['total'] as num?)?.toInt() ?? 0;
  }

  Future<void> deleteConversation(String userId, String conversationId) async {
    if (conversationId.isEmpty) return;
    final db = await _db;
    await db.transaction((txn) async {
      final existing = await txn.query('direct_chat_conversations', where: 'user_id=? AND id=?', whereArgs: [userId, conversationId], limit: 1);
      String? otherUserId;
      String? name;
      String? avatarUrl;
      if (existing.isNotEmpty) {
        final conversation = _fromRow(existing.first);
        otherUserId = conversation.peerId(userId);
        name = conversation.name;
        avatarUrl = conversation.avatarUrl;
      }
      await txn.insert('direct_chat_deleted_conversations', {
        'user_id': userId,
        'conversation_id': conversationId,
        'deleted_at': DateTime.now().toUtc().millisecondsSinceEpoch,
        'other_user_id': otherUserId,
        'name': name,
        'avatar_url': avatarUrl,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.delete('direct_chat_messages', where: 'user_id=? AND conversation_id=?', whereArgs: [userId, conversationId]);
      await txn.delete('direct_chat_outbox', where: 'user_id=? AND conversation_id=?', whereArgs: [userId, conversationId]);
      await txn.delete('direct_chat_read_cursors', where: 'user_id=? AND conversation_id=?', whereArgs: [userId, conversationId]);
      await txn.delete('direct_chat_conversations', where: 'user_id=? AND id=?', whereArgs: [userId, conversationId]);
    });
    _changes.add(userId);
  }

  void emit(String userId) => _changes.add(userId);

  String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    final lower = trimmed.toLowerCase();
    if (lower == 'chat' || lower == 'ami') return null;
    return trimmed;
  }

  Conversation _fromRow(Map<String, dynamic> row) {
    final last = row['last_message'];
    return Conversation(
      id: '${row['id']}', participantIds: List<String>.from(jsonDecode(row['participant_ids'] as String)),
      lastMessagePreview: last == null ? null : Message.fromJson(Map<String,dynamic>.from(jsonDecode(last) as Map)),
      unreadCount: (row['unread_count'] as num?)?.toInt() ?? 0,
      updatedAt: DateTime.fromMillisecondsSinceEpoch((row['updated_at'] as num).toInt(), isUtc: true),
      name: row['name'] as String?, avatarUrl: row['avatar_url'] as String?, isGroup: row['is_group'] == 1, isPinned: row['is_pinned'] == 1,
    );
  }
}
