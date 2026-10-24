import 'package:get/get.dart';
import '../../centre/models/event_model.dart';
import '../../centre/repositories/event_repository.dart';
import '../../../module_authentification/centre/services/auth_service.dart';

class UserAgendaController extends GetxController {
  final EventRepository _repository;

  UserAgendaController({EventRepository? repository}) 
    : _repository = repository ?? Get.find<EventRepository>();

  final RxList<EventModel> myAgenda = <EventModel>[].obs;
  final RxBool isLoading = false.obs;

  @override
  void onInit() {
    super.onInit();
    loadMyAgenda();
  }

  Future<void> loadMyAgenda() async {
    isLoading.value = true;
    try {
      final userId = Get.find<AuthService>().userId;
      if (userId == null) return;

      final events = await _repository.getUserAgenda(userId);
      myAgenda.assignAll(events);
    } catch (e) {
      print('[Error] UserAgendaController.loadMyAgenda: $e');
    } finally {
      isLoading.value = false;
    }
  }

  EventModel? get activeEvent {
    final now = DateTime.now();
    try {
      return myAgenda.firstWhere((e) => 
        e.startsAt.isBefore(now) && (e.endsAt == null || e.endsAt!.isAfter(now))
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> removeFromAgenda(String eventId) async {
    final userId = Get.find<AuthService>().userId;
    if (userId == null || userId.isEmpty) {
      Get.snackbar('Connexion requise', 'Connectez-vous pour modifier votre agenda.');
      return;
    }
    try {
      await _repository.removeEventFromCalendarOptimistic(eventId, userId);
      myAgenda.removeWhere((e) => e.id == eventId);
      Get.snackbar('Agenda', 'Événement retiré de votre agenda.', snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      Get.snackbar('Erreur', 'Impossible de retirer l\'événement de votre agenda.');
      await loadMyAgenda();
    }
  }
}
