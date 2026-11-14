import 'package:get/get.dart';
import '../../centre/models/event_model.dart';
import '../pages/event_itinerary_overview_screen.dart';
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

  @override
  void onReady() {
    super.onReady();
    final arguments = Get.arguments;
    final requestedEventId = arguments is Map
        ? arguments['openEventId']?.toString()
        : null;
    if (requestedEventId != null && requestedEventId.isNotEmpty) {
      _openRequestedEventItinerary(requestedEventId);
    }
  }

  Future<void> _openRequestedEventItinerary(String eventId) async {
    try {
      // Refresh first so the event list is current, then fall back to the
      // repository for events that are no longer present in the agenda list.
      await loadMyAgenda();
      EventModel? event;
      for (final candidate in myAgenda) {
        if (candidate.id == eventId) {
          event = candidate;
          break;
        }
      }
      event ??= await _repository.getEventById(eventId);
      if (isClosed) return;
      Get.to(() => EventItineraryOverviewScreen(event: event!));
    } catch (error) {
      print('[UserAgendaController] Unable to open requested itinerary: $error');
      if (!isClosed) {
        Get.snackbar(
          'Mon planning',
          'Impossible de charger le planning de cet événement.',
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    }
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
