import 'dart:async';
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../models/message.dart';
import 'messaging_database.dart';
import 'media_local_cache.dart';

class MessagesDao {
  MessagesDao(this._database, [MediaLocalCache? mediaCache]) : _mediaCache = mediaCache ?? MediaLocalCache(_database.db);
  final MessagingDatabase _database;
  final MediaLocalCache _mediaCache;
  final StreamController<String> _changes = StreamController<String>.broadcast();
  Future<Database> get _db => _database.database;
  Future<void> init() => _database.ensureSchema();

  Stream<List<Message>> watchConversation(String userId, String conversationId) async* {
    await init();
    yield await getConversation(userId, conversationId);
    await for (final key in _changes.stream.where((v) => v == '$userId:$conversationId')) yield await getConversation(userId, conversationId);
  }

  Future<List<Message>> getConversation(String userId, String conversationId) async {
    final db = await _db;
    final deletedAt = await _conversationDeletedAt(userId, conversationId);
    final args = <dynamic>[userId, conversationId];
    var where = 'user_id = ? AND conversation_id = ? AND deleted_for_me = 0 AND deleted_at IS NULL';
    if (deletedAt != null) {
      where += ' AND created_at > ?';
      args.add(deletedAt);
    }
    final rows = await db.query('direct_chat_messages', where: where, whereArgs: args, orderBy: 'created_at DESC');
    return rows.map(_fromRow).toList();
  }

  Future<DateTime?> latestSentAt(String userId, String conversationId) async {
    final db = await _db;
    final deletedAt = await _conversationDeletedAt(userId, conversationId);
    final args = <dynamic>[userId, conversationId];
    var where = 'user_id = ? AND conversation_id = ?';
    if (deletedAt != null) { where += ' AND created_at > ?'; args.add(deletedAt); }
    final rows = await db.query('direct_chat_messages', columns: ['created_at'], where: where, whereArgs: args, orderBy: 'created_at DESC', limit: 1);
    return rows.isEmpty ? null : DateTime.fromMillisecondsSinceEpoch((rows.first['created_at'] as num).toInt(), isUtc: true);
  }

  Future<Message?> getById(String userId, String messageId) async {
    final db = await _db;
    final rows = await db.query('direct_chat_messages', where: 'user_id=? AND id=?', whereArgs: [userId, messageId], limit: 1);
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  Future<bool> isDeletedForMe(String userId, String messageId, {String? localId}) async {
    final db = await _db;
    final rows = await db.query('direct_chat_deleted_messages', columns: ['message_id'], where: localId == null ? 'user_id=? AND message_id=?' : 'user_id=? AND (message_id=? OR local_id=?)', whereArgs: localId == null ? [userId, messageId] : [userId, messageId, localId], limit: 1);
    return rows.isNotEmpty;
  }

  Future<int?> _conversationDeletedAt(String userId, String conversationId) async {
    final db = await _db;
    final rows = await db.query('direct_chat_deleted_conversations', columns: ['deleted_at'], where: 'user_id=? AND conversation_id=?', whereArgs: [userId, conversationId], limit: 1);
    return rows.isEmpty ? null : (rows.first['deleted_at'] as num).toInt();
  }

  Future<void> upsert(String userId, Message message) async {
    final db = await _db;
    if (await isDeletedForMe(userId, message.id, localId: message.localId)) {
      await _mediaCache.deleteMessageMedia(userId, message.id);
      if (message.localId != message.id) await _mediaCache.deleteMessageMedia(userId, message.localId);
      return;
    }
    final conversationDeletedAt = await _conversationDeletedAt(userId, message.conversationId);
    if (conversationDeletedAt != null && message.sentAt.millisecondsSinceEpoch <= conversationDeletedAt) {
      await _mediaCache.deleteMessageMedia(userId, message.id);
      if (message.localId != message.id) await _mediaCache.deleteMessageMedia(userId, message.localId);
      return;
    }
    // Les synchronisations serveur/Realtime peuvent renvoyer un ancien état
    // ("sent") après un accusé de réception ("delivered"/"read"). Ne jamais
    // faire régresser un accusé déjà enregistré localement.
    final existing = await db.query(
      'direct_chat_messages',
      columns: ['id', 'local_id', 'status'],
      where: 'user_id = ? AND (id = ? OR local_id = ?)',
      whereArgs: [userId, message.id, message.localId],
      limit: 1,
    );
    var incoming = message;
    if (existing.isNotEmpty) {
      final previousId = '${existing.first['id']}';
      final previousLocalId = '${existing.first['local_id'] ?? existing.first['id']}';
      final previousStatus = _status('${existing.first['status']}');
      if (previousStatus == MessageStatus.read &&
          message.status != MessageStatus.failed &&
          message.status != MessageStatus.error) {
        incoming = message.copyWith(status: MessageStatus.read, localId: previousLocalId);
      } else if ((previousStatus == MessageStatus.delivered ||
                  previousStatus == MessageStatus.received) &&
          message.status != MessageStatus.read &&
          message.status != MessageStatus.failed &&
          message.status != MessageStatus.error) {
        incoming = message.copyWith(status: MessageStatus.delivered, localId: previousLocalId);
      } else if (previousStatus == MessageStatus.sent &&
          (message.status == MessageStatus.pending ||
           message.status == MessageStatus.sending)) {
        incoming = message.copyWith(status: MessageStatus.sent, localId: previousLocalId);
      }
      if (previousId != message.id) {
        await db.delete('direct_chat_messages',
            where: 'user_id = ? AND id = ?', whereArgs: [userId, previousId]);
      }
    }
    await db.insert('direct_chat_messages', _toRow(userId, incoming), conflictAlgorithm: ConflictAlgorithm.replace);
    _changes.add('$userId:${message.conversationId}');
  }

  Future<void> deleteForMe(String userId, String messageId) async {
    final db = await _db;
    final rows = await db.query('direct_chat_messages', columns: ['conversation_id', 'local_id'], where: 'user_id=? AND id=?', whereArgs: [userId, messageId], limit: 1);
    if (rows.isEmpty) {
      await _insertDeletionTombstone(userId, messageId: messageId, localId: null, conversationId: '');
      return;
    }
    final conversationId = '${rows.first['conversation_id']}';
    final localId = '${rows.first['local_id'] ?? messageId}';
    await _insertDeletionTombstone(userId, messageId: messageId, localId: localId, conversationId: conversationId);
    await db.delete('direct_chat_messages', where: 'user_id=? AND id=?', whereArgs: [userId, messageId]);
    await _mediaCache.deleteMessageMedia(userId, messageId);
    if (localId.isNotEmpty && localId != messageId) await _mediaCache.deleteMessageMedia(userId, localId);
    await refreshConversationPreview(userId, conversationId);
    _changes.add('$userId:$conversationId');
  }

  Future<void> _insertDeletionTombstone(String userId, {required String messageId, required String? localId, required String conversationId}) async {
    final db = await _db;
    await db.insert('direct_chat_deleted_messages', {'user_id': userId, 'message_id': messageId, 'local_id': localId, 'conversation_id': conversationId, 'deleted_at': DateTime.now().toUtc().millisecondsSinceEpoch}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> removeSilently(String userId, String messageId) async {
    final db = await _db;
    final rows = await db.query('direct_chat_messages', columns: ['conversation_id'], where: 'user_id=? AND id=?', whereArgs: [userId, messageId], limit: 1);
    await db.delete('direct_chat_messages', where: 'user_id=? AND id=?', whereArgs: [userId, messageId]);
    await _mediaCache.deleteMessageMedia(userId, messageId);
    if (rows.isNotEmpty) {
      final conversationId = '${rows.first['conversation_id']}';
      await refreshConversationPreview(userId, conversationId);
      _changes.add('$userId:$conversationId');
    }
  }

  Future<void> removeByIds(String userId, Iterable<String> messageIds) async {
    for (final id in messageIds.where((id) => id.isNotEmpty).toSet()) await removeSilently(userId, id);
  }

  Future<Message?> latestVisibleMessage(String userId, String conversationId) async {
    if (conversationId.isEmpty) return null;
    final db = await _db;
    final deletedAt = await _conversationDeletedAt(userId, conversationId);
    final args = <dynamic>[userId, conversationId];
    var where = 'user_id=? AND conversation_id=? AND deleted_for_me=0 AND deleted_at IS NULL';
    if (deletedAt != null) {
      where += ' AND created_at > ?';
      args.add(deletedAt);
    }
    final rows = await db.query('direct_chat_messages', where: where, whereArgs: args, orderBy: 'created_at DESC', limit: 1);
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  Future<int> refreshConversationPreview(String userId, String conversationId, {bool clearIfEmpty = true}) async {
    if (conversationId.isEmpty) return 0;
    final lastMessage = await latestVisibleMessage(userId, conversationId);
    if (lastMessage == null && !clearIfEmpty) return 0;
    final values = <String, dynamic>{
      'last_message': lastMessage == null ? null : jsonEncode(lastMessage.toJson()),
    };
    if (lastMessage != null) {
      values['updated_at'] = lastMessage.sentAt.millisecondsSinceEpoch;
    }
    final db = await _db;
    return db.update('direct_chat_conversations', values, where: 'user_id=? AND id=?', whereArgs: [userId, conversationId]);
  }

  Future<int> unreadCount(String userId, String conversationId, DateTime? after) async {
    final db = await _db;
    final deletedAt = await _conversationDeletedAt(userId, conversationId);
    final args = <dynamic>[userId, conversationId, userId, (after ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)).millisecondsSinceEpoch];
    var where = 'user_id=? AND conversation_id=? AND deleted_for_me=0 AND sender_id<>? AND deleted_at IS NULL AND created_at>?';
    if (deletedAt != null) { where += ' AND created_at>?'; args.add(deletedAt); }
    final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM direct_chat_messages WHERE $where', args);
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  Map<String, dynamic> _toRow(String userId, Message m) => {
    'user_id': userId, 'id': m.id, 'local_id': m.localId, 'conversation_id': m.conversationId, 'sender_id': m.senderId,
    'text': m.content, 'media_urls': m.mediaUrls == null ? null : jsonEncode(m.mediaUrls), 'audio_url': m.audioUrl,
    'audio_duration_seconds': m.audioDuration?.inSeconds, 'type': m.type.name, 'created_at': m.sentAt.millisecondsSinceEpoch,
    'status': m.status.name, 'replied_to_id': m.repliedToId, 'deleted_at': m.deletedAt?.millisecondsSinceEpoch,
    'deleted_silently': m.deletedSilently ? 1 : 0, 'edited_at': m.editedAt?.millisecondsSinceEpoch, 'edited_silently': 0,
    'deleted_for_me': m.deletedForMe ? 1 : 0, 'sender_is_certified_at_deletion': m.senderIsCertifiedAtDeletion == null ? null : (m.senderIsCertifiedAtDeletion! ? 1 : 0),
  };

  Message _fromRow(Map<String, dynamic> row) => Message(
    id: '${row['id']}', localId: '${row['local_id'] ?? row['id']}', conversationId: '${row['conversation_id']}', senderId: '${row['sender_id']}',
    content: row['text'] as String?, mediaUrls: _parseMediaUrls(row['media_urls']), audioUrl: row['audio_url'] as String?,
    audioDuration: row['audio_duration_seconds'] == null ? null : Duration(seconds: (row['audio_duration_seconds'] as num).toInt()), type: MessageType.values.firstWhere((e) => e.name == row['type'], orElse: () => MessageType.text),
    sentAt: DateTime.fromMillisecondsSinceEpoch((row['created_at'] as num).toInt(), isUtc: true), status: _status('${row['status']}'),
    editedAt: row['edited_at'] == null ? null : DateTime.fromMillisecondsSinceEpoch((row['edited_at'] as num).toInt(), isUtc: true), deletedAt: row['deleted_at'] == null ? null : DateTime.fromMillisecondsSinceEpoch((row['deleted_at'] as num).toInt(), isUtc: true),
    deletedForMe: row['deleted_for_me'] == 1, isDeletedForEveryone: row['deleted_at'] != null, senderIsCertifiedAtDeletion: row['sender_is_certified_at_deletion'] == null ? null : row['sender_is_certified_at_deletion'] == 1, repliedToId: row['replied_to_id'] as String?,
  );

  List<String>? _parseMediaUrls(dynamic value) {
    if (value == null) return null;
    if (value is List) return value.map((e) => '$e').where((e) => e.isNotEmpty).toList();
    try {
      final decoded = jsonDecode('$value');
      if (decoded is List) return decoded.map((e) => '$e').where((e) => e.isNotEmpty).toList();
    } catch (_) {}
    return null;
  }

  MessageStatus _status(String value) => switch (value) { 'pending' || 'sending' => MessageStatus.pending, 'delivered' || 'received' => MessageStatus.delivered, 'read' => MessageStatus.read, 'failed' || 'error' => MessageStatus.failed, _ => MessageStatus.sent };
}
