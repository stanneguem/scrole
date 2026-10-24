import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../app/local_storage/structured/app_cache_database.dart';
import '../../externe/services/supabase_event_service.dart';
import '../persistence/evenement_local_dao.dart';
import '../repositories/event_repository.dart';
import '../../interne/controllers/edit_event_controller.dart';

class EditEventBinding extends Bindings {
  @override
  void dependencies() {
    if (!Get.isRegistered<SupabaseEventService>()) {
      Get.lazyPut(() => SupabaseEventService(Supabase.instance.client));
    }
    if (!Get.isRegistered<EvenementLocalDao>()) {
      Get.lazyPut(() => EvenementLocalDao(Get.find<AppDatabase>()));
    }
    if (!Get.isRegistered<EventRepository>()) {
      Get.lazyPut(() => EventRepository(
        Get.find<SupabaseEventService>(),
        Get.find<EvenementLocalDao>(),
      ));
    }
    final event = Get.arguments;
    if (event != null) {
      Get.lazyPut<EditEventController>(() => EditEventController(event: event));
    }
  }
}
