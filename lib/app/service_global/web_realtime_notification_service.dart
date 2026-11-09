import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../modules/module_authentification/centre/services/auth_service.dart';
import '../../modules/module_notification/centre/services/notification_db_service.dart';

/// Browser notification history/realtime delivery.
///
/// Push notifications are intentionally separate: they require Firebase Web
/// credentials, a VAPID key and a registered service worker. This service
/// keeps the in-app notification centre live without depending on native APIs.
class WebRealtimeNotificationService extends GetxService {
  RealtimeChannel? _channel;
  Worker? _authWorker;
  String? _subscribedUserId;

  Future<WebRealtimeNotificationService> init() async {
    final auth = Get.find<AuthService>();
    _authWorker = ever(auth.currentUser, (user) {
      final id = auth.userId;
      if (id == null) {
        unawaited(_unsubscribe());
      } else if (id != _subscribedUserId) {
        unawaited(_subscribe(id));
      }
    });
    final userId = auth.userId;
    if (userId != null) await _subscribe(userId);
    return this;
  }

  Future<void> _subscribe(String userId) async {
    if (_subscribedUserId == userId && _channel != null) return;
    await _unsubscribe();
    final client = Supabase.instance.client;
    final db = Get.find<NotificationDbService>();

    _channel = client.channel('web_notifications_$userId')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'notifications',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'user_id',
          value: userId,
        ),
        callback: (payload) async {
          await _saveIncoming(db, userId, payload.newRecord);
        },
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'notifications',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'user_id',
          value: userId,
        ),
        callback: (payload) async {
          final row = payload.newRecord;
          final id = row['id']?.toString();
          if (id == null || id.isEmpty || row['read_at'] == null) return;
          await db.syncRemoteReadState(id: id, userId: userId, isRead: true);
        },
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.delete,
        schema: 'public',
        table: 'notifications',
        callback: (payload) async {
          final id = payload.oldRecord['id']?.toString();
          if (id != null && id.isNotEmpty) {
            await db.syncRemoteDeletion(id: id, userId: userId);
          }
        },
      )
      .subscribe((status, error) {
        if (error != null) {
          debugPrint('[WebNotifications] Realtime error: $error');
        }
      });
    _subscribedUserId = userId;
  }

  Future<void> _saveIncoming(
    NotificationDbService db,
    String userId,
    Map<String, dynamic> row,
  ) async {
    final id = row['id']?.toString();
    if (id == null || id.isEmpty) return;

    // Confirm the canonical row still exists and has not already been read.
    // This prevents a delayed INSERT event from restoring stale notifications.
    try {
      final current = await Supabase.instance.client
          .from('notifications')
          .select('read_at')
          .eq('id', id)
          .eq('user_id', userId)
          .maybeSingle();
      if (current == null) {
        await db.syncRemoteDeletion(id: id, userId: userId);
        return;
      }
      final rawData = row['data'];
      final data = rawData is Map
          ? Map<String, dynamic>.from(rawData)
          : <String, dynamic>{};
      final type = row['type']?.toString() ?? 'info';
      final payload = jsonEncode({
        ...data,
        'type': type,
        'notification_id': id,
        if (row['actor_id'] != null) 'actor_id': row['actor_id'],
      });
      await db.saveNotification(
        id: id,
        userId: userId,
        title: row['title']?.toString() ?? 'Scrole',
        message: row['body']?.toString() ?? '',
        type: type,
        payload: payload,
        createdAt: DateTime.tryParse(row['created_at']?.toString() ?? ''),
        isRead: current['read_at'] != null,
      );
    } catch (error) {
      debugPrint('[WebNotifications] Unable to persist notification: $error');
    }
  }

  Future<void> _unsubscribe() async {
    final channel = _channel;
    _channel = null;
    _subscribedUserId = null;
    if (channel != null) {
      await Supabase.instance.client.removeChannel(channel);
    }
  }

  @override
  void onClose() {
    _authWorker?.dispose();
    unawaited(_unsubscribe());
    super.onClose();
  }
}
