import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../centre/models/activity_model.dart';
import '../../centre/models/staff_model.dart';
import '../../centre/repositories/event_repository.dart';
import '../../../module_authentification/centre/services/auth_service.dart';

class EventActivityController extends GetxController {
  final String eventId;
  final EventRepository _repository;

  EventActivityController({
    required this.eventId,
    EventRepository? repository,
  }) : _repository = repository ?? Get.find<EventRepository>();

  final RxList<EventActivityModel> eventActivities = <EventActivityModel>[].obs;
  final RxList<EventActivityModel> proposedActivities = <EventActivityModel>[].obs;
  final RxList<AvailableActivityModel> availableActivities = <AvailableActivityModel>[].obs;
  final RxList<AvailableActivityModel> searchResults = <AvailableActivityModel>[].obs;
  final RxList<StaffMemberModel> eventStaff = <StaffMemberModel>[].obs;

  final RxBool isLoading = false.obs;
  final RxBool isSaving = false.obs;

  final RxString searchQuery = ''.obs;
  Worker? _searchWorker;

  // Mode sélection multiple
  final RxBool isMultiSelectMode = false.obs;
  final RxSet<String> selectedActivityIds = <String>{}.obs;

  @override
  void onInit() {
    super.onInit();
    loadEventActivities();
    loadEventStaff();
    fetchAvailableActivities('');

    _searchWorker = debounce(
      searchQuery,
      (q) => fetchAvailableActivities(q.toString()),
      time: const Duration(milliseconds: 350),
    );
  }

  @override
  void onClose() {
    _searchWorker?.dispose();
    super.onClose();
  }

  void enterMultiSelectMode(String initialActivityId) {
    isMultiSelectMode.value = true;
    selectedActivityIds.add(initialActivityId);
  }

  void toggleSelection(String activityId) {
    if (selectedActivityIds.contains(activityId)) {
      selectedActivityIds.remove(activityId);
      if (selectedActivityIds.isEmpty) {
        isMultiSelectMode.value = false;
      }
    } else {
      selectedActivityIds.add(activityId);
    }
  }

  void exitMultiSelectMode() {
    selectedActivityIds.clear();
    isMultiSelectMode.value = false;
  }

  void searchGlobalActivities(String query) {
    searchQuery.value = query;
  }

  Future<void> fetchAvailableActivities(String query, {int limit = 30, int offset = 0}) async {
    isLoading.value = true;
    try {
      final results = await _repository.fetchActiveActivitiesForEvent(
        eventId: eventId,
        search: query,
        limit: limit,
        offset: offset,
      );
      if (offset == 0) {
        availableActivities.assignAll(results);
        searchResults.assignAll(results);
      } else {
        availableActivities.addAll(results);
        searchResults.addAll(results);
      }
    } catch (e) {
      debugPrint('[EventActivityController] fetchAvailableActivities error: $e');
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> loadEventActivities() async {
    try {
      final all = await _repository.getEventActivities(eventId);
      eventActivities.assignAll(all);
      proposedActivities.assignAll(all.where((a) => a.status == 'en_attente'));
    } catch (e) {
      debugPrint('[Error] EventActivityController.loadEventActivities: $e');
    }
  }

  Future<void> validateProposedActivity(String id, bool accept) async {
    try {
      await _repository.validateActivity(id, accept);
      Get.snackbar('Succès', accept ? 'Activité acceptée' : 'Activité rejetée');
      await loadEventActivities();
    } catch (e) {
      Get.snackbar('Erreur', e.toString());
    }
  }

  Future<void> loadEventStaff() async {
    try {
      final results = await _repository.getEventStaff(eventId);
      eventStaff.assignAll(results);
    } catch (e) {
      debugPrint('[Error] EventActivityController.loadEventStaff: $e');
    }
  }

  Future<void> addActivityToEvent(String activityId, double price, String currency) async {
    isSaving.value = true;
    try {
      final available = availableActivities.firstWhereOrNull((a) => a.id == activityId);
      final userId = Get.find<AuthService>().userId ?? '';

      // Indication visuelle optimiste immédiate dans la liste
      final idx = availableActivities.indexWhere((a) => a.id == activityId);
      if (idx != -1) {
        availableActivities[idx] = availableActivities[idx].copyWith(isAlreadyAdded: true);
      }

      await _repository.addActivityOptimistic(
        eventId: eventId,
        activityId: activityId,
        price: price,
        currency: currency,
        userId: userId,
        activityInfo: {
          'id': activityId,
          'nom': available?.name ?? 'Activité',
          'description': available?.description,
          'prix_indicatif': available?.basePrice ?? price,
          'devise': currency,
        },
      );
      await loadEventActivities();
      Get.snackbar('Activités', 'Activité ajoutée à l\'événement !', snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      Get.snackbar('Erreur', e.toString());
    } finally {
      isSaving.value = false;
    }
  }

  Future<void> addMultipleActivitiesToEvent() async {
    if (selectedActivityIds.isEmpty) return;
    isSaving.value = true;

    try {
      final userId = Get.find<AuthService>().userId ?? '';
      final idsToAdd = List<String>.from(selectedActivityIds);

      for (final id in idsToAdd) {
        final available = availableActivities.firstWhereOrNull((a) => a.id == id);
        final price = available?.basePriceConverted ?? available?.basePrice ?? 0.0;
        final currency = available?.displayCurrencyCode ?? available?.currencyCode ?? 'XAF';

        final idx = availableActivities.indexWhere((a) => a.id == id);
        if (idx != -1) {
          availableActivities[idx] = availableActivities[idx].copyWith(isAlreadyAdded: true);
        }

        await _repository.addActivityOptimistic(
          eventId: eventId,
          activityId: id,
          price: price,
          currency: currency,
          userId: userId,
          activityInfo: {
            'id': id,
            'nom': available?.name ?? 'Activité',
            'description': available?.description,
            'prix_indicatif': price,
            'devise': currency,
          },
        );
      }

      exitMultiSelectMode();
      await loadEventActivities();
      Get.back(); // Ferme le BottomSheet de confirmation
      Get.snackbar('Activités', '${idsToAdd.length} activités ajoutées à l\'événement !', snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      Get.snackbar('Erreur', e.toString());
    } finally {
      isSaving.value = false;
    }
  }

  Future<List<StaffMemberModel>> fetchEventActivityStaff(String activityId) async {
    try {
      final actId = activityId.isNotEmpty ? activityId : '';
      debugPrint('[EventActivityController] fetchEventActivityStaff: eventId=$eventId, activityId=$actId');
      return await _repository.getEventActivityStaff(eventId: eventId, activityId: actId);
    } catch (e) {
      debugPrint('[EventActivityController] fetchEventActivityStaff error: $e');
      rethrow;
    }
  }

  Future<void> assignStaffToActivity(String eventActivityId, String staffEvenementId) async {
    try {
      await _repository.assignStaffToActivity(eventActivityId, staffEvenementId);
      Get.snackbar('Staff', 'Membre assigné à l\'activité', snackPosition: SnackPosition.BOTTOM);
      await loadEventActivities();
    } catch (e) {
      final errStr = e.toString();
      debugPrint('[EventActivityController] assignStaffToActivity error: $errStr');
      if (errStr.contains('P0001') || errStr.contains('pas liée à cet événement')) {
        Get.snackbar(
          'Attribution impossible',
          'Cette activité n\'est pas associée à cet événement. Veuillez d\'abord l\'ajouter à l\'événement.',
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 4),
        );
      } else {
        Get.snackbar('Erreur', 'Impossible d\'attribuer le staff : $e', snackPosition: SnackPosition.BOTTOM);
      }
      await loadEventActivities();
    }
  }

  Future<void> updateEventActivityPrice(String eventActivityId, double newPrice, {String? activityId}) async {
    final idx = eventActivities.indexWhere((a) => a.id == eventActivityId || (activityId != null && a.activityId == activityId));
    EventActivityModel? originalModel;
    if (idx != -1) {
      originalModel = eventActivities[idx];
      eventActivities[idx] = originalModel.copyWith(price: newPrice);
    }

    try {
      await _repository.updateEventActivityPrice(
        eventActivityId: eventActivityId,
        newPrice: newPrice,
        eventId: eventId,
        activityId: activityId ?? (originalModel?.activityId),
      );
      Get.snackbar('Prix mis à jour', 'Le prix de l\'activité a été modifié.', snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      debugPrint('[ActivityEventPrice] update failed in controller: $e');
      if (idx != -1 && originalModel != null) {
        eventActivities[idx] = originalModel;
      }
      Get.snackbar('Erreur', 'Impossible de modifier le prix : $e', snackPosition: SnackPosition.BOTTOM);
      rethrow;
    }
  }

  Future<void> removeActivity(EventActivityModel activity) async {
    final targetId = activity.id;
    final targetActId = activity.activityId;

    eventActivities.removeWhere((a) => a.id == targetId || (a.activityId.isNotEmpty && a.activityId == targetActId));

    try {
      await _repository.removeActivityFromEventOptimistic(
        eventId: activity.eventId.isNotEmpty ? activity.eventId : eventId,
        activityId: targetActId.isNotEmpty ? targetActId : targetId,
      );
      Get.snackbar('Activité retirée', 'L\'activité "${activity.name}" a été retirée de cet événement.', snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      debugPrint('[EventActivityController] removeActivity error: $e');
      await loadEventActivities();
      Get.snackbar('Erreur', 'Impossible de retirer l\'activité : $e', snackPosition: SnackPosition.BOTTOM);
      rethrow;
    }
  }
}
