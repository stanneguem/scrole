import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import '../../centre/models/event_guest_invitation_model.dart';
import '../../centre/repositories/event_repository.dart';
import '../../../../modules/module_discussion_direct/interne/controllers/contacts_controller.dart';

class GuestInvitationController extends GetxController {
  final String eventId;
  final EventRepository _repository;

  GuestInvitationController({
    required this.eventId,
    EventRepository? repository,
  }) : _repository = repository ?? Get.find<EventRepository>();

  final RxList<EventGuestInvitationModel> invitations = <EventGuestInvitationModel>[].obs;
  final RxList<ContactModel> candidates = <ContactModel>[].obs;
  final RxBool isLoadingInvitations = false.obs;
  final RxBool isLoadingCandidates = false.obs;
  final RxString searchQuery = ''.obs;

  @override
  void onInit() {
    super.onInit();
    loadInvitations();
    loadCandidates();
    debounce(searchQuery, (_) => loadCandidates(), time: const Duration(milliseconds: 350));
  }

  Future<void> loadInvitations() async {
    isLoadingInvitations.value = true;
    try {
      final list = await _repository.getEventGuestInvitations(eventId);
      invitations.assignAll(list);
    } catch (e) {
      debugPrint('[GuestInvitationController] loadInvitations error: $e');
    } finally {
      isLoadingInvitations.value = false;
    }
  }

  Future<void> loadCandidates() async {
    isLoadingCandidates.value = true;
    try {
      final list = await _repository.getEligibleGuestCandidates(eventId, search: searchQuery.value.trim());
      candidates.assignAll(list);
    } catch (e) {
      debugPrint('[GuestInvitationController] loadCandidates error: $e');
    } finally {
      isLoadingCandidates.value = false;
    }
  }

  Future<void> inviteGuest(String userId) async {
    try {
      await _repository.inviteEventGuest(eventId: eventId, userId: userId);
      candidates.removeWhere((c) => c.id == userId);
      Get.snackbar(
        'Invitation d\'honneur',
        'L\'invitation a été envoyée avec succès.',
        snackPosition: SnackPosition.BOTTOM,
      );
      loadInvitations();
    } catch (e) {
      Get.snackbar('Erreur', e.toString(), snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> removeGuest(EventGuestInvitationModel guest) async {
    try {
      await _repository.removeEventGuest(eventId: eventId, userId: guest.userId, inviteId: guest.id);
      invitations.removeWhere((i) => i.id == guest.id || i.userId == guest.userId);
      Get.snackbar('Invité retiré', 'L\'invité a été retiré de la liste.', snackPosition: SnackPosition.BOTTOM);
      loadCandidates();
    } catch (e) {
      Get.snackbar('Erreur', e.toString(), snackPosition: SnackPosition.BOTTOM);
    }
  }

  List<EventGuestInvitationModel> get acceptedGuests =>
      invitations.where((i) => i.status == GuestInvitationStatus.accepted).toList();

  List<EventGuestInvitationModel> get pendingGuests =>
      invitations.where((i) => i.status == GuestInvitationStatus.pending).toList();

  List<EventGuestInvitationModel> get declinedGuests =>
      invitations.where((i) => i.status == GuestInvitationStatus.declined).toList();

  List<ContactModel> get filteredCandidates => candidates;
}
