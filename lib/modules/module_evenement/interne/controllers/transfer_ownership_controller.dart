import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import '../../centre/models/event_model.dart';
import '../../centre/models/event_transfer_model.dart';
import '../../centre/models/co_creator_model.dart';
import '../../centre/repositories/event_repository.dart';

class TransferOwnershipController extends GetxController {
  final EventModel event;
  final EventRepository _repository;

  TransferOwnershipController({
    required this.event,
    EventRepository? repository,
  }) : _repository = repository ?? Get.find<EventRepository>();

  final RxList<CoCreatorModel> acceptedCoCreators = <CoCreatorModel>[].obs;
  final RxList<EventTransferModel> proposals = <EventTransferModel>[].obs;

  final RxBool isLoadingCoCreators = false.obs;
  final RxBool isLoadingProposals = false.obs;
  final RxMap<String, bool> processingCandidateIds = <String, bool>{}.obs;

  @override
  void onInit() {
    super.onInit();
    debugPrint('[TRANSFER] TransferOwnershipController initialized for eventId=${event.id}');
    loadCoCreators();
    loadProposals();
  }

  Future<void> loadCoCreators() async {
    isLoadingCoCreators.value = true;
    try {
      final list = await _repository.getEventCoCreators(event.id);
      acceptedCoCreators.assignAll(list.where((c) => c.status == CoCreatorStatus.accepted));
    } catch (e) {
      debugPrint('[TransferOwnershipController] loadCoCreators error: $e');
    } finally {
      isLoadingCoCreators.value = false;
    }
  }

  Future<void> loadProposals() async {
    isLoadingProposals.value = true;
    try {
      final list = await _repository.getEventTransferProposals(event.id);
      proposals.assignAll(list);
    } catch (e) {
      debugPrint('[TransferOwnershipController] loadProposals error: $e');
    } finally {
      isLoadingProposals.value = false;
    }
  }

  EventTransferModel? getActiveProposalForUser(String userId) {
    return proposals.firstWhereOrNull(
      (p) => p.proposedTo == userId && p.status == TransferStatus.pending,
    );
  }

  EventTransferModel? getLatestProposalForUser(String userId) {
    return proposals.firstWhereOrNull((p) => p.proposedTo == userId);
  }

  Future<void> proposeTransfer(String targetUserId, String candidateName) async {
    if (processingCandidateIds[targetUserId] == true) return;

    processingCandidateIds[targetUserId] = true;
    try {
      await _repository.proposeTransfer(event.id, targetUserId);
      Get.snackbar(
        'Proposition envoyée',
        'La proposition de transfert a été envoyée avec succès à $candidateName.',
        snackPosition: SnackPosition.BOTTOM,
      );
      await loadProposals();
    } catch (e) {
      debugPrint('[TransferOwnershipController] proposeTransfer error: $e');
      final errStr = e.toString();
      String friendlyMsg = 'Impossible d\'envoyer la proposition : $e';
      if (errStr.contains('Seul le créateur') || errStr.contains('créateur')) {
        friendlyMsg = 'Seul le fondateur actuel de l\'événement peut transférer la propriété.';
      } else if (errStr.contains('déjà en attente')) {
        friendlyMsg = 'Une proposition de transfert est déjà en attente pour ce co-fondateur.';
      } else if (errStr.contains('co-créateur') || errStr.contains('co-fondateur')) {
        friendlyMsg = 'Le transfert de propriété est uniquement possible vers un co-fondateur confirmé.';
      }
      Get.snackbar('Erreur', friendlyMsg, snackPosition: SnackPosition.BOTTOM, duration: const Duration(seconds: 4));
    } finally {
      processingCandidateIds[targetUserId] = false;
    }
  }

  Future<void> cancelTransfer(String transferId, String candidateUserId) async {
    if (processingCandidateIds[candidateUserId] == true) return;

    processingCandidateIds[candidateUserId] = true;
    try {
      await _repository.cancelTransfer(transferId);
      Get.snackbar(
        'Proposition annulée',
        'La proposition de transfert a été annulée.',
        snackPosition: SnackPosition.BOTTOM,
      );
      await loadProposals();
    } catch (e) {
      debugPrint('[TransferOwnershipController] cancelTransfer error: $e');
      Get.snackbar('Erreur', 'Impossible d\'annuler la proposition : $e', snackPosition: SnackPosition.BOTTOM);
    } finally {
      processingCandidateIds[candidateUserId] = false;
    }
  }
}
