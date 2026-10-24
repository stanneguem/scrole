import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import '../../centre/models/event_sponsor_invitation_model.dart';
import '../../centre/repositories/event_repository.dart';
import '../../../../modules/module_discussion_direct/interne/controllers/contacts_controller.dart';

class SponsorInvitationController extends GetxController {
  final String eventId;
  final EventRepository _repository;

  SponsorInvitationController({
    required this.eventId,
    EventRepository? repository,
  }) : _repository = repository ?? Get.find<EventRepository>();

  final RxList<EventSponsorInvitationModel> invitations = <EventSponsorInvitationModel>[].obs;
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
      final list = await _repository.getEventSponsorInvitations(eventId);
      invitations.assignAll(list);
    } catch (e) {
      debugPrint('[SponsorInvitationController] loadInvitations error: $e');
    } finally {
      isLoadingInvitations.value = false;
    }
  }

  Future<void> loadCandidates() async {
    isLoadingCandidates.value = true;
    try {
      final list = await _repository.getEligibleSponsorCandidates(eventId, search: searchQuery.value.trim());
      candidates.assignAll(list);
    } catch (e) {
      debugPrint('[SponsorInvitationController] loadCandidates error: $e');
    } finally {
      isLoadingCandidates.value = false;
    }
  }

  Future<void> inviteSponsor(String userId) async {
    try {
      await _repository.inviteEventSponsor(eventId: eventId, userId: userId);
      candidates.removeWhere((c) => c.id == userId);
      Get.snackbar(
        'Invitation Sponsor',
        'L\'invitation sponsor a été envoyée avec succès.',
        snackPosition: SnackPosition.BOTTOM,
      );
      loadInvitations();
    } catch (e) {
      Get.snackbar('Erreur', e.toString(), snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> removeSponsor(EventSponsorInvitationModel sponsor) async {
    try {
      await _repository.removeEventSponsor(inviteId: sponsor.id);
      invitations.removeWhere((i) => i.id == sponsor.id || i.userId == sponsor.userId);
      Get.snackbar('Sponsor retiré', 'Le sponsor a été retiré de la liste.', snackPosition: SnackPosition.BOTTOM);
      loadCandidates();
    } catch (e) {
      Get.snackbar('Erreur', e.toString(), snackPosition: SnackPosition.BOTTOM);
    }
  }

  List<EventSponsorInvitationModel> get acceptedSponsors =>
      invitations.where((i) => i.status == SponsorInvitationStatus.accepted).toList();

  List<EventSponsorInvitationModel> get pendingSponsors =>
      invitations.where((i) => i.status == SponsorInvitationStatus.pending).toList();

  List<EventSponsorInvitationModel> get declinedSponsors =>
      invitations.where((i) => i.status == SponsorInvitationStatus.declined).toList();

  List<ContactModel> get filteredCandidates => candidates;
}
