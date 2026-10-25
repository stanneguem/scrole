import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../app/local_storage/structured/app_cache_database.dart';
import '../../../../app/service_global/connectivity_service.dart';
import '../services/chat_media_cache.dart';
import '../persistence/conversations_dao.dart';
import '../persistence/messages_dao.dart';
import '../persistence/messaging_database.dart';
import '../persistence/media_local_cache.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../models/messaging_result.dart';
import '../../externe/services/supabase_messaging_service.dart';

class MessagingRepository {
  MessagingRepository(this._db, this._remote) {
    _database = MessagingDatabase(_db);
    _mediaCache = MediaLocalCache(_db);
    _messages = MessagesDao(_database, _mediaCache);
    _conversations = ConversationsDao(_database);
  }

  final AppDatabase _db;
  final SupabaseMessagingService _remote;
  late final MessagingDatabase _database;
  late final MediaLocalCache _mediaCache;
  late final MessagesDao _messages;
  late final ConversationsDao _conversations;

  final Map<String, StreamController<bool>> _typingControllers = {};
  final Map<String, RealtimeChannel> _typingChannels = {};
  final Map<String, RealtimeChannel> _messageChannels = {};
  final Map<String, bool> _messageSubscribedOnce = {};
  final Map<String, int> _conversationViewers = {};
  RealtimeChannel? _inboxChannel;
  bool _inboxSubscribedOnce = false;
  StreamSubscription? _connectivitySubscription;
  bool _outboxRunning = false;

  String? get currentUserId => _remote.currentUserId;

  Future<String?> resolveLocalMedia(String messageId, String remoteUrl) async {
    final uid = currentUserId;
    if (uid == null) return null;
    return ChatMediaCache.instance.localPathFor(remoteUrl);
  }

  Future<MessagingResult<String>> cacheMedia(String messageId, String remoteUrl) async {
    final uid = currentUserId;
    if (uid == null) return const MessagingResult.failure('not_authenticated', 'Utilisateur non authentifié.');
    if (remoteUrl.isEmpty) return const MessagingResult.failure('invalid_media', 'Média invalide.');
    try {
      final path = await ChatMediaCache.instance.resolveLocalPath(remoteUrl);
      if (path != null) {
        return MessagingResult.success(path);
      }
      return const MessagingResult.failure('media_download_failed', 'Impossible de mettre en cache le média.');
    } catch (e) {
      return MessagingResult.failure('media_download_failed', e.toString());
    }
  }

  Future<void> initialize() async {
    await _database.ensureSchema();
    try {
      final connectivity = Get.find<ConnectivityService>();
      _connectivitySubscription = connectivity.onStatusChange.listen((status) {
        if (status == InternetStatus.connected) unawaited(_syncAfterReconnect());
      });
    } catch (_) {}
    _ensureInboxRealtime();
    unawaited(processOutbox());
  }

  Stream<List<Message>> watchConversation(String id) {
    final uid = currentUserId;
    if (uid == null || id.isEmpty || id.startsWith('draft_')) return const Stream.empty();
    
    _conversationViewers[id] = (_conversationViewers[id] ?? 0) + 1;
    _ensureMessageRealtime(id);
    
    return _messages.watchConversation(uid, id);
  }

  Future<void> stopWatchingConversation(String id) async {
    if (id.isEmpty || id.startsWith('draft_')) return;
    final viewers = (_conversationViewers[id] ?? 1) - 1;
    if (viewers <= 0) {
      _conversationViewers.remove(id);
      final typing = _typingChannels.remove(id);
      if (typing != null) await _remote.unsubscribe(typing);
      final msg = _messageChannels.remove(id);
      if (msg != null) await _remote.unsubscribe(msg);
      _typingControllers.remove(id)?.close();
    } else {
      _conversationViewers[id] = viewers;
    }
  }

  Stream<List<Conversation>> watchConversationsList() {
    final uid = currentUserId;
    if (uid == null) return const Stream.empty();
    _ensureInboxRealtime();
    return _conversations.watchAll(uid);
  }

  Stream<int> watchGlobalUnreadCount() async* {
    final uid = currentUserId;
    if (uid == null) {
      yield 0;
      return;
    }
    yield await _conversations.unreadCountSum(uid);
    await for (final _ in _conversations.watchAll(uid)) {
      yield await _conversations.unreadCountSum(uid);
    }
  }

  Future<Conversation?> getLocalConversationWithUser(String otherUserId) async {
    final uid = currentUserId;
    if (uid == null || otherUserId.isEmpty) return null;
    return _conversations.getByOtherUser(uid, otherUserId);
  }

  Future<MessagingResult<Conversation>> resolveConversationForFirstMessage(
    String otherUserId,
    String currentConversationId, {
    String? otherUserName,
    String? otherUserAvatar,
  }) async {
    final uid = currentUserId;
    if (uid == null) return const MessagingResult.failure('not_authenticated', 'Utilisateur non authentifié.');
    if (otherUserId.isEmpty) return const MessagingResult.failure('invalid_user', 'Utilisateur invalide.');

    if (!currentConversationId.startsWith('draft_')) {
      final local = await _conversations.getByOtherUser(uid, otherUserId);
      if (local != null) return MessagingResult.success(local);
      return const MessagingResult.failure('conversation_not_found', 'Conversation introuvable.');
    }

    try {
      final connected = Get.isRegistered<ConnectivityService>()
          ? await Get.find<ConnectivityService>().checkConnection()
          : await InternetConnection().hasInternetAccess;
      if (!connected) return const MessagingResult.failure('offline_conversation_unavailable', 'Cette nouvelle discussion nécessite une connexion Internet.');

      return await _persistPeerConversation(
        uid,
        otherUserId,
        otherUserName: otherUserName,
        otherUserAvatar: otherUserAvatar,
      );
    } catch (e) {
      return MessagingResult.failure('conversation_failed', e.toString());
    }
  }

  Future<MessagingResult<Conversation>> getOrCreateConversation(
    String otherUserId, {
    String? otherUserName,
    String? otherUserAvatar,
  }) async {
    final uid = currentUserId;
    if (uid == null) return const MessagingResult.failure('not_authenticated', 'Utilisateur non authentifié.');
    if (otherUserId.isEmpty) return const MessagingResult.failure('invalid_user', 'Utilisateur invalide.');
    // Opening a contact must never create a server conversation. Creation is
    // deferred to resolveConversationForFirstMessage(), called by send actions.
    final existing = await _conversations.getByOtherUser(uid, otherUserId);
    if (existing == null || existing.lastMessagePreview == null) {
      return const MessagingResult.failure(
        'conversation_not_found',
        'Aucune conversation existante. Envoyez un premier message pour la créer.',
      );
    }
    return MessagingResult.success(existing);
  }

  Future<MessagingResult<Conversation>> _persistPeerConversation(
    String uid,
    String otherUserId, {
    String? otherUserName,
    String? otherUserAvatar,
  }) async {
    final conversation = await _remote.getOrCreateConversation(otherUserId);
    if (conversation == null) {
      return const MessagingResult.failure('conversation_failed', 'Impossible de créer la conversation.');
    }

    final db = await _db.database;
    await db.delete(
      'direct_chat_deleted_conversations',
      where: 'user_id=? AND conversation_id=?',
      whereArgs: [uid, conversation.id],
    );

    final persisted = conversation.copyWith(
      participantIds: [otherUserId],
      name: _usablePeerName(conversation.name) ?? _usablePeerName(otherUserName),
      avatarUrl: _usablePeerName(conversation.avatarUrl) ?? otherUserAvatar,
    );
    await _conversations.upsert(uid, persisted);
    return MessagingResult.success(persisted);
  }

  String? _usablePeerName(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    final lower = trimmed.toLowerCase();
    if (lower == 'chat' || lower == 'ami') return null;
    return trimmed;
  }

  Future<MessagingResult<void>> syncConversations() async {
    final uid = currentUserId;
    if (uid == null) return const MessagingResult.failure('not_authenticated', 'Utilisateur non authentifié.');
    try {
      _ensureInboxRealtime();
      await _conversations.replaceAll(uid, await _remote.fetchConversations());
      await _reconcileLocalPreviews(uid);
      await _restoreDeletedConversations(uid);
      return const MessagingResult.success();
    } catch (e) {
      return MessagingResult.failure('sync_failed', e.toString());
    }
  }

  Future<MessagingResult<void>> syncConversation(String id) async {
    final uid = currentUserId;
    if (uid == null) return const MessagingResult.failure('not_authenticated', 'Utilisateur non authentifié.');
    if (id.isEmpty || id.startsWith('draft_')) return const MessagingResult.success();
    
    try {
      // Stratégie robuste : on récupère les 50 derniers messages pour combler d'éventuels "trous"
      // (par rapport à une simple récupération "après le dernier timestamp")
      final list = await _remote.fetchMessages(id, limit: 50);
      
      if (list.isNotEmpty) {
        for (final m in list) {
          await _applyIncoming(uid, m);
        }
      }
      return const MessagingResult.success();
    } catch (e) {
      debugPrint('[Messaging] Sync failed for conversation $id: $e');
      return MessagingResult.failure('sync_failed', e.toString());
    }
  }

  Future<void> _syncAfterReconnect() async {
    final uid = currentUserId;
    if (uid == null) return;
    try {
      await syncConversations();
      for (final c in await _conversations.getAll(uid)) {
        await syncConversation(c.id);
      }
      await processOutbox();
    } catch (_) {}
  }

  Future<MessagingResult<bool>> toggleConversationPinned(String conversationId) async {
    final uid = currentUserId;
    if (uid == null) return const MessagingResult.failure('not_authenticated', 'Utilisateur non authentifié.');
    if (conversationId.isEmpty) return const MessagingResult.failure('invalid_conversation', 'Conversation invalide.');
    try {
      final pinned = await _conversations.togglePinned(uid, conversationId);
      return MessagingResult.success(pinned);
    } catch (e) {
      return MessagingResult.failure('pin_failed', e.toString());
    }
  }

  Future<MessagingResult<void>> deleteConversation(String conversationId) async {
    final uid = currentUserId;
    if (uid == null) return const MessagingResult.failure('not_authenticated', 'Utilisateur non authentifié.');
    if (conversationId.isEmpty) return const MessagingResult.failure('invalid_conversation', 'Conversation invalide.');
    try {
      await _conversations.deleteConversation(uid, conversationId);
      await _remote.deleteConversationForMe(conversationId);
      return const MessagingResult.success();
    } catch (e) {
      return MessagingResult.failure('delete_conversation_failed', e.toString());
    }
  }

  Future<MessagingResult<Message>> sendMessage(Message message) async {
    final uid = currentUserId;
    if (uid == null) return const MessagingResult.failure('not_authenticated', 'Utilisateur non authentifié.');
    final pending = message.copyWith(status: MessageStatus.pending);
    try {
      await _messages.upsert(uid, pending);
      await _enqueueOutbox(uid, pending);
      try {
        final remote = await _remote.insertMessage(pending);
        if (remote == null) return const MessagingResult.failure('send_failed', 'Le serveur n’a pas confirmé le message.');
        final result = remote.copyWith(localId: pending.localId, status: MessageStatus.sent);
        await _messages.upsert(uid, result);
        await _removeOutbox(uid, pending.localId);
        await _refreshConversationList(uid, result.conversationId);
        return MessagingResult.success(result);
      } catch (e) {
        await _markOutboxFailure(uid, pending.localId, e.toString());
        await _messages.upsert(uid, pending.copyWith(status: MessageStatus.failed));
        return MessagingResult.failure('send_failed', e.toString());
      }
    } catch (e) {
      return const MessagingResult.failure('cache_write_failed', 'Impossible d’enregistrer le message localement.');
    }
  }

  Future<MessagingResult<Message>> sendMediaMessage(Message message) async {
    final uid = currentUserId;
    if (uid == null) return const MessagingResult.failure('not_authenticated', 'Utilisateur non authentifié.');
    final pending = message.copyWith(status: MessageStatus.pending);
    try {
      await _messages.upsert(uid, pending);
      final originalMediaUrls = message.mediaUrls;
      final originalAudioUrl = message.audioUrl;

      final prepared = await _prepareMedia(pending);
      if (prepared == null) {
        await _messages.upsert(uid, pending.copyWith(status: MessageStatus.failed));
        return const MessagingResult.failure('media_upload_failed', 'Impossible de téléverser le média.');
      }

      if (originalMediaUrls != null && prepared.mediaUrls != null) {
        for (var i = 0; i < originalMediaUrls.length; i++) {
          if (i < prepared.mediaUrls!.length) {
            await ChatMediaCache.instance.saveLocalToSandbox(prepared.mediaUrls![i], originalMediaUrls[i]);
          }
        }
      }
      if (originalAudioUrl != null && prepared.audioUrl != null) {
        await ChatMediaCache.instance.saveLocalToSandbox(prepared.audioUrl!, originalAudioUrl);
      }

      return sendMessage(prepared);
    } catch (e) {
      await _messages.upsert(uid, pending.copyWith(status: MessageStatus.failed));
      return MessagingResult.failure('media_upload_failed', e.toString());
    }
  }

  Future<Message?> _prepareMedia(Message m) async {
    var media = m.mediaUrls;
    if (media != null) {
      final out = <String>[];
      for (final path in media) {
        if (_isRemote(path)) {
          out.add(path);
        } else {
          final url = await _remote.uploadFile(path, 'media', contentType: _mime(path), conversationId: m.conversationId);
          if (url == null) return null;
          out.add(url);
        }
      }
      media = out;
    }
    var audio = m.audioUrl;
    if (audio != null && audio.isNotEmpty && !_isRemote(audio)) {
      audio = await _remote.uploadFile(audio, 'audio', contentType: _mime(audio), conversationId: m.conversationId);
    }
    if (m.audioUrl != null && audio == null) return null;
    return m.copyWith(mediaUrls: media, audioUrl: audio);
  }

  bool _isRemote(String v) =>
      ChatMediaCache.isHttpUrl(v) || ChatMediaCache.isStorageKey(v);

  String _mime(String p) {
    final e = p.split('.').last.toLowerCase();
    return switch (e) {
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      'mp4' => 'video/mp4',
      'mov' => 'video/quicktime',
      'webm' => 'video/webm',
      'm4a' => 'audio/mp4',
      'aac' => 'audio/aac',
      'wav' => 'audio/wav',
      'mp3' => 'audio/mpeg',
      _ => 'application/octet-stream'
    };
  }

  Future<MessagingResult<Message>> editMessage(String id, String content) async {
    final uid = currentUserId;
    if (uid == null) return const MessagingResult.failure('not_authenticated', 'Utilisateur non authentifié.');
    final cached = await _findMessage(uid, id);
    if (cached == null) return const MessagingResult.failure('not_found', 'Message introuvable.');
    if (cached.senderId != uid) return const MessagingResult.failure('forbidden', 'Vous ne pouvez pas modifier ce message.');
    if (DateTime.now().toUtc().difference(cached.sentAt.toUtc()) >= const Duration(minutes: 5)) {
      return const MessagingResult.failure('edit_window_expired', 'Le délai de modification est expiré.');
    }
    try {
      final updated = await _remote.editMessage(id, content.trim());
      if (updated == null) return const MessagingResult.failure('edit_failed', 'Modification refusée par le serveur.');
      final r = updated.copyWith(localId: cached.localId);
      await _messages.upsert(uid, r);
      await _refreshConversationList(uid, r.conversationId);
      return MessagingResult.success(r);
    } catch (e) {
      return MessagingResult.failure('edit_failed', e.toString());
    }
  }

  Future<MessagingResult<void>> deleteForMe(String id) async {
    final uid = currentUserId;
    if (uid == null) return const MessagingResult.failure('not_authenticated', 'Utilisateur non authentifié.');
    final cached = await _findMessage(uid, id);
    if (cached == null) return const MessagingResult.failure('not_found', 'Message introuvable.');
    try {
      if (cached.audioUrl != null) await ChatMediaCache.instance.removeLocal(cached.audioUrl!);
      if (cached.mediaUrls != null) {
        for (final m in cached.mediaUrls!) {
          await ChatMediaCache.instance.removeLocal(m);
        }
      }
      await _messages.deleteForMe(uid, id);
      await _refreshConversationList(uid, cached.conversationId);
      return const MessagingResult.success();
    } catch (e) {
      return MessagingResult.failure('delete_for_me_failed', e.toString());
    }
  }

  Future<MessagingResult<Message>> deleteForEveryone(String id) async {
    final uid = currentUserId;
    if (uid == null) return const MessagingResult.failure('not_authenticated', 'Utilisateur non authentifié.');
    final cached = await _findMessage(uid, id);
    if (cached == null) return const MessagingResult.failure('not_found', 'Message introuvable.');
    if (cached.senderId != uid) return const MessagingResult.failure('forbidden', 'Seul l’auteur peut supprimer ce message.');
    if (DateTime.now().toUtc().difference(cached.sentAt.toUtc()) >= const Duration(minutes: 5)) {
      return const MessagingResult.failure('delete_window_expired', 'Le délai de suppression est expiré.');
    }
    try {
      final deleted = await _remote.deleteForEveryone(id);
      if (deleted == null) return const MessagingResult.failure('delete_failed', 'Suppression refusée par le serveur.');
      final r = deleted.copyWith(localId: cached.localId, isDeletedForEveryone: true, deletedAt: deleted.deletedAt ?? DateTime.now().toUtc());
      await _applyIncoming(uid, r);
      return MessagingResult.success(r);
    } catch (e) {
      return MessagingResult.failure('delete_failed', e.toString());
    }
  }

  Future<(DateTime?, String?)?> getLocalReadCursor(String id) async {
    final uid = currentUserId;
    if (uid == null) return null;
    final db = await _db.database;
    final rows = await db.query('direct_chat_read_cursors', columns: ['last_read_at', 'last_read_message_id'], where: 'user_id=? AND conversation_id=?', whereArgs: [uid, id], limit: 1);
    if (rows.isEmpty) return null;
    final r = rows.first;
    return (
      r['last_read_at'] == null ? null : DateTime.fromMillisecondsSinceEpoch((r['last_read_at'] as num).toInt(), isUtc: true),
      r['last_read_message_id']?.toString()
    );
  }

  Future<MessagingResult<void>> markConversationRead(String conversationId, String messageId, DateTime at) async {
    final uid = currentUserId;
    if (uid == null) return const MessagingResult.failure('not_authenticated', 'Utilisateur non authentifié.');
    try {
      final db = await _db.database;
      final now = DateTime.now().toUtc();
      
      // 1. Mise à jour locale immédiate (Cursor de lecture)
      await db.insert('direct_chat_read_cursors', {
        'user_id': uid,
        'conversation_id': conversationId,
        'last_read_at': at.toUtc().millisecondsSinceEpoch,
        'last_read_message_id': messageId,
        'updated_at': now.millisecondsSinceEpoch
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      // 2. Recalcul local du compteur de non-lus
      await _conversations.setUnread(uid, conversationId, await _messages.unreadCount(uid, conversationId, at));

      // 3. Tentative de synchronisation distante
      try {
        await _remote.markRead(conversationId, at, messageId);
        // Si succès, on s'assure qu'aucun outbox "read" ne traîne pour cette conv
        await _removeOutbox(uid, 'read_cursor:$conversationId');
      } catch (e) {
        // 4. En cas d'échec (offline), on met en file d'attente (Outbox)
        debugPrint('[Messaging] MarkRead failed, enqueuing for sync: $e');
        await _enqueueReadCursorOutbox(uid, conversationId, messageId, at);
      }
      
      return const MessagingResult.success();
    } catch (e) {
      return MessagingResult.failure('read_failed', e.toString());
    }
  }

  Future<void> _enqueueReadCursorOutbox(String uid, String conversationId, String messageId, DateTime at) async {
    final db = await _db.database;
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final payload = {
      'type': 'read_cursor',
      'conversation_id': conversationId,
      'message_id': messageId,
      'at': at.toUtc().toIso8601String(),
    };
    await db.insert('direct_chat_outbox', {
      'user_id': uid,
      'id': 'read_cursor:$conversationId', // Un seul curseur par conversation dans l'outbox
      'conversation_id': conversationId,
      'payload': jsonEncode(payload),
      'attempts': 0,
      'created_at': now,
      'updated_at': now
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Stream<bool> watchTyping(String id) {
    if (id.startsWith('draft_')) return const Stream.empty();
    final c = _typingControllers.putIfAbsent(id, () => StreamController<bool>.broadcast());
    if (!_typingChannels.containsKey(id)) {
      _typingChannels[id] = _remote.subscribeTyping(id, (value) {
        // Presence events may arrive while the channel is being removed.
        // Never emit into a stream that has already been closed or replaced.
        if (!c.isClosed && identical(_typingControllers[id], c)) {
          c.add(value);
        }
      });
    }
    return c.stream;
  }

  Future<MessagingResult<void>> setTyping(String id, bool typing) async {
    if (id.startsWith('draft_')) return const MessagingResult.success();
    try {
      final controller = _typingControllers.putIfAbsent(
        id,
        () => StreamController<bool>.broadcast(),
      );
      final ch = _typingChannels[id] ??= _remote.subscribeTyping(id, (value) {
        if (!controller.isClosed &&
            identical(_typingControllers[id], controller)) {
          controller.add(value);
        }
      });
      await _remote.sendTyping(ch, typing);
      return const MessagingResult.success();
    } catch (e) {
      return MessagingResult.failure('typing_failed', e.toString());
    }
  }

  Future<void> processOutbox() async {
    final uid = currentUserId;
    if (uid == null || _outboxRunning) return;
    _outboxRunning = true;
    try {
      final db = await _db.database;
      final rows = await db.query('direct_chat_outbox', where: 'user_id=? AND attempts < 5', whereArgs: [uid], orderBy: 'created_at ASC');
      
      for (final row in rows) {
        final payloadRaw = row['payload'] as String;
        final id = row['id'] as String;
        
        try {
          final payload = jsonDecode(payloadRaw);
          
          if (payload is Map && payload['type'] == 'read_cursor') {
            // Traitement d'un accusé de lecture
            final convId = payload['conversation_id'];
            final msgId = payload['message_id'];
            final at = DateTime.parse(payload['at']);
            await _remote.markRead(convId, at, msgId);
            await _removeOutbox(uid, id);
          } else {
            // Traitement d'un message classique
            final m = Message.fromJson(Map<String, dynamic>.from(payload as Map));
            final remote = await _remote.insertMessage(m);
            if (remote == null) throw Exception('send_failed');
            await _messages.upsert(uid, remote.copyWith(localId: m.localId, status: MessageStatus.sent));
            await _removeOutbox(uid, m.localId);
            await _refreshConversationList(uid, m.conversationId);
          }
        } catch (e) {
          debugPrint('[Messaging] Outbox item $id failed: $e');
          await _markOutboxFailure(uid, id, e.toString());
        }
      }
    } finally {
      _outboxRunning = false;
    }
  }

  Future<MessagingResult<void>> retryMessage(String localId) async {
    final uid = currentUserId;
    if (uid == null) return const MessagingResult.failure('not_authenticated', 'Utilisateur non authentifié.');
    try {
      final db = await _db.database;
      await db.update('direct_chat_outbox', {'attempts': 0, 'last_error': null, 'updated_at': DateTime.now().toUtc().millisecondsSinceEpoch}, where: 'user_id=? AND id=?', whereArgs: [uid, localId]);
      await db.update('direct_chat_messages', {'status': MessageStatus.pending.name}, where: 'user_id=? AND local_id=?', whereArgs: [uid, localId]);
      unawaited(processOutbox());
      return const MessagingResult.success();
    } catch (e) {
      return MessagingResult.failure('retry_failed', e.toString());
    }
  }

  void _ensureInboxRealtime() {
    if (_inboxChannel != null || currentUserId == null) return;
    
    // On passe le callback onStatus à la méthode subscribeInbox
    _inboxChannel = _remote.subscribeInbox(
      onMessage: (m) {
        final uid = currentUserId;
        if (uid != null) unawaited(_applyIncoming(uid, m));
      },
      onDeleted: (messageId) {
        final uid = currentUserId;
        if (uid != null) unawaited(_applyRemoteDeletion(uid, messageId));
      },
      onStatus: (status, error) async {
        if (status == RealtimeSubscribeStatus.subscribed) {
          if (_inboxSubscribedOnce) {
            // Reconnexion : on rattrape la liste des conversations
            await syncConversations();
          }
          _inboxSubscribedOnce = true;
        }
      },
    );
  }

  Future<void> dispose() async {
    _connectivitySubscription?.cancel();
    _inboxChannel?.unsubscribe();
    _inboxChannel = null;
    
    for (final ch in _typingChannels.values) {
      await _remote.unsubscribe(ch);
    }
    _typingChannels.clear();
    
    for (final ch in _messageChannels.values) {
      await _remote.unsubscribe(ch);
    }
    _messageChannels.clear();
    
    for (final controller in _typingControllers.values) {
      await controller.close();
    }
    _typingControllers.clear();
    _conversationViewers.clear();
  }

  void _ensureMessageRealtime(String id) {
    _ensureInboxRealtime();
    if (_messageChannels.containsKey(id)) return;
    
    final channel = _remote.subscribeMessages(
      id, 
      (m) {
        final uid = currentUserId;
        if (uid != null) unawaited(_applyIncoming(uid, m));
      }, 
      onDeleted: (messageId) {
        final uid = currentUserId;
        if (uid != null) unawaited(_applyRemoteDeletion(uid, messageId));
      }, 
      onReceipt: (receipt) {
        final uid = currentUserId;
        if (uid != null) unawaited(_applyReceipt(uid, receipt));
      },
      onStatus: (status, error) async {
        if (status == RealtimeSubscribeStatus.subscribed) {
          if (_messageSubscribedOnce[id] == true) {
            // Reconnexion : on rattrape les messages manqués de cette conversation
            await syncConversation(id);
          }
          _messageSubscribedOnce[id] = true;
        }
      },
    );

    _messageChannels[id] = channel;
  }

  Future<void> handlePushWake(String? conversationId) async {
    final uid = currentUserId;
    if (uid == null) return;
    _ensureInboxRealtime();
    
    if (conversationId != null && conversationId.isNotEmpty) {
      // Synchro ciblée sur une conversation
      await syncConversation(conversationId);
      await _restoreDeletedConversation(uid, conversationId);
    } else {
      // Synchro globale (ex: retour au premier plan)
      await syncConversations();
      final all = await _conversations.getAll(uid);
      for (final c in all) {
        // On récupère les messages manqués pour chaque conversation
        unawaited(syncConversation(c.id));
      }
    }
  }

  Future<void> _applyReceipt(String uid, Map<String, dynamic> receipt) async {
    final messageId = receipt['message_id']?.toString();
    final receiptUserId = receipt['user_id']?.toString();
    if (messageId == null || messageId.isEmpty || receiptUserId == null || receiptUserId == uid) return;
    final cached = await _findMessage(uid, messageId);
    if (cached == null || cached.senderId != uid) return;
    final readAt = receipt['read_at'];
    final deliveredAt = receipt['delivered_at'];
    final status = readAt != null ? MessageStatus.read : deliveredAt != null ? MessageStatus.delivered : cached.status;
    if (status == cached.status) return;
    await _messages.upsert(uid, cached.copyWith(status: status));
  }

  Future<void> _applyIncoming(String uid, Message m) async {
    final deleted = await _conversations.deletedAt(uid, m.conversationId);
    if (deleted != null && m.sentAt.millisecondsSinceEpoch > deleted) {
      final db = await _db.database;
      await db.delete('direct_chat_deleted_conversations', where: 'user_id=? AND conversation_id=?', whereArgs: [uid, m.conversationId]);
    } else if (deleted != null) {
      return;
    }

    final local = await _findByLocalId(uid, m.localId);
    final r = local != null ? m.copyWith(localId: local.localId) : m;
    if (r.isDeletedForEveryone && r.senderIsCertifiedAtDeletion == true) {
      await _applyRemoteDeletion(uid, r.id);
      return;
    }
    await _messages.upsert(uid, r);
    await _ensureConversationFromIncoming(uid, r);
    await _refreshConversationList(uid, r.conversationId);
    if (r.senderId != uid && r.status != MessageStatus.read) {
      // Cache attachments on the recipient device before recording delivery;
      // recording the receipt allows the backend to delete the R2 objects.
      unawaited(_cacheIncomingMediaThenAcknowledge(r));
    }
  }

  Future<void> _cacheIncomingMediaThenAcknowledge(Message message) async {
    final refs = <String>[
      ...(message.mediaUrls ?? const <String>[]),
      if (message.audioUrl != null && message.audioUrl!.isNotEmpty) message.audioUrl!,
    ];
    for (final ref in refs) {
      try {
        final localPath = await ChatMediaCache.instance.resolveLocalPath(ref);
        if (localPath == null) {
          debugPrint('[Messaging] Waiting for media cache before delivery receipt: ${message.id}');
          return;
        }
      } catch (error) {
        debugPrint('[Messaging] Media cache failed before delivery receipt: $error');
        return;
      }
    }
    try {
      await _remote.markDelivered(message.id, cleanupMedia: refs.isNotEmpty);
    } catch (error) {
      debugPrint('[Messaging] Delivery acknowledgement failed: $error');
    }
  }

  Future<void> _applyRemoteDeletion(String uid, String messageId) async {
    final cached = await _messages.getById(uid, messageId);
    await _messages.removeSilently(uid, messageId);
    if (cached != null) await _refreshConversationList(uid, cached.conversationId);
  }

  Future<void> _ensureConversationFromIncoming(String uid, Message m) async {
    if (await _conversations.getById(uid, m.conversationId) != null) return;
    final otherId = m.senderId == uid ? null : m.senderId;
    if (otherId != null && otherId.isNotEmpty) {
      try {
        await _persistPeerConversation(uid, otherId);
        return;
      } catch (_) {}
    }
    await _conversations.upsert(
      uid,
      Conversation(
        id: m.conversationId,
        participantIds: [if (otherId != null && otherId.isNotEmpty) otherId],
        lastMessagePreview: m.isDeleted ? null : m,
        updatedAt: m.sentAt,
      ),
    );
  }

  Future<void> _refreshConversationList(String uid, String conversationId) async {
    await _messages.refreshConversationPreview(uid, conversationId);
    final cursor = await getLocalReadCursor(conversationId);
    await _conversations.setUnread(uid, conversationId, await _messages.unreadCount(uid, conversationId, cursor?.$1));
  }

  Future<void> _reconcileLocalPreviews(String uid) async {
    for (final conversation in await _conversations.getAll(uid)) {
      final serverLast = conversation.lastMessagePreview;
      final deletedLocally = serverLast != null && await _messages.isDeletedForMe(uid, serverLast.id, localId: serverLast.localId);
      await _messages.refreshConversationPreview(uid, conversation.id, clearIfEmpty: deletedLocally);
    }
    _conversations.emit(uid);
  }

  Future<void> _restoreDeletedConversations(String uid) async {
    for (final row in await _conversations.deletedConversations(uid)) {
      await _restoreDeletedConversation(uid, '${row['conversation_id']}', row: row);
    }
  }

  Future<void> _restoreDeletedConversation(String uid, String conversationId, {Map<String, dynamic>? row}) async {
    if (conversationId.isEmpty) return;
    var marker = row;
    if (marker == null) {
      for (final item in await _conversations.deletedConversations(uid)) {
        if ('${item['conversation_id']}' == conversationId) {
          marker = item;
          break;
        }
      }
    }
    if (marker == null) return;
    final deletedAt = DateTime.fromMillisecondsSinceEpoch((marker['deleted_at'] as num).toInt(), isUtc: true);
    final otherUserId = marker['other_user_id']?.toString();
    var missed = <Message>[];
    try {
      missed = await _remote.fetchMissedMessages(conversationId, deletedAt);
    } catch (_) {}
    if (missed.isEmpty && otherUserId != null && otherUserId.isNotEmpty) {
      missed = await _missedAfterRejoin(conversationId, otherUserId, deletedAt);
    }
    for (final m in missed) {
      await _applyIncoming(uid, m);
    }
  }

  Future<List<Message>> _missedAfterRejoin(
    String conversationId,
    String otherUserId,
    DateTime deletedAt,
  ) async {
    try {
      await _remote.getOrCreateConversation(otherUserId);
      return await _remote.fetchMissedMessages(conversationId, deletedAt);
    } catch (_) {
      return const [];
    }
  }

  Future<Message?> _findMessage(String uid, String id) async => _messages.getById(uid, id);

  Future<Message?> _findByLocalId(String uid, String localId) async {
    if (localId.isEmpty) return null;
    try {
      final db = await _db.database;
      final rows = await db.query('direct_chat_messages', where: 'user_id=? AND local_id=?', whereArgs: [uid, localId], limit: 1);
      return rows.isEmpty ? null : await _messages.getById(uid, '${rows.first['id']}');
    } catch (_) {
      return null;
    }
  }

  Future<void> _enqueueOutbox(String uid, Message m) async {
    final db = await _db.database;
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await db.insert('direct_chat_outbox', {
      'user_id': uid,
      'id': m.localId,
      'conversation_id': m.conversationId,
      'payload': jsonEncode(m.toJson()),
      'attempts': 0,
      'created_at': now,
      'updated_at': now
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _removeOutbox(String uid, String localId) async {
    final db = await _db.database;
    await db.delete('direct_chat_outbox', where: 'user_id=? AND id=?', whereArgs: [uid, localId]);
  }

  Future<void> _markOutboxFailure(String uid, String id, String error) async {
    final db = await _db.database;
    await db.rawUpdate('UPDATE direct_chat_outbox SET attempts=attempts+1,last_error=?,updated_at=? WHERE user_id=? AND id=?', [
      error,
      DateTime.now().toUtc().millisecondsSinceEpoch,
      uid,
      id
    ]);
    final updated = await db.query('direct_chat_outbox', columns: ['attempts'], where: 'user_id=? AND id=?', whereArgs: [uid, id]);
    if (updated.isNotEmpty && (updated.first['attempts'] as num).toInt() >= 5) {
      await db.update('direct_chat_messages', {'status': MessageStatus.failed.name}, where: 'user_id=? AND local_id=?', whereArgs: [uid, id]);
    }
  }

  String generateLocalId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // Version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // Variant IETF
    String hex(int b) => b.toRadixString(16).padLeft(2, '0');
    final chars = bytes.map(hex).join();
    return '${chars.substring(0, 8)}-${chars.substring(8, 12)}-${chars.substring(12, 16)}-${chars.substring(16, 20)}-${chars.substring(20, 32)}';
  }
}
