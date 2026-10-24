import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../app/local_storage/structured/app_cache_database.dart';
import '../../externe/services/supabase_event_service.dart';
import '../persistence/evenement_local_dao.dart';
import '../repositories/event_repository.dart';
import '../../interne/controllers/event_controller.dart';

import '../../../../app/service_global/connectivity_service.dart';
import '../services/event_outbox_processor.dart';

class MainEventBinding extends Bindings {
  @override
  void dependencies() {
    if (!Get.isRegistered<SupabaseEventService>()) {
      Get.lazyPut(() => SupabaseEventService(Supabase.instance.client));
    }
    if (!Get.isRegistered<EvenementLocalDao>()) {
      Get.lazyPut(() => EvenementLocalDao(Get.find<AppDatabase>()));
    }
    if (!Get.isRegistered<EventOutboxProcessor>()) {
      Get.put(EventOutboxProcessor(
        Get.find<EvenementLocalDao>(),
        Get.find<SupabaseEventService>(),
        Get.find<ConnectivityService>(),
      ), permanent: true);
    }
    if (!Get.isRegistered<EventRepository>()) {
      Get.lazyPut(() => EventRepository(
        Get.find<SupabaseEventService>(),
        Get.find<EvenementLocalDao>(),
      ));
    }
    Get.lazyPut(() => EventController());
  }
}
