import 'package:get/get.dart';
import '../../../../app/service_global/supabse_service.dart';
import '../../centre/models/remote_notification_model.dart';

class NotificationRepository {
  final _client = Get.find<SupabaseService>().client;

  Future<List<RemoteNotificationModel>> getMyNotifications({int limit = 50}) async {
    final response = await _client.rpc(
      'get_my_notifications',
      params: {'p_limit': limit},
    );

    if (response is! List) return const [];

    return response
        .whereType<Map>()
        .map((item) => RemoteNotificationModel.fromJson(
              Map<String, dynamic>.from(item),
            ))
        .toList();
  }

  Future<void> markAsRead(String notificationId) async {
    await _client.rpc(
      'mark_notification_read',
      params: {'p_notification_id': notificationId},
    );
  }

  Future<void> deleteNotification(String notificationId) async {
    await _client.rpc(
      'delete_notification',
      params: {'p_notification_id': notificationId},
    );
  }
}
