import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../app/local_storage/structured/app_cache_database.dart';
import '../../externe/services/supabase_event_service.dart';
import '../persistence/evenement_local_dao.dart';
import '../repositories/event_repository.dart';
import '../../interne/controllers/transfer_ownership_controller.dart';
import '../models/event_model.dart';

class TransferOwnershipBinding extends Bindings {
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
    
    final args = Get.arguments;
    if (args is EventModel) {
      Get.lazyPut<TransferOwnershipController>(() => TransferOwnershipController(event: args));
    } else {
      // Fallback si on arrive avec seulement l'ID
      final eventId = Get.parameters['id'];
      if (eventId != null) {
        Get.lazyPut<TransferOwnershipController>(() => TransferOwnershipController(
          event: EventModel(id: eventId, creatorId: '', name: 'Chargement...', slug: '', startsAt: DateTime.now(), createdAt: DateTime.now()),
        ));
        // Idéalement, le controller devrait charger l'event complet si besoin
      }
    }
  }
}
