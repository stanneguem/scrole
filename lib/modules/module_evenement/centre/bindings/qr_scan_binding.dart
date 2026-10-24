import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../app/local_storage/structured/app_cache_database.dart';
import '../../externe/services/supabase_event_service.dart';
import '../persistence/evenement_local_dao.dart';
import '../repositories/event_repository.dart';
import '../models/event_model.dart';
import '../../interne/controllers/qr_scan_controller.dart';

class QrScanBinding extends Bindings {
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
    
    final eventId = Get.parameters['id'];
    String? activityId;
    DateTime? eventStartsAt;
    final args = Get.arguments;
    if (args is Map) {
      activityId = args['activityId']?.toString();
      if (args['event'] is EventModel) {
        eventStartsAt = (args['event'] as EventModel).startsAt;
      } else if (args['startsAt'] is DateTime) {
        eventStartsAt = args['startsAt'] as DateTime;
      }
    } else if (args is EventModel) {
      eventStartsAt = args.startsAt;
    }
    
    if (eventId != null) {
      Get.lazyPut<QrScanController>(() => QrScanController(
        eventId: eventId,
        eventActivityId: activityId,
        eventStartsAt: eventStartsAt,
      ));
    }
  }
}
