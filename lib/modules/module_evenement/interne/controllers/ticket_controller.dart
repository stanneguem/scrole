import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../app/service_global/currency_service.dart';
import '../../centre/models/event_model.dart';
import '../../centre/models/ticket_model.dart';
import '../../centre/repositories/event_repository.dart';

class TicketController extends GetxController {
  final String eventId;
  final EventRepository _repository;
  StreamSubscription<EventModel>? _eventUpdateSubscription;

  TicketController({
    required this.eventId,
    EventRepository? repository,
  }) : _repository = repository ?? Get.find<EventRepository>();

  final Rxn<EventModel> event = Rxn<EventModel>();
  final RxList<TicketModel> tickets = <TicketModel>[].obs;
  final RxBool isLoading = false.obs;
  final RxBool isSaving = false.obs;

  // Controllers pour le formulaire d'ajout
  final nameController = TextEditingController();
  final priceController = TextEditingController();
  final quantityController = TextEditingController();
  final RxString currency = 'XAF'.obs;

  @override
  void onInit() {
    super.onInit();
    _eventUpdateSubscription = _repository.onEventUpdated.listen((updatedEvent) {
      if (updatedEvent.id == eventId) {
        debugPrint('[TicketController] Stream onEventUpdated received: isFree=${updatedEvent.isFree}');
        event.value = updatedEvent;
      }
    });

    final args = Get.arguments;
    if (args is EventModel) {
      event.value = args;
    }

    try {
      if (Get.isRegistered<CurrencyService>()) {
        currency.value = Get.find<CurrencyService>().defaultCurrencyCode;
      }
    } catch (_) {}

    loadEventDetails();
    loadTickets();
  }

  @override
  void onClose() {
    _eventUpdateSubscription?.cancel();
    nameController.dispose();
    priceController.dispose();
    quantityController.dispose();
    super.onClose();
  }

  Future<void> loadEventDetails() async {
    try {
      final ev = await _repository.getEventById(eventId);
      if (ev != null) {
        debugPrint('[TicketController] loadEventDetails fresh: isFree=${ev.isFree}');
        event.value = ev;
      }
    } catch (e) {
      debugPrint('[TicketController] loadEventDetails error: $e');
    }
  }

  Future<void> loadTickets() async {
    isLoading.value = true;
    try {
      final results = await _repository.getEventTickets(eventId);
      tickets.assignAll(results);
    } catch (e) {
      debugPrint('[Error] TicketController.loadTickets: $e');
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> addTicket() async {
    if (event.value != null && event.value!.isFree) {
      Get.snackbar(
        'Événement gratuit',
        'Cet événement est configuré comme gratuit. Impossible de créer un billet payant.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    final name = nameController.text.trim();
    final priceStr = priceController.text.trim();

    if (name.isEmpty) {
      Get.snackbar('Nom requis', 'Veuillez saisir le nom du billet.', snackPosition: SnackPosition.BOTTOM);
      return;
    }

    final price = double.tryParse(priceStr);
    if (price == null || price < 0) {
      Get.snackbar('Prix invalide', 'Veuillez saisir un prix positif valide.', snackPosition: SnackPosition.BOTTOM);
      return;
    }

    isSaving.value = true;
    try {
      final newTicketMap = <String, dynamic>{
        'event_id': eventId,
        'name': name,
        'price': price,
        'currency_code': currency.value,
      };

      await _repository.addTicketOptimistic(newTicketMap);

      nameController.clear();
      priceController.clear();

      await loadTickets();
      Get.back();
      Get.snackbar('Billet créé', 'Le billet "$name" a été créé avec succès.', snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      debugPrint('[TicketController] addTicket error: $e');
      Get.snackbar('Erreur', 'Impossible de créer le billet : $e', snackPosition: SnackPosition.BOTTOM);
      await loadTickets();
    } finally {
      isSaving.value = false;
    }
  }

  Future<void> deleteTicket(String ticketId) async {
    try {
      await _repository.deleteTicket(ticketId);
      tickets.removeWhere((t) => t.id == ticketId);
      Get.snackbar('Billet supprimé', 'Le billet a été supprimé.', snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      Get.snackbar('Erreur', 'Impossible de supprimer le billet : $e', snackPosition: SnackPosition.BOTTOM);
    }
  }
}
