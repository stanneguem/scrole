import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:scrole/modules/module_discussion_direct/centre/persistence/social_local_dao.dart';
import 'package:scrole/modules/module_discussion_direct/centre/repositories/messaging_repository.dart';
import 'package:scrole/modules/module_discussion_direct/centre/services/social_outbox_processor.dart';
import 'package:scrole/modules/module_discussion_direct/externe/repositories/social_repository.dart';
import 'package:scrole/modules/module_discussion_direct/externe/services/fcm_notification_service.dart';
import 'package:scrole/modules/module_discussion_direct/externe/services/supabase_messaging_service.dart';
import 'package:scrole/modules/module_discussion_direct/interne/controllers/direct_conversation_controller.dart';
import 'package:scrole/modules/module_discussion_direct/interne/controllers/direct_messages_controller.dart';
import 'package:scrole/app/local_storage/structured/app_cache_database.dart';
import 'package:scrole/app/service_global/connectivity_service.dart';

class MessagingBinding extends Bindings {
  @override
  void dependencies() {
    if (!Get.isRegistered<SupabaseMessagingService>()) {
      Get.lazyPut<SupabaseMessagingService>(() => SupabaseMessagingService(Supabase.instance.client), fenix: true);
    }
    if (!Get.isRegistered<MessagingRepository>()) {
      Get.lazyPut<MessagingRepository>(() => MessagingRepository(Get.find<AppDatabase>(), Get.find<SupabaseMessagingService>()), fenix: true);
    }
    if (!Get.isRegistered<SocialLocalDao>()) {
      Get.lazyPut<SocialLocalDao>(() => SocialLocalDao(Get.find<AppDatabase>()), fenix: true);
    }
    if (!Get.isRegistered<SocialOutboxProcessor>()) {
      Get.put(SocialOutboxProcessor(Get.find<SocialLocalDao>(), Get.find<ConnectivityService>()), permanent: true);
    }
    if (!Get.isRegistered<SocialRepository>()) Get.lazyPut<SocialRepository>(() => SocialRepository(), fenix: true);
    if (!Get.isRegistered<FcmNotificationService>()) {
      Get.lazyPut<FcmNotificationService>(() => FcmNotificationService(Get.find<MessagingRepository>()), fenix: true);
    }
    if (!Get.isRegistered<DirectMessagesController>()) {
      Get.lazyPut<DirectMessagesController>(() => DirectMessagesController());
    }
  }
}

class ConversationBinding extends Bindings {
  @override
  void dependencies() {
    MessagingBinding().dependencies();
    if (Get.isRegistered<DirectConversationController>()) {
      Get.delete<DirectConversationController>(force: true);
    }
    Get.put(DirectConversationController());
  }
}
