import 'package:get/get.dart';
import '../../centre/models/event_model.dart';
import '../../centre/repositories/event_repository.dart';
import '../enums/event_enum.dart';

class EventManagementController extends GetxController {
  final EventModel event;
  final EventRepository _repository;

  EventManagementController({
    required this.event,
    EventRepository? repository,
  }) : _repository = repository ?? Get.find<EventRepository>();

  final RxBool isPublishing = false.obs;
  final RxBool isDeleting = false.obs;
  late final Rx<EventStatus> status;

  @override
  void onInit() {
    super.onInit();
    status = event.status.obs;
  }

  Future<void> deleteEvent() async {
    if (isDeleting.value) return;
    isDeleting.value = true;
    try {
      await _repository.deleteEvent(event.id);
      Get.back(); // Fermer l'écran des paramètres
      Get.back(); // Revenir à la liste des événements
      Get.snackbar('Succès', 'L\'événement a été supprimé.');
    } catch (e) {
      Get.snackbar('Erreur', 'Impossible de supprimer l\'événement.');
    } finally {
      isDeleting.value = false;
    }
  }
}
